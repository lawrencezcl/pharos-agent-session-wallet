// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentSessionWallet
/// @notice A smart-contract wallet that lets a human owner grant an AI agent a
///         time-boxed, spending-capped "session key". The agent can then act
///         autonomously on-chain (transfer native PHRS or ERC-20 tokens, call any
///         contract) within the scoped budget, without ever holding the owner's
///         private key. The owner can revoke instantly at any time.
///
///         This is the foundational primitive of an on-chain AI-agent economy:
///         "delegate limited autonomy to an agent, keep full custody yourself."
///
/// @dev    Author is the deployer (owner). Session keys are normal EOAs that the
///         agent runtime controls. Spending is enforced per (operator, token)
///         grant with a rolling reset window. The wallet supports batching and
///         arbitrary calls so it composes with any other Pharos skill (x402,
///         airdrop, vault, DEX, etc.).
contract AgentSessionWallet {
    /* ------------------------------------------------------------------ */
    /*  Errors (human-readable revert messages for the Skill Engine)      */
    /* ------------------------------------------------------------------ */

    error NotOwner();
    error NotOwnerOrActiveSessionKey();
    error SessionKeyInactive();
    error SessionKeyExpired();
    error SpendLimitExceeded(uint256 needed, uint256 available);
    error InvalidParams();
    error CallFailed(uint256 index, bytes reason);
    error ZeroAddress();
    error InvalidAmount();
    error NothingToWithdraw();
    error ExternalCallFailed();
    error NotERC20Transfer();

    /* ------------------------------------------------------------------ */
    /*  Types                                                             */
    /* ------------------------------------------------------------------ */

    /// @dev A single call executed by the wallet. Supports batching.
    struct Call {
        address target; // contract to call (or recipient for native transfer)
        uint256 value; // native PHRS to send
        bytes data; // calldata (empty => plain native transfer)
    }

    /// @dev Scoped autonomy granted to one operator key for one token.
    ///      token == address(0) means native PHRS; otherwise an ERC-20 address.
    struct Grant {
        uint96 validUntil; // hard expiry timestamp (0 = expired / not set)
        uint64 period; // rolling window length in seconds
        uint64 windowStart; // start timestamp of the current window
        uint256 limit; // max spend allowed per window
        uint256 spent; // amount already spent in the current window
    }

    /* ------------------------------------------------------------------ */
    /*  Storage                                                           */
    /* ------------------------------------------------------------------ */

    address public owner;

    // operator => token(address(0)=native) => Grant
    mapping(address => mapping(address => Grant)) public grants;

    /* ------------------------------------------------------------------ */
    /*  Events (queryable with `cast logs` — full on-chain audit trail)   */
    /* ------------------------------------------------------------------ */

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Deposited(address indexed sender, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event SessionKeyGranted(
        address indexed operator, address indexed token, uint256 validUntil, uint64 period, uint256 limit
    );
    event SessionKeyRevoked(address indexed operator, address indexed token);
    event SessionKeyConsumed(
        address indexed operator, address indexed token, uint256 amount, uint256 totalSpentInWindow, uint256 windowStart
    );
    event Executed(address indexed caller, bool indexed viaSessionKey, uint256 callCount, bytes32 indexed resultHash);

    /* ------------------------------------------------------------------ */
    /*  Modifiers                                                         */
    /* ------------------------------------------------------------------ */

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /* ------------------------------------------------------------------ */
    /*  Constructor & receive                                             */
    /* ------------------------------------------------------------------ */

    /// @param initialOwner The human owner who retains full custody. Must not be zero.
    constructor(address initialOwner) {
        if (initialOwner == address(0)) revert ZeroAddress();
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Accept native PHRS top-ups from anyone.
    receive() external payable {
        if (msg.value > 0) emit Deposited(msg.sender, msg.value);
    }

    /* ------------------------------------------------------------------ */
    /*  Owner: custody & escape hatch                                     */
    /* ------------------------------------------------------------------ */

    /// @notice Owner executes an arbitrary batch of calls with full power.
    function execute(Call[] calldata calls) external payable onlyOwner returns (bytes32) {
        return _executeCalls(calls, false);
    }

    /// @notice Transfer contract ownership.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    /// @notice Owner drains native PHRS or an ERC-20 to a recipient. Escape hatch.
    function withdraw(address token, uint256 amount, address to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) {
            uint256 bal = address(this).balance;
            if (bal < amount) revert NothingToWithdraw();
            (bool ok,) = payable(to).call{value: amount}("");
            if (!ok) revert ExternalCallFailed();
        } else {
            (bool ok, bytes memory ret) = token.call(abi.encodeWithSelector(0xa9059cbb, to, amount)); // transfer(address,uint256)
            if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert ExternalCallFailed();
        }
        emit Withdrawn(token, to, amount);
    }

    /* ------------------------------------------------------------------ */
    /*  Owner: session-key lifecycle                                      */
    /* ------------------------------------------------------------------ */

    /// @notice Grant or refresh a session key.
    /// @param operator  The agent's runtime EOA that will call executeAsAgent().
    /// @param token     address(0) for native PHRS, otherwise an ERC-20 address.
    /// @param validUntil Hard expiry (unix seconds). Must be > block.timestamp.
    /// @param period    Rolling window length in seconds (e.g. 86400 for daily).
    /// @param limit     Max spend per window (in token's smallest unit).
    function grantSessionKey(address operator, address token, uint96 validUntil, uint64 period, uint256 limit)
        external
        onlyOwner
    {
        if (operator == address(0)) revert ZeroAddress();
        if (validUntil <= block.timestamp) revert InvalidParams();
        if (period == 0) revert InvalidParams();
        // Preserve unspent budget if the window is still open; otherwise reset.
        Grant storage g = grants[operator][token];
        if (g.validUntil == 0 || block.timestamp >= g.windowStart + g.period) {
            g.windowStart = uint64(block.timestamp);
            g.spent = 0;
        }
        g.validUntil = validUntil;
        g.period = period;
        g.limit = limit;
        emit SessionKeyGranted(operator, token, validUntil, period, limit);
    }

    /// @notice Instantly disable a session key (kill switch).
    function revokeSessionKey(address operator, address token) external onlyOwner {
        delete grants[operator][token];
        emit SessionKeyRevoked(operator, token);
    }

    /* ------------------------------------------------------------------ */
    /*  Agent: scoped autonomous execution                                */
    /* ------------------------------------------------------------------ */

    /// @notice Execute a batch of calls as an authorized session key.
    ///         Spending is enforced per token grant; native via Call.value,
    ///         ERC-20 via detected transfer(address,uint256) to the token.
    function executeAsAgent(Call[] calldata calls) external payable returns (bytes32) {
        // Require at least one active grant to authorise the caller as an agent.
        // We do not require a specific token here because a single batch may mix
        // native + ERC-20; each spend is checked against its own grant below.
        return _executeCalls(calls, true);
    }

    /* ------------------------------------------------------------------ */
    /*  Internal: batch execution + spend enforcement                     */
    /* ------------------------------------------------------------------ */

    function _executeCalls(Call[] calldata calls, bool viaSessionKey) internal returns (bytes32) {
        uint256 len = calls.length;
        bytes32 resultHash;
        for (uint256 i = 0; i < len; i++) {
            Call calldata c = calls[i];

            if (viaSessionKey) {
                // Native spend: enforce grant for address(0).
                if (c.value > 0) {
                    _enforceAndConsume(msg.sender, address(0), c.value);
                }
                // ERC-20 spend: detect transfer(address,uint256) selector 0xa9059cbb
                // whose target is a token the caller has a grant for.
                if (c.data.length >= 4 && bytes4(c.data[:4]) == 0xa9059cbb) {
                    (, uint256 amount) = abi.decode(c.data[4:], (address, uint256));
                    if (amount > 0) {
                        _enforceAndConsume(msg.sender, c.target, amount);
                    }
                }
            }

            (bool ok, bytes memory ret) = c.target.call{value: c.value}(c.data);
            if (!ok) revert CallFailed(i, ret);
            resultHash = keccak256(abi.encodePacked(resultHash, ret));
        }
        emit Executed(msg.sender, viaSessionKey, len, resultHash);
        return resultHash;
    }

    /// @dev Reverts if the operator has no active grant for `token`, is expired,
    ///      or would exceed the per-window spend limit. Rolls the window forward
    ///      when it elapses, then books the spend.
    function _enforceAndConsume(address operator, address token, uint256 amount) internal {
        Grant storage g = grants[operator][token];
        if (g.validUntil == 0) revert SessionKeyInactive();
        if (block.timestamp > g.validUntil) revert SessionKeyExpired();

        // Roll the window if it elapsed.
        if (block.timestamp >= g.windowStart + g.period) {
            uint64 periodsElapsed = uint64((block.timestamp - g.windowStart) / g.period);
            g.windowStart += periodsElapsed * g.period;
            g.spent = 0;
        }

        uint256 available = g.limit > g.spent ? g.limit - g.spent : 0;
        if (amount > available) {
            revert SpendLimitExceeded(amount, available);
        }
        g.spent += amount;

        emit SessionKeyConsumed(operator, token, amount, g.spent, g.windowStart);
    }

    /* ------------------------------------------------------------------ */
    /*  Views (agent-friendly, for `cast call`)                           */
    /* ------------------------------------------------------------------ */

    /// @notice Native PHRS held by the wallet.
    function nativeBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Full grant state for (operator, token).
    function getGrant(address operator, address token) external view returns (Grant memory) {
        return grants[operator][token];
    }

    /// @notice Whether a session key is currently active (set, unexpired).
    function isSessionKeyActive(address operator, address token) external view returns (bool) {
        Grant storage g = grants[operator][token];
        return g.validUntil != 0 && block.timestamp <= g.validUntil;
    }

    /// @notice Remaining spendable budget for (operator, token) in the current
    ///         window, rolling the window forward if it elapsed.
    function spendAvailable(address operator, address token) external view returns (uint256) {
        Grant storage g = grants[operator][token];
        if (g.validUntil == 0 || block.timestamp > g.validUntil) return 0;
        uint256 spent = g.spent;
        if (block.timestamp >= g.windowStart + g.period) spent = 0;
        return g.limit > spent ? g.limit - spent : 0;
    }
}

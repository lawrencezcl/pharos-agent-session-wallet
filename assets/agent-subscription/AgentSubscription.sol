// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentSubscription
/// @notice A recurring pull-payment primitive for the on-chain agent economy.
///         A service provider (which may itself be an AI agent) creates a Plan
///         (token, amountPerPeriod, period). A subscriber — or an agent acting
///         on its behalf via AgentSessionWallet.executeAsAgent — subscribes once,
///         and the provider (or any keeper/agent) calls `charge` each period to
///         pull the next fee. The subscriber can cancel instantly at any time
///         (pull-payment: funds never leave the subscriber's control until a
///         valid charge). Supports ERC-20 (approval-based) and native PHRS
///         (prefund-based) plans.
///
///         Use case: agents subscribing to recurring data feeds, APIs, or other
///         agents' services — the subscription layer x402 (per-call) cannot do.
contract AgentSubscription {
    /* ------------------------------------------------------------------ */
    /*  Errors (human-readable, for the Skill Engine)                     */
    /* ------------------------------------------------------------------ */

    error ZeroAddress();
    error InvalidParams();
    error PlanNotActive();
    error PlanNotERC20();
    error PlanNotNative();
    error AlreadySubscribed();
    error NotSubscribed();
    error NotDueYet(uint64 nextChargeAt, uint64 now_);
    error InsufficientNativePrefund();
    error TransferFailed();
    error NotProvider();
    error NotSubscriber();
    error AmountMismatch();

    /* ------------------------------------------------------------------ */
    /*  Types                                                             */
    /* ------------------------------------------------------------------ */

    /// @dev A recurring plan offered by a provider. token==address(0) => native PHRS.
    struct Plan {
        address provider; // fee recipient; only this address can pause/resume
        address token; // address(0) = native PHRS; otherwise ERC-20
        uint256 amountPerPeriod; // fee per period (token smallest unit)
        uint64 period; // seconds between charges
        bool active; // provider can deactivate to stop new subs + charges
    }

    /// @dev A subscriber's membership to a plan. Keyed by (subscriber, planId).
    struct Membership {
        uint64 nextChargeAt; // earliest timestamp the next charge is allowed
        uint64 charges; // number of successful charges so far
        uint64 cancelledAt; // 0 = active; >0 = cancelled timestamp
        bool exists;
    }

    /* ------------------------------------------------------------------ */
    /*  Storage                                                           */
    /* ------------------------------------------------------------------ */

    uint256 public nextPlanId; // 0 reserved as "none"; first real plan is 1

    mapping(uint256 => Plan) public plans;

    // subscriber => planId => Membership
    mapping(address => mapping(uint256 => Membership)) public memberships;

    // Native prefund balances: subscriber => planId => wei held for future charges.
    mapping(address => mapping(uint256 => uint256)) public nativePrefund;

    /* ------------------------------------------------------------------ */
    /*  Events (queryable with `cast logs`)                               */
    /* ------------------------------------------------------------------ */

    event PlanCreated(
        uint256 indexed planId, address indexed provider, address indexed token, uint256 amountPerPeriod, uint64 period
    );
    event Subscribed(address indexed subscriber, uint256 indexed planId, uint64 nextChargeAt);
    event Charged(
        address indexed subscriber,
        uint256 indexed planId,
        address indexed provider,
        uint256 amount,
        uint64 chargeCount,
        uint64 nextChargeAt
    );
    event Cancelled(address indexed subscriber, uint256 indexed planId, uint64 at);
    event PlanPaused(uint256 indexed planId);
    event PlanResumed(uint256 indexed planId);
    event NativePrefunded(address indexed subscriber, uint256 indexed planId, uint256 amount, uint256 totalHeld);
    event NativeRefunded(address indexed subscriber, uint256 indexed planId, uint256 amount);

    /* ------------------------------------------------------------------ */
    /*  Provider: plan lifecycle                                          */
    /* ------------------------------------------------------------------ */

    /// @notice Create a recurring plan.
    /// @param token     address(0) for native PHRS, otherwise an ERC-20 address.
    /// @param amountPerPeriod Fee charged each period.
    /// @param period    Seconds between charges. Must be > 0.
    function createPlan(address token, uint256 amountPerPeriod, uint64 period) external returns (uint256 planId) {
        if (amountPerPeriod == 0) revert InvalidParams();
        if (period == 0) revert InvalidParams();
        planId = ++nextPlanId;
        plans[planId] =
            Plan({provider: msg.sender, token: token, amountPerPeriod: amountPerPeriod, period: period, active: true});
        emit PlanCreated(planId, msg.sender, token, amountPerPeriod, period);
    }

    function pausePlan(uint256 planId) external {
        Plan storage p = plans[planId];
        if (p.provider != msg.sender) revert NotProvider();
        p.active = false;
        emit PlanPaused(planId);
    }

    function resumePlan(uint256 planId) external {
        Plan storage p = plans[planId];
        if (p.provider != msg.sender) revert NotProvider();
        p.active = true;
        emit PlanResumed(planId);
    }

    /* ------------------------------------------------------------------ */
    /*  Subscriber: subscribe / cancel / prefund                          */
    /* ------------------------------------------------------------------ */

    /// @notice Subscribe to an ERC-20 plan. Caller must have approved this
    ///         contract to spend `amountPerPeriod` (standard ERC20 approve).
    ///         Charges pull via transferFrom at each period.
    function subscribeERC20(uint256 planId) external {
        Plan storage p = plans[planId];
        if (p.amountPerPeriod == 0) revert PlanNotActive();
        if (!p.active) revert PlanNotActive();
        if (p.token == address(0)) revert PlanNotERC20();

        Membership storage m = memberships[msg.sender][planId];
        if (m.exists) revert AlreadySubscribed();

        m.exists = true;
        m.nextChargeAt = uint64(block.timestamp) + p.period;
        emit Subscribed(msg.sender, planId, m.nextChargeAt);
    }

    /// @notice Subscribe to a native-PHRS plan and prefund `numberOfPeriods`
    ///         charges in the same call. The exact wei required is
    ///         amountPerPeriod * numberOfPeriods; send it as msg.value.
    function subscribeNative(uint256 planId, uint64 numberOfPeriods) external payable {
        Plan storage p = plans[planId];
        if (p.amountPerPeriod == 0) revert PlanNotActive();
        if (!p.active) revert PlanNotActive();
        if (p.token != address(0)) revert PlanNotNative();
        if (numberOfPeriods == 0) revert InvalidParams();

        Membership storage m = memberships[msg.sender][planId];
        if (m.exists) revert AlreadySubscribed();

        uint256 required = p.amountPerPeriod * numberOfPeriods;
        if (msg.value != required) revert AmountMismatch();

        m.exists = true;
        m.nextChargeAt = uint64(block.timestamp) + p.period;
        nativePrefund[msg.sender][planId] += required;
        emit Subscribed(msg.sender, planId, m.nextChargeAt);
        emit NativePrefunded(msg.sender, planId, required, nativePrefund[msg.sender][planId]);
    }

    /// @notice Top up the prefund for an active native subscription.
    function prefundNative(uint256 planId, uint64 numberOfPeriods) external payable {
        Plan storage p = plans[planId];
        if (p.amountPerPeriod == 0) revert PlanNotActive();
        if (p.token != address(0)) revert PlanNotNative();
        if (numberOfPeriods == 0) revert InvalidParams();
        uint256 required = p.amountPerPeriod * numberOfPeriods;
        if (msg.value != required) revert AmountMismatch();
        nativePrefund[msg.sender][planId] += required;
        emit NativePrefunded(msg.sender, planId, required, nativePrefund[msg.sender][planId]);
    }

    /// @notice Subscriber cancels future charges immediately. For native plans,
    ///         any remaining prefund is refunded in the same call.
    function cancel(uint256 planId) external {
        Membership storage m = memberships[msg.sender][planId];
        if (!m.exists) revert NotSubscribed();
        if (m.cancelledAt != 0) revert NotSubscribed();
        m.cancelledAt = uint64(block.timestamp);
        emit Cancelled(msg.sender, planId, m.cancelledAt);

        Plan storage p = plans[planId];
        if (p.token == address(0)) {
            uint256 refund = nativePrefund[msg.sender][planId];
            if (refund > 0) {
                nativePrefund[msg.sender][planId] = 0;
                (bool ok,) = payable(msg.sender).call{value: refund}("");
                if (!ok) revert TransferFailed();
                emit NativeRefunded(msg.sender, planId, refund);
            }
        }
    }

    /* ------------------------------------------------------------------ */
    /*  Provider / keeper / agent: pull a charge                          */
    /* ------------------------------------------------------------------ */

    /// @notice Charge one period if due. Anyone may call (keeper/agent), funds
    ///         always go to the plan provider. No-op-safe if not due.
    function charge(address subscriber, uint256 planId) external returns (uint256 chargedAmount) {
        Plan storage p = plans[planId];
        if (p.amountPerPeriod == 0 || !p.active) revert PlanNotActive();
        Membership storage m = memberships[subscriber][planId];
        if (!m.exists || m.cancelledAt != 0) revert NotSubscribed();
        if (block.timestamp < m.nextChargeAt) {
            revert NotDueYet(m.nextChargeAt, uint64(block.timestamp));
        }

        chargedAmount = p.amountPerPeriod;
        m.charges += 1;
        m.nextChargeAt += p.period;

        if (p.token == address(0)) {
            uint256 held = nativePrefund[subscriber][planId];
            if (held < chargedAmount) revert InsufficientNativePrefund();
            nativePrefund[subscriber][planId] = held - chargedAmount;
            (bool ok,) = payable(p.provider).call{value: chargedAmount}("");
            if (!ok) revert TransferFailed();
        } else {
            (bool ok, bytes memory ret) =
                p.token
                    .call(
                        abi.encodeWithSelector(0x23b872dd, subscriber, p.provider, chargedAmount) // transferFrom
                    );
            if (!ok || (ret.length != 0 && !abi.decode(ret, (bool)))) revert TransferFailed();
        }

        emit Charged(subscriber, planId, p.provider, chargedAmount, m.charges, m.nextChargeAt);
    }

    /* ------------------------------------------------------------------ */
    /*  Views (agent-friendly, for `cast call`)                           */
    /* ------------------------------------------------------------------ */

    function getPlan(uint256 planId) external view returns (Plan memory) {
        return plans[planId];
    }

    function getMembership(address subscriber, uint256 planId) external view returns (Membership memory) {
        return memberships[subscriber][planId];
    }

    /// @notice Is the subscriber active (subscribed and not cancelled)?
    function isSubscriberActive(address subscriber, uint256 planId) external view returns (bool) {
        Membership storage m = memberships[subscriber][planId];
        return m.exists && m.cancelledAt == 0;
    }

    /// @notice Seconds until the next charge is allowed (0 = due now).
    function secondsUntilDue(address subscriber, uint256 planId) external view returns (int256) {
        Membership storage m = memberships[subscriber][planId];
        if (!m.exists) return -1;
        if (block.timestamp >= m.nextChargeAt) return 0;
        return int256(uint256(m.nextChargeAt)) - int256(block.timestamp);
    }

    function nativePrefundOf(address subscriber, uint256 planId) external view returns (uint256) {
        return nativePrefund[subscriber][planId];
    }
}

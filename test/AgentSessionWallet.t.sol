// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentSessionWallet} from "../src/AgentSessionWallet.sol";

/// @title Minimal ERC20 mock for spend-limit tests.
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _sym) {
        name = _name;
        symbol = _sym;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract AgentSessionWalletTest is Test {
    AgentSessionWallet internal wallet;
    MockERC20 internal token;

    address internal owner = address(0x0F1);
    address internal agent = address(0xA6E);
    address internal recipient = address(0xBEE);
    address internal attacker = address(0xE11);

    bytes4 internal constant TRANSFER_SELECTOR = 0xa9059cbb;

    function setUp() public {
        wallet = new AgentSessionWallet(owner);
        token = new MockERC20("Test", "TST");
        vm.deal(address(wallet), 100 ether);
        token.mint(address(wallet), 1_000_000e18);
        vm.deal(owner, 10 ether);
        vm.deal(agent, 1 ether);
    }

    /* -------------------- access control -------------------- */

    function test_RevertIfNonOwnerExecutes() public {
        AgentSessionWallet.Call[] memory calls = _empty();
        vm.prank(attacker);
        vm.expectRevert(AgentSessionWallet.NotOwner.selector);
        wallet.execute(calls);
    }

    function test_RevertIfNonOwnerRevokes() public {
        vm.prank(attacker);
        vm.expectRevert(AgentSessionWallet.NotOwner.selector);
        wallet.revokeSessionKey(agent, address(0));
    }

    function test_RevertIfNonOwnerGrants() public {
        vm.prank(attacker);
        vm.expectRevert(AgentSessionWallet.NotOwner.selector);
        wallet.grantSessionKey(agent, address(0), uint96(block.timestamp + 1 days), 1 days, 1 ether);
    }

    function test_RevertZeroOwner() public {
        vm.expectRevert(AgentSessionWallet.ZeroAddress.selector);
        new AgentSessionWallet(address(0));
    }

    /* -------------------- grants & spend limits -------------------- */

    function test_GrantAndSpendNative() public {
        _grantNative(agent, uint96(block.timestamp + 1 days), 1 days, 1 ether);

        AgentSessionWallet.Call[] memory calls = _nativeCall(recipient, 0.4 ether);
        uint256 before = recipient.balance;
        vm.prank(agent);
        wallet.executeAsAgent(calls);
        assertEq(recipient.balance - before, 0.4 ether);
        assertEq(_spent(agent, address(0)), 0.4 ether);
    }

    function test_RevertSpendLimitExceeded() public {
        _grantNative(agent, uint96(block.timestamp + 1 days), 1 days, 0.5 ether);
        AgentSessionWallet.Call[] memory calls = _nativeCall(recipient, 0.6 ether);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentSessionWallet.SpendLimitExceeded.selector, 0.6 ether, 0.5 ether));
        wallet.executeAsAgent(calls);
    }

    function test_RevertInactiveSessionKey() public {
        AgentSessionWallet.Call[] memory calls = _nativeCall(recipient, 0.1 ether);
        vm.prank(agent);
        vm.expectRevert(AgentSessionWallet.SessionKeyInactive.selector);
        wallet.executeAsAgent(calls);
    }

    function test_RevertExpiredSessionKey() public {
        _grantNative(agent, uint96(block.timestamp + 1 hours), 1 days, 1 ether);
        vm.warp(block.timestamp + 2 hours);
        AgentSessionWallet.Call[] memory calls = _nativeCall(recipient, 0.1 ether);
        vm.prank(agent);
        vm.expectRevert(AgentSessionWallet.SessionKeyExpired.selector);
        wallet.executeAsAgent(calls);
    }

    /* -------------------- window rollover -------------------- */

    function test_WindowResetsAfterPeriod() public {
        _grantNative(agent, uint96(block.timestamp + 2 days), 1 days, 1 ether);

        _agentSpendNative(0.8 ether);
        assertEq(_spent(agent, address(0)), 0.8 ether);
        assertEq(wallet.spendAvailable(agent, address(0)), 0.2 ether);

        vm.warp(block.timestamp + 1 days + 1);
        assertEq(wallet.spendAvailable(agent, address(0)), 1 ether);

        _agentSpendNative(1 ether);
        assertEq(_spent(agent, address(0)), 1 ether);
    }

    /* -------------------- revocation -------------------- */

    function test_RevokeKillsSessionKey() public {
        _grantNative(agent, uint96(block.timestamp + 1 days), 1 days, 1 ether);
        vm.prank(owner);
        wallet.revokeSessionKey(agent, address(0));
        assertFalse(wallet.isSessionKeyActive(agent, address(0)));

        AgentSessionWallet.Call[] memory calls = _nativeCall(recipient, 0.1 ether);
        vm.prank(agent);
        vm.expectRevert(AgentSessionWallet.SessionKeyInactive.selector);
        wallet.executeAsAgent(calls);
    }

    /* -------------------- ERC-20 spend enforcement -------------------- */

    function test_ERC20SpendEnforced() public {
        vm.startPrank(owner);
        wallet.grantSessionKey(agent, address(token), uint96(block.timestamp + 1 days), 1 days, 100e18);
        vm.stopPrank();

        AgentSessionWallet.Call[] memory calls = _erc20TransferCall(recipient, 30e18);
        uint256 before = token.balanceOf(recipient);
        vm.prank(agent);
        wallet.executeAsAgent(calls);
        assertEq(token.balanceOf(recipient) - before, 30e18);
        assertEq(_spent(agent, address(token)), 30e18);
    }

    function test_ERC20SpendLimitExceeded() public {
        vm.startPrank(owner);
        wallet.grantSessionKey(agent, address(token), uint96(block.timestamp + 1 days), 1 days, 20e18);
        vm.stopPrank();

        AgentSessionWallet.Call[] memory calls = _erc20TransferCall(recipient, 50e18);
        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(AgentSessionWallet.SpendLimitExceeded.selector, 50e18, 20e18));
        wallet.executeAsAgent(calls);
    }

    /* -------------------- batching -------------------- */

    function test_BatchMixedNativeAndERC20() public {
        vm.startPrank(owner);
        wallet.grantSessionKey(agent, address(0), uint96(block.timestamp + 1 days), 1 days, 1 ether);
        wallet.grantSessionKey(agent, address(token), uint96(block.timestamp + 1 days), 1 days, 100e18);
        vm.stopPrank();

        AgentSessionWallet.Call[] memory calls = new AgentSessionWallet.Call[](2);
        calls[0] = AgentSessionWallet.Call({target: recipient, value: 0.3 ether, data: ""});
        calls[1] = _erc20TransferSingle(recipient, 25e18);

        uint256 natBefore = recipient.balance;
        uint256 tokBefore = token.balanceOf(recipient);
        vm.prank(agent);
        wallet.executeAsAgent(calls);

        assertEq(recipient.balance - natBefore, 0.3 ether);
        assertEq(token.balanceOf(recipient) - tokBefore, 25e18);
        assertEq(_spent(agent, address(0)), 0.3 ether);
        assertEq(_spent(agent, address(token)), 25e18);
    }

    /* -------------------- owner escape hatch -------------------- */

    function test_OwnerWithdrawNative() public {
        uint256 before = recipient.balance;
        vm.prank(owner);
        wallet.withdraw(address(0), 5 ether, recipient);
        assertEq(recipient.balance - before, 5 ether);
    }

    function test_OwnerWithdrawERC20() public {
        uint256 before = token.balanceOf(recipient);
        vm.prank(owner);
        wallet.withdraw(address(token), 500e18, recipient);
        assertEq(token.balanceOf(recipient) - before, 500e18);
    }

    function test_OwnerExecuteBatch() public {
        AgentSessionWallet.Call[] memory calls = _nativeCall(recipient, 7 ether);
        uint256 before = recipient.balance;
        vm.prank(owner);
        wallet.execute(calls);
        assertEq(recipient.balance - before, 7 ether);
    }

    function test_DepositEmitsEvent() public {
        address funder = address(0xC0F);
        vm.deal(funder, 2 ether);
        vm.expectEmit(true, false, false, true);
        emit AgentSessionWallet.Deposited(funder, 2 ether);
        vm.prank(funder);
        (bool ok,) = address(wallet).call{value: 2 ether}("");
        assertTrue(ok);
    }

    /* -------------------- helpers -------------------- */

    function _grantNative(address op, uint96 until, uint64 period, uint256 limit) internal {
        vm.prank(owner);
        wallet.grantSessionKey(op, address(0), until, period, limit);
    }

    function _agentSpendNative(uint256 amount) internal {
        AgentSessionWallet.Call[] memory calls = _nativeCall(recipient, amount);
        vm.prank(agent);
        wallet.executeAsAgent(calls);
    }

    function _spent(address op, address tkn) internal view returns (uint256) {
        (,,,, uint256 spent) = _unpackGrant(op, tkn);
        return spent;
    }

    function _unpackGrant(address op, address tkn) internal view returns (uint96, uint64, uint64, uint256, uint256) {
        (uint96 validUntil, uint64 period, uint64 windowStart, uint256 limit, uint256 spent) = wallet.grants(op, tkn);
        return (validUntil, period, windowStart, limit, spent);
    }

    function _empty() internal pure returns (AgentSessionWallet.Call[] memory) {
        return new AgentSessionWallet.Call[](0);
    }

    function _nativeCall(address to, uint256 amount) internal pure returns (AgentSessionWallet.Call[] memory) {
        AgentSessionWallet.Call[] memory calls = new AgentSessionWallet.Call[](1);
        calls[0] = AgentSessionWallet.Call({target: to, value: amount, data: ""});
        return calls;
    }

    function _erc20TransferCall(address to, uint256 amount) internal view returns (AgentSessionWallet.Call[] memory) {
        AgentSessionWallet.Call[] memory calls = new AgentSessionWallet.Call[](1);
        calls[0] = _erc20TransferSingle(to, amount);
        return calls;
    }

    function _erc20TransferSingle(address to, uint256 amount) internal view returns (AgentSessionWallet.Call memory) {
        return AgentSessionWallet.Call({
            target: address(token), value: 0, data: abi.encodeWithSelector(TRANSFER_SELECTOR, to, amount)
        });
    }
}

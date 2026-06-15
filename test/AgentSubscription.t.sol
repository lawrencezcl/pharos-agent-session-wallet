// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentSubscription} from "../src/AgentSubscription.sol";

contract MockERC20Sub {
    string public name = "TST";
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _xfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        return _xfer(from, to, amount);
    }

    function _xfer(address from, address to, uint256 amount) internal returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract AgentSubscriptionTest is Test {
    AgentSubscription internal sub;
    MockERC20Sub internal token;

    address internal provider = address(0xB0B);
    address internal subscriber = address(0x5A);
    address internal keeper = address(0x4BEE);

    function setUp() public {
        sub = new AgentSubscription();
        token = new MockERC20Sub();
        vm.deal(subscriber, 100 ether);
        token.mint(subscriber, 1_000_000e18);
    }

    /* -------------------- plan creation -------------------- */

    function test_CreatePlanERC20() public {
        vm.prank(provider);
        uint256 id = sub.createPlan(address(token), 5e18, 1 days);
        assertEq(id, 1);
        (address p, address t, uint256 amt, uint64 per, bool active) = _plan(id);
        assertEq(p, provider);
        assertEq(t, address(token));
        assertEq(amt, 5e18);
        assertEq(per, 1 days);
        assertTrue(active);
    }

    function test_RevertCreatePlanZeroAmount() public {
        vm.prank(provider);
        vm.expectRevert(AgentSubscription.InvalidParams.selector);
        sub.createPlan(address(token), 0, 1 days);
    }

    function test_RevertCreatePlanZeroPeriod() public {
        vm.prank(provider);
        vm.expectRevert(AgentSubscription.InvalidParams.selector);
        sub.createPlan(address(token), 5e18, 0);
    }

    /* -------------------- ERC20 subscribe + charge -------------------- */

    function test_ERC20SubscribeAndChargeAfterPeriod() public {
        uint256 id = _erc20Plan(provider);
        vm.startPrank(subscriber);
        token.approve(address(sub), 5e18);
        sub.subscribeERC20(id);
        vm.stopPrank();

        // not due yet
        vm.prank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                AgentSubscription.NotDueYet.selector, uint64(block.timestamp + 1 days), uint64(block.timestamp)
            )
        );
        sub.charge(subscriber, id);

        // warp forward, charge succeeds
        vm.warp(block.timestamp + 1 days + 1);
        uint256 provBefore = token.balanceOf(provider);
        vm.prank(keeper);
        sub.charge(subscriber, id);
        assertEq(token.balanceOf(provider) - provBefore, 5e18);

        (, uint64 charges,, bool exists) = _membership(subscriber, id);
        assertEq(charges, 1);
        assertTrue(exists);
    }

    function test_RevertERC20SubscribeTwice() public {
        uint256 id = _erc20Plan(provider);
        vm.startPrank(subscriber);
        token.approve(address(sub), 5e18);
        sub.subscribeERC20(id);
        vm.expectRevert(AgentSubscription.AlreadySubscribed.selector);
        sub.subscribeERC20(id);
        vm.stopPrank();
    }

    function test_RevertERC20SubscribeToNativePlan() public {
        uint256 id = _nativePlan(provider);
        vm.prank(subscriber);
        vm.expectRevert(AgentSubscription.PlanNotERC20.selector);
        sub.subscribeERC20(id);
    }

    /* -------------------- native subscribe + charge -------------------- */

    function test_NativeSubscribePrefundAndCharge() public {
        uint256 id = _nativePlan(provider); // 0.1 PHRS / day
        vm.startPrank(subscriber);
        sub.subscribeNative{value: 0.3 ether}(id, 3); // 3 periods
        assertEq(sub.nativePrefundOf(subscriber, id), 0.3 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        uint256 provBefore = provider.balance;
        vm.prank(keeper);
        sub.charge(subscriber, id);
        assertEq(provider.balance - provBefore, 0.1 ether);
        assertEq(sub.nativePrefundOf(subscriber, id), 0.2 ether);

        (, uint64 charges,,) = _membership(subscriber, id);
        assertEq(charges, 1);
    }

    function test_RevertNativeAmountMismatch() public {
        uint256 id = _nativePlan(provider);
        vm.prank(subscriber);
        vm.expectRevert(AgentSubscription.AmountMismatch.selector);
        sub.subscribeNative{value: 0.2 ether}(id, 3); // needs 0.3
    }

    function test_RevertNativeChargeInsufficientPrefund() public {
        uint256 id = _nativePlan(provider);
        vm.startPrank(subscriber);
        sub.subscribeNative{value: 0.1 ether}(id, 1); // only 1 period
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(keeper);
        sub.charge(subscriber, id); // consumes the 1 period

        vm.warp(block.timestamp + 1 days);
        vm.prank(keeper);
        vm.expectRevert(AgentSubscription.InsufficientNativePrefund.selector);
        sub.charge(subscriber, id);
    }

    /* -------------------- cancel + refund -------------------- */

    function test_NativeCancelRefundsRemainingPrefund() public {
        uint256 id = _nativePlan(provider);
        vm.startPrank(subscriber);
        sub.subscribeNative{value: 0.3 ether}(id, 3);
        vm.warp(block.timestamp + 1 days + 1);

        // one charge first
        vm.stopPrank();
        vm.prank(keeper);
        sub.charge(subscriber, id); // prefund now 0.2

        // subscriber cancels, gets 0.2 back
        uint256 subBefore = subscriber.balance;
        vm.prank(subscriber);
        sub.cancel(id);
        assertEq(subscriber.balance - subBefore, 0.2 ether);
        assertFalse(sub.isSubscriberActive(subscriber, id));
        assertEq(sub.nativePrefundOf(subscriber, id), 0);

        // keeper can no longer charge
        vm.warp(block.timestamp + 1 days);
        vm.prank(keeper);
        vm.expectRevert(AgentSubscription.NotSubscribed.selector);
        sub.charge(subscriber, id);
    }

    function test_ERC20CancelStopsFutureCharges() public {
        uint256 id = _erc20Plan(provider);
        vm.startPrank(subscriber);
        token.approve(address(sub), 5e18);
        sub.subscribeERC20(id);
        sub.cancel(id);
        vm.stopPrank();
        assertFalse(sub.isSubscriberActive(subscriber, id));

        vm.warp(block.timestamp + 2 days);
        vm.prank(keeper);
        vm.expectRevert(AgentSubscription.NotSubscribed.selector);
        sub.charge(subscriber, id);
    }

    function test_RevertCancelNotSubscribed() public {
        uint256 id = _erc20Plan(provider);
        vm.prank(subscriber);
        vm.expectRevert(AgentSubscription.NotSubscribed.selector);
        sub.cancel(id);
    }

    /* -------------------- pause / resume -------------------- */

    function test_PauseStopsNewSubsAndCharges() public {
        uint256 id = _erc20Plan(provider);
        vm.prank(provider);
        sub.pausePlan(id);

        vm.startPrank(subscriber);
        token.approve(address(sub), 5e18);
        vm.expectRevert(AgentSubscription.PlanNotActive.selector);
        sub.subscribeERC20(id);
        vm.stopPrank();
    }

    function test_RevertPauseByNonProvider() public {
        uint256 id = _erc20Plan(provider);
        vm.prank(subscriber);
        vm.expectRevert(AgentSubscription.NotProvider.selector);
        sub.pausePlan(id);
    }

    /* -------------------- views -------------------- */

    function test_SecondsUntilDue() public {
        uint256 id = _erc20Plan(provider);
        vm.startPrank(subscriber);
        token.approve(address(sub), 5e18);
        sub.subscribeERC20(id);
        vm.stopPrank();

        assertEq(sub.secondsUntilDue(subscriber, id), int256(uint256(1 days)));
        vm.warp(block.timestamp + 1 days + 5);
        assertEq(sub.secondsUntilDue(subscriber, id), 0);
    }

    function test_SecondsUntilDueNotSubscribed() public {
        uint256 id = _erc20Plan(provider);
        assertEq(sub.secondsUntilDue(subscriber, id), -1);
    }

    /* -------------------- helpers -------------------- */

    function _erc20Plan(address who) internal returns (uint256) {
        vm.prank(who);
        return sub.createPlan(address(token), 5e18, 1 days);
    }

    function _nativePlan(address who) internal returns (uint256) {
        vm.prank(who);
        // 0.1 PHRS (1e17 wei) per day
        return sub.createPlan(address(0), 0.1 ether, 1 days);
    }

    function _plan(uint256 id) internal view returns (address, address, uint256, uint64, bool) {
        (address provider, address token, uint256 amt, uint64 per, bool active) = sub.plans(id);
        return (provider, token, amt, per, active);
    }

    function _membership(address who, uint256 id) internal view returns (uint64, uint64, uint64, bool) {
        (uint64 nextChargeAt, uint64 charges, uint64 cancelledAt, bool exists) = sub.memberships(who, id);
        return (nextChargeAt, charges, cancelledAt, exists);
    }
}

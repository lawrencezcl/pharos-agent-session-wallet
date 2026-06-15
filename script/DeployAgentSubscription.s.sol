// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentSubscription} from "../src/AgentSubscription.sol";

/// @notice Deploy AgentSubscription. No constructor args.
///   forge script script/DeployAgentSubscription.s.sol:DeployAgentSubscription \
///     --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
contract DeployAgentSubscription is Script {
    function run() external {
        vm.startBroadcast();
        AgentSubscription sub = new AgentSubscription();
        vm.stopBroadcast();

        console.log("=== Deploy Result ===");
        console.log("AgentSubscription address:", address(sub));
        console.log("Deployer:", msg.sender);
        console.log("Chain ID:", block.chainid);
    }
}

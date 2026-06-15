// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentSessionWallet} from "../src/AgentSessionWallet.sol";

/// @notice Deploy AgentSessionWallet. The wallet owner defaults to the deployer
///         unless OWNER_ADDRESS is provided.
///         Usage:
///           forge script script/DeployAgentSessionWallet.s.sol:DeployAgentSessionWallet \
///             --rpc-url $RPC --private-key $PRIVATE_KEY --broadcast
contract DeployAgentSessionWallet is Script {
    function run() external {
        address owner = vm.envOr("OWNER_ADDRESS", msg.sender);
        if (owner == address(0)) owner = msg.sender;

        vm.startBroadcast();
        AgentSessionWallet wallet = new AgentSessionWallet(owner);
        vm.stopBroadcast();

        console.log("=== Deploy Result ===");
        console.log("Wallet address:", address(wallet));
        console.log("Owner:", wallet.owner());
        console.log("Deployer:", msg.sender);
        console.log("Chain ID:", block.chainid);
    }
}

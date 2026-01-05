// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/ReputationManager.sol";
import "../src/AgentEscrow.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying Aura-Market contracts...");
        console.log("Deployer:", vm.addr(deployerPrivateKey));

        AgentRegistry registry = new AgentRegistry();
        console.log("AgentRegistry deployed at:", address(registry));

        ReputationManager reputationManager = new ReputationManager(address(registry));
        console.log("ReputationManager deployed at:", address(reputationManager));

        AgentEscrow escrow = new AgentEscrow(
            address(registry),
            address(reputationManager)
        );
        console.log("AgentEscrow deployed at:", address(escrow));

        registry.authorizeManager(address(escrow));
        console.log("AgentEscrow authorized in Registry");

        registry.authorizeManager(address(reputationManager));
        console.log("ReputationManager authorized in Registry");

        reputationManager.authorizeContract(address(escrow));
        console.log("AgentEscrow authorized in ReputationManager");

        console.log("\n=== Deployment Complete ===");
        console.log("AgentRegistry:", address(registry));
        console.log("ReputationManager:", address(reputationManager));
        console.log("AgentEscrow:", address(escrow));

        vm.stopBroadcast();
    }
}

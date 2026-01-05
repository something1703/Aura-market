// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/AgentRegistry.sol";
import "../src/AgentEscrow.sol";

contract SetupDemoScript is Script {
    function run() external {
        address registryAddress = vm.envAddress("REGISTRY_ADDRESS");
        address escrowAddress = vm.envAddress("ESCROW_ADDRESS");
        
        uint256 agentAKey = vm.envUint("AGENT_A_KEY");
        uint256 agentBKey = vm.envUint("AGENT_B_KEY");

        AgentRegistry registry = AgentRegistry(registryAddress);
        AgentEscrow escrow = AgentEscrow(payable(escrowAddress));

        console.log("Setting up demo agents...");

        vm.startBroadcast(agentAKey);
        registry.registerAgent{value: 0.1 ether}(
            "ipfs://QmAgentAMetadata",
            "orchestration,project-management",
            "https://agent-a.api/mcp"
        );
        console.log("Agent A registered:", vm.addr(agentAKey));
        vm.stopBroadcast();

        vm.startBroadcast(agentBKey);
        registry.registerAgent{value: 0.2 ether}(
            "ipfs://QmAgentBMetadata",
            "security-audit,code-review,solidity",
            "https://agent-b.api/mcp"
        );
        console.log("Agent B registered:", vm.addr(agentBKey));
        vm.stopBroadcast();

        vm.startBroadcast(agentAKey);
        uint256 jobId = escrow.createJob{value: 1 ether}(
            vm.addr(agentBKey),
            block.timestamp + 7 days
        );
        console.log("Job created with ID:", jobId);
        vm.stopBroadcast();

        console.log("\n=== Demo Setup Complete ===");
    }
}

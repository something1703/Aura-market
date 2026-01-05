// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";
import "../src/ReputationManager.sol";
import "../src/AgentEscrow.sol";

contract IntegrationTest is Test {
    AgentRegistry public registry;
    ReputationManager public reputationManager;
    AgentEscrow public escrow;

    address public master = address(0x1);
    address public worker = address(0x2);
    address public subcontractor = address(0x3);

    function setUp() public {
        registry = new AgentRegistry();
        reputationManager = new ReputationManager(address(registry));
        escrow = new AgentEscrow(address(registry), address(reputationManager));

        registry.authorizeManager(address(escrow));
        registry.authorizeManager(address(reputationManager));
        reputationManager.authorizeContract(address(escrow));

        escrow.setPlatformFeeRecipient(address(0x4));

        vm.deal(master, 100 ether);
        vm.deal(worker, 100 ether);
        vm.deal(subcontractor, 100 ether);
    }

    function testCompleteWorkflowSuccess() public {
        vm.prank(master);
        registry.registerAgent{value: 1 ether}(
            "ipfs://master-metadata",
            "orchestration,management",
            "https://master.api"
        );

        vm.prank(worker);
        registry.registerAgent{value: 2 ether}(
            "ipfs://worker-metadata",
            "security-audit,code-review",
            "https://worker.api"
        );

        assertEq(registry.getAgentCount(), 2);

        vm.prank(master);
        uint256 jobId = escrow.createJob{value: 5 ether}(
            worker,
            block.timestamp + 7 days
        );

        AgentEscrow.Job memory job = escrow.getJob(jobId);
        assertEq(job.master, master);
        assertEq(job.worker, worker);
        assertEq(job.price, 5 ether);
        assertTrue(job.state == AgentEscrow.JobState.CREATED);

        vm.prank(worker);
        escrow.acceptJob(jobId);

        job = escrow.getJob(jobId);
        assertTrue(job.state == AgentEscrow.JobState.ACCEPTED);

        bytes32 outputHash = keccak256("audit-report-complete");
        string memory proofRef = "ipfs://QmAuditProof123";

        vm.prank(worker);
        escrow.submitResult(jobId, outputHash, proofRef);

        job = escrow.getJob(jobId);
        assertTrue(job.state == AgentEscrow.JobState.SUBMITTED);
        assertEq(job.outputHash, outputHash);

        uint256 workerBalanceBefore = worker.balance;

        vm.prank(master);
        escrow.approveAndRelease(jobId);

        uint256 workerBalanceAfter = worker.balance;
        uint256 expectedPayment = 5 ether * 98 / 100;

        assertEq(workerBalanceAfter - workerBalanceBefore, expectedPayment);

        job = escrow.getJob(jobId);
        assertTrue(job.state == AgentEscrow.JobState.APPROVED);
        assertTrue(job.fundsReleased);

        ReputationManager.ReputationData memory rep = reputationManager.getReputation(worker);
        assertEq(rep.score, 10);
        assertEq(rep.completedJobs, 1);
        assertEq(rep.failedJobs, 0);
        assertEq(rep.totalEarned, expectedPayment);
    }

    function testCompleteWorkflowRejection() public {
        vm.prank(master);
        registry.registerAgent{value: 1 ether}(
            "ipfs://master",
            "orchestration",
            "https://master.api"
        );

        vm.prank(worker);
        registry.registerAgent{value: 2 ether}(
            "ipfs://worker",
            "audit",
            "https://worker.api"
        );

        vm.prank(master);
        uint256 jobId = escrow.createJob{value: 3 ether}(
            worker,
            block.timestamp + 7 days
        );

        vm.prank(worker);
        escrow.acceptJob(jobId);

        vm.prank(worker);
        escrow.submitResult(jobId, keccak256("bad-work"), "ipfs://bad");

        uint256 masterBalanceBefore = master.balance;
        uint256 workerStakeBefore = registry.getAgent(worker).stakeAmount;

        vm.prank(master);
        escrow.rejectAndSlash(jobId, 0.5 ether);

        uint256 masterBalanceAfter = master.balance;
        uint256 workerStakeAfter = registry.getAgent(worker).stakeAmount;

        assertEq(masterBalanceAfter - masterBalanceBefore, 3 ether);
        assertEq(workerStakeBefore - workerStakeAfter, 0.5 ether);

        ReputationManager.ReputationData memory rep = reputationManager.getReputation(worker);
        assertEq(rep.failedJobs, 1);
        assertEq(rep.slashCount, 1);
    }

    function testMultiAgentSubcontracting() public {
        vm.prank(master);
        registry.registerAgent{value: 1 ether}(
            "ipfs://master",
            "orchestration",
            "https://master.api"
        );

        vm.prank(worker);
        registry.registerAgent{value: 2 ether}(
            "ipfs://worker",
            "audit",
            "https://worker.api"
        );

        vm.prank(subcontractor);
        registry.registerAgent{value: 1.5 ether}(
            "ipfs://subcontractor",
            "documentation",
            "https://subcontractor.api"
        );

        vm.prank(master);
        uint256 jobId1 = escrow.createJob{value: 10 ether}(
            worker,
            block.timestamp + 14 days
        );

        vm.prank(worker);
        escrow.acceptJob(jobId1);

        vm.prank(worker);
        uint256 jobId2 = escrow.createJob{value: 3 ether}(
            subcontractor,
            block.timestamp + 7 days
        );

        vm.prank(subcontractor);
        escrow.acceptJob(jobId2);

        vm.prank(subcontractor);
        escrow.submitResult(jobId2, keccak256("documentation"), "ipfs://docs");

        uint256 subcontractorBalanceBefore = subcontractor.balance;

        vm.prank(worker);
        escrow.approveAndRelease(jobId2);

        uint256 subcontractorBalanceAfter = subcontractor.balance;
        assertEq(subcontractorBalanceAfter - subcontractorBalanceBefore, 3 ether * 98 / 100);

        vm.prank(worker);
        escrow.submitResult(jobId1, keccak256("audit-with-docs"), "ipfs://audit");

        uint256 workerBalanceBefore = worker.balance;

        vm.prank(master);
        escrow.approveAndRelease(jobId1);

        uint256 workerBalanceAfter = worker.balance;
        assertEq(workerBalanceAfter - workerBalanceBefore, 10 ether * 98 / 100);

        ReputationManager.ReputationData memory workerRep = reputationManager.getReputation(worker);
        assertEq(workerRep.completedJobs, 2);

        ReputationManager.ReputationData memory subRep = reputationManager.getReputation(subcontractor);
        assertEq(subRep.completedJobs, 1);
    }

    function testJobCancellation() public {
        vm.prank(master);
        registry.registerAgent{value: 1 ether}(
            "ipfs://master",
            "orchestration",
            "https://master.api"
        );

        vm.prank(worker);
        registry.registerAgent{value: 1 ether}(
            "ipfs://worker",
            "audit",
            "https://worker.api"
        );

        vm.prank(master);
        uint256 jobId = escrow.createJob{value: 2 ether}(
            worker,
            block.timestamp + 7 days
        );

        uint256 masterBalanceBefore = master.balance;

        vm.prank(master);
        escrow.cancelJob(jobId);

        uint256 masterBalanceAfter = master.balance;
        assertEq(masterBalanceAfter - masterBalanceBefore, 2 ether);

        AgentEscrow.Job memory job = escrow.getJob(jobId);
        assertTrue(job.state == AgentEscrow.JobState.CANCELLED);
    }

    function testReputationImpactsDiscovery() public {
        vm.prank(worker);
        registry.registerAgent{value: 1 ether}(
            "ipfs://worker",
            "audit",
            "https://worker.api"
        );

        vm.prank(master);
        registry.registerAgent{value: 1 ether}(
            "ipfs://master",
            "orchestration",
            "https://master.api"
        );

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(master);
            uint256 jobId = escrow.createJob{value: 1 ether}(
                worker,
                block.timestamp + 7 days
            );

            vm.prank(worker);
            escrow.acceptJob(jobId);

            vm.prank(worker);
            escrow.submitResult(jobId, keccak256(abi.encodePacked(i)), "ipfs://proof");

            vm.prank(master);
            escrow.approveAndRelease(jobId);
        }

        ReputationManager.ReputationData memory rep = reputationManager.getReputation(worker);
        assertEq(rep.completedJobs, 5);
        assertEq(rep.score, 50);

        uint256 trustScore = reputationManager.getTrustScore(worker);
        assertGt(trustScore, 40);
    }

    function testStakeManagement() public {
        vm.prank(worker);
        registry.registerAgent{value: 1 ether}(
            "ipfs://worker",
            "audit",
            "https://worker.api"
        );

        AgentRegistry.AgentProfile memory profile = registry.getAgent(worker);
        assertEq(profile.stakeAmount, 1 ether);

        vm.prank(worker);
        registry.depositStake{value: 2 ether}();

        profile = registry.getAgent(worker);
        assertEq(profile.stakeAmount, 3 ether);

        vm.prank(worker);
        registry.withdrawStake(2 ether);

        profile = registry.getAgent(worker);
        assertEq(profile.stakeAmount, 1 ether);
    }

    function testQueryFunctions() public {
        vm.prank(master);
        registry.registerAgent{value: 1 ether}(
            "ipfs://master",
            "orchestration",
            "https://master.api"
        );

        vm.prank(worker);
        registry.registerAgent{value: 1 ether}(
            "ipfs://worker",
            "audit",
            "https://worker.api"
        );

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(master);
            escrow.createJob{value: 1 ether}(
                worker,
                block.timestamp + 7 days
            );
        }

        uint256[] memory masterJobs = escrow.getJobsByMaster(master, 10);
        assertEq(masterJobs.length, 3);

        uint256[] memory workerJobs = escrow.getJobsByWorker(worker, 10);
        assertEq(workerJobs.length, 3);
    }

    function testDeadlineEnforcement() public {
        vm.prank(master);
        registry.registerAgent{value: 1 ether}(
            "ipfs://master",
            "orchestration",
            "https://master.api"
        );

        vm.prank(worker);
        registry.registerAgent{value: 1 ether}(
            "ipfs://worker",
            "audit",
            "https://worker.api"
        );

        vm.prank(master);
        uint256 jobId = escrow.createJob{value: 1 ether}(
            worker,
            block.timestamp + 1 days
        );

        vm.prank(worker);
        escrow.acceptJob(jobId);

        vm.warp(block.timestamp + 2 days);

        vm.prank(worker);
        vm.expectRevert(AgentEscrow.DeadlinePassed.selector);
        escrow.submitResult(jobId, keccak256("late"), "ipfs://late");

        vm.prank(master);
        escrow.cancelJob(jobId);

        AgentEscrow.Job memory job = escrow.getJob(jobId);
        assertTrue(job.state == AgentEscrow.JobState.CANCELLED);
    }
}

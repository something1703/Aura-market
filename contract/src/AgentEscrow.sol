// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "./interfaces/IAgentRegistry.sol";
import "./interfaces/IReputationManager.sol";

contract AgentEscrow {
    enum JobState {
        CREATED,
        ACCEPTED,
        SUBMITTED,
        APPROVED,
        SLASHED,
        CANCELLED
    }

    struct Job {
        uint256 jobId;
        address master;
        address worker;
        uint256 price;
        JobState state;
        bytes32 outputHash;
        string proofRef;
        uint256 createdAt;
        uint256 deadline;
        bool fundsReleased;
    }

    IAgentRegistry public immutable agentRegistry;
    IReputationManager public immutable reputationManager;

    mapping(uint256 => Job) private jobs;
    uint256 public jobCounter;

    uint256 public constant PLATFORM_FEE_PERCENTAGE = 2;
    uint256 public constant MAX_FEE_PERCENTAGE = 10;
    address public platformFeeRecipient;
    address public immutable owner;

    event JobCreated(
        uint256 indexed jobId,
        address indexed master,
        address indexed worker,
        uint256 price,
        uint256 deadline,
        uint256 timestamp
    );

    event JobAccepted(
        uint256 indexed jobId,
        address indexed worker,
        uint256 timestamp
    );

    event ResultSubmitted(
        uint256 indexed jobId,
        bytes32 outputHash,
        string proofRef,
        uint256 timestamp
    );

    event JobApproved(
        uint256 indexed jobId,
        address indexed master,
        address indexed worker,
        uint256 payment,
        uint256 timestamp
    );

    event JobSlashed(
        uint256 indexed jobId,
        address indexed worker,
        uint256 slashAmount,
        uint256 timestamp
    );

    event JobCancelled(
        uint256 indexed jobId,
        uint256 timestamp
    );

    event FeeRecipientUpdated(
        address indexed oldRecipient,
        address indexed newRecipient,
        uint256 timestamp
    );

    error NotJobMaster();
    error NotJobWorker();
    error InvalidJobState();
    error InvalidPrice();
    error InvalidWorker();
    error CannotHireSelf();
    error MasterNotRegistered();
    error WorkerNotRegistered();
    error InvalidDeadline();
    error InvalidOutputHash();
    error DeadlinePassed();
    error FundsAlreadyReleased();
    error CannotCancelJob();
    error Unauthorized();
    error InvalidAddress();
    error TransferFailed();

    modifier onlyMaster(uint256 _jobId) {
        if (jobs[_jobId].master != msg.sender) revert NotJobMaster();
        _;
    }

    modifier onlyWorker(uint256 _jobId) {
        if (jobs[_jobId].worker != msg.sender) revert NotJobWorker();
        _;
    }

    modifier inState(uint256 _jobId, JobState _state) {
        if (jobs[_jobId].state != _state) revert InvalidJobState();
        _;
    }

    constructor(address _agentRegistry, address _reputationManager) {
        if (_agentRegistry == address(0) || _reputationManager == address(0)) {
            revert InvalidAddress();
        }
        
        agentRegistry = IAgentRegistry(_agentRegistry);
        reputationManager = IReputationManager(_reputationManager);
        platformFeeRecipient = msg.sender;
        owner = msg.sender;
    }

    function createJob(
        address _worker,
        uint256 _deadline
    ) external payable returns (uint256) {
        if (msg.value == 0) revert InvalidPrice();
        if (_worker == address(0)) revert InvalidWorker();
        if (_worker == msg.sender) revert CannotHireSelf();
        if (!agentRegistry.isAgentActive(msg.sender)) revert MasterNotRegistered();
        if (!agentRegistry.isAgentActive(_worker)) revert WorkerNotRegistered();
        if (_deadline <= block.timestamp) revert InvalidDeadline();

        uint256 jobId = jobCounter++;

        jobs[jobId] = Job({
            jobId: jobId,
            master: msg.sender,
            worker: _worker,
            price: msg.value,
            state: JobState.CREATED,
            outputHash: bytes32(0),
            proofRef: "",
            createdAt: block.timestamp,
            deadline: _deadline,
            fundsReleased: false
        });

        emit JobCreated(
            jobId,
            msg.sender,
            _worker,
            msg.value,
            _deadline,
            block.timestamp
        );

        return jobId;
    }

    function acceptJob(uint256 _jobId) 
        external 
        onlyWorker(_jobId) 
        inState(_jobId, JobState.CREATED) 
    {
        jobs[_jobId].state = JobState.ACCEPTED;

        emit JobAccepted(_jobId, msg.sender, block.timestamp);
    }

    function submitResult(
        uint256 _jobId,
        bytes32 _outputHash,
        string memory _proofRef
    ) 
        external 
        onlyWorker(_jobId) 
        inState(_jobId, JobState.ACCEPTED) 
    {
        if (_outputHash == bytes32(0)) revert InvalidOutputHash();
        
        Job storage job = jobs[_jobId];
        if (block.timestamp > job.deadline) revert DeadlinePassed();

        job.outputHash = _outputHash;
        job.proofRef = _proofRef;
        job.state = JobState.SUBMITTED;

        emit ResultSubmitted(_jobId, _outputHash, _proofRef, block.timestamp);
    }

    function approveAndRelease(uint256 _jobId) 
        external 
        onlyMaster(_jobId) 
        inState(_jobId, JobState.SUBMITTED) 
    {
        Job storage job = jobs[_jobId];
        if (job.fundsReleased) revert FundsAlreadyReleased();

        job.state = JobState.APPROVED;
        job.fundsReleased = true;

        uint256 platformFee = (job.price * PLATFORM_FEE_PERCENTAGE) / 100;
        uint256 workerPayment = job.price - platformFee;

        console.log("Job price:", job.price);
        console.log("Platform fee:", platformFee);
        console.log("Worker payment:", workerPayment);
        console.log("Platform fee recipient:", platformFeeRecipient);

        reputationManager.increaseReputation(job.worker, 10);
        reputationManager.recordEarnings(job.worker, workerPayment);
        reputationManager.increaseReputation(job.master, 0);

        console.log("Balance before transfers:", address(this).balance);
        console.log("Worker payment:", workerPayment, "to", job.worker);
        console.log("Platform fee:", platformFee, "to", platformFeeRecipient);

        payable(job.worker).transfer(workerPayment);
        
        payable(platformFeeRecipient).transfer(platformFee);

        emit JobApproved(
            _jobId,
            job.master,
            job.worker,
            workerPayment,
            block.timestamp
        );
    }

    function rejectAndSlash(uint256 _jobId, uint256 _slashAmount) 
        external 
        onlyMaster(_jobId) 
        inState(_jobId, JobState.SUBMITTED) 
    {
        Job storage job = jobs[_jobId];
        if (job.fundsReleased) revert FundsAlreadyReleased();

        job.state = JobState.SLASHED;
        job.fundsReleased = true;

        reputationManager.decreaseReputation(job.worker, 20);
        if (_slashAmount > 0) {
            reputationManager.applySlash(job.worker, _slashAmount);
        }

        (bool success, ) = payable(job.master).call{value: job.price}("");
        if (!success) revert TransferFailed();

        emit JobSlashed(_jobId, job.worker, _slashAmount, block.timestamp);
    }

    function cancelJob(uint256 _jobId) 
        external 
        onlyMaster(_jobId) 
    {
        Job storage job = jobs[_jobId];
        
        bool canCancel = job.state == JobState.CREATED || 
                        (job.state == JobState.ACCEPTED && block.timestamp > job.deadline);
        
        if (!canCancel) revert CannotCancelJob();
        if (job.fundsReleased) revert FundsAlreadyReleased();

        job.state = JobState.CANCELLED;
        job.fundsReleased = true;

        (bool success, ) = payable(job.master).call{value: job.price}("");
        if (!success) revert TransferFailed();

        emit JobCancelled(_jobId, block.timestamp);
    }

    function getJob(uint256 _jobId) external view returns (Job memory) {
        return jobs[_jobId];
    }

    function getJobsByMaster(address _master, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256 count = 0;
        for (uint256 i = 0; i < jobCounter && count < _limit; i++) {
            if (jobs[i].master == _master) {
                count++;
            }
        }

        uint256[] memory jobIds = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < jobCounter && index < count; i++) {
            if (jobs[i].master == _master) {
                jobIds[index] = i;
                index++;
            }
        }

        return jobIds;
    }

    function getJobsByWorker(address _worker, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory) 
    {
        uint256 count = 0;
        for (uint256 i = 0; i < jobCounter && count < _limit; i++) {
            if (jobs[i].worker == _worker) {
                count++;
            }
        }

        uint256[] memory jobIds = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < jobCounter && index < count; i++) {
            if (jobs[i].worker == _worker) {
                jobIds[index] = i;
                index++;
            }
        }

        return jobIds;
    }

    function setPlatformFeeRecipient(address _recipient) external {
        if (msg.sender != owner) revert Unauthorized();
        if (_recipient == address(0)) revert InvalidAddress();
        
        address oldRecipient = platformFeeRecipient;
        platformFeeRecipient = _recipient;
        
        emit FeeRecipientUpdated(oldRecipient, _recipient, block.timestamp);
    }
}

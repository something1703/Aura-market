// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IAgentRegistry.sol";

contract ReputationManager {
    struct ReputationData {
        uint256 score;
        uint256 completedJobs;
        uint256 failedJobs;
        uint256 totalEarned;
        uint256 slashCount;
        uint256 lastUpdateTime;
    }

    IAgentRegistry public immutable agentRegistry;
    
    mapping(address => ReputationData) private reputations;
    mapping(address => bool) private authorizedContracts;
    
    address public immutable owner;

    event ReputationUpdated(
        address indexed agent,
        uint256 newScore,
        uint256 timestamp
    );

    event StakeSlashed(
        address indexed agent,
        uint256 amount,
        uint256 timestamp
    );

    event JobCompleted(
        address indexed agent,
        uint256 timestamp
    );

    event JobFailed(
        address indexed agent,
        uint256 timestamp
    );

    event ContractAuthorized(
        address indexed contractAddress,
        uint256 timestamp
    );

    event ContractRevoked(
        address indexed contractAddress,
        uint256 timestamp
    );

    error NotAuthorized();
    error NotOwner();
    error NotActive();
    error InvalidAddress();

    modifier onlyAuthorized() {
        if (!authorizedContracts[msg.sender] && msg.sender != owner) {
            revert NotAuthorized();
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _agentRegistry) {
        if (_agentRegistry == address(0)) revert InvalidAddress();
        agentRegistry = IAgentRegistry(_agentRegistry);
        owner = msg.sender;
    }

    function authorizeContract(address _contract) external onlyOwner {
        if (_contract == address(0)) revert InvalidAddress();
        authorizedContracts[_contract] = true;
        emit ContractAuthorized(_contract, block.timestamp);
    }

    function revokeContract(address _contract) external onlyOwner {
        authorizedContracts[_contract] = false;
        emit ContractRevoked(_contract, block.timestamp);
    }

    function increaseReputation(address _agent, uint256 _amount) external onlyAuthorized {
        if (!agentRegistry.isAgentActive(_agent)) revert NotActive();
        
        ReputationData storage rep = reputations[_agent];
        rep.score += _amount;
        rep.completedJobs += 1;
        rep.lastUpdateTime = block.timestamp;

        emit ReputationUpdated(_agent, rep.score, block.timestamp);
        emit JobCompleted(_agent, block.timestamp);
    }

    function decreaseReputation(address _agent, uint256 _amount) external onlyAuthorized {
        if (!agentRegistry.isAgentActive(_agent)) revert NotActive();
        
        ReputationData storage rep = reputations[_agent];
        
        if (rep.score >= _amount) {
            rep.score -= _amount;
        } else {
            rep.score = 0;
        }
        
        rep.failedJobs += 1;
        rep.lastUpdateTime = block.timestamp;

        emit ReputationUpdated(_agent, rep.score, block.timestamp);
        emit JobFailed(_agent, block.timestamp);
    }

    function applySlash(address _agent, uint256 _amount) external onlyAuthorized {
        if (!agentRegistry.isAgentActive(_agent)) revert NotActive();
        
        ReputationData storage rep = reputations[_agent];
        rep.slashCount += 1;
        rep.lastUpdateTime = block.timestamp;

        agentRegistry.slashStake(_agent, _amount);

        emit StakeSlashed(_agent, _amount, block.timestamp);
    }

    function recordEarnings(address _agent, uint256 _amount) external onlyAuthorized {
        if (!agentRegistry.isAgentActive(_agent)) revert NotActive();
        reputations[_agent].totalEarned += _amount;
        reputations[_agent].lastUpdateTime = block.timestamp;
    }

    function getReputation(address _agent) external view returns (ReputationData memory) {
        return reputations[_agent];
    }

    function getReputationScore(address _agent) external view returns (uint256) {
        return reputations[_agent].score;
    }

    function getTrustScore(address _agent) external view returns (uint256) {
        ReputationData memory rep = reputations[_agent];
        
        if (rep.completedJobs == 0) return 0;
        
        uint256 successRate = (rep.completedJobs * 100) / (rep.completedJobs + rep.failedJobs);
        uint256 baseScore = rep.score;
        
        if (rep.slashCount > 0) {
            baseScore = baseScore > (rep.slashCount * 50) ? baseScore - (rep.slashCount * 50) : 0;
        }
        
        return (baseScore * successRate) / 100;
    }

    function isContractAuthorized(address _contract) external view returns (bool) {
        return authorizedContracts[_contract];
    }

    function getAgentStats(address _agent) 
        external 
        view 
        returns (
            uint256 successRate,
            uint256 totalJobs,
            uint256 trustScore
        ) 
    {
        ReputationData memory rep = reputations[_agent];
        totalJobs = rep.completedJobs + rep.failedJobs;
        
        if (totalJobs == 0) {
            return (0, 0, 0);
        }
        
        successRate = (rep.completedJobs * 10000) / totalJobs;
        
        uint256 baseScore = rep.score;
        if (rep.slashCount > 0) {
            baseScore = baseScore > (rep.slashCount * 50) ? baseScore - (rep.slashCount * 50) : 0;
        }
        trustScore = (baseScore * successRate) / 10000;
        
        return (successRate, totalJobs, trustScore);
    }
}

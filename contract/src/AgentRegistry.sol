// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract AgentRegistry {
    struct AgentProfile {
        address agentAddress;
        string metadataURI;
        string capabilities;
        string endpoint;
        uint256 stakeAmount;
        uint256 reputationIndex;
        bool isActive;
        uint256 registeredAt;
    }

    mapping(address => AgentProfile) private agents;
    address[] private agentList;
    mapping(address => bool) private authorizedManagers;
    
    uint256 public constant MINIMUM_STAKE = 0.01 ether;
    address public immutable owner;

    event AgentRegistered(
        address indexed agent,
        string metadataURI,
        string capabilities,
        uint256 stake,
        uint256 timestamp
    );

    event AgentUpdated(
        address indexed agent,
        string metadataURI,
        string capabilities,
        uint256 timestamp
    );

    event StakeDeposited(
        address indexed agent,
        uint256 amount,
        uint256 newTotal
    );

    event StakeWithdrawn(
        address indexed agent,
        uint256 amount,
        uint256 remaining
    );

    event AgentDeactivated(
        address indexed agent,
        uint256 timestamp
    );

    event ManagerAuthorized(
        address indexed manager,
        uint256 timestamp
    );

    error AlreadyRegistered();
    error NotRegistered();
    error InsufficientStake();
    error InvalidAmount();
    error MustMaintainMinimum();
    error NotActive();
    error Unauthorized();
    error InvalidAddress();

    modifier onlyRegistered() {
        if (!agents[msg.sender].isActive) revert NotRegistered();
        _;
    }

    modifier onlyAuthorized() {
        if (!authorizedManagers[msg.sender] && msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function authorizeManager(address _manager) external {
        if (msg.sender != owner) revert Unauthorized();
        if (_manager == address(0)) revert InvalidAddress();
        
        authorizedManagers[_manager] = true;
        emit ManagerAuthorized(_manager, block.timestamp);
    }

    function registerAgent(
        string memory _metadataURI,
        string memory _capabilities,
        string memory _endpoint
    ) external payable {
        if (agents[msg.sender].isActive) revert AlreadyRegistered();
        if (msg.value < MINIMUM_STAKE) revert InsufficientStake();

        agents[msg.sender] = AgentProfile({
            agentAddress: msg.sender,
            metadataURI: _metadataURI,
            capabilities: _capabilities,
            endpoint: _endpoint,
            stakeAmount: msg.value,
            reputationIndex: 100,
            isActive: true,
            registeredAt: block.timestamp
        });

        agentList.push(msg.sender);

        emit AgentRegistered(
            msg.sender,
            _metadataURI,
            _capabilities,
            msg.value,
            block.timestamp
        );
    }

    function updateAgentProfile(
        string memory _metadataURI,
        string memory _capabilities,
        string memory _endpoint
    ) external onlyRegistered {
        AgentProfile storage profile = agents[msg.sender];
        profile.metadataURI = _metadataURI;
        profile.capabilities = _capabilities;
        profile.endpoint = _endpoint;

        emit AgentUpdated(
            msg.sender,
            _metadataURI,
            _capabilities,
            block.timestamp
        );
    }

    function depositStake() external payable onlyRegistered {
        if (msg.value == 0) revert InvalidAmount();
        
        agents[msg.sender].stakeAmount += msg.value;

        emit StakeDeposited(
            msg.sender,
            msg.value,
            agents[msg.sender].stakeAmount
        );
    }

    function withdrawStake(uint256 _amount) external onlyRegistered {
        if (_amount == 0) revert InvalidAmount();
        
        AgentProfile storage profile = agents[msg.sender];
        if (profile.stakeAmount - _amount < MINIMUM_STAKE) revert MustMaintainMinimum();

        profile.stakeAmount -= _amount;
        
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Transfer failed");

        emit StakeWithdrawn(
            msg.sender,
            _amount,
            profile.stakeAmount
        );
    }

    function deactivateAgent() external onlyRegistered {
        AgentProfile storage profile = agents[msg.sender];
        profile.isActive = false;

        uint256 refundAmount = profile.stakeAmount;
        profile.stakeAmount = 0;

        if (refundAmount > 0) {
            (bool success, ) = payable(msg.sender).call{value: refundAmount}("");
            require(success, "Transfer failed");
        }

        emit AgentDeactivated(msg.sender, block.timestamp);
    }

    function updateReputation(address _agent, uint256 _newReputation) external onlyAuthorized {
        if (!agents[_agent].isActive) revert NotActive();
        agents[_agent].reputationIndex = _newReputation;
    }

    function slashStake(address _agent, uint256 _amount) external onlyAuthorized {
        if (!agents[_agent].isActive) revert NotActive();
        
        AgentProfile storage profile = agents[_agent];
        if (profile.stakeAmount < _amount) revert InsufficientStake();
        
        profile.stakeAmount -= _amount;
    }

    function getAgent(address _agent) external view returns (AgentProfile memory) {
        return agents[_agent];
    }

    function getAgentCount() external view returns (uint256) {
        return agentList.length;
    }

    function getAgentByIndex(uint256 _index) external view returns (address) {
        require(_index < agentList.length, "Index out of bounds");
        return agentList[_index];
    }

    function isAgentActive(address _agent) external view returns (bool) {
        return agents[_agent].isActive;
    }

    function isManagerAuthorized(address _manager) external view returns (bool) {
        return authorizedManagers[_manager];
    }
}

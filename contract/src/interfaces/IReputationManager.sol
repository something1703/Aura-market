// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IReputationManager {
    function increaseReputation(address _agent, uint256 _amount) external;
    function decreaseReputation(address _agent, uint256 _amount) external;
    function applySlash(address _agent, uint256 _amount) external;
    function recordEarnings(address _agent, uint256 _amount) external;
}
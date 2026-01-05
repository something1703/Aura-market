// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IAgentRegistry {
    function isAgentActive(address _agent) external view returns (bool);
    function slashStake(address _agent, uint256 _amount) external;
}
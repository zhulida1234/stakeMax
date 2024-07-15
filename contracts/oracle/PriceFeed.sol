// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../interface/IPriceFeed.sol";

contract PriceFeed is IPriceFeed{

    int256 public answer;
    uint80 public roundId;
    string public override description = "PriceFeed";
    address public override aggregator;

    uint256 public decimals;

    address public gov;

    mapping (uint80 => int256) public answers;
    mapping (address => bool) public isAdmin;

    constructor() {
        gov = msg.sender;
        isAdmin[msg.sender] = true;
    }

    function setAdmin(address _account, bool _isAdmin) public {
        require(msg.sender == gov, "PriceFeed: forbidden");
        isAdmin[_account] = _isAdmin;
    }

    function latestAnswer() external view returns (int256){
        return answer;
    }

    function latestRound() external view returns (uint80){
        return roundId;
    }

    function getRoundData(uint80 _roundId) external view returns (uint80, int256, uint256, uint256, uint80){
        return (_roundId, answers[_roundId], 0, 0, 0);
    }

}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../interface/IPriceFeed.sol";

contract PriceFeed is IPriceFeed {
    int256 public answer;
    uint80 public roundId;

    uint256 public decimals;


    mapping(uint256 => int256) public answers;
    mapping(address => bool) public isAdmin;

    modifier onlyAdmin {
        require(isAdmin[msg.sender],"PriceFeed: forbidden");
        _;
    }

    constructor() {
        isAdmin[msg.sender] = true;
    }

    function setAdmin(address _account, bool _isAdmin) public onlyAdmin{
        isAdmin[_account] = _isAdmin;
    }

    function latestAnswer() external view returns (int256) {
        return answer;
    }

    function latestRound() external view returns (uint80) {
        return roundId;
    }

    function setLatestAnswer(int256 _answer) public {
        require(isAdmin[msg.sender], "PriceFeed: forbidden");
        roundId = roundId + 1;
        answer = _answer;
        answers[roundId] = _answer;
    }

    function getRoundData(
        uint256 _roundId
    )
        external
        view
        override
        returns (uint256, int256, uint256, uint256, uint80)
    {
        return (_roundId, answers[_roundId], 0, 0, 0);
    }
}
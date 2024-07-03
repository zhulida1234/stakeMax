// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

contract AbiUtil {

    // 活动开始时间
    uint256 public startTimeStamp;
    // 活动结束时间
    uint256 public endTimeStamp;
    // 每秒奖励的数量
    uint256 public rewardPerSecond;
    // 奖励token地址
    address b2stAddress;

    function package(address _b2stAddress,uint256 _rewardPerSecond,uint256 _startTimeStamp,uint256 _endTimeStamp) public pure returns (bytes memory) {
        return abi.encodeWithSignature("initialize(address,uint256,uint256,uint256)", _b2stAddress, _rewardPerSecond, _startTimeStamp, _endTimeStamp);
    }
}
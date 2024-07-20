// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../MaxStake.sol";

contract TestMaxStake is MaxStake {

    function testUpdatePool(uint256 _pid) external {
        updatePool(_pid);
    }

    function setEndTimeStamp(uint256 _endTimeStamp) external onlyOwner{
        endTimeStamp = _endTimeStamp;
    }

    function getUserInfo(uint _pid,address _addr) external view returns (User memory){
        return userInfo[_pid][_addr];
    }

}
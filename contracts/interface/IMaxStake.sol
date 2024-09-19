//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IMaxStake {

    function deposit(uint256 _pid, uint256 amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function setTokenUnlockTime(uint256 _pid, address _user, uint256 saleEndTime);

    function getKValues(address _addr) public view returns (uint8, uint256);

    function setKValues(address _addr, uint8 _level, uint256 _kValue);

    function getMaxK() public view returns (uint256);
}

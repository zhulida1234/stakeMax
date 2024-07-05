//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IAdmin {
    function isAdmin(address user) external view returns (bool);
}

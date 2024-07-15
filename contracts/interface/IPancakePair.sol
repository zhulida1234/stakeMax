// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IPancakePair {
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
}
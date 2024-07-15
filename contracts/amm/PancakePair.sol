// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "../interface/IPancakePair.sol";

contract PancakePair is IPancakePair {

    uint256 private reserve0;           
    uint256 private reserve1;           
    uint256  private blockTimestampLast; 

    function setReserves(uint256 _reserve0, uint256 _reserve1) external {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
        blockTimestampLast = block.timestamp;
    }

    function getReserves()
        external
        view
        override
        returns (uint256 _reserve0, uint256 _reserve1, uint256 _blockTimestampLast)
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IPoolPriceFeed{

    function getPrice(address _token, bool _maximise, bool _includeAmmPrice) external view returns (uint256);

}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/Strings.sol)

pragma solidity ^0.8.20;

/**
 * @dev String operations.
 */
interface IERC20Metadata {

    /**
    *  @dev return token name
     * @dev 返回代币的名称。
     */
    function name() external view returns (string memory);

    /**
     * @dev return token symbol
     * @dev 返回代币的符号。
     */
    function symbol() external view returns (string memory);

    /**
    * @dev return decimals
     * @dev 返回代币的小数位数。
     * 例如，如果 `decimals` 等于 `2`，一个代币单位相当于 `10^2` 个最小单位。
     */
    function decimals() external view returns (uint8);
    
}
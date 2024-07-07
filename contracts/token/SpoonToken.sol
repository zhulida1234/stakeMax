// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./ERC20.sol";
import "../interface/IERC20.sol";
import "../interface/IERC20Metadata.sol";

contract SpoonToken is ERC20("Spoon Token","Spoon"),IERC20Metadata {


     function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns (uint8){
        return 1;
    }

}
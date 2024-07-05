// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./ERC20.sol";
import "./IERC20.sol";
import "./Ownable.sol";
import "./IERC20Metadata.sol";

/**
 * @title Reward Token
 * @author 
 * @notice this Token used by stake reward,when Stake another token,while earn the rewardToken
 */
contract RewardToken is ERC20("Reward Token","Reward"),IERC20Metadata,Ownable {


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
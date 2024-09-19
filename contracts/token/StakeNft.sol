// SPDX-License-Identifier: MIT
// by 0xAA
pragma solidity ^0.8.21;

import "./interface/IAdmin.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Admin} from "../Admin.sol";
import "./interface/IMaxStake.sol";


contract StakeNft is ERC721, Admin {
    uint public MAX_APES = 10000; // 总量

    uint public MAX_K = 10000; // 满足K值可以进行mint NFT

    uint256 private _tokenIdCounter;

    IMaxStake public maxStake;
    //nft对应等级的映射
    mapping(address => uint8) nftLevel;
    //构造函数
    constructor(string memory name_, string memory symbol_, address maxStakeAddress) ERC721(name_, symbol_){
        maxStake = IMaxStake(maxStakeAddress);
    }
    // 铸造函数
    function mint(){
        uint256 kValue = maxStake.getKValues(msg.sender);
        require(kValue >= MAX_K, "your points are insufficient");
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter += 1;
        require(tokenId >= 0 && tokenId < MAX_APES, "tokenId out of range");
        _mint(msg.sender, tokenId);
    }
}
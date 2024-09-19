// SPDX-License-Identifier: MIT
// by 0xAA
pragma solidity ^0.8.21;

import "./interface/IAdmin.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Admin} from "../Admin.sol";

contract StakeNft is ERC721, Admin {
    uint public MAX_APES = 10000; // 总量
    uint256 private _tokenIdCounter;

    //nft对应等级的映射
    mapping(address => uint8) nftLevel;
    //构造函数
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_){
    }
    // 铸造函数
    function mint(address to) external onlyAdmin {
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter += 1;
        require(tokenId >= 0 && tokenId < MAX_APES, "tokenId out of range");
        _mint(to, tokenId);
    }
}
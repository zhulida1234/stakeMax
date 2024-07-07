//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./interface/IAdmin.sol";

contract Admin is IAdmin{

    // Listing all admins
    // admins 地址列表
    address [] public admins;

    // Modifier for easier checking if user is admin
    // 是否是admin的映射
    mapping(address => bool) public isAdmin;

    // Modifier restricting access to only admin
    // 校验只有Admin才有权限操作
    modifier onlyAdmin {
        require(isAdmin[msg.sender], "Only admin can call.");
        _;
    }

    // Constructor to set initial admins during deployment
    // 构造器
    function init(address [] memory _admins) external {
        require(_admins.length>0, "at least one admin");
        for(uint i=0;i<_admins.length;++i){
            admins.push(_admins[i]);
            isAdmin[_admins[i]]=true;
        }
    }

    // add another admin,It must admin can operator
    // 增加另外一个admin，只有admin的权限用户可以操作
    function addAdmin(address _adminAddress) external onlyAdmin {
        require(_adminAddress!=address(0),"Admin can't be the 0 address");
        require(!isAdmin[_adminAddress],"this address alread admin");
        admins.push(_adminAddress);
        isAdmin[_adminAddress] = true;
    }

    // remove a admin,Only allow deletion if the admin pool is greater than 1.
    // 删除一个admin地址，只允许admin池子在大于1的情况下操作
    function removeAdmin(address _adminAddress) external onlyAdmin {
        require(isAdmin[_adminAddress]);
        require(admins.length>1, "Can't remove all admins since contract becomes unusable");
        uint i =0;

        while(admins[i]!=_adminAddress){
            if(i == admins.length){
                revert("the admin address can't exist");
            }
        }

        admins[i] = admins[admins.length-1];
        isAdmin[_adminAddress]= false;
        admins.pop();
    }
    
    //obtain all Admin address
    // 获取所有的admin 地址列表
    function getAllAdmins() external view returns(address [] memory){
        return admins;
    }


}
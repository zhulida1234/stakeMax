//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Admin.sol";
import "./MaxSale.sol";

contract SalesFactory is Admin{

    address public stakingContractAddress;
    // through Factory Created sale, sale address mapping bool
    // 是否通过工厂创建的销售合约
    mapping (address => bool) public isSaleCreatedThroughFactory;
    // owner address mapping to sale address
    // 所有者和销售合约的地址映射
    mapping (address => address) public saleOwnerToSale;
    // all Sales Listing
    // 所有销售合约列表
    address [] public allSales;

    event SaleDeployed(address saleContract);
    event SaleOwnerAndTokenSetInFactory(address sale, address saleOwner, address saleToken);

    constructor (address _stakingContractAddress) {
        stakingContractAddress = _stakingContractAddress;
    }

    function setStakingContractAddr(address _stakingContractAddress) external {
        stakingContractAddress = _stakingContractAddress;
    }

    function getLastDeployedSale() external view returns (address) {
        if(allSales.length > 0) {
            return allSales[allSales.length-1];
        }
        return address(0);
    }


    // deploy a new sale contract
    // 通过工厂部署一个全新的 销售合约
    function deploySale(address _adminAddress) external onlyAdmin {
        require(isAdmin[_adminAddress],"only admin address can be deploy new Sale");
        MaxSale sale = new MaxSale(_adminAddress,stakingContractAddress);

        isSaleCreatedThroughFactory[address(sale)] = true;
        allSales.push(address(sale));

        emit SaleDeployed(address(sale));
    }



}
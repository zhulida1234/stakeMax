const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MaxStake", function () {
    let MaxStake;
    let maxStake;
    let rewardToken;
    let interestToken;
    let cupToken;
    let owner;
    let addr1;

    beforeEach(async function () {

        const RewardToken = await ethers.getContractFactory("RewardToken");
        rewardToken = await RewardToken.deploy();
        await rewardToken.waitForDeployment();

        const InterestToken = await ethers.getContractFactory("InterestToken");
        interestToken = await InterestToken.deploy();
        await interestToken.waitForDeployment();

        const CupToken = await ethers.getContractFactory("CupToken");
        cupToken = await CupToken.deploy();
        await cupToken.waitForDeployment();

        // Get the ContractFactory and Signers here.
        MaxStake = await ethers.getContractFactory("MaxStake");
        [owner, addr1] = await ethers.getSigners();
        // console("owner,addr1",owner,addr1);
        // Deploy the contract.
        maxStake = await MaxStake.deploy();
        await maxStake.waitForDeployment();

        await maxStake.initialize(rewardToken.target, 10, 1721373854, 1739525054);
    });


    it("Should not allow non-admin to pause withdraw ", async function () {
        await expect(maxStake.connect(addr1).pauseWithdraw()).to.be.revertedWith("Invalid Operator");

        await maxStake.connect(owner).pauseWithdraw();
        expect(await maxStake.withdrawPaused()).to.equal(true);
    });

    it("Should not allow non-admin to pause Claim ", async function () {
        await expect(maxStake.connect(addr1).pauseClaim()).to.be.revertedWith("Invalid Operator");

        await maxStake.connect(owner).pauseClaim();
        expect(await maxStake.claimPaused()).to.equal(true);
    });

    it("Should only unPaused state can be pause withdraw ", async function () {
        await maxStake.connect(owner).pauseWithdraw();

        await expect(maxStake.pauseWithdraw()).to.be.revertedWith("withdraw is Paused");
    });

    it("Should only unPaused state can be pause claim ", async function () {
        await maxStake.connect(owner).pauseClaim();

        await expect(maxStake.pauseClaim()).to.be.revertedWith("claim is Paused");
    });

    it("Should allow owner to fund", async function () {
        const initialTotalRewards = await maxStake.totalRewards();
        const initialEndTimeStamp = await maxStake.endTimeStamp();
        const amount = BigInt(10**37);
        
        await rewardToken.mint(owner.address,amount);

        // 授权合约从所有者账户中转移 RewardToken
        await rewardToken.approve(maxStake.target, amount);

        // 验证授权额度是否正确设置
        const allowance = await rewardToken.allowance(owner.address, maxStake.target);

        // 作为合约所有者调用 fund 方法
        await maxStake.connect(owner).fund(amount);

        // 确认 owner 的初始余额
        const ownerBalanceAfter = await rewardToken.balanceOf(owner.address);
        console.log("ownerBalanceAfter set:", ownerBalanceAfter.toString());
        
        // 验证 totalRewards 是否正确更新
        expect(await maxStake.totalRewards()).to.equal(initialTotalRewards + amount);

        // 验证 endTimeStamp 是否正确更新
        const rewardPerSecond = await maxStake.rewardPerSecond();
        expect(await maxStake.endTimeStamp()).to.equal(initialEndTimeStamp+amount / rewardPerSecond);

        // // 验证 RewardToken 是否从所有者账户转移到合约地址
        expect(await rewardToken.balanceOf(owner.address)).to.equal(0);
        expect(await rewardToken.balanceOf(maxStake.target)).to.equal(amount);
    });

    it("Should not allow non-owner to fund", async function () {
        const amount = ethers.parseEther("100");  // 直接从 ethers 导入 parseEther

        // 授权合约从 addr1 账户中转移 RewardToken
        await rewardToken.connect(addr1).approve(maxStake.target, amount);

        // 作为非合约所有者调用 fund 方法应该失败
        await expect(maxStake.connect(addr1).fund(amount)).to.be.revertedWith("Invalid Operator");
    });

    it("Should not allow to fund after endTimeStamp", async function () {
        const amount = ethers.parseEther("100");  // 直接从 ethers 导入 parseEther

        // 将 endTimeStamp 设置为过去的时间
        await maxStake.setEndTimeStamp(Math.floor(Date.now() / 1000) - 1);

        // 授权合约从所有者账户中转移 RewardToken
        await rewardToken.approve(maxStake.target, amount);

        // 作为合约所有者调用 fund 方法应该失败
        await expect(maxStake.connect(owner).fund(amount)).to.be.revertedWith("Time is too late");
    });

});
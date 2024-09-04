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
        console.info("init info");
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
        MaxStake = await ethers.getContractFactory("TestMaxStake");
        [owner, addr1] = await ethers.getSigners();
        // console("owner,addr1",owner,addr1);
        // Deploy the contract.
        maxStake = await MaxStake.deploy();
        await maxStake.waitForDeployment();

        await maxStake.initialize(rewardToken.target, 10, 1721373854, 1739525054);
    });


    it("Should not allow non-admin to pause withdraw ", async function () {
        await expect(maxStake.connect(addr1).pauseWithdraw()).to.be.revertedWith("Invalid Operator");
        console.info("Should not allow non-admin to pause withdraw");
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

    it("Should revert if token address is invalid", async function () {
        await expect(
            maxStake.add(
                "0x0000000000000000000000000000000000000000", // Invalid address
                false,
                1000,
                ethers.parseEther("1"),
                ethers.parseEther("1")
            )
        ).to.be.revertedWith("Invalid token address");
    });

    it("Should not allow non-owner to add", async function () {
        // 作为非合约所有者调用 add 方法应该失败
        await expect(
            maxStake.connect(addr1).add(
                cupToken.target,
                false,
                1, // Zero pool weight
                ethers.parseEther("1"),
                ethers.parseEther("1")
            )
        ).to.be.revertedWith("Invalid Operator");
    });

    it("Should revert if pool weight is zero", async function () {
        await expect(
            maxStake.add(
                cupToken.target,
                false,
                0, // Zero pool weight
                ethers.parseEther("1"),
                ethers.parseEther("1")
            )
        ).to.be.revertedWith("Pool weight must be greater than zero");
    });

    it("Should revert if minimum deposit amount is zero", async function () {
        await expect(
            maxStake.add(
                cupToken.target,
                false,
                1000,
                0, // Zero minimum deposit amount
                ethers.parseEther("1")
            )
        ).to.be.revertedWith("Minimum deposit amount must be greater than zero");
    });

    it("Should revert if minimum unstake amount is zero", async function () {
        await expect(
            maxStake.add(
                cupToken.target,
                false,
                1000,
                ethers.parseEther("1"),
                0 // Zero minimum unstake amount
            )
        ).to.be.revertedWith("Minimum unstake amount must be greater than zero");
    });

    it("Should add a pool correctly if all parameters are valid", async function () {
        await maxStake.add(
            cupToken.target,
            false,
            1000,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );

        const pool = await maxStake.pools(0);
        expect(pool.stTokenAddress).to.equal(cupToken.target);
        expect(pool.poolWeight).to.equal(1000);
        expect(pool.minDepositAmount).to.equal(ethers.parseEther("1"));
        expect(pool.minUnstakeAmount).to.equal(ethers.parseEther("1"));
    });

    it("Should add a token to the pool only once time", async function () {
        await maxStake.add(
            cupToken.target,
            false,
            1000,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );

        await expect(
            maxStake.add(
                cupToken.target,
                false,
                1000,
                ethers.parseEther("1"),
                ethers.parseEther("1") // Zero minimum unstake amount
            )
        ).to.be.revertedWith("Token can only add once");

    });

    it("Should update the pool correctly", async function () {
        await maxStake.add(
            cupToken.target,
            false,
            1000,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );

        const poolBefore = await maxStake.pools(0);
        console.log("Updated before pool info:", poolBefore);

        const poolIndex = 0; // Use appropriate index based on your pools setup

        // Call testUpdatePool to trigger updatePool internally
        await maxStake.testUpdatePool(poolIndex);

        // Fetch the updated pool info
        const poolAfter = await maxStake.pools(poolIndex);

        // Validate the updated values
        console.log("Updated after pool info:", poolAfter);
        
    });

    it("Should not allow non-owner to set Weight", async function () {
        await maxStake.add(
            cupToken.target,
            false,
            1000,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );

        // 作为非合约所有者调用 set 方法应该失败
        await expect(
            maxStake.connect(addr1).set(
                0,
                1,
                false // Zero pool weight
            )
        ).to.be.revertedWith("Invalid Operator");
    });

    if("Should set the pool Weight result correctly", async function() {
        const beforeWeight = 1000;
        await maxStake.add(
            cupToken.target,
            false,
            beforeWeight,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );
        expect(maxStake.totalAllocPoint).to.equal(beforeWeight);

        await maxStake.set(0,500,false);
        const poolSetAfter = await maxStake.pools(0);
        expect(poolSetAfter.poolWeight).to.equal(500);
        expect(maxStake.totalAllocPoint).to.equal(500);
    });

    //-------------------- deposit func test -----------------------------
    it("Should revert if end time has passed", async function () {

        await maxStake.setEndTimeStamp(Math.floor(Date.now() / 1000) - 1);

        await expect(
            maxStake.deposit(0, ethers.parseEther("10"))
        ).to.be.revertedWith("time is over");
    });

    it("Should revert if deposit amount is less than minimum deposit amount", async function () {
        await maxStake.add(
            cupToken.target,
            false,
            1000,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );

        await expect(
            maxStake.deposit(0, ethers.parseEther("0.5"))
        ).to.be.revertedWith("amount less than limit");
    });

    it("Should deposit and update user and pool state correctly", async function () {
        await maxStake.add(
            cupToken.target,
            false,
            1000,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );

        const amount = ethers.parseEther("10");
        await cupToken.mint(owner.address, amount);
        await cupToken.approve(maxStake.target, amount);

        const initialBalance = await cupToken.balanceOf(owner.address);

        // Perform the deposit
        await maxStake.deposit(0, amount);

        const userInfo = await maxStake.getUserInfo(0, owner.address);
        expect(userInfo.stAmount).to.equal(amount);

        const pool = await maxStake.pools(0);
        expect(pool.stTokenAmount).to.equal(amount);

        const finalBalance = await cupToken.balanceOf(owner.address);
        expect(finalBalance).to.equal(initialBalance-(amount));
    });

    it("Should distribute rewards correctly on subsequent deposits", async function () {
        await maxStake.add(
            cupToken.target,
            false,
            1000,
            ethers.parseEther("1"),
            ethers.parseEther("1")
        );

        const rewardAmount = BigInt(10**37);
        
        await rewardToken.mint(owner.address,rewardAmount);

        // 授权合约从所有者账户中转移 RewardToken
        await rewardToken.approve(maxStake.target, rewardAmount);

        await maxStake.fund(rewardAmount);

        const amount = ethers.parseEther("10");
        await cupToken.mint(owner.address, amount*BigInt(2));
        await cupToken.approve(maxStake.target, amount*BigInt(2));

        // Initial deposit
        await maxStake.deposit(0, amount);

        // Increase time to accumulate rewards
        await ethers.provider.send("evm_increaseTime", [1000]);
        await ethers.provider.send("evm_mine");

        const balance = await cupToken.balanceOf(owner.address);
        console.log("amount,cup balance",amount,balance);
        // Second deposit
        await maxStake.deposit(0, amount);

        const userInfo = await maxStake.getUserInfo(0, owner.address);
        expect(userInfo.stAmount).to.equal(amount*BigInt(2));

        const reward = await rewardToken.balanceOf(owner.address);
        expect(reward).to.be.gt(0); // Should be greater than zero as rewards should have been accumulated
    });

    //------------------------ test withdraw func ---------------------------------
    it("Should allow user to withdraw", async function () {
        await maxStake.add(cupToken.target, false, 1000, ethers.parseEther("1"), ethers.parseEther("1"));
        
        const amount = ethers.parseEther("10");
        await cupToken.mint(owner.address, amount);
        await cupToken.approve(maxStake.target, amount);
        await maxStake.connect(owner).deposit(0, amount);

        const rewardAmount = BigInt(10**37);
        
        await rewardToken.mint(owner.address,rewardAmount);

        // 授权合约从所有者账户中转移 RewardToken
        await rewardToken.approve(maxStake.target, rewardAmount);

        await maxStake.fund(rewardAmount);
        //--------------------以上是准备数据----------------------

        const pid = 0;
        const withdrawAmount = ethers.parseEther("5");
        
        const userInfo = await maxStake.getUserInfo(pid, owner.address);
        const initialStakedAmount = userInfo.stAmount;
        const initialReward = await maxStake.testPending(pid, owner.address);
        console.info("initialStakedAmount:,initialReward:",initialStakedAmount,initialReward);

        await maxStake.withdraw(pid, withdrawAmount);

        const userInfoAfter = await maxStake.getUserInfo(pid, owner.address);
        const finalStakedAmount = userInfoAfter.stAmount;
        const finalReward = await rewardToken.balanceOf(owner.address);
        const poolStTokenAmount = await maxStake.poolStTokenAmount(pid);

        expect(finalStakedAmount).to.equal(initialStakedAmount-(withdrawAmount));
        expect(poolStTokenAmount).to.equal(initialStakedAmount-(withdrawAmount));

        const rewardAfterWithdrawal = await rewardToken.balanceOf(owner.address);
        expect(rewardAfterWithdrawal).to.be.greaterThan(initialReward);
    });

    it("Should revert if withdraw amount is invalid", async function () {
        await expect(
            maxStake.connect(owner).withdraw(0, 0)
        ).to.be.revertedWith("Invalid Amount");
    });

    it("Should revert if withdraw amount exceeds staked amount", async function () {
        await maxStake.add(cupToken.target, false, 1000, ethers.parseEther("1"), ethers.parseEther("1"));
        
        const amount = ethers.parseEther("10");
        await cupToken.mint(owner.address, amount);
        await cupToken.approve(maxStake.target, amount);
        await maxStake.connect(owner).deposit(0, amount);

        const rewardAmount = BigInt(10**37);
        
        await rewardToken.mint(owner.address,rewardAmount);

        // 授权合约从所有者账户中转移 RewardToken
        await rewardToken.approve(maxStake.target, rewardAmount);

        await maxStake.fund(rewardAmount);


        const pid = 0;
        const withdrawAmount = ethers.parseEther("20"); // Exceeding staked amount

        await expect(
            maxStake.connect(owner).withdraw(pid, withdrawAmount)
        ).to.be.revertedWith("the balance less than amount");
    });


    it("Should allow user to claim rewards", async function () {
        await maxStake.add(cupToken.target, false, 1000, ethers.parseEther("1"), ethers.parseEther("1"));
        
        const amount = ethers.parseEther("10");
        await cupToken.mint(owner.address, amount);
        await cupToken.approve(maxStake.target, amount);
        await maxStake.deposit(0, amount);

        await rewardToken.mint(maxStake.target, ethers.parseEther("100")); // Mint reward tokens to contract

        await ethers.provider.send("evm_increaseTime", [1000]);
        await ethers.provider.send("evm_mine");

        const pid = 0;

        const initialRewardBalance = await rewardToken.balanceOf(owner.address);
        const pendingReward = await maxStake.testPending(pid, owner.address);

        await expect(maxStake.connect(owner).reward(pid))
            .to.emit(maxStake, 'Reward')
            .withArgs(pid);

        const finalRewardBalance = await rewardToken.balanceOf(owner.address);
        console.log("finalRewardBalance,initialRewardBalance,pendingReward",finalRewardBalance,initialRewardBalance,pendingReward);
        
        expect(finalRewardBalance).to.greaterThanOrEqual(initialRewardBalance+(pendingReward));

        const userInfo = await maxStake.getUserInfo(pid, owner.address);
        expect(userInfo.pendingB2).to.equal(0);
        expect(userInfo.finishedB2).to.greaterThanOrEqual(pendingReward);
    });

    it("Should revert if claim is paused", async function () {
        await maxStake.pauseClaim();

        await expect(
            maxStake.reward(0)
        ).to.be.revertedWith("claim is Paused");
    });


});
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PoolPriceFeed", function () {
    let PoolPriceFeed;
    let poolPriceFeed;
    let cupToken;
    let priceFeed;
    let pancakePair;
    let owner;
    let addr1;

    beforeEach(async function () {

        // Deploy mock Token
        const CupToken = await ethers.getContractFactory("CupToken")
        cupToken = await CupToken.deploy();
        await cupToken.waitForDeployment();

        // Deploy mock PriceFeed
        const PriceFeed = await ethers.getContractFactory("PriceFeed");
        priceFeed = await PriceFeed.deploy();
        await priceFeed.waitForDeployment();

        // Deploy mock PancakePair
        const PancakePair = await ethers.getContractFactory("PancakePair");
        pancakePair = await PancakePair.deploy();
        await pancakePair.waitForDeployment();

        // Get the ContractFactory and Signers here.
        PoolPriceFeed = await ethers.getContractFactory("PoolPriceFeed");
        [owner, addr1] = await ethers.getSigners();
        // console("owner,addr1",owner,addr1);
        // Deploy the contract.
        poolPriceFeed = await PoolPriceFeed.deploy();
        await poolPriceFeed.waitForDeployment();


        // Set initial configuration
        // await poolPriceFeed.setTokens(priceFeed.target, mockPriceFeed.address, mockPriceFeed.address);
        // await poolPriceFeed.setPairs(mockPancakePair.address, mockPancakePair.address, mockPancakePair.address);
        await poolPriceFeed.setTokenConfig(cupToken.target, priceFeed.target, 8, false);
      });


      it("Should set the correct initial values", async function () {
        expect(await poolPriceFeed.isAdmin(owner.address)).to.be.true;
      });

      it("Should set adjustment basis points correctly", async function () {
        await poolPriceFeed.setAdjustment(priceFeed.target, true, 10);
        expect(await poolPriceFeed.adjustmentBasisPoints(priceFeed.target)).to.equal(10);
        expect(await poolPriceFeed.isAdjustmentAdditive(priceFeed.target)).to.be.true;
      });

      it("Should set spread basis points correctly", async function () {
        await poolPriceFeed.setSpreadBasisPoints(priceFeed.target, 25);
        expect(await poolPriceFeed.spreadBasisPoints(priceFeed.target)).to.equal(25);
    });

    it("Should get primary price correctly", async function () {
        await priceFeed.setLatestAnswer(200000000); // Mock price feed response
        const price = await poolPriceFeed.getPrimaryPrice(cupToken.target, true);
        const expectedPrice = BigInt(200000000) * BigInt(10 ** 22);
        expect(price).to.equal(expectedPrice); // Adjust for PRICE_PRECISION
    });

    it("Should get AMM price correctly", async function () {
        await pancakePair.setReserves(1000, 2000); // Mock reserves
        const inputPrice = BigInt(1000) * BigInt(10 ** 30);
        const price = await poolPriceFeed.getAmmPrice(cupToken.target, true, inputPrice);
        expect(price).to.be.above(0);
    });

});
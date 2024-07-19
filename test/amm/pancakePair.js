const { expect } = require("chai");
const { ethers } = require("hardhat");


describe("PancakePair", function () {

    let PancakePair;
    let pancakePair;

    beforeEach(async function () {
        PancakePair = await ethers.getContractFactory("PancakePair");

        pancakePair = await PancakePair.deploy();
        await pancakePair.waitForDeployment();
    });


    it("Should set reserve0 and reserve1 correctly", async function () {

        await pancakePair.setReserves(100, 200);
        const [resultReserve0, resultReserve1, blockTimestampLast] = await pancakePair.getReserves();
        expect(resultReserve0).to.equal(100);
        expect(resultReserve1).to.equal(200);
      });

});
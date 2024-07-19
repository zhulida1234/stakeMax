const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PriceFeed", function () {
  let PriceFeed;
  let priceFeed;
  let owner;
  let addr1;

  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    PriceFeed = await ethers.getContractFactory("PriceFeed");
    [owner, addr1] = await ethers.getSigners();
    // console("owner,addr1",owner,addr1);
    // Deploy the contract.
    priceFeed = await PriceFeed.deploy();
    await priceFeed.waitForDeployment();
  });

  it("Should set the correct initial values", async function () {
    expect(await priceFeed.isAdmin(owner.address)).to.be.true;
  });

  it("Should allow the owner to set admin", async function () {
    await priceFeed.setAdmin(addr1.address, true);
    expect(await priceFeed.isAdmin(addr1.address)).to.be.true;

    await priceFeed.setAdmin(addr1.address, false);
    expect(await priceFeed.isAdmin(addr1.address)).to.be.false;
  });

  it("Should not allow non-owner to set admin", async function () {
    await expect(priceFeed.connect(addr1).setAdmin(addr1.address, true)).to.be.revertedWith("PriceFeed: forbidden");
  });

  it("Should allow admin to set latest answer", async function () {
    await priceFeed.setLatestAnswer(100);
    expect(await priceFeed.latestAnswer()).to.equal(100);
  });

  it("Should not allow non-admin to set latest answer", async function () {
    await expect(priceFeed.connect(addr1).setLatestAnswer(100)).to.be.revertedWith("PriceFeed: forbidden");
  });

  it("Should update roundId and answer correctly", async function () {
    await priceFeed.setLatestAnswer(100);
    expect(await priceFeed.latestAnswer()).to.equal(100);
    expect(await priceFeed.latestRound()).to.equal(1);

    await priceFeed.setLatestAnswer(200);
    expect(await priceFeed.latestAnswer()).to.equal(200);
    expect(await priceFeed.latestRound()).to.equal(2);
  });

  it("Should return correct round data", async function () {
    await priceFeed.setLatestAnswer(100);
    const roundData = await priceFeed.getRoundData(1);
    expect(roundData[1]).to.equal(100);
  });
});
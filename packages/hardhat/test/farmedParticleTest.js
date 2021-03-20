const { ethers } = require("hardhat");
const { use, expect } = require("chai");
const { solidity } = require("ethereum-waffle");

use(solidity);

describe("Farmed Paticle Dapp", function () {
  let farmedParticleContract;

  describe("deploy FarmedParticle", function () {
    it("Should deploy FarmedParticle", async function () {
      const [owner] = await ethers.getSigners();

      const FarmedParticle = await ethers.getContractFactory("FarmedParticle");

      farmedParticleContract = await FarmedParticle.deploy(owner.address, 2);
    });

    describe("setHarvestThresholds()", function () {
      it("Should be able to set new harvest thresholds", async function () {
        const newFullThreshold = 10;
        const newHalfThreshold = 5;

        await farmedParticleContract.setHarvestThresholds(newFullThreshold, newHalfThreshold);
        expect(await farmedParticleContract.getFullHarvestThreshold()).to.equal(newFullThreshold);
        expect(await farmedParticleContract.getHalfHarvestThreshold()).to.equal(newHalfThreshold);
      });
    });
  });
});

/* eslint no-use-before-define: "warn" */
const fs = require("fs");
const chalk = require("chalk");
const { config, ethers, tenderly, run } = require("hardhat");
const { utils } = require("ethers");
const R = require("ramda");


const main = async () => {

  console.log("\n\n 📡 Deploying...\n");

  // read in all the assets to get their IPFS hash...
  let uploadedAssets = JSON.parse(fs.readFileSync("./uploaded.json"))
  let bytes32Array = []
  for(let a in uploadedAssets){
    console.log(" 🏷 IPFS:",a)
    let bytes32 = utils.id(a)
    console.log(" #️⃣ hashed:",bytes32)
    bytes32Array.push(bytes32)
  }
  console.log(" \n")

  const creatorAddressKovan = "0x3a5098C1dce83D2DAe00719f63e17e6447a13023";
  const creatorAnnuity = 5;

  // deploy the contract with all the artworks forSale
  // const yourCollectible = await deploy("YourCollectible",[ bytes32Array ]) // <-- add in constructor args like line 19 vvvv

  //const yourContract = await ethers.getContractAt('YourContract', "0xaAC799eC2d00C013f1F11c37E654e59B0429DF6A") //<-- if you want to instantiate a version of a contract at a specific address!
  const farmedParticleContract = await deploy("FarmedParticle", [creatorAddressKovan, creatorAnnuity])

  // TODO after deploy:
  // setChargedParticles - kovan: 0xF03EAB2b60eFB6E24C1b254A2D6fC91Eb639D6d3
  // setChargedSettings - kovan: 0x57B5C64E0494a7Bd4A98B33C105E3ef31301dFdF
  // setChargedState - kovan: 0xD63423049022bd77C530aD6f293Bc4209A6d565B
  // setAssetTokenMap:
  //   dai: 0xff795577d9ac8bd7d90ee22b6c1703490b6512fd
  //   uni: 0x075a36ba8846c6b6f53644fdd3bf17e5151789dc
  //   usdc: 0xe22da380ee6b445bb8273c81944adeb6e8450422
  // setStatusToTokenURIMap
  //   emptyUri: https://ipfs.io/ipfs/bafkreichleu2uxowpv657abpzw7rhx3dziz5affbdwek2rywowgvxh6owm
  //   plantedUri: https://ipfs.io/ipfs/bafkreig4fzs7ldjzlm4lfcabofwpjr74dj5lsjvfizcafqnugrohdkgndm
  //   halfDaiUri: https://ipfs.io/ipfs/bafkreibszz3qdrfvll5hq4t4xbqu3pksbfem23idpgmyimfe77ht7ctmrq
  //   halfUniUri: https://ipfs.io/ipfs/bafkreihh4jp2mschybttfsogsqo624tdjpqkdaevpa3cnyko3lvswsned4
  //   halfUsdcUri: https://ipfs.io/ipfs/bafkreicpzmnhifgysl57omc333q72ayny6kf4tb7mgwnmi3hwzb73o7tci
  //   fullDaiUri: https://ipfs.io/ipfs/bafkreiftngc7f2ms273dktxtvrrkmvsklmnu2dakwrzhglnpjtjb4oein4
  //   fullUniUri: https://ipfs.io/ipfs/bafkreiggbbfwbsddjequgwoadrvaysing3eqldvlyjmdqmt3sbpbo4pzo4
  //   fullUsdcUri: https://ipfs.io/ipfs/bafkreig3r4dz665h6p4wcudfg47ucrbgzrzgvkpehvf2i53ulcidyik7ni

  // const exampleToken = await deploy("ExampleToken")
  // const examplePriceOracle = await deploy("ExamplePriceOracle")
  // const smartContractWallet = await deploy("SmartContractWallet",[exampleToken.address,examplePriceOracle.address])

  /*
  //If you want to send value to an address from the deployer
  const deployerWallet = ethers.provider.getSigner()
  await deployerWallet.sendTransaction({
    to: "0x34aA3F359A9D614239015126635CE7732c18fDF3",
    value: ethers.utils.parseEther("0.001")
  })
  */


  /*
  //If you want to send some ETH to a contract on deploy (make your constructor payable!)
  const yourContract = await deploy("YourContract", [], {
  value: ethers.utils.parseEther("0.05")
  });
  */


  /*
  //If you want to link a library into your contract:
  // reference: https://github.com/austintgriffith/scaffold-eth/blob/using-libraries-example/packages/hardhat/scripts/deploy.js#L19
  const yourContract = await deploy("YourContract", [], {}, {
   LibraryName: **LibraryAddress**
  });
  */


  //If you want to verify your contract on tenderly.co (see setup details in the scaffold-eth README!)
  /*
  await tenderlyVerify(
    {contractName: "YourContract",
     contractAddress: yourContract.address
  })
  */

  // If you want to verify your contract on etherscan
  /*
  console.log(chalk.blue('verifying on etherscan'))
  await run("verify:verify", {
    address: farmedParticleContract.address,
    constructorArguments: [creatorAddressKovan, creatorAnnuity] // If your contract has constructor arguments, you can pass them as an array
  })
  */

  console.log(
    " 💾  Artifacts (address, abi, and args) saved to: ",
    chalk.blue("packages/hardhat/artifacts/"),
    "\n\n"
  );
};

const deploy = async (contractName, _args = [], overrides = {}, libraries = {}) => {
  console.log(` 🛰  Deploying: ${contractName}`);

  const contractArgs = _args || [];
  const contractArtifacts = await ethers.getContractFactory(contractName,{libraries: libraries});
  const deployed = await contractArtifacts.deploy(...contractArgs, overrides);
  const encoded = abiEncodeArgs(deployed, contractArgs);
  fs.writeFileSync(`artifacts/${contractName}.address`, deployed.address);

  let extraGasInfo = ""
  if(deployed&&deployed.deployTransaction){
    const gasUsed = deployed.deployTransaction.gasLimit.mul(deployed.deployTransaction.gasPrice)
    extraGasInfo = `${utils.formatEther(gasUsed)} ETH, tx hash ${deployed.deployTransaction.hash}`
  }

  console.log(
    " 📄",
    chalk.cyan(contractName),
    "deployed to:",
    chalk.magenta(deployed.address)
  );
  console.log(
    " ⛽",
    chalk.grey(extraGasInfo)
  );

  await tenderly.persistArtifacts({
    name: contractName,
    address: deployed.address
  });

  if (!encoded || encoded.length <= 2) return deployed;
  fs.writeFileSync(`artifacts/${contractName}.args`, encoded.slice(2));

  return deployed;
};


// ------ utils -------

// abi encodes contract arguments
// useful when you want to manually verify the contracts
// for example, on Etherscan
const abiEncodeArgs = (deployed, contractArgs) => {
  // not writing abi encoded args if this does not pass
  if (
    !contractArgs ||
    !deployed ||
    !R.hasPath(["interface", "deploy"], deployed)
  ) {
    return "";
  }
  const encoded = utils.defaultAbiCoder.encode(
    deployed.interface.deploy.inputs,
    contractArgs
  );
  return encoded;
};

// checks if it is a Solidity file
const isSolidity = (fileName) =>
  fileName.indexOf(".sol") >= 0 && fileName.indexOf(".swp") < 0 && fileName.indexOf(".swap") < 0;

const readArgsFile = (contractName) => {
  let args = [];
  try {
    const argsFile = `./contracts/${contractName}.args`;
    if (!fs.existsSync(argsFile)) return args;
    args = JSON.parse(fs.readFileSync(argsFile));
  } catch (e) {
    console.log(e);
  }
  return args;
};

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

// If you want to verify on https://tenderly.co/
const tenderlyVerify = async ({contractName, contractAddress}) => {

  let tenderlyNetworks = ["kovan","goerli","mainnet","rinkeby","ropsten","matic","mumbai","xDai","POA"]
  let targetNetwork = process.env.HARDHAT_NETWORK || config.defaultNetwork

  if(tenderlyNetworks.includes(targetNetwork)) {
    console.log(chalk.blue(` 📁 Attempting tenderly verification of ${contractName} on ${targetNetwork}`))

    await tenderly.persistArtifacts({
      name: contractName,
      address: contractAddress
    });

    let verification = await tenderly.verify({
        name: contractName,
        address: contractAddress,
        network: targetNetwork
      })

    return verification
  } else {
      console.log(chalk.grey(` 🧐 Contract verification not supported on ${targetNetwork}`))
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

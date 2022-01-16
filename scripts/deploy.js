// This is a script for deploying your contracts. You can adapt it to deploy
// yours, or create new ones.
async function main() {
    // This is just a convenience check
    if (network.name === "hardhat") {
      console.warn(
        "You are trying to deploy a contract to the Hardhat Network, which" +
          "gets automatically created and destroyed every time. Use the Hardhat" +
          " option '--network localhost'"
      );
    }
  
    // ethers is avaialble in the global scope
    const [deployer] = await ethers.getSigners();
    const deployerAddr = await deployer.getAddress();
    console.log(
      "Deploying the contracts with the account:",
      deployerAddr
    );
  
    console.log("Account balance:", (await deployer.getBalance()).toString());
  
    const Program = await ethers.getContractFactory("Program");
    const program = await Program.deploy();
    await program.deployed();
    console.log("Program address:", program.address);

    const Developer = await ethers.getContractFactory("Developer");
    const developer = await Developer.deploy(program.address);
    await developer.deployed();
    console.log("Developer address:", developer.address);

    // const Loot = await ethers.getContractFactory("Loot");
    // const loot = await Loot.deploy();
    // await loot.deployed();
    // console.log("Loot address:", loot.address);
    
    const lootAddr = "0x2c9079c7005022DD53cc283c9fE54290E8038aBC";
    const Robot = await ethers.getContractFactory("Robot");
    const robot = await Robot.deploy(program.address, lootAddr);
    await robot.deployed();
    console.log("robot address:", robot.address);

    const RobocupCompetitionPlatform = await ethers.getContractFactory("RobocupCompetitionPlatform");
    const robocup = await RobocupCompetitionPlatform.deploy(robot.address, program.address);
    await robocup.deployed();
    console.log("RobocupCompetitionPlatform address:", robocup.address);
  }
  
  function saveFrontendFiles(program) {
    const fs = require("fs");  
    const contractsDir = __dirname + "/../frontend/ethereum-boilerplate/src/contracts";
  
    if (!fs.existsSync(contractsDir)) {
      fs.mkdirSync(contractsDir);
    }
  
    fs.writeFileSync(
      contractsDir + "/contract-address.json",
      JSON.stringify({ Program: program.address }, undefined, 2)
    );
  
    const ProgramArtifact = artifacts.readArtifactSync("Program");
  
    fs.writeFileSync(
      contractsDir + "/Program.json",
      JSON.stringify(ProgramArtifact, null, 2)
    );
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
  
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


    const Robot = await ethers.getContractFactory("Robot");
    const robot = await Robot.deploy(program.address);
    await robot.deployed();
    console.log("robot address:", robot.address);

    const RobocupCompetitionPlatform = await ethers.getContractFactory("RobocupCompetitionPlatform");
    const robocup = await RobocupCompetitionPlatform.deploy(robot.address, program.address);
    await robocup.deployed();
    console.log("RobocupCompetitionPlatform address:", robocup.address);
  
    console.log("start set program");
    await program.setDevContractAddr(developer.address);
    await program.setSupportAbility("AISoccer", true);
    await program.setAbilityInitNumber("AISoccer", 1);

    console.log("start set developer");
    await developer.registerDev("Sam", "full stack engineer on blockchain industry", "0x0000000000000000000000000000000000000000", 0, "https://pbs.twimg.com/profile_images/1454759537429266436/BX-zxPAo_400x400.jpg", "https://github.com/syslink");
    await developer.registerProgram("AISoccer", 1, 0, "0x12345678", "champion program", "https://github.com/AISoccerMaster");
    await developer.registerProgram("AISoccer", 1, 1, "0x23456789", "champion program", "https://github.com/AISoccerMaster");

    const programNum = await program.getUserTokenNumber(deployerAddr);
    const programIds = await program.getUserTokenIds(deployerAddr, 0, 2);
    console.log("programNum = ", programNum, programIds);
    await robot.setRobocup(robocup.address);

    var mintPrice = await robot.getCurrentPriceToMint(3);
    console.log("mint 3 price", mintPrice.toString());
    await robot.mint(3, mintPrice.toHexString(), {value: mintPrice.toHexString()});
    
    var burnPrice = await robot.getCurrentPriceToBurn(1);
    console.log("burn 1 price", burnPrice.toString());
    burnPrice = await robot.getCurrentPriceToBurn(2);
    console.log("burn 2 price", burnPrice.toString());
    burnPrice = await robot.getCurrentPriceToBurn(3);
    console.log("burn 3 price", burnPrice.toString());

    mintPrice = await robot.getCurrentPriceToMint(1);
    console.log("mint 1 price", mintPrice.toString());
    await robot.mint(1, mintPrice.toHexString(), {value: mintPrice.toHexString()});

    console.log("start bind program with robot");
    await program.setApprovalForAll(robot.address, true);
    var robotId_1 = await robot.tokenOfOwnerByIndex(deployerAddr, 0);
    await robot.bindProgram2Robot(programIds[0], robotId_1);

    var robotId_2 = await robot.tokenOfOwnerByIndex(deployerAddr, 1);
    await robot.bindProgram2Robot(programIds[1], robotId_2);
    console.log("RobotId:", robotId_1, robotId_2);

    console.log("start competition of robocup");
    await robocup.setEmulatePlatform("0xF0d219afAfDc79b81344534c37Bc69Fc64091F85", true);
    await robocup.addExpectRobotWithProgram(robotId_1, 1);
    await robocup.addExpectRobotWithProgram(robotId_2, 2);
    await robocup.launchChallenge(robotId_1, 1, robotId_2, 2, {value: ethers.utils.parseEther("0.01")});
    var competitionInfo = await robocup.tokenId2CompetitionMap(1);
    console.log(competitionInfo);
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
  
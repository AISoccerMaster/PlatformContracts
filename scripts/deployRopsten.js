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
    const program = await Program.attach("0x939cEc587C391Fa17ddbaFc7577e115e6AAD8E74");

    const Developer = await ethers.getContractFactory("Developer");
    const developer = await Developer.attach("0x344af095C889456e810C25252b41C891A21F1E35");

    const Robot = await ethers.getContractFactory("Robot");
    const robot = await Robot.attach("0x19F3fb33fE394A8B6c132E92DE3ff2157598678D");

    const RobocupCompetitionPlatform = await ethers.getContractFactory("RobocupCompetitionPlatform");
    const robocup = await RobocupCompetitionPlatform.attach("0x7D0719491fbc1D1D4f65b185a729756541c3b16f");
    
    const startFrom = 7;

    if (startFrom <= 1) {
        console.log("start set program");
        await program.setDevContractAddr(developer.address);
        await program.setSupportAbility("AISoccer", true);
        await program.setAbilityInitNumber("AISoccer", 1);
    }

    if (startFrom <= 2) {
        console.log("start set developer");
        await developer.registerDev("Sam", "full stack engineer on blockchain industry", "0x0000000000000000000000000000000000000000", 0, "https://pbs.twimg.com/profile_images/1454759537429266436/BX-zxPAo_400x400.jpg", "https://github.com/syslink");
        await developer.registerProgram("AISoccer", 1, 0, "0x12345678", "champion program", "https://github.com/AISoccerMaster");
        await developer.registerProgram("AISoccer", 1, 1, "0x23456789", "champion program", "https://github.com/AISoccerMaster");
        await developer.registerProgram("AISoccer", 1, 2, "0x23456789", "champion program", "https://github.com/AISoccerMaster");

        const programNum = await program.getUserTokenNumber(deployerAddr);
        const programIds = await program.getUserTokenIds(deployerAddr, 0, programNum);
        console.log("programNum = ", programNum, programIds);
    }

    if (startFrom <= 3) {
        console.log("start set robot");
        await robot.setRobocup(robocup.address);
    }

    if (startFrom <= 4) {
        var mintPrice = await robot.getCurrentPriceToMint(2);
        console.log("mint 2 price", mintPrice.toString());
        await robot.mint(2, mintPrice.toHexString(), {value: mintPrice.toHexString()});
    }

    var robotId_1 = await robot.tokenOfOwnerByIndex(deployerAddr, 0);
    var robotId_2 = await robot.tokenOfOwnerByIndex(deployerAddr, 1);
    console.log("robotIds = ", robotId_1, robotId_2);

    if (startFrom <= 5) {
        console.log("start bind program with robot");
        await program.setApprovalForAll(robot.address, true);
        
        const programNum = await program.getUserTokenNumber(deployerAddr);
        const programIds = await program.getUserTokenIds(deployerAddr, 0, programNum);
        console.log("programNum = ", programNum, programIds);

        console.log("bind 1");
        await robot.bindProgram2Robot(programIds[0], robotId_1);

        console.log("bind 2");
        await robot.bindProgram2Robot(programIds[1], robotId_2);
    }

    if (startFrom <= 6) {
        console.log("start competition of robocup");
        await robocup.setEmulatePlatform("0xF0d219afAfDc79b81344534c37Bc69Fc64091F85", true);
        
        console.log("start add expected robot");
        
        var hasContained = await robocup.checkRobotContainProgram(robotId_1, 1);
        if (!hasContained) {
            await robocup.addExpectRobotWithProgram(robotId_1, 1);
        }
        hasContained = await robocup.checkRobotContainProgram(robotId_2, 2);
        if (!hasContained) {
            await robocup.addExpectRobotWithProgram(robotId_2, 2);
        }
    }

    if (startFrom <= 7) {  
      console.log("start launch challenge");
      await robocup.launchChallenge(robotId_1, 1, robotId_2, 2, {value: ethers.utils.parseEther("0.01")});
      var competitionInfo = await robocup.tokenId2CompetitionMap(1);
      console.log(competitionInfo);
    }
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
  
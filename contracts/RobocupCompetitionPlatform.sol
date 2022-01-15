// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./Base64.sol";

interface IRobot is IERC721 {
    function checkRobotContainProgram(uint256 _robotId, uint256 _programId) view external returns(bool); 
}

interface IProgram {
    function getAbility(uint256 _programId) view external returns(string memory);
}

contract RobocupCompetitionPlatform is ERC721Enumerable, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;

    string public constant AbilityName = "AISoccer";
    mapping(uint256 => EnumerableSet.UintSet) private expectRobotProgramMap;  // the robots which wanna competition
    EnumerableSet.UintSet private expectRobotIds;

    uint256 public constant MAX_INT = 2**256 - 1;
    uint256 public FeePerCompetition = .001 ether;

    IRobot public robotContract;
    IProgram public programContract;

    enum CompetitionStatus { NotStart, Running, End }
    struct CompetitionInfo {
        uint256 id;
        
        uint256 robotOneId;
        uint256 programOneId;

        uint256 robotTwoId;
        uint256 programTwoId;

        uint256 startTime;
        uint256 endTime;

        uint256 robotOneScore;
        uint256 robotTwoScore;

        string logHash;
        string monitorUrl;
    }
    uint256 public tokenId;    
    mapping(uint256 => CompetitionInfo) public tokenId2CompetitionMap;
    mapping(uint256 => mapping(uint256 => EnumerableSet.UintSet)) private robot2Program2CompetitionIdsMap;
    
    EnumerableSet.AddressSet private emulatePlatforms;
    mapping(address => mapping(CompetitionStatus => EnumerableSet.UintSet)) private ep2Status2CompetitionIdsMap;
    mapping(uint256 => address) public competitionId2EpMap;

    constructor(address _robotContract, address _programContract) ERC721("Robocup Competition", "RBC") Ownable() {
        robotContract = IRobot(_robotContract);
        programContract = IProgram(_programContract);
    }

    function setEmulatePlatform(address _emulatePlatform, bool bAdded) external onlyOwner {
        bAdded ? emulatePlatforms.add(_emulatePlatform) : emulatePlatforms.remove(_emulatePlatform);
    }

    function addExpectRobotWithProgram(uint256 _robotId, uint256 _programId) external {
        require(!expectRobotProgramMap[_robotId].contains(_programId), "Robocup: robot with the program has been contained");
        require(robotContract.ownerOf(_robotId) == msg.sender, "Robocup: Not owner of robot");
        require(robotContract.checkRobotContainProgram(_robotId, _programId), "Robocup: robot does NOT contain the program");
        require(compareStrings(programContract.getAbility(_programId), AbilityName), "Robocup: program's ability is NOT AISoccer");

        expectRobotProgramMap[_robotId].add(_programId);
        if (!expectRobotIds.contains(_robotId)) expectRobotIds.add(_robotId);
    }

    function removeExpectRobotWithProgram(uint256 _robotId, uint256 _programId) external {
        require(expectRobotProgramMap[_robotId].contains(_programId), "Robocup: robot with the program has NOT been contained");
        require(robotContract.ownerOf(_robotId) == msg.sender, "Robocup: Not owner of robot");
        EnumerableSet.UintSet storage competitionIds = robot2Program2CompetitionIdsMap[_robotId][_programId];
        for (uint256 i = 0; i < competitionIds.length(); i++) {
            uint256 competitionId = competitionIds.at(i);
            CompetitionStatus status = getCompetitionStatus(competitionId);
            require(status == CompetitionStatus.End, "Robocup: there is still competition to attend");
        }
        expectRobotProgramMap[_robotId].remove(_programId);
        if (expectRobotProgramMap[_robotId].length() == 0) expectRobotIds.remove(_robotId);
    }

    function launchChallenge(uint256 _myRobotId, uint256 _myProgramId, uint256 _peerRobotId, uint256 _peerProgramId) payable external {
        require(msg.value == FeePerCompetition, "Robocup: NOT enough fee");
        require(robotContract.ownerOf(_myRobotId) == msg.sender, "Robocup: Not owner of robot");
        require(expectRobotProgramMap[_myRobotId].contains(_myProgramId), "Robocup: my robot with the program has NOT been contained");
        require(expectRobotProgramMap[_peerRobotId].contains(_peerProgramId), "Robocup: peer robot with the program has NOT been contained");
        require(compareStrings(programContract.getAbility(_myProgramId), AbilityName), "Robocup: my program's ability is NOT AISoccer");
        require(compareStrings(programContract.getAbility(_peerProgramId), AbilityName), "Robocup: peer program's ability is NOT AISoccer");

        tokenId++;
        tokenId2CompetitionMap[tokenId] = CompetitionInfo(tokenId, _myRobotId, _myProgramId, _peerRobotId, _peerProgramId, MAX_INT, MAX_INT, 0, 0, "", "");

        robot2Program2CompetitionIdsMap[_myRobotId][_myProgramId].add(tokenId);
        robot2Program2CompetitionIdsMap[_peerRobotId][_peerProgramId].add(tokenId);

        _mint(msg.sender, tokenId);
    }

    function getCompetitionStatus(uint256 _competitionId) view public returns(CompetitionStatus) {
        CompetitionInfo memory competitionInfo = tokenId2CompetitionMap[_competitionId];
        if (block.timestamp < competitionInfo.startTime) return CompetitionStatus.NotStart;
        if (block.timestamp >= competitionInfo.startTime && block.timestamp <= competitionInfo.endTime) return CompetitionStatus.Running;
        return CompetitionStatus.End;
    }

    function getAllExpectRobotNumber() view external returns(uint256) {
        return expectRobotIds.length();
    }

    function getAllExpectRobotIds(uint256 _fromIndex, uint256 _toIndex) view external returns(uint256[] memory robotIds) {
        uint256 length = expectRobotIds.length();
        if (_toIndex > length) _toIndex = length;
        require(_fromIndex < _toIndex, "Robocup: index out of range!");

        robotIds = new uint256[](_toIndex - _fromIndex);
        uint256 count = 0;
        for (uint256 i = _fromIndex; i < _toIndex; i++) {
            robotIds[count++] = expectRobotIds.at(i);
        }
    }

    function checkRobotContainProgram(uint256 _robotId, uint256 _programId) view external returns(bool) {
        return expectRobotProgramMap[_robotId].contains(_programId);
    }

    function getProgramsOfRobot(uint256 _robotId) view external returns(uint256[] memory programIds) {
        uint256 length = expectRobotProgramMap[_robotId].length();
        programIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            programIds[i] = expectRobotProgramMap[_robotId].at(i);
        }
    }

    function takeCompetition(uint256 _competitionId, uint256 _startTime) external {
        require(emulatePlatforms.contains(msg.sender), "Robocup: NOT legal emulate platform");
        require(competitionId2EpMap[_competitionId] == address(0), "Robocup: competition has been taken");  

        tokenId2CompetitionMap[_competitionId].startTime = _startTime;
        ep2Status2CompetitionIdsMap[msg.sender][CompetitionStatus.NotStart].add(_competitionId);
        competitionId2EpMap[_competitionId] = msg.sender;
    }

    function setCompetitionRunning(uint256 _competitionId, string memory _monitorUrl) external {
        require(competitionId2EpMap[_competitionId] == msg.sender, "Robocup: NOT the emulate platform of the competition");  

        tokenId2CompetitionMap[_competitionId].monitorUrl = _monitorUrl;
        ep2Status2CompetitionIdsMap[msg.sender][CompetitionStatus.NotStart].remove(_competitionId);
        ep2Status2CompetitionIdsMap[msg.sender][CompetitionStatus.Running].add(_competitionId);
    }   

    function setCompetitionResult(uint256 _competitionId, uint256 _endTime, uint256 _robotOneScore, uint256 _robotTwoScore, string memory _logHash) external {
        require(competitionId2EpMap[_competitionId] == msg.sender, "Robocup: NOT the emulate platform of the competition");  

        tokenId2CompetitionMap[_competitionId].endTime = _endTime;
        tokenId2CompetitionMap[_competitionId].robotOneScore = _robotOneScore;
        tokenId2CompetitionMap[_competitionId].robotTwoScore = _robotTwoScore;
        tokenId2CompetitionMap[_competitionId].logHash = _logHash;

        ep2Status2CompetitionIdsMap[msg.sender][CompetitionStatus.Running].remove(_competitionId);
        ep2Status2CompetitionIdsMap[msg.sender][CompetitionStatus.End].add(_competitionId);

        payable(msg.sender).transfer(FeePerCompetition);
    }    

    function getCompetitionInfos(address _epAddr, CompetitionStatus status) view external returns(CompetitionInfo[] memory competitionInfos) {
        uint256 length = ep2Status2CompetitionIdsMap[_epAddr][status].length();

        competitionInfos = new CompetitionInfo[](length);
        for (uint256 i = 0; i < length; i++) {
            competitionInfos[i] = tokenId2CompetitionMap[ep2Status2CompetitionIdsMap[_epAddr][status].at(i)];
        }
    }
    
    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        CompetitionInfo memory competitionInfo = tokenId2CompetitionMap[_tokenId];
        CompetitionStatus status = getCompetitionStatus(_tokenId);
        string[9] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';

        parts[1] = string(abi.encodePacked("Robot.Program#", competitionInfo.robotOneId.toString(), ".", competitionInfo.programOneId.toString(), 
                                        "VS Robot.Program#", competitionInfo.robotTwoId.toString(), ".", competitionInfo.programTwoId.toString()));

        parts[2] = '</text><text x="10" y="40" class="base">';
        
        if (status == CompetitionStatus.End) {
            parts[3] = string(abi.encodePacked("Score(End):", competitionInfo.robotOneScore.toString(), " : ", competitionInfo.robotTwoScore.toString()));
            
            parts[4] = '</text><text x="10" y="60" class="base">';

            parts[5] = string(abi.encodePacked("TimeStamp:", competitionInfo.startTime.toString(), " - ", competitionInfo.endTime.toString()));
        } else if (status == CompetitionStatus.Running) {
            parts[3] = string(abi.encodePacked("Running Now"));
            
            parts[4] = '</text><text x="10" y="60" class="base">';

            parts[5] = string(abi.encodePacked("TimeStamp:", competitionInfo.startTime.toString(), " - "));
        } else {
            parts[3] = string(abi.encodePacked("Not Started"));
            
            parts[4] = '</text><text x="10" y="60" class="base">';

            parts[5] = string(abi.encodePacked("TimeStamp: - "));
        }

        parts[6] = '</text><text x="10" y="60" class="base">';

        parts[7] = string(abi.encodePacked("LogHash:", competitionInfo.logHash));

        parts[8] = '</text></svg>';

        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]));
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Robocup Competition #', _tokenId.toString(), '", "description": "Robocup competition records the battle between robots.", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function compareStrings(string memory a, string memory b) public view returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
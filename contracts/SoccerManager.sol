pragma solidity 0.8.10;
import "./RobotMgr.sol";

contract SoccerManager {
  struct RobotTeam {
    uint256 id;
    string name;
    string logoUrl;
    address owner;
    bool removed;
    uint256[] robotIdArr;
    uint256[] competitionDates;
  }

  RobotTeam[] public robotTeams;
  mapping(address => uint256[]) public managerToRobotTeam;  // soccer manager => team ids
  mapping(uint256 => uint256) public robotToTeamMap;        // robot id => team id
  RobotMgr robotMgr;
  address competitionAddr;

  event NewTeamCreated(address indexed owner, uint256 teamIdID, string name);

  modifier teamOwner(uint256 _teamId) {
    require(robotTeams.length > _teamId, "The team is not exist!");
    require(robotTeams[_teamId].owner == msg.sender, "You are not the owner of this team!");
    _;
  }

  modifier robotOwner(uint256 _robotId) {
    require(robotMgr.robotIndexToOwner(_robotId) == msg.sender, "You are not the owner of this robot!");
    _;
  }

  modifier canUpdateRobot(uint256 _teamId) {
    require(!isSealedNow(_teamId), "A competition will be coming, the team can not update the robot!");
    _;
  }
  // 判断此俱乐部球员此时是否已不可变动，在比赛前一小时和比赛后20分钟内不可变
  function isSealedNow(uint256 _teamId) view public returns(bool) {
    uint256[] memory competitionDates = robotTeams[_teamId].competitionDates;
    for(uint256 i = competitionDates.length - 1; i >= 0; i--) {
      if(now >= competitionDates[i] - 3600 && now < competitionDates[i] + 10 * 60 * 2) {
        return true;
      }
    }
    return false;
  }
  // 设置机器人合约地址
  function setRobotMgr(address robotMgrAddr) public {
      robotMgr = RobotMgr(robotMgrAddr);
  }
  // 设置比赛合约地址
  function setCompetition(address _competitionAddr) public {
      competitionAddr = _competitionAddr;
  }
  // 创建队伍
  function createTeam(string memory _name, string memory _logoUrl) public {
      uint256 teamId = uint256(robotTeams.length);
      RobotTeam memory robotTeam = RobotTeam({
        id:teamId, name:_name, logoUrl:_logoUrl, owner:msg.sender, removed:false,
        robotIdArr:new uint256[](0), competitionDates:new uint256[](0)});
      robotTeams.push(robotTeam);
      managerToRobotTeam[msg.sender].push(teamId);
      emit NewTeamCreated(msg.sender, teamId, _name);
  }
  // 移除队伍
  function removeTeam(uint256 _teamId) public teamOwner(_teamId) {
      robotTeams[_teamId].removed = true;
  }
  // 恢复队伍
  function recoverTeam(uint256 _teamId) public teamOwner(_teamId) {
      robotTeams[_teamId].removed = false;
  }
   // 添加队伍比赛日期
  function addCompetitionDate(uint256 _teamId, uint256 date) public {
    require(msg.sender == competitionAddr, "Only competition contract can call this function.");
    robotTeams[_teamId].competitionDates.push(date);
  }
   // 将机器人添加到队伍中
  function addRobotToTeam(uint256 _robotId, uint256 _teamId) public teamOwner(_teamId) canUpdateRobot(_teamId) returns(bool) {
    address usageRightOwner = robotMgr.getRobotUsageRightOwner(_robotId);
    require(usageRightOwner == msg.sender, "You don't have the operator right of the robot.");

    bool bExist;
    uint teamId;
    (bExist, teamId) = isRobotAddedToTeam(_robotId);
    require (bExist && teamId !=_teamId, "Robot has been added to another team.");
    if (bExist && teamId ==_teamId) {
      return true;
    }

    robotTeams[_teamId].robotIdArr.push(_robotId);
    robotToTeamMap[_robotId] = _teamId;
    return true;
  }
  // 将机器人从队伍中移除
  function removeRobotFromTeam(uint256 _robotId, uint256 _teamId) public teamOwner(_teamId) canUpdateRobot(_teamId) returns(bool) {
    address usageRightOwner = robotMgr.getRobotUsageRightOwner(_robotId);
    require(usageRightOwner == msg.sender, "You don't have the operator right of the robot.");

    uint256 index;
    bool bExist;
    (index, bExist) = isRobotInTeam(_robotId, _teamId);
    require(bExist == true, "The robot is not in this team!");

    uint256 length = robotTeams[_teamId].robotIdArr.length;
    for(uint256 i = index; i < length - 1; i++) {
      robotTeams[_teamId].robotIdArr[i] = robotTeams[_teamId].robotIdArr[i + 1];
    }
    delete robotTeams[_teamId].robotIdArr[length - 1];
    robotTeams[_teamId].robotIdArr.length--;
    delete robotToTeamMap[_robotId];

    return true;
  }
  // 获取机器人所在队伍的ID
  function isRobotAddedToTeam(uint256 _robotId) view public returns(bool, uint256) {
    if (robotTeams.length == 0) {
      return (false, 0);
    }
    uint256 teamId = robotToTeamMap[_robotId];
    if (teamId > 0) {
      return (true, teamId);
    } else {
      for(uint256 i = 0; i < robotTeams[0].robotIdArr.length; i++) {
        if(robotTeams[0].robotIdArr[i] == _robotId) {
          return (true, 0);
        }
      }
    }
    return (false, 0);
  }
  // 判断机器人是否在指定队伍中
  function isRobotInTeam(uint256 _robotId, uint256 _teamId) view private returns(uint256, bool) {
      require(robotTeams.length > _teamId, "The team is not exist.");
      for(uint256 i = 0; i < robotTeams[_teamId].robotIdArr.length; i++) {
          if(robotTeams[_teamId].robotIdArr[i] == _robotId) {
            return (i, true);
          }
      }
      return (0, false);
  }
  // 判断队伍是否属于某个owner
  function isTeamBelongToOwner(uint256 _teamId, address owner) view public returns(bool) {
      require(robotTeams.length > _teamId, "The team is not exist!");
      return robotTeams[_teamId].owner == owner;
  }
  // 获取一共有多少支队伍
  function getTeamCount() public view returns(uint256) {
      return robotTeams.length;
  }
  // 获取指定队伍的经理人地址
  function getTeamOwner(uint256 _teamId) public view returns(address) {
      require(robotTeams.length > _teamId, "The team is not exist!");
      return robotTeams[_teamId].owner;
  }
}
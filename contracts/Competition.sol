pragma solidity 0.8.10;
import "./SoccerManager.sol";
import "./EmulatePlatform.sol";
/*
赛事信息，包括赛事状态，参与者，赛事结果以及赛事规则
*/
contract Competition is Ownable {
  enum Status { WaitForAccept, Canceled, Reject, WaitForEmulatePlatform, WaitForStart,
    Running, TeamOneWin, TeamTwoWin, Tied, Exception }
  struct CompetitionInfo {
    uint256 id;
    address initiator;
    address opponent;
    uint256 startTime;
    uint256 teamOneId;
    uint256 teamTwoId;
    uint256 wager;
    uint256 appearanceFee;
    bool teamTwoAccept;
    Status status;
    uint256 teamOneScore;
    uint256 teamTwoScore;
    uint256 epId;
    bool hasSettlement;
  }

  struct CompetitionLog {
    uint256 competitionId;
    uint256[] teamOneKickInMoments;
    uint256[] teamTwoKickInMoments;
    string logUrl;
    bytes32 logHash;
    string[] liveUrls;     // ip:port of live of competition
    uint256 epAwardChargeRatio;    // 由于费率可以被Owner改变，因此需要将发起比赛时的值记录下来，后续分配都按此值进行分配，而不是最新的
    uint256 epPunishChargeRatio;
    uint256 commissionRatio;
  }
  uint256 competitionDuration = 10 * 60 * 1000;  // 600 seconds per competition
  uint256 epAwardChargeRatio = 10;   // 1 / 10
  uint256 epPunishChargeRatio = 50;  // 1 / 50
  uint256 commissionRatio = 20; // 1 / 20
  SoccerManager soccerManager;
  EmulatePlatform emulatePlatform;
  CompetitionInfo[] public competitionInfos;
  mapping(uint256 => CompetitionLog) public competitionLogs;  // soccer manager's competitions
  mapping(address => uint256[]) public managerCompetitions;  // soccer manager's competitions
  mapping(uint256 => uint256[]) public teamCompetitions;  // team id => competition ids, include all competitions
  mapping(uint256 => uint256[]) public epCompetitions;    //  competitions on each emulate platform, ep->competitions
  mapping(uint256 => uint256) public epSuccessCompetitionsNum;    //  successful competitions' number of each emulate platform, ep->competitions' number
  mapping(uint256 => uint256[]) public epCheatCompetitions;    //  emulate platform reports wrong result of competition, ep->competitions

  event LaunchCompetition(address initiator, address opponent, uint256 indexed teamOneId, uint256 indexed teamTwoId, uint256 startTime);
  event AcceptCompetition(address opponent, address initiator, uint256 indexed competitionId);
  event RejectCompetition(address opponent, address initiator, uint256 indexed competitionId);
  event CancelCompetition(address initiator, address opponent, uint256 indexed competitionId);

  function setSoccerManager(address soccerManagerAddr) public onlyOwner {
    soccerManager = SoccerManager(soccerManagerAddr);
  }

  function setEmulatePlatform(address emulatePlatformAddr) public onlyOwner {
    emulatePlatform = EmulatePlatform(emulatePlatformAddr);
  }

  modifier validCompetitionId(uint256 _competitionId) {
    require(competitionInfos.length > _competitionId, "The id of competition is not exist.");
    _;
  }

  modifier validEPId(uint256 _epId) {
    require(emulatePlatform.getEPNum() > _epId, "The id of emulate platform is not exist.");
    _;
  }

  modifier validTeamId(uint256 _teamId) {
    require(soccerManager.getTeamCount() > _teamId, "Team id isn't exist.");
    _;
  }

  modifier waitForAccept(uint256 _competitionId) {
    require(competitionInfos.length > _competitionId, "This competition hasn't been launched.");
    require(competitionInfos[_competitionId].status == Status.WaitForAccept, "This competition should be in status of waiting for accept!");
    _;
  }

  modifier shouldBeInitiator(uint256 _competitionId) {
    require(competitionInfos.length > _competitionId, "This competition hasn't been launched.");
    require(competitionInfos[_competitionId].initiator == msg.sender, "You aren't the initiator of this competition.");
    _;
  }

  modifier shouldBeOpponent(uint256 _competitionId) {
    require(competitionInfos.length > _competitionId, "This competition hasn't been launched.");
    require(competitionInfos[_competitionId].opponent == msg.sender, "You aren't the opponent of this competition.");
    _;
  }

  modifier isCompetitionEPOwner(uint256 _competitionId) {
    require(competitionInfos.length > _competitionId, "This competition hasn't been launched.");
    uint256 epId = competitionInfos[_competitionId].epId;
    require(emulatePlatform.isValidOwner(msg.sender, epId), "Only the owner of the emulate platform can operate the competition.");
    _;
  }
  // 1 / _epPunishChargeRatio 是实际的赛场惩罚比例
  function setEpPunishChargeRatio(uint256 _epPunishChargeRatio) public onlyOwner {
    require(_epPunishChargeRatio > 0, "EP punish charge ratio must be bigger than zero.");
    epPunishChargeRatio = _epPunishChargeRatio;
  }
  // 1 / _epAwardChargeRatio 是实际的赛场奖励比例
  function setEpAwardChargeRatio(uint256 _epAwardChargeRatio) public onlyOwner {
    require(_epAwardChargeRatio > 0, "EP award charge ratio must be bigger than zero.");
    epAwardChargeRatio = _epAwardChargeRatio;
  }
  // 1 / _commissionRatio 是实际的平台抽佣比例
  function setCommissionRatio(uint256 _commissionRatio) public onlyOwner {
    require(_commissionRatio > 0, "Platform commission ratio must be bigger than zero.");
    commissionRatio = _commissionRatio;
  }
  // 获取某个经理人是否有球队在某个时间段有比赛的信息.
  function getConfirmCompetition(address _owner, uint256 _startTime) public view returns(int) {
    uint256[] memory competitionIds = managerCompetitions[_owner];  //
    for(uint i = 0; i < competitionIds.length; i++) {
      CompetitionInfo memory competition = competitionInfos[i];
      if(!competition.teamTwoAccept)
        continue;
      if(_startTime > competition.startTime && _startTime < competition.startTime + competitionDuration) {
        return (int)(i);
      }
    }
    return -1;
  }
  // 获取自身发起的尚未被对手响应的赛事ID
  // 为什么要获取自身发起的未确认赛事：
  // 为了满足：当有N多其它队伍向某支队伍发起挑战时，这支队伍可以置之不理，依然可以向自己感兴趣的其它队伍发起挑战
  function getUnConfirmCompetition(address _owner, uint256 _startTime) public view returns(int) {
    uint256[] memory competitionIds = managerCompetitions[_owner];  //
    for(uint i = 0; i < competitionIds.length; i++) {
      CompetitionInfo memory competition = competitionInfos[i];
      if(competition.status != Status.WaitForAccept || competition.initiator != _owner)
        continue;
      if(_startTime > competition.startTime - competitionDuration && _startTime < competition.startTime + competitionDuration) {
        return int(i);
      }
    }
    return -1;
  }
  // 发起一场赛事，包括本队伍，想要进行比赛的对手队伍，以及开始时间，成功发起比赛需要满足：
  // 1: 比赛时间必须在当前时间+两场赛事时长（20分钟）之后开始
  // 2: 自身没有时间冲突的赛事（包括已确认和自身发起的未确认的赛事）
  // 3: 对手没有时间冲突的赛事（包括已确认和自身发起的未确认的赛事）
  function launchCompetition(uint256 _myTeamId, uint256 _opponentTeamId, uint256 _startTime)
  public payable validTeamId(_myTeamId) validTeamId(_opponentTeamId) {
    require(_myTeamId != _opponentTeamId, "Please specify two different teams!");
    require(soccerManager.isTeamBelongToOwner(_myTeamId, msg.sender), "The initiator team isn't belong to you!");
    require(_startTime > now + 2 * competitionDuration,
      "Start time should be later than two competitions' duration from now on.");
    require(getConfirmCompetition(msg.sender, _startTime) == -1,
      "You have a confirmed competition in your expected time!");
    require(getUnConfirmCompetition(msg.sender, _startTime) == -1,
      "You have another unconfirmed competition in your expected time, so can't launch this competition!");

    address opponentOwner = soccerManager.getTeamOwner(_opponentTeamId);

    require(getConfirmCompetition(opponentOwner, _startTime) == -1,
      "You opponent has a competition in your expected time!");
    require(getUnConfirmCompetition(opponentOwner, _startTime) == -1,
      "You opponent has an unconfirmed competition in your expected time!");

    uint256 competitionId = competitionInfos.length;
    CompetitionInfo memory competitionInfo = CompetitionInfo({
      id:competitionId, initiator:msg.sender, opponent:opponentOwner, startTime:_startTime,
      teamOneId:_myTeamId, teamTwoId:_opponentTeamId, wager:msg.value, appearanceFee:0,
      teamTwoAccept:false, status:Status.WaitForAccept, teamOneScore:0, teamTwoScore:0, epId:0, hasSettlement:false
      });

    competitionInfos.push(competitionInfo);
    managerCompetitions[msg.sender].push(competitionId);
    //managerCompetitions[opponentOwner].push(competitionInfo);
    teamCompetitions[_myTeamId].push(competitionId);
    teamCompetitions[_opponentTeamId].push(competitionId);

    competitionLogs[competitionId].epAwardChargeRatio = epAwardChargeRatio;
    competitionLogs[competitionId].epPunishChargeRatio = epPunishChargeRatio;
    competitionLogs[competitionId].commissionRatio = commissionRatio;

    emit LaunchCompetition(msg.sender, opponentOwner, _myTeamId, _opponentTeamId, _startTime);
  }
  // 接受挑战，可接受的条件：
  // 1：自己并没有另一场时间冲突的已确定的赛事，
  //    作此判断是因为自己在被人挑战的时候，是可以发起新的挑战的（即便时间冲突了也可以），所以有可能在接受挑战的时候，自己发起的挑战已经被接受
  // 2：距离比赛开始时间至少间隔了一场比赛的时间，即十分钟，而发起比赛者必须至少要提前二十分钟
  //
  // 为何不需要考虑挑战者是否有赛事冲突？因为挑战者无法在同一时间段内发起两场赛事，同时在发起挑战后也无法接受其它队伍的挑战（除非发起的挑战被拒或自己主动取消）
  function acceptCompetition(uint256 _competitionId) public payable
  validCompetitionId(_competitionId)
  waitForAccept(_competitionId)
  shouldBeOpponent(_competitionId)
  {
    CompetitionInfo storage competitionInfo = competitionInfos[_competitionId];
    require(competitionInfo.startTime > now + competitionDuration,
      "Start time should be later than one competition' duration from now on.");
    require(competitionInfo.wager <= msg.value, "Your paid value should be more than the wager!");
    require(getConfirmCompetition(msg.sender, competitionInfo.startTime) == -1,
      "You have a competition in your expected time, reject it!");
    require(getUnConfirmCompetition(msg.sender, competitionInfo.startTime) == -1,
      "You have another unconfirmed competition in your expected time, so can't accept this competition!");

    competitionInfo.teamTwoAccept = true;
    competitionInfo.status = Status.WaitForEmulatePlatform;

    managerCompetitions[msg.sender].push(_competitionId);
    emit AcceptCompetition(msg.sender, competitionInfos[_competitionId].initiator, _competitionId);
  }
  // 设置比赛进行的仿真平台，需满足：
  // 1: sender必须是仿真平台的owner
  // 2: 赛事必须处于WaitForEmulatePlatform状态，即比赛双方已同意比赛
  // 仿真平台对承办赛事，需要抵押保证金，当比赛出现异常，需要将保证金分给比赛双方，保证金比例为比赛赌注的1/epPunishChargeRatio
  // 譬如双方赌注是10个TOKEN，则比赛成功举行，仿真平台可得10/epAwardChargeRatio个TOKEN，否则将支付10/epPunishChargeRatio个Token给比赛双方，各得一半的token
  function setEmulatePlatform(uint256 _epId, uint256 _competitionId) public payable validCompetitionId(_competitionId) {
    require(emulatePlatform.isValidOwner(msg.sender, _epId), "The emulate platform should belong to sender.");
    require(competitionInfos[_competitionId].status == Status.WaitForEmulatePlatform, "It isn't the phase to set the emulate platform for competition.");
    require(msg.value > competitionInfos[_competitionId].wager / epPunishChargeRatio, "Your transfer value is too small.");

    CompetitionInfo storage competitionInfo = competitionInfos[_competitionId];
    competitionInfo.epId = _epId;
    competitionInfo.status = Status.WaitForStart;

    // 给队伍添加确定要进行的比赛的时间
    soccerManager.addCompetitionDate(competitionInfo.teamOneId, competitionInfo.startTime);
    soccerManager.addCompetitionDate(competitionInfo.teamTwoId, competitionInfo.startTime);

    epCompetitions[_epId].push(_competitionId);

    if (msg.value > competitionInfos[_competitionId].wager / epPunishChargeRatio) {
      msg.sender.transfer(msg.value - competitionInfos[_competitionId].wager / epPunishChargeRatio);
    }
  }
  // 拒绝挑战
  function rejectCompetition(uint256 _competitionId) public
  validCompetitionId(_competitionId)
  waitForAccept(_competitionId)
  shouldBeOpponent(_competitionId)
  {
    competitionInfos[_competitionId].status = Status.Reject;
    emit RejectCompetition(msg.sender, competitionInfos[_competitionId].initiator, _competitionId);
  }
  // 赛事发起者取消比赛，需要将费用收回（包括PK费和出场费）
  function cancelCompetition(uint256 _competitionId) public
  validCompetitionId(_competitionId)
  waitForAccept(_competitionId)
  shouldBeInitiator(_competitionId)
  {
    competitionInfos[_competitionId].status = Status.Canceled;

    msg.sender.transfer(competitionInfos[_competitionId].wager + competitionInfos[_competitionId].appearanceFee);

    uint256 teamTwoId = competitionInfos[_competitionId].teamTwoId;
    address teamTwoOwner = soccerManager.getTeamOwner(teamTwoId);
    emit CancelCompetition(msg.sender, teamTwoOwner, _competitionId);
  }

  // 查询某team参与的赛事情况
  function queryCompetition(uint256 _teamId, uint256 _startTime, uint256 _endTime, bool _allTypes, Status _status) view public returns(uint256[] memory){
    uint256[] memory competitionIds = teamCompetitions[_teamId];
    uint256 number = 0;
    for (uint256 i = 0; i < competitionIds.length; i++) {
      uint256 id = competitionIds[i];
      if (competitionInfos[id].startTime >= _startTime && competitionInfos[id].startTime < _endTime) {
        if (_allTypes || competitionInfos[id].status == _status) {
          number++;
        }
      }
    }
    uint256[] memory ids = new uint256[](number);
    uint256 index = 0;
    for (uint256 i = 0; i < competitionIds.length; i++) {
      uint256 id = competitionIds[i];
      if (competitionInfos[id].startTime >= _startTime && competitionInfos[id].startTime < _endTime) {
        if (_allTypes || competitionInfos[id].status == _status) {
          ids[index++] = id;
        }
      }
    }
    return ids;
  }
  // 修改赛事赌注
  function modifyWager(uint256 _competitionId) public payable
  validCompetitionId(_competitionId)
  waitForAccept(_competitionId)
  shouldBeInitiator(_competitionId)
  {
    msg.sender.transfer(competitionInfos[_competitionId].wager);
    competitionInfos[_competitionId].wager = msg.value;
  }
  // 挑战被拒绝后，挑战者取回赌注和出场费
  function refundAfterReject(uint256 _competitionId) public
  validCompetitionId(_competitionId)
  shouldBeInitiator(_competitionId)
  {
    require(competitionInfos[_competitionId].status == Status.Reject, "This competition should be rejected!");

    msg.sender.transfer(competitionInfos[_competitionId].wager + competitionInfos[_competitionId].appearanceFee);
  }
  // 添加出场费
  function addAppearanceFee(uint256 _competitionId) public payable
  validCompetitionId(_competitionId)
  waitForAccept(_competitionId)
  shouldBeInitiator(_competitionId)
  {
    competitionInfos[_competitionId].appearanceFee += msg.value;
  }
  // 仿真平台启动比赛
  function epStartCompetition(uint256 _competitionId) public
  validCompetitionId(_competitionId)
  isCompetitionEPOwner(_competitionId)
  {
    require(competitionInfos[_competitionId].status == Status.WaitForStart, "Competition isn't waiting for start.");

    competitionInfos[_competitionId].status = Status.Running;
  }
  // 仿真平台设置比赛结果，需满足：
  // 1: 当前赛事正处于Running状态
  // 2: 赛事尚未结束
  function epSetCompetitionResult(uint256 _competitionId, Status competitionStat) public
  validCompetitionId(_competitionId)
  isCompetitionEPOwner(_competitionId)
  {
    require(competitionInfos[_competitionId].status == Status.Running, "Only running competition can be set result by emulate platform.");
    require(now > competitionInfos[_competitionId].startTime + competitionDuration, "The competition hasn't finished.");
    require(competitionStat == Status.TeamOneWin || competitionStat == Status.TeamTwoWin
    || competitionStat == Status.Tied || competitionStat == Status.Exception,
      "Competition can only be set status TeamOneWin/TeamTwoWin/Tied/Exception by emulate platform.");
    competitionInfos[_competitionId].status = competitionStat;
    if (competitionStat != Status.Exception) {
      epSuccessCompetitionsNum[competitionInfos[_competitionId].epId]++;
    }
  }

  function processFeeOfEPOwner(CompetitionInfo memory competitionInfo) private {
    CompetitionLog memory competitionLog = competitionLogs[competitionInfo.id];
    uint256 wager = competitionInfo.wager;
    Status competitionStat = competitionInfo.status;
    if (competitionStat != Status.Exception) {
      uint256 award = wager / competitionLog.epAwardChargeRatio;
      uint256 punish = wager / competitionLog.epPunishChargeRatio;
      uint256 commission = award / competitionLog.commissionRatio;
      address payable epOwner;
      (,epOwner,,,,,,,,) = emulatePlatform.epList(competitionInfo.epId);
      address payable platformOwner = owner();
      epOwner.transfer(award - commission + punish);
      platformOwner.transfer(commission);
    }
  }

  function processFeeOfTeam(CompetitionInfo memory competitionInfo) private {
    CompetitionLog memory competitionLog = competitionLogs[competitionInfo.id];
    uint256 wager = competitionInfo.wager;
    address payable teamOneOwner = soccerManager.getTeamOwner(competitionInfo.teamOneId);
    address payable teamTwoOwner = soccerManager.getTeamOwner(competitionInfo.teamTwoId);
    Status competitionStat = competitionInfo.status;
    address payable platformOwner = owner();
    if (competitionInfo.appearanceFee > 0) {  // 出场费
      uint256 commission = competitionInfo.appearanceFee / competitionLog.commissionRatio;
      teamTwoOwner.transfer(competitionInfo.appearanceFee - commission);
      platformOwner.transfer(commission);
    }
    if (competitionStat == Status.Exception) {
      uint256 punish = wager / competitionLog.epPunishChargeRatio;
      uint256 commission = punish / competitionLog.commissionRatio;
      uint256 eachTeamFee = (punish - commission) / 2;
      teamOneOwner.transfer(eachTeamFee);
      teamTwoOwner.transfer(eachTeamFee);
      platformOwner.transfer(punish - 2 * eachTeamFee);
    }
    uint256 epAward = wager / competitionLog.epAwardChargeRatio;
    if (competitionStat == Status.TeamOneWin) {
      uint256 commission = wager / competitionLog.commissionRatio;
      teamOneOwner.transfer(wager * 2 - commission - epAward);
      platformOwner.transfer(commission);
    }
    if (competitionStat == Status.TeamTwoWin) {
      uint256 commission = wager / competitionLog.commissionRatio;
      teamTwoOwner.transfer(wager * 2 - commission - epAward);
      platformOwner.transfer(commission);
    }
    if (competitionStat == Status.Tied) {
      teamOneOwner.transfer(wager - epAward / 2);
      teamTwoOwner.transfer(wager - epAward / 2);
    }
  }
  // 对赛事进行结算，分以下几种情况：
  // 1: 赛事异常：将赌注和出场费原路退回，同时赛场（即仿真平台）运营方向赛事双方支付赔偿（赔偿的费用在承办比赛的时候已经支付到合约中），各自得wager / epPunishChargeRatio / 2
  // 2: 其中一支队伍赢得比赛：首先向赛场运营方支付场地费用wager / epAwardChargeRatio * （1 - 1 / commissionRatio），并归还抵押金 wager / epPunishChargeRatio，
  //    再向本平台支付平台费（wager/commissionRatio），有出场费的话，向受邀方支付出场费，最后再向赢的一方支付2 * wager - wager / epAwardChargeRatio - wager / commissionRatio
  // 3: 打平：首先支付场地使用费和抵押金wager * (1/epAwardChargeRatio + 1/epPunishChargeRatio)，然后支付出场费（有的话），最后向双方各支付wager * (1 - 1/(2*epAwardChargeRatio))
  // 其它：任意用户都可发起此操作，但只有在比赛结束后3天后才能发起此操作，这3天时间可用来对赛事进行申诉
  function executeSettlement(uint256 _competitionId) public
  validCompetitionId(_competitionId)
  {
    CompetitionInfo storage competitionInfo = competitionInfos[_competitionId];
    Status competitionStat = competitionInfo.status;
    require(competitionStat == Status.WaitForStart || competitionStat == Status.Running
    || competitionStat == Status.TeamOneWin || competitionStat == Status.TeamTwoWin
    || competitionStat == Status.Tied || competitionStat == Status.Exception,
      "Settlement can only be executed when competition's status is one of WaitForStart/Running/TeamOneWin/TeamTwoWin/Tied/Exception.");
    require(!competitionInfo.hasSettlement, "Competition has been settlement.");
    require(now > competitionInfo.startTime + competitionDuration + 24 * 3600 * 3, "It can't be settlement until 3 days later after competition being over.");
    if (competitionStat == Status.WaitForStart || competitionStat == Status.Running) {
      competitionInfo.status = Status.Exception;
    }
    processFeeOfEPOwner(competitionInfo);
    processFeeOfTeam(competitionInfo);

    competitionInfo.hasSettlement = true;
  }

  // 仿真平台添加比分以及进球时刻
  function epAddScore(uint256 _competitionId, bool teamOneScore, uint256 moment/*second from start*/) public
  validCompetitionId(_competitionId)
  {
    Status competitionStat = competitionInfos[_competitionId].status;
    require(competitionStat == Status.Running, "Competition can only be set score when competition is running.");

    uint256 epId = competitionInfos[_competitionId].epId;
    require(emulatePlatform.isValidOwner(msg.sender, epId), "Only the owner of the emulate platform of the competition can set score.");

    if (teamOneScore) {
      competitionInfos[_competitionId].teamOneScore++;
      competitionLogs[_competitionId].teamOneKickInMoments.push(moment);
    } else {
      competitionInfos[_competitionId].teamTwoScore++;
      competitionLogs[_competitionId].teamTwoKickInMoments.push(moment);
    }
  }
  // 仿真平台添加赛事记录，以供后续查看
  function epAddFullLog(uint256 _competitionId, string memory _logUrl, bytes32 _logHash) public
  validCompetitionId(_competitionId)
  {
    require(bytes(competitionLogs[_competitionId].logUrl).length == 0, "Competition's log can't be set again.");
    uint256 epId = competitionInfos[_competitionId].epId;
    require(emulatePlatform.isValidOwner(msg.sender, epId), "Only the owner of the emulate platform of the competition can set log.");
    competitionLogs[_competitionId].logUrl = _logUrl;
    competitionLogs[_competitionId].logHash = _logHash;
  }
  // 获取状态匹配的所有赛事记录
  function getCompetitionsByStat(Status status) view public returns(uint256[] memory) {
    uint256 totalNum = 0;
    for (uint i = 0; i < competitionInfos.length; i++) {
      if (competitionInfos[i].status == status) {
        totalNum++;
      }
    }
    uint256[] memory idList = new uint256[](totalNum);
    uint256 index = 0;
    for (uint i = 0; i < competitionInfos.length; i++) {
      if (competitionInfos[i].status == status) {
        idList[index++] = i;
      }
    }
    return idList;
  }
  // 检查正在运行的比赛是否正常
  function checkRunningCompetition(uint256[] memory competitionIds) public {
    for (uint i = 0; i < competitionIds.length; i++) {
      uint256 index = competitionIds[i];
      if (index < competitionInfos.length
      && competitionInfos[index].status == Status.Running
      && now - competitionInfos[index].startTime > 2 * competitionDuration) {
        competitionInfos[index].status == Status.Exception;
      }
    }
  }
  // 检查等待启动的比赛是否正常启动
  function checkWaitForStartCompetition(uint256[] memory competitionIds) public {
    for (uint i = 0; i < competitionIds.length; i++) {
      uint256 index = competitionIds[i];
      if (index < competitionInfos.length
      && competitionInfos[index].status == Status.WaitForStart
      && now - competitionInfos[index].startTime > competitionDuration) {
        competitionInfos[index].status == Status.Exception;
      }
    }
  }
  // owner可以添加某个赛事平台违规记录
  function addCheatCompetitionOfEp(uint256 _epId, uint256 _competitionId) public
  onlyOwner()
  validCompetitionId(_competitionId)
  validEPId(_epId)
  {
    epCheatCompetitions[_epId].push(_competitionId);
  }
  // 可以通过多个直播服务器直播赛事
  function addLiveUrl(uint256 _competitionId, string memory _liveUrl) public
  validCompetitionId(_competitionId)
  isCompetitionEPOwner(_competitionId)
  {
    competitionLogs[_competitionId].liveUrls.push(_liveUrl);
  }
}
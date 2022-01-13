pragma solidity 0.8.10;
import "./AIDeveloper.sol";

contract RobotMgr is Ownable {

  enum RobotStatus {
    unRent,
    renting,
    rented
  }
  struct Robot {
    uint256 id;
    address payable owner;
    string bodyImageUrl;
    uint aiProcedureId;
    RobotStatus status;
  }

  struct RentInfo {
    uint id;
    uint robotId;
    address robotOwner;
    address payable renter;
    uint minRentalTime;   // second
    uint maxRentalTime;   // second
    uint rentalDate;
    uint returnDate;
    uint256 rentalPrice;  // price per second
    uint lastWithdrawDate;
  }

  event Birth(address indexed owner, uint256 robotId, uint indexed aiProcedureId, string bodyImageUrl);
  event Rent(uint256 indexed robotId, address indexed _renter, uint _rentalDate, uint _returnDate, uint _rentalPrice);
  event ReturnRental(uint256 indexed robotId, address indexed _renter, uint _returnDate);
  event Sublet(uint256 indexed robotId, address indexed oldRenter, address indexed newRenter, uint256 price);

  AIDeveloper aiDev;   // AIDeveloper contract address, used to call its function
  Robot[] public robots;
  RentInfo[] public rentInfos;
  uint256[] rentingRobotIds;
  mapping (uint256 => address) public robotIndexToOwner;   // robot -> owner
  mapping (uint256 => uint256) public robotIndexToRenter;  // robot -> renter info
  mapping (uint256 => uint256) public robotInSubletting;   // robot -> price of sublet
  mapping (address => mapping(uint256 => uint256)) public renterToRentInfos;  // renter -> robotId -> rentInfo
  mapping (address => uint256[]) public ownershipRobots;

  modifier whenInRenting(uint256 _robotId) {
    require(robots.length > _robotId, "Robot is not exist!");
    require(robots[_robotId].status == RobotStatus.renting, "Robot isn't in renting!");
    require(rentInfos.length > 0 && rentInfos[robotIndexToRenter[_robotId]].robotId == _robotId, "Robot's rentInfo is not exist.");
    _;
  }

  modifier whenRented(uint256 _robotId) {
    require(robots.length > _robotId, "Robot is not exist!");
    require(rentInfos.length > 0 && rentInfos[robotIndexToRenter[_robotId]].robotId == _robotId, "Robot's rentInfo is not exist.");
    require(robots[_robotId].status == RobotStatus.rented, "Robot is not rented!");
    require(rentInfos[robotIndexToRenter[_robotId]].returnDate < now, "Robot should be returned to owner.");
    _;
  }

  modifier onlyRobotOwner(uint256 _robotId) {
    require(robots.length > _robotId, "Robot is not exist!");
    require(robots[_robotId].owner == msg.sender, "Only robot's owner could call this interface!");
    _;
  }

  modifier onlyRenter(uint256 _robotId) {
    require(robots.length > _robotId, "Robot is not exist!");
    require(rentInfos.length > 0 && rentInfos[robotIndexToRenter[_robotId]].robotId == _robotId, "Robot's rentInfo is not exist.");
    require(rentInfos[robotIndexToRenter[_robotId]].renter == msg.sender, "Only robot's renter could call this interface!");
    _;
  }

  modifier notInCompetition(uint256 _robotId) {
    require(robots.length > _robotId, "Robot is not exist!");
    require(!robots[_robotId].isInCompetition, "Robot is in competition!");
    _;
  }

  constructor() public {
  }
  // 绑定AI开发者合约
  function setAIDeveloperContract(address contractAddr) public onlyOwner {
    aiDev = AIDeveloper(contractAddr);
  }
  // 创建机器人，指定AI程序和机器人图片
  function createRobot(uint _aiProcedureId, string memory _bodyImageUrl) public {
    address aiOwner;
    (, , , , aiOwner) = aiDev.getAIProcedureById(_aiProcedureId);
    require(msg.sender == aiOwner, "Sender is not the owner of AI procedure.");

    uint256 newRobotId = robots.length;
    Robot memory robot = Robot({
      id:newRobotId, owner:msg.sender, bodyImageUrl:_bodyImageUrl,
      aiProcedureId:_aiProcedureId, status:RobotStatus.unRent});
    robots.push(robot);

    //robotIndexToOwner[newRobotId] = msg.sender;
    ownershipRobots[msg.sender].push(newRobotId);
    emit Birth(msg.sender, newRobotId, _aiProcedureId, _bodyImageUrl);
  }
  // 机器人所有者创建租赁合约
  function rentableSetup(uint256 _robotId, uint256 _pricePerHour, uint _minRentalTime, uint _maxRentalTime) public {
    require(_pricePerHour > 0, "Price per hour can't be less then zero!");
    require(robots.length > _robotId, "Robot is not exist!");
    require(robots[_robotId].owner == msg.sender, "Robot doesn't belong to you!");
    require(robots[_robotId].status == RobotStatus.unRent, "Robot can't be set to rentable twice!");

    uint rentInfoId = rentInfos.length;
    RentInfo memory rentInfo = RentInfo({
      id: rentInfoId, robotId:_robotId, robotOwner: msg.sender, renter:address(0),
      minRentalTime:_minRentalTime, maxRentalTime:_maxRentalTime,
      rentalDate:0, returnDate:0, rentalPrice:_pricePerHour / 3600, lastWithdrawDate:0});

    // 如果机器人之前存在过租赁信息，则删除之
    // 在何种情况下会满足此条件？ 在机器人完成一次租赁后（无论是否正常结束），会存在此情况
    if (rentInfos[robotIndexToRenter[_robotId]].robotId == _robotId && rentInfos[robotIndexToRenter[_robotId]].robotOwner == msg.sender) {
      delete rentInfos[robotIndexToRenter[_robotId]];
    }
    robotIndexToRenter[_robotId] = rentInfoId;
    rentInfos.push(rentInfo);

    robots[_robotId].status = RobotStatus.renting;
  }
  // 租赁指定ID的机器人
  // 1:更新机器人的租赁信息，包括租赁日期、归还日期、租赁者地址和租赁状态
  // 2:更新租赁者的租赁信息
  function rent(uint256 _robotId) public payable whenInRenting(_robotId){
    require (msg.value > 0, "Rent cost must be bigger than zero.");

    RentInfo storage rentInfo = rentInfos[robotIndexToRenter[_robotId]];
    require (rentInfo.rentalPrice > 0, "Robot's owner hasn't set the price.");

    uint rentalTime = msg.value / rentInfo.rentalPrice;
    require(rentalTime >= rentInfo.minRentalTime && rentalTime <= rentInfo.maxRentalTime, "Rent cost should be in available time range.");

    rentInfo.rentalDate = block.timestamp;
    rentInfo.returnDate = block.timestamp + rentalTime;
    rentInfo.renter = msg.sender;

    robots[_robotId].status = RobotStatus.rented;
    robots[_robotId].owner.transfer(msg.value);  // 将租赁资金转给机器人的owner
    renterToRentInfos[msg.sender][_robotId] = robotIndexToRenter[_robotId];

    emit Rent(_robotId, msg.sender, rentInfo.rentalDate, rentInfo.returnDate, rentInfo.rentalPrice);
  }
  // 获取当前拥有指定机器人使用权的用户地址
  function getRobotUsageRightOwner(uint256 _robotId) public view returns (address) {
    require(robots.length > _robotId, "Robot is not exist!");
    if (robots[_robotId].status == RobotStatus.renting) {
      return address(0);
    }
    if (robots[_robotId].status == RobotStatus.unRent) {
      return robots[_robotId].owner;
    }
    if (robots[_robotId].status == RobotStatus.rented) {
      if (now > rentInfos[robotIndexToRenter[_robotId]].returnDate) {  // no one can use robot when in this case
        return address(0);
      } else {
        return rentInfos[robotIndexToRenter[_robotId]].renter;
      }
    }
    return address(0);
  }
  // 获取指定的机器人是否可租赁信息
  function canBeRented(uint256 _robotId) public view returns (bool) {
    require(robots.length > _robotId, "Robot is not exist!");
    require(rentInfos.length > 0 && rentInfos[robotIndexToRenter[_robotId]].robotId == _robotId, "Robot's rentInfo is not exist.");
    return robots[_robotId].status == RobotStatus.renting;
  }
  // 设置租赁价格
  function setRentalPricePerHour(uint256 _robotId, uint256 _pricePerHour) public whenInRenting(_robotId) {
    require(_pricePerHour > 0, "Price can't be less then zero!");
    RentInfo storage rentInfo = rentInfos[robotIndexToRenter[_robotId]];
    require(rentInfo.robotOwner == msg.sender, "Only Robot's owner can set the price.");
    rentInfo.rentalPrice = _pricePerHour / 3600;
  }
  function setRentalPricePerDay(uint256 _robotId, uint _pricePerDay) public whenInRenting(_robotId) {
    require(_pricePerDay > 0, "Price can't be less then zero!");
    RentInfo storage rentInfo = rentInfos[robotIndexToRenter[_robotId]];
    require(rentInfo.robotOwner == msg.sender, "Only Robot's owner can set the price.");
    rentInfos[robotIndexToRenter[_robotId]].rentalPrice = _pricePerDay / 24 / 3600;
  }
  function setRentalPricePerSecond(uint256 _robotId, uint _pricePerSecond) public whenInRenting(_robotId) {
    require(_pricePerSecond > 0, "Price can't be less then zero!");
    RentInfo storage rentInfo = rentInfos[robotIndexToRenter[_robotId]];
    require(rentInfo.robotOwner == msg.sender, "Only Robot's owner can set the price.");
    rentInfos[robotIndexToRenter[_robotId]].rentalPrice = _pricePerSecond;
  }
  // 已经持续的租赁时长（秒）
  function rentalElapsedTime(uint256 _robotId) public view whenRented(_robotId) returns (uint){
    return now - rentInfos[robotIndexToRenter[_robotId]].rentalDate;
  }
  // 已经产生的费用
  function rentalAccumulatedPrice(uint256 _robotId) public view whenRented(_robotId) returns (uint){
    uint _rentalElapsedTime = rentalElapsedTime(_robotId);
    return rentInfos[robotIndexToRenter[_robotId]].rentalPrice * _rentalElapsedTime;
  }
  // 剩余租赁时间
  function rentalTimeRemaining(uint256 _robotId) public view whenRented(_robotId) returns (uint){
    return (rentInfos[robotIndexToRenter[_robotId]].returnDate - now);
  }
  // 剩余租赁费用
  function rentalBalanceRemaining(uint256 _robotId) public view whenRented(_robotId) returns (uint){
    return rentalTimeRemaining(_robotId) * rentInfos[robotIndexToRenter[_robotId]].rentalPrice;
  }
  // 总的租赁时长
  function rentalTotalTime(uint256 _robotId) public view whenRented(_robotId) returns (uint){
    return (rentInfos[robotIndexToRenter[_robotId]].returnDate - rentInfos[robotIndexToRenter[_robotId]].rentalDate);
  }
  // 机器人所有者将 尚未成功出租 或者 租赁期已到的 机器人强制收回
  function forceRentalEnd(uint256 _robotId) public onlyRobotOwner(_robotId){
    require(robots[_robotId].status == RobotStatus.renting
    || (robots[_robotId].status == RobotStatus.rented
        && rentInfos[robotIndexToRenter[_robotId]].robotId == _robotId
        && now > rentInfos[robotIndexToRenter[_robotId]].returnDate),  "Robot is rented now!");

    resetRental(_robotId, rentInfos[robotIndexToRenter[_robotId]].renter);
    emit ReturnRental(_robotId, rentInfos[robotIndexToRenter[_robotId]].renter, now);
  }
  // 重置租赁信息
  function resetRental(uint256 _robotId, address renter) private {
    require(robots.length > _robotId, "Robot is not exist!");
    robots[_robotId].status = RobotStatus.unRent;
    if (rentInfos[robotIndexToRenter[_robotId]].renter == renter) {
      delete rentInfos[robotIndexToRenter[_robotId]];
    }
    delete renterToRentInfos[renter][_robotId];
    delete robotInSubletting[_robotId];
  }
  // 租赁者转租机器人
  function sublet(uint256 _robotId, uint256 price) public onlyRenter(_robotId) whenRented(_robotId) {
    require(price > 0, "sublet price must be bigger than zero.");
    robotInSubletting[_robotId] = price;
  }
  // 租赁者取消转租
  function cancelSublet(uint256 _robotId) public onlyRenter(_robotId) whenRented(_robotId) {
    require(robotInSubletting[_robotId] > 0, "Your robot has not been subletted.");
    delete robotInSubletting[_robotId];
  }
  // 租下转租的robot
  function rentSublettedRobot(uint256 _robotId) payable public whenRented(_robotId) {
    require(robotInSubletting[_robotId] > 0, "This robot is not in subletting.");
    require(robotInSubletting[_robotId] <= msg.value, "Your need pay more.");
    address payable oldRenter = rentInfos[robotIndexToRenter[_robotId]].renter;

    oldRenter.transfer(robotInSubletting[_robotId]);
    rentInfos[robotIndexToRenter[_robotId]].renter = msg.sender;
    if (msg.value > robotInSubletting[_robotId]) {
      msg.sender.transfer(msg.value - robotInSubletting[_robotId]);
    }
    delete renterToRentInfos[oldRenter][_robotId];
    renterToRentInfos[msg.sender][_robotId] = robotIndexToRenter[_robotId];
    delete robotInSubletting[_robotId];
    emit Sublet(_robotId, oldRenter, msg.sender, robotInSubletting[_robotId]);
  }
}
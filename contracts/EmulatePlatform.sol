pragma solidity 0.8.10;

contract EmulatePlatform is Ownable {
  mapping (address => uint256[]) public ownerEPMap;
  EPInfo[] public epList;
  struct EPInfo {
    uint256 id;
    address owner;
    uint256 cpu;  // G
    uint256 coreNum;
    uint256 memorySize; // G
    uint256 bandwidth; // M
    string provider; // amazon, aliyun...
    string email;  //
    bool passed;
    uint256 successNum;
  }
  constructor() public {
  }

  modifier validId(uint256 _epId) {
    require(epList.length > _epId, "The id of emulate platform is not exist.");
    _;
  }
  // 添加一个仿真平台
  function addPlatform(uint256 _cpu, uint256 _coreNum, uint256 _memorySize, uint256 _bandwidth, string memory _provider, string memory _email) public {
    EPInfo memory epInfo = EPInfo({id:epList.length, owner:msg.sender, cpu:_cpu, coreNum:_coreNum, memorySize:_memorySize,
      bandwidth:_bandwidth, provider:_provider, email:_email, passed:false, successNum: 0});
    ownerEPMap[msg.sender].push(epInfo.id);
    epList.push(epInfo);
  }
  // 设置审批是否通过
  function setPassed(uint256 _epId, bool _passed) public validId(_epId) onlyOwner() {
    epList[_epId].passed = _passed;
  }
  // 获取指定平台是否审核通过的信息
  function isPassed(uint256 _epId) view public validId(_epId) returns(bool) {
    return epList[_epId].passed;
  }
  // 判断仿真平台的owener是否是指定的owner
  function isValidOwner(address _owner, uint256 _epId) view public validId(_epId) returns(bool) {
    return epList[_epId].owner == _owner;
  }
  // 获取所有仿真平台的IDs
  function getEpIds() view public returns(uint256[] memory) {
    return ownerEPMap[msg.sender];
  }
  // 获取仿真平台的总数
  function getEPNum() view public returns(uint256) {
    return epList.length;
  }
}
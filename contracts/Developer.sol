pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Program.sol";

contract Developer is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct DevInfo {
      address devAddr;
      string name;
      string desc;
      string headIconUrl;
      string githubUrl;
    }

    Program public programContractAddr;

    bool public bPermissionless;
    EnumerableSet.AddressSet private permittedDevs;
    EnumerableSet.AddressSet private registeredDevs;
    mapping(address => DevInfo) public addrDevInfoMap;
    mapping(address => uint256[]) public addrProgramTokenIdsMap;

    event RegisterDev(address owner, string indexed name, string indexed githubUrl);
    event AddProgram(address owner, uint256 aiProgramTokenId);

    constructor(address _programContractAddr) public {
        programContractAddr = Program(_programContractAddr);
        bPermissionless = true;
    }

    function setPermission(bool _bPermissionless) external onlyOwner {
        bPermissionless = _bPermissionless;
    }

    function setDev(address _devAddr, bool _bAdded) external onlyOwner {
        _bAdded ? permittedDevs.add(_devAddr) : permittedDevs.remove(_devAddr);
    }

    function isDevPermitted(address _devAddr) external returns(bool) {
        return permittedDevs.contains(_devAddr);
    }
    // 注册开发者
    function registerDev(string memory _name, string memory _desc, string memory _headIconUrl, string memory _githubUrl) external {
        require(bPermissionless || permittedDevs.contains(msg.sender), "Developer: NOT allowed");
        require(!registeredDevs.contains(msg.sender), "Developer:You have registered as a developer.");
        require(bytes(_name).length > 2 && bytes(_desc).length < 200, "Developer: the length of name or desc is error.");
        
        addrDevInfoMap[msg.sender] = new DevInfo(msg.sender, _name, _org, _desc, _headIconUrl, _githubUrl);
        registeredDevs.add(msg.sender);

        emit RegisterDev(msg.sender, _name, _githubUrl);
    }

    function getAllDevInfo() external returns(DevInfo[] memory devInfos) {
        uint256 length = registeredDevs.length();
        devInfos = new DevInfos[](length);
        for (uint256 i = 0; i < length; i++) {
          address devAddr = registeredDevs.at(i);
          devInfos[i] = addrDevInfoMap[devAddr];
        }
    }

    // 开发者添加AI程序，包括AI上传的URL以及对应的hash值，实际AI程序保存在云或IPFS上
    function registerProgram(string memory _ability, 
                        uint256 _mainVersion, 
                        uint256 _subVersion, 
                        bytes32 _hashValue, 
                        string memory _desc, 
                        string memory _repositUrl) external returns(uint256) {
        require(bPermissionless || permittedDevs.contains(msg.sender), "Developer: NOT allowed");
        uint256 programTokenId = aiProgramAddr.mint(msg.sender, _ability, _mainVersion, _subVersion, _hashValue, _desc, _repositUrl);
        addrProgramTokenIdsMap[msg.sender].push(programTokenId);
        
        emit AddProgram(msg.sender, programTokenId);
        return programTokenId;
    }

    function getProgramNumber(address _dev) external returns(uint256) {
        return addrProgramTokenIdsMap[_dev].length;
    }
}
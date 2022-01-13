pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Program is ERC721Enumerable, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;
    
    struct ProgramInfo {
        uint256 tokenId;
        string ability;
        address dev;
        uint256 mainVersion;
        uint256 subVersion;
        uint256 uploadTime;
        bytes32 hashValue;
        string desc;
        string repositUrl;
    }

    address public devContract;
    uint256 public tokenId;
    mapping(uint256 => ProgramInfo) public programInfoMap;
    mapping(string => bool) public supportedAbilityMap;   // 

    modifier onlyDev() {
        require(msg.sender == devContract, "Program: only dev contract can call this contract.");
        _;
    }

    constructor(address _devContract) ERC721("Program Info", "PRG") {
        devContract = _devContract;
    }

    function setSupportAbility(string memory abilityName, bool _bSupported) external onlyOwner {
        supportedAbilityMap[abilityName] = _bSupported;
    }

    function mint(address _dev, 
                  string memory _ability, 
                  uint256 _mainVersion, 
                  uint256 _subVersion, 
                  bytes32 _hashValue, 
                  string memory _desc, 
                  string memory _repositUrl) external onlyDev returns(uint256) {
        require(supportedAbilityMap[ability], "Program: ability NOT supported");
        require(bytes(_desc).length < 50, "Program: the length of desc should be less than 50 bytes.");
        tokenId++;
        programInfoMap[tokenId] = new ProgramInfo(tokenId, _ability, _dev, _mainVersion, _subVersion, block.timestamp, _hashValue, _desc, _repositUrl);
        _mint(devAddr, _tokenId);
        return tokenId;
    }

    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        ProgramInfo memory programInfo = programInfoMap[tokenId];

        string[13] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';

        parts[1] = string(abi.encodePacked("Ability:", programInfo.ability));

        parts[2] = '</text><text x="10" y="40" class="base">';

        parts[3] = string(abi.encodePacked("DevAddr:", uint256(programInfo.dev).toHexString()));

        parts[4] = '</text><text x="10" y="60" class="base">';

        parts[5] = string(abi.encodePacked("Timestamp:", uint256(programInfo.uploadTime).toString()));

        parts[6] = '</text><text x="10" y="80" class="base">';

        parts[7] = string(abi.encodePacked("Version:", uint256(programInfo.mainVersion).toString(), ":", uint256(programInfo.subVersion).toString()));

        parts[8] = '</text><text x="10" y="100" class="base">';

        parts[9] = string(abi.encodePacked("Reposit:", programInfo.repositUrl));

        parts[10] = '</text><text x="10" y="120" class="base">';

        parts[11] = string(abi.encodePacked("Description:", programInfo.desc));

        parts[12] = '</text></svg>';

        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7]));
        output = string(abi.encodePacked(output, parts[8], parts[9], parts[10], parts[11], parts[12]));
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Bag #', toString(tokenId), '", "description": "Programs are developed by developers and can be attached to robots as one of the capabilities they can have..", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }
}
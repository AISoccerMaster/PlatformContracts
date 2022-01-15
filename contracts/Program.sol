// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./Base64.sol";

contract Program is ERC1155Supply, Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Strings for uint256;
    
    struct ProgramInfo {
        uint256 tokenId;
        string ability;  // AISoccer
        address dev;
        uint256 mainVersion;
        uint256 subVersion;
        uint256 uploadTime;
        bytes32 hashValue;
        string desc;
        string repositUrl;
        bool bPublic;  // if bPublic is true, this program could be sold to public
    }

    address public devContract;
    uint256 public tokenId;
    mapping(uint256 => ProgramInfo) public programInfoMap;
    mapping(string => bool) public supportedAbilityMap;   // 
    mapping(string => uint256) public abilityInitNumberMap;   // 

    modifier onlyDev() {
        require(msg.sender == devContract, "Program: only dev contract can call this contract.");
        _;
    }

    constructor(address _devContract) ERC1155("") {
        devContract = _devContract;
    }

    function setSupportAbility(string memory abilityName, bool _bSupported) external onlyOwner {
        supportedAbilityMap[abilityName] = _bSupported;
    }

    function setAbilityInitNumber(string memory abilityName, uint256 _initNumber) external onlyOwner {
        abilityInitNumberMap[abilityName] = _initNumber;
    }

    function registerProgram(address _dev, 
                  string memory _ability, 
                  uint256 _mainVersion,
                  uint256 _subVersion, 
                  bytes32 _hashValue, 
                  string memory _desc, 
                  string memory _repositUrl) external onlyDev returns(uint256) {
        require(supportedAbilityMap[_ability], "Program: ability NOT supported");
        require(bytes(_desc).length < 50, "Program: the length of desc should be less than 50 bytes.");
        tokenId++;
        programInfoMap[tokenId] = ProgramInfo(tokenId, _ability, _dev, _mainVersion, _subVersion, block.timestamp, _hashValue, _desc, _repositUrl, false);
        _mint(_dev, tokenId, abilityInitNumberMap[_ability], "");
        return tokenId;
    }

    // after public, dev will cost ERC20 for every program
    function mintProgram(uint256 _tokenId, uint256 _amount) external {
        ProgramInfo memory programInfo = programInfoMap[tokenId];
        require(programInfo.bPublic && msg.sender == programInfo.dev, "Program: only dev could mint public program.");
        _mint(msg.sender, _tokenId, _amount, "");
    }

    function setPublic(uint256 _tokenId) external onlyOwner {
        programInfoMap[tokenId].bPublic = true;
    }

    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        ProgramInfo memory programInfo = programInfoMap[_tokenId];

        string[13] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';

        parts[1] = string(abi.encodePacked("Ability:", programInfo.ability));

        parts[2] = '</text><text x="10" y="40" class="base">';

        parts[3] = string(abi.encodePacked("DevAddr:", uint256(uint160(programInfo.dev)).toHexString()));

        parts[4] = '</text><text x="10" y="60" class="base">';

        parts[5] = string(abi.encodePacked("Timestamp:", programInfo.uploadTime.toString()));

        parts[6] = '</text><text x="10" y="80" class="base">';

        parts[7] = string(abi.encodePacked("Version:", programInfo.mainVersion.toString(), ":", programInfo.subVersion.toString()));

        parts[8] = '</text><text x="10" y="100" class="base">';

        parts[9] = string(abi.encodePacked("Reposit:", programInfo.repositUrl));

        parts[10] = '</text><text x="10" y="120" class="base">';

        parts[11] = string(abi.encodePacked("Description:", programInfo.desc));

        parts[12] = '</text></svg>';

        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7]));
        output = string(abi.encodePacked(output, parts[8], parts[9], parts[10], parts[11], parts[12]));
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Program #', _tokenId.toString(), '", "description": "Programs are developed by developers and can be attached to robots as one of the capabilities they can have..", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function getAbility(uint256 _programId) view external returns(string memory) {
        return programInfoMap[_programId].ability;
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }
}
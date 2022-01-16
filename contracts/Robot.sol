// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Loot.sol";

interface IRobocupCompetitionPlatform {
    function checkRobotContainProgram(uint256 _robotId, uint256 _programId) view external returns(bool);
    function removeExpectRobotWithProgram(uint256 _robotId, uint256 _programId) external;
}

interface ILoot {
    function random(string memory input) external pure returns (uint256);
    
    function getWeapon(uint256 tokenId) external view returns (string memory);
    
    function getChest(uint256 tokenId) external view returns (string memory);
    
    function getHead(uint256 tokenId) external view returns (string memory);
    
    function getWaist(uint256 tokenId) external view returns (string memory);

    function getFoot(uint256 tokenId) external view returns (string memory);
    
    function getHand(uint256 tokenId) external view returns (string memory);
    
    function getNeck(uint256 tokenId) external view returns (string memory);
    
    function getRing(uint256 tokenId) external view returns (string memory);

    function pluck(uint256 tokenId, string memory keyPrefix, string[] memory sourceArray) external view returns (string memory);
}

contract Robot is ERC721Enumerable, IERC1155Receiver, Ownable {
    using SafeMath for uint256;
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    // this is currently 1%
    uint256 public initMintPrice = 0.005 ether; // at 0
    uint256 public initBurnPrice = 0.004 ether; // at 1
    address payable public creator;
    uint256 public totalEverMinted = 0;
    uint256 public reserve = 0;

    IERC1155 public programContract;
    mapping(uint256 => EnumerableSet.UintSet) private robot2BoundProgramsMap;
    mapping(uint256 => EnumerableSet.UintSet) private program2RobotsMap;

    IRobocupCompetitionPlatform public robocup;
    ILoot public loot;

    string[] private roles = [
        "Male",
        "Female"
    ];
    
    event Minted(uint256[] indexed tokenIds, uint256 amount, uint256 indexed pricePaid, uint256 indexed reserveAfterMint);
    event Burned(uint256[] indexed tokenIds, uint256 amount, uint256 indexed priceReceived, uint256 indexed reserveAfterBurn);

    constructor(address _programContract, address _loot) ERC721("Robot", "BOT") Ownable() {
        creator = payable(msg.sender);
        programContract = IERC1155(_programContract);
        loot = ILoot(_loot);
    }

    function setCreator(address payable _creator) public onlyOwner {
        creator = _creator;
    }

    function setRobocup(address _robocup) public onlyOwner {
        robocup = IRobocupCompetitionPlatform(_robocup);
    }

        
    function getRole(uint256 tokenId) public view returns (string memory) {
        return loot.pluck(tokenId, "ROLE", roles);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string[19] memory parts;
        parts[0] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';

        parts[1] = loot.getWeapon(tokenId);

        parts[2] = '</text><text x="10" y="40" class="base">';

        parts[3] = loot.getChest(tokenId);

        parts[4] = '</text><text x="10" y="60" class="base">';

        parts[5] = loot.getHead(tokenId);

        parts[6] = '</text><text x="10" y="80" class="base">';

        parts[7] = loot.getWaist(tokenId);

        parts[8] = '</text><text x="10" y="100" class="base">';

        parts[9] = loot.getFoot(tokenId);

        parts[10] = '</text><text x="10" y="120" class="base">';

        parts[11] = loot.getHand(tokenId);

        parts[12] = '</text><text x="10" y="140" class="base">';

        parts[13] = loot.getNeck(tokenId);

        parts[14] = '</text><text x="10" y="160" class="base">';

        parts[15] = loot.getRing(tokenId);

        parts[16] = '</text><text x="10" y="180" class="base">';

        parts[17] = getRole(tokenId);

        parts[18] = '</text></svg>';

        string memory output = string(abi.encodePacked(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], parts[8]));
        output = string(abi.encodePacked(output, parts[9], parts[10], parts[11], parts[12], parts[13], parts[14], parts[15], parts[16]));
        output = string(abi.encodePacked(output, parts[17], parts[18]));
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Robot #', tokenId.toString(), '", "description": "Robot is randomly generated NFT with equipment, and can assign Program NFTs to robot, thus robot can get certain abilities.", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function mint(uint256 _amount, uint256 _maxPriceFirstRobot) payable external returns (uint256[] memory _tokenIds)  {
        require(msg.sender == tx.origin, "Robot: only EOA");
        require(_amount > 0, "Robot: _amount must be larger than zero.");

        uint256 firstPrice = getCurrentPriceToMint(1); 
        require(firstPrice <= _maxPriceFirstRobot, "Robot: Price does NOT match your expected.");

        uint256 totalMintPrice = _amount == 1 ? firstPrice : getCurrentPriceToMint(_amount);
        require(msg.value >= totalMintPrice, "Robot: Not enough ETH sent");

        _tokenIds = new uint256[](_amount);
        for (uint256 i = 0; i < _amount; i++) {
            bytes32 hashed = keccak256(abi.encodePacked(totalEverMinted, block.timestamp, msg.sender));
            _tokenIds[i] = uint256(uint32(uint256(hashed)));

            _mint(msg.sender, _tokenIds[i]);
            totalEverMinted +=1; 
        }

        // disburse
        uint256 reserveCut = getReserveCut(_amount);
        reserve = reserve.add(reserveCut);
        creator.transfer(totalMintPrice.sub(reserveCut)); // 0.5%

        if(msg.value.sub(totalMintPrice) > 0) {
            payable(msg.sender).transfer(msg.value.sub(totalMintPrice)); // excess/padding/buffer
        }

        emit Minted(_tokenIds, _amount, totalMintPrice, reserve);
    }

    function burn(uint256[] memory _tokenIds) external {
        require(msg.sender == tx.origin, "Robot: only EOA");
        
        uint256 burnPrice = getCurrentPriceToBurn(_tokenIds.length);
        
        // checks if allowed to burn
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(msg.sender == ownerOf(_tokenIds[i]), "Robot: Not the correct owner");
            _burn(_tokenIds[i]);
        }

        reserve = reserve.sub(burnPrice);
        payable(msg.sender).transfer(burnPrice);

        emit Burned(_tokenIds, _tokenIds.length, burnPrice, reserve);
    }

    function getCurrentPriceToMint(uint256 _amount) public view returns (uint256) {
        uint256 curSupply = getCurrentSupply();
        
        uint256 totalPrice;
        for (uint256 i = 1; i <= _amount; i++) {
            uint256 mintPrice = (curSupply + i).mul(initMintPrice);
            totalPrice = totalPrice.add(mintPrice);
        }
        
        return totalPrice;
    }

    // helper function for legibility
    function getReserveCut(uint256 _amount) public view returns (uint256) {
        return getCurrentPriceToBurn(_amount);
    }

    function getCurrentPriceToBurn(uint256 _amount) public view returns (uint256) {
        uint256 curSupply = getCurrentSupply();
        if (curSupply == 0) return 0;
        
        uint256 totalBurnPrice;
        for (uint256 i = 0; i < _amount; i++) {
            uint256 burnPrice = (curSupply - i).mul(initBurnPrice);
            totalBurnPrice = totalBurnPrice.add(burnPrice);
        }
        
        return totalBurnPrice;
    }

    function getCurrentSupply() public view returns (uint256) {
        return totalSupply();
    }

    function bindProgram2Robot(uint256 _programId, uint256 _robotId) external {
        require(programContract.balanceOf(msg.sender, _programId) > 0, "Robot: you have no program");
        require(msg.sender == ownerOf(_robotId), "Robot: robot NOT belong to you");
        require(!robot2BoundProgramsMap[_robotId].contains(_programId), "Robot: the robot has bound the program");

        programContract.safeTransferFrom(msg.sender, address(this), _programId, 1, "");
        robot2BoundProgramsMap[_robotId].add(_programId);
        program2RobotsMap[_programId].add(_robotId);
    }

    function unbindProgramFromRobot(uint256 _programId, uint256 _robotId) external {
        require(msg.sender == ownerOf(_robotId), "Robot: robot NOT belong to you");
        require(robot2BoundProgramsMap[_robotId].contains(_programId), "Robot: the program has NOT been bound the robot");

        if (robocup.checkRobotContainProgram(_robotId, _programId)) {
            robocup.removeExpectRobotWithProgram(_robotId, _programId);
        }

        programContract.safeTransferFrom(address(this), msg.sender, _programId, 1, "");
        robot2BoundProgramsMap[_robotId].remove(_programId);
        program2RobotsMap[_programId].remove(_robotId);
    }

    function checkRobotContainProgram(uint256 _robotId, uint256 _programId) view external returns(bool) {
        return robot2BoundProgramsMap[_robotId].contains(_programId);
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) pure external returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) pure external returns (bytes4) {
        return bytes4(keccak256(""));
    }

}
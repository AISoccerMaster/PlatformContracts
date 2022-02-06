// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20Metadata.sol"; 
import "@openzeppelin/contracts/access/Ownable.sol"; 
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../Base64.sol";


interface ISwapRouter {
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}

interface IRobot {
    function mint(uint256 _amount, uint256 _maxPriceFirstRobot, uint256[] memory _weight) external returns (uint256[] memory _tokenIds);
}

contract Cell is ERC721Enumerable, Ownable {
    using SafeMath for uint256;
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    // this is currently 1%
    uint256 public initMintPrice;
    uint256 public initBurnPrice;

    address public constant DeadAddr = 0x000000000000000000000000000000000000dEaD;

    address payable public creator;
    uint256 public totalEverMinted = 0;
    uint256 public reserve = 0;
    uint256 public genesisTime;
    mapping(uint256 => uint256) public nftMintTimeMap;
    mapping(uint256 => uint256) public nftPriceMap;

    mapping(uint256 => IERC20Metadata) public nftBurnedTokenMap;
    EnumerableSet.AddressSet private allowedBurnedTokenSet;
    mapping(address => address) public burnedToken2RouterMap;
    
    IERC20Metadata public costToken;
    
    event Minted(uint256 indexed startTokenId, uint256 amount, uint256 indexed pricePaid, uint256 indexed reserveAfterMint);
    event Burned(uint256[] indexed tokenIds, uint256 amount, uint256 indexed priceReceived, uint256 indexed reserveAfterBurn);

    constructor(address _costToken) ERC721("Cell NFT", "Cell") Ownable() {
        creator = payable(msg.sender);
        costToken = IERC20Metadata(_costToken);
        uint256 decimals = costToken.decimals();
        initMintPrice = 10.mul(10 ** decimals);
        initBurnPrice = 9.mul(10 ** decimals);
        genesisTime = block.timestamp;
    }

    function setCreator(address payable _creator) public onlyOwner {
        creator = _creator;
    }

    function setAllowedBurnedToken(address _burnedToken, bool _bAdded) external onlyOwner {
        _bAdded ? allowedBurnedTokenSet.add(_burnedToken) : allowedBurnedTokenSet.remove(_burnedToken);
    }

    function setBurnedTokenRouter(address _burnedToken, address _router) external onlyOwner {
        require(allowedBurnedTokenSet.contains(_burnedToken), "TangaNFT: burned token NOT allowed.");
        burnedToken2RouterMap[_burnedToken] = _router;
        costToken.approve(_router, 2**256 - 1);
    }

    function getAllBurnedTokens() external view returns(address[] memory burnedTokens){
        uint256 length = allowedBurnedTokenSet.length();
        burnedTokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            burnedTokens[i] = allowedBurnedTokenSet.at(i);
        }
    }

    function isAllowedBurnedToken(address _burnedToken) public view returns(bool) {
        return allowedBurnedTokenSet.contains(_burnedToken);
    }

    function getSun(uint256 _number) public view returns (string memory) {
        return pluck("Sun", _number, unicode"🌞");
    }

    function getPeople(uint256 _number) public view returns (string memory) {
        return pluck("People", _number, unicode'👫');
    }
    
    function getSandyBeach(uint256 _number) public view returns (string memory) {
        return pluck("Sandy Beach", _number, unicode'🏖️');
    }
    
    function getVolcanic(uint256 _number) public view returns (string memory) {
        return pluck("Volcanic", _number, unicode'🌋');
    }

    function pluck(string memory keyPrefix, uint256 _number, string memory _emoji) internal view returns (string memory) {        
        string memory output = string(abi.encodePacked(keyPrefix, ": "));
        for (uint256 i = 0; i < _number; i++) {
            output = string(abi.encodePacked(output, _emoji));
        }
        return output;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        IERC20Metadata burnedToken = IERC20Metadata(nftBurnedTokenMap[tokenId]);
        string memory burnedTokenAddr = uint256(uint160(burnedToken)).toHexString();
        string memory name = burnedToken.name();
        string memory symbol = burnedToken.symbol();
        uint256 decimals = costToken.decimals();

        uint256 mintPrice = nftPriceMap[tokenId].div(10 ** decimals);
        
        string[11] memory parts;
        uint256 i = 0;
        parts[i++] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 425 425"><style>.base { fill: white; font-family: serif; font-size: 14px; }</style><rect width="100%" height="100%" fill="black" /><text x="10" y="20" class="base">';

        parts[i++] = 'Eve of West World';

        parts[i++] = '</text><text x="10" y="40" class="base">';

        parts[i++] = string(abi.encodePacked('Mint Time: ', nftMintTimeMap[tokenId].toString()));

        parts[i++] = '</text><text x="10" y="60" class="base">';

        parts[i++] = string(abi.encodePacked('Mint Price: ', mintPrice.toString(), ' ', symbol));

        parts[i++] = '</text><text x="10" y="80" class="base">';

        parts[i++] = string(abi.encodePacked('Burned Token Name: ', name, '(', symbol, ')');

        parts[i++] = '</text><text x="10" y="100" class="base">';

        parts[i++] = string(abi.encodePacked('Burned Token Address: ', burnedTokenAddr));

        parts[i++] = '</text></svg>';

        string memory output = "";
        for (uint j = 0; j < i; j++) {
            output = string(abi.encodePacked(output, parts[j]));
        }
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "Cell NFT #', tokenId.toString(), '", "description": "Cell NFT can be minted by consuming specified token, and if burned, it could be generate a robot NFT.", "image": "data:image/svg+xml;base64,', Base64.encode(bytes(output)), '"}'))));
        output = string(abi.encodePacked('data:application/json;base64,', json));

        return output;
    }

    function mint(uint256 _amount, uint256 _maxPriceFirstNFT, address _burnedToken) external  {
        require(msg.sender == tx.origin, "TangaNFT: only EOA");
        require(_amount > 0, "TangaNFT: _amount must be larger than zero.");
        require(allowedBurnedTokenSet.contains(_burnedToken), "TangaNFT: burned token NOT allowed.");

        uint256 firstPrice = getCurrentPriceToMint(1); 
        require(firstPrice <= _maxPriceFirstRobot, "TangaNFT: Price does NOT match your expected.");

        uint256 totalMintPrice = _amount == 1 ? firstPrice : getCurrentPriceToMint(_amount);
        costToken.transferFrom(msg.sender, address(this), totalMintPrice);

        uint256 curSupply = getCurrentSupply();
        for (uint256 i = 0; i < _amount; i++) {
            totalEverMinted +=1;    

            _mint(msg.sender, totalEverMinted);
            uint256 mintPrice = (curSupply + i + 1).mul(initMintPrice);  
            nftPriceMap[totalEverMinted] = mintPrice;  
            nftMintTimeMap[totalEverMinted] = block.timestamp;  
            nftBurnedTokenMap[totalEverMinted] = _burnedToken;
        }

        // disburse
        uint256 reserveCut = getReserveCut(_amount);
        reserve = reserve.add(reserveCut);
        costToken.transfer(creator, totalMintPrice.sub(reserveCut).div(2)); // 50% fee to creator, and left 50% to burn token

        emit Minted(totalEverMinted - amount + 1, _amount, totalMintPrice, reserve);
    }

    function burn(uint256[] memory _tokenIds) external {
        require(msg.sender == tx.origin, "TangaNFT: only EOA");
        require(_tokenIds.length > 0, "TangaNFT: NO tokenId");

        uint256 totalBurnPrice = getCurrentPriceToBurn(_tokenIds.length);
        
        // checks if allowed to burn
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 burnPrice = getCurrentPriceToBurn(1);

            require(msg.sender == ownerOf(_tokenIds[i]), "TangaNFT: Not the correct owner");
            _burn(_tokenIds[i]);

            uint256 costTokenAmount2Burn = getCurrentPriceToMint(1).sub(burnPrice).div(2);
            address burnedToken = nftBurnedTokenMap[_tokenIds[i]];
            ISwapRouter router = ISwapRouter(burnedToken2RouterMap[burnedToken]);
            router.swapExactTokensForTokens(costTokenAmount2Burn, 0, [costToken, burnedToken], DeadAddr, block.timestamp);
        }

        reserve = reserve.sub(totalBurnPrice);
        costToken.transfer(msg.sender, totalBurnPrice);

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
}
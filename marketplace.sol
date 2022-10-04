// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


import "hardhat/console.sol";

contract NFTMarketplace is ERC721URIStorage,ERC2981,ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsSold;

    
    address payable owner;
    address payable artist;

    mapping(uint256 => MarketItem) private idToMarketItem;
    mapping(string =>uint256) public uriToId;
    
  

    struct MarketItem {
      uint256 royaltyPercent;
      address payable creator;
      uint256 tokenId;
      address payable seller;
      address payable owner;
      uint256 price;
      bool sold;
    }

    mapping(uint256 => MarketItem) _MarketItem;

    event MarketItemCreated (
      uint256 indexed tokenId,
      address seller,
      address owner,
      address creator,
      uint256 price,
      bool sold
    );

    constructor() ERC721("Vault Industria", "VIMP") {
      owner = payable(msg.sender);
    }

   /**
 * @dev See {IERC165-supportsInterface}.
 */
function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC2981) returns (bool) {
    return super.supportsInterface(interfaceId);
}



  

   

    /* Mints a token and lists it in the marketplace */
    function createToken(string memory tokenURI, uint256 price, uint256 royalty) public payable returns (uint) {
      _tokenIds.increment();
      uint256 newTokenId = _tokenIds.current();

      _mint(msg.sender, newTokenId);
      _setTokenURI(newTokenId, tokenURI);
      createMarketItem(newTokenId, price,royalty);
      uriToId[tokenURI] = newTokenId;
    
      return newTokenId;
    }

    function getTokenId(string memory tokenURI) public view returns (uint256) {
      return uriToId[tokenURI];
    }

    function createMarketItem(
      uint256 tokenId,
      uint256 price,
      uint256 royaltyPercent
    ) private {
      require(price > 0, "Price must be at least 1 wei");
 
      address creator = msg.sender;
      idToMarketItem[tokenId] =  MarketItem(
        royaltyPercent,
       payable(creator),
        tokenId,
        payable(msg.sender),
        payable(address(this)),
        price,
        false
      );

      _transfer(msg.sender, address(this), tokenId);
      emit MarketItemCreated(
        tokenId,
        msg.sender,
        creator,
        address(this),
        price,
        false
      );
    }

    /* delist from market place*/ 

    function delist(uint256 tokenId) public{
      _transfer(address(this),msg.sender, tokenId);

    }

    /* allows someone to resell a token they have purchased */
    function resellToken(uint256 tokenId, uint256 price) public payable {
      require(idToMarketItem[tokenId].owner == msg.sender, "Only item owner can perform this operation");
     
      
      idToMarketItem[tokenId].sold = false;
      idToMarketItem[tokenId].price = price;
      idToMarketItem[tokenId].seller = payable(msg.sender);
      idToMarketItem[tokenId].owner = payable(address(this));
      _itemsSold.decrement();

      _transfer(msg.sender, address(this), tokenId);
      
      
    }
    

    /* Creates the sale of a marketplace item */
    /* Transfers ownership of the item, as well as funds between parties */
    function createMarketSale(
      uint256 tokenId
      ) public payable {
      uint price = idToMarketItem[tokenId].price;
      address seller = idToMarketItem[tokenId].seller;
      address payable creators = idToMarketItem[tokenId].creator;
      uint royalty = idToMarketItem[tokenId].royaltyPercent;
      uint bps = royalty*100;
      uint earning = bps * price /10000;

  

      require(msg.value == price, "Please submit the asking price in order to complete the purchase");
      idToMarketItem[tokenId].owner = payable(msg.sender);
      idToMarketItem[tokenId].sold = true;
      idToMarketItem[tokenId].seller = payable(address(0));
      
      

      _itemsSold.increment();
      _transfer(address(this), msg.sender, tokenId);
     
       _payRoyalty(earning,creators);
      payable(seller).transfer(msg.value-earning);
     
    
    

   

    }

    /* Returns all unsold market items */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
      uint itemCount = _tokenIds.current();
      uint unsoldItemCount = _tokenIds.current() - _itemsSold.current();
      uint currentIndex = 0;

      MarketItem[] memory items = new MarketItem[](unsoldItemCount);
      for (uint i = 0; i < itemCount; i++) {
        if (idToMarketItem[i + 1].owner == address(this)) {
          uint currentId = i + 1;
          MarketItem storage currentItem = idToMarketItem[currentId];
          items[currentIndex] = currentItem;
          currentIndex += 1;
        }
      }
      return items;
    }

    /*fetch item based on tokenURI*/

    function fetchNFT(uint tokenz) public pure returns(MarketItem[] memory){

    MarketItem[] memory item = new MarketItem[](tokenz);

    return item; 

    }

    /* Returns only items that a user has purchased */
    function fetchMyNFTs() public view returns (MarketItem[] memory) {
      uint totalItemCount = _tokenIds.current();
      uint itemCount = 0;
      uint currentIndex = 0;

      for (uint i = 0; i < totalItemCount; i++) {
        if (idToMarketItem[i + 1].owner == msg.sender) {
          itemCount += 1;
        }
      }

      MarketItem[] memory items = new MarketItem[](itemCount);
      for (uint i = 0; i < totalItemCount; i++) {
        if (idToMarketItem[i + 1].owner == msg.sender) {
          uint currentId = i + 1;
          MarketItem storage currentItem = idToMarketItem[currentId];
          items[currentIndex] = currentItem;
          currentIndex += 1;
        }
      }
      return items;
    }

    /* Returns only items a user has listed */
    function fetchItemsListed() public view returns (MarketItem[] memory) {
      uint totalItemCount = _tokenIds.current();
      uint itemCount = 0;
      uint currentIndex = 0;

      for (uint i = 0; i < totalItemCount; i++) {
        if (idToMarketItem[i + 1].seller == msg.sender) {
          itemCount += 1;
        }
      }

      MarketItem[] memory items = new MarketItem[](itemCount);
      for (uint i = 0; i < totalItemCount; i++) {
        if (idToMarketItem[i + 1].seller == msg.sender) {
          uint currentId = i + 1;
          MarketItem storage currentItem = idToMarketItem[currentId];
          items[currentIndex] = currentItem;
          currentIndex += 1;
        }
      }
      return items;
    }

    function checkValue(uint256 tokenId) public view  returns(uint){
    
        return idToMarketItem[tokenId].price * 1 wei;
      
    }

      function _payRoyalty(uint256 _royalityFee,address artists) internal {
     
        (bool success1, ) = payable(artists).call{value: _royalityFee}("");
        require(success1);
    }
}


















































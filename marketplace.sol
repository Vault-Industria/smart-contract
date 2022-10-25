// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

import "hardhat/console.sol";

contract NFTMarketplace is ERC721URIStorage, ERC2981 {
    event Start();
    event Bid(address indexed sender, uint256 amount);
    event Withdraw(address indexed bidder, uint256 amount);
    event Ended(uint256 highestBid, address highestBidder);

    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemsSold;
    

    uint auctionCount;
    uint fixedCount;
    address payable owner;
    address payable artist;

    mapping(uint256 => MarketItem) private idToMarketItem;
    mapping(uint256 => AuctionItem) private idToAuctionItem;
    mapping(string => uint256) public uriToId;

    struct MarketItem {
        uint96 royaltyPercent;
        address payable creator;
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        bool sold;
    }

    struct AuctionItem {
        uint96 royaltyPercent;
        address payable creator;
        uint256 tokenId;
        address payable seller;
        address payable owner;
        uint256 price;
        uint256 start;
        bool started;
        bool sold;
        uint endAt;
        uint256 highestBid;
        address highestBidder;
        bool ended;
    }

    mapping(uint256 => mapping(address => uint256)) bids;

    mapping(uint256 => MarketItem) _MarketItem;

    event MarketItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        address creator,
        uint256 price,
        bool sold
    );

    event AuctionItemCreated(
        uint256 indexed tokenId,
        address seller,
        address owner,
        address creator,
        uint256 price,
        uint256 start,
        bool started,
        bool sold,
        uint endAt,
        uint256 highestBid,
        address highestBidder
    );

    constructor() ERC721("Vault Industria", "VIMP") {
        owner = payable(msg.sender);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /* Mints a token and lists it in the marketplace */
    function createToken(
        string memory tokenURI,
        uint256 price,
        uint96 royalty
    ) public payable returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        createMarketItem(newTokenId, price, royalty);
        uriToId[tokenURI] = newTokenId;

        return newTokenId;
    }

    function createAuctionToken(
        string memory tokenURI,
        uint256 price,
        uint96 royalty,
        uint endTime
    ) public payable returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        createAuctionItem(newTokenId, price, royalty, endTime);
        uriToId[tokenURI] = newTokenId;

        return newTokenId;
    }

    function getTokenId(string memory tokenURI) public view returns (uint256) {
        return uriToId[tokenURI];
    }

    function createMarketItem(
        uint256 tokenId,
        uint256 price,
        uint96 royaltyPercent
    ) private {
        require(price > 0, "Price must be at least 1 wei");

        address creator = msg.sender;

        idToMarketItem[tokenId] = MarketItem(
            royaltyPercent,
            payable(creator),
            tokenId,
            payable(msg.sender),
            payable(address(this)),
            price,
            false
        );

        _transfer(msg.sender, address(this), tokenId);
        fixedCount++;

        emit MarketItemCreated(
            tokenId,
            msg.sender,
            creator,
            address(this),
            price,
            false
        );

    }

    function createAuctionItem(
        uint256 tokenId,
        uint256 price,
        uint96 royaltyPercent,
        uint endTime
    ) private {
        require(price > 0, "Price must be at least 1 wei");
        uint endsAt = endTime;
        address creator = msg.sender;

        idToAuctionItem[tokenId] = AuctionItem(
            royaltyPercent,
            payable(creator),
            tokenId,
            payable(msg.sender),
            payable(address(this)),
            price,
            endTime,
            true,
            false,
            endsAt,
            price,
            msg.sender,
            false
        );

        _transfer(msg.sender, address(this), tokenId);

        emit AuctionItemCreated(
            tokenId,
            msg.sender,
            creator,
            address(this),
            price,
            endTime,
            true,
            false,
            endsAt,
            price,
            msg.sender
        );
        auctionCount++;

        emit Start();
    }

    /* delist from market place*/

    function delist(uint256 tokenId) public {
        require(idToMarketItem[tokenId].seller == msg.sender);
        idToMarketItem[tokenId].sold = false;
        _itemsSold.decrement();
        _transfer(address(this), msg.sender, tokenId);
    }

    /* allows someone to resell a token they have purchased */
    function resellToken(uint256 tokenId, uint256 price) public payable {
        require(
            idToMarketItem[tokenId].owner == msg.sender,
            "Only item owner can perform this operation"
        );

        idToMarketItem[tokenId].sold = false;
        idToMarketItem[tokenId].price = price;
        idToMarketItem[tokenId].seller = payable(msg.sender);
        idToMarketItem[tokenId].owner = payable(address(this));
        _itemsSold.decrement();

        _transfer(msg.sender, address(this), tokenId);
    }


    /* Creates the sale of a marketplace item */
    /* Transfers ownership of the item, as well as funds between parties */
    function createMarketSale(uint256 tokenId) public payable {
        uint256 price = idToMarketItem[tokenId].price;
        address seller = idToMarketItem[tokenId].seller;
        address creators = idToMarketItem[tokenId].creator;
        uint256 royalty = idToMarketItem[tokenId].royaltyPercent;
        uint256 bps = royalty * 100;
        uint256 earning = (bps * price) / 10000;

        require(
            msg.value == price,
            "Please submit the asking price in order to complete the purchase"
        );
        idToMarketItem[tokenId].owner = payable(msg.sender);
        idToMarketItem[tokenId].sold = true;
        idToMarketItem[tokenId].seller = payable(address(0));

        _itemsSold.increment();
        _transfer(address(this), msg.sender, tokenId);

        payable(seller).transfer(msg.value);
        fixedCount--;
    }

    /* Bids are being made */

    function bid(uint256 _tokenId) external payable {
        bool started = idToAuctionItem[_tokenId].started;
        uint256 ending = idToAuctionItem[_tokenId].endAt;
        uint256 highestBd = idToAuctionItem[_tokenId].highestBid;

        require(started, "Not started");
        require(block.timestamp < ending, "Ended!");
        require(msg.value > highestBd);

        if (idToAuctionItem[_tokenId].highestBidder != address(0)) {
            bids[_tokenId][
                idToAuctionItem[_tokenId].highestBidder
            ] += highestBd;
        }

        idToAuctionItem[_tokenId].highestBid = msg.value;
        idToAuctionItem[_tokenId].highestBidder = msg.sender;

        emit Bid(msg.sender, msg.value);
    }

    function withdraw(uint256 _tokenId) external payable {
     
        uint256 bal = bids[_tokenId][msg.sender] * (1 ether);
        bids[_tokenId][msg.sender] = 0;

        (bool sent, bytes memory data) = payable(msg.sender).call{value: bal}(
            ""
        );
        require(sent, "Could not withdraw");

        emit Withdraw(msg.sender, bal);
    }

    //End the auction
    function end(uint256 _tokenId) external {
        require(idToAuctionItem[_tokenId].started, "You need to start");
        require(
            block.timestamp >= idToAuctionItem[_tokenId].endAt,
            "Auction is still going on"
        );
        require(!idToAuctionItem[_tokenId].ended, "Auction already ended");

        if (idToAuctionItem[_tokenId].highestBidder != address(0)) {
            _transfer(
                address(this),
                idToAuctionItem[_tokenId].highestBidder,
                _tokenId
            );
            _itemsSold.increment();
            (bool sent, bytes memory data) = idToAuctionItem[_tokenId]
                .seller
                .call{value: idToAuctionItem[_tokenId].highestBid}("");
            require(sent, "Could not pay seller");
        } else {
            _transfer(
                address(this),
                idToAuctionItem[_tokenId].seller,
                _tokenId
            );
        }

        idToAuctionItem[_tokenId].ended = true;
        auctionCount--;

        emit Ended(
            idToAuctionItem[_tokenId].highestBid,
            idToAuctionItem[_tokenId].highestBidder
        );
    }

    /* Returns all unsold market items */
    function fetchMarketItems() public view returns (MarketItem[] memory) {
        uint256 itemCount = _tokenIds.current();
        uint256 unsoldItemCount = _tokenIds.current() - _itemsSold.current();
        uint256 currentIndex = 0;

        MarketItem[] memory items = new MarketItem[](unsoldItemCount-auctionCount);
        for (uint256 i = 0; i < itemCount; i++) {
           
                  if (idToMarketItem[i + 1].owner == address(this) ) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            

            }
          
        }
        return items;
    }

    /* Returns all unsold market items */
    function fetchAuctionItems() public view returns (AuctionItem[] memory) {
        uint256 itemCount = _tokenIds.current();
        uint256 unsoldItemCount = _tokenIds.current() - _itemsSold.current();
        uint256 currentIndex = 0;

        AuctionItem[] memory items = new AuctionItem[](unsoldItemCount-fixedCount);
        for (uint256 i = 0; i < itemCount; i++) {
            if (idToAuctionItem[i + 1].owner == address(this)) {
                uint256 currentId = i + 1;
                AuctionItem storage currentItem = idToAuctionItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /*fetch item based on tokenURI*/

    function fetchNFT(uint256 tokenz)
        public
        pure
        returns (MarketItem[] memory)
    {
        MarketItem[] memory item = new MarketItem[](tokenz);

        return item;
    }

    /* Returns only items that a user has purchased */
    function fetchMyNFTs() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].owner == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].owner == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items that a user has purchased  on auction*/
    function fetchMyAuctionNFTs() public view returns (AuctionItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToAuctionItem[i + 1].owner == msg.sender) {
                itemCount += 1;
            }
        }

        AuctionItem[] memory items = new AuctionItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToAuctionItem[i + 1].owner == msg.sender) {
                uint256 currentId = i + 1;
                AuctionItem storage currentItem = idToAuctionItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items a user has listed */
    function fetchItemsListed() public view returns (MarketItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].seller == msg.sender) {
                itemCount += 1;
            }
        }

        MarketItem[] memory items = new MarketItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToMarketItem[i + 1].seller == msg.sender) {
                uint256 currentId = i + 1;
                MarketItem storage currentItem = idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items a user has Auctioned */
    function fetchItemsAuctione() public view returns (AuctionItem[] memory) {
        uint256 totalItemCount = _tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToAuctionItem[i + 1].seller == msg.sender) {
                itemCount += 1;
            }
        }

        AuctionItem[] memory items = new AuctionItem[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToAuctionItem[i + 1].seller == msg.sender) {
                uint256 currentId = i + 1;
                AuctionItem storage currentItem = idToAuctionItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./NitrilityMarketplace.sol";
import "./NitrilityFactory.sol";

contract NitrilityNFT is ERC721URIStorage {
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    address payable marketOwner;
    address payable nitrilityMarketplace;
    address payable nitrilityFactory;

    Counters.Counter private listedLicenseIds;
    Counters.Counter private tokenIds;
    Counters.Counter private soldLicenseIds;

    mapping(uint256 => SoldLicense) private idToSoldLicense;

    struct SoldLicense {
        uint256 tokenId;
        string tokenURI;
        string artistId;
        address payable seller;
        address payable owner;
        uint256 price;
    }
    
    constructor(address _nitrilityMarketplace, address _nitrilityFactory) ERC721("Nitrility NFT", "NNFT") {
        marketOwner = payable(msg.sender);
        nitrilityMarketplace = payable(_nitrilityMarketplace);
        nitrilityFactory = payable(_nitrilityFactory);
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || _msgSender() == marketOwner || _msgSender() == nitrilityMarketplace || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not token owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual override returns (bool) {
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender || spender == nitrilityFactory);
    }

    function burn(uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved, market owner");
        _burn(tokenId);
    }

    modifier onlyOwner() {
        require(msg.sender == marketOwner, "Only owner of this contract can do this");
        _;
    }

    /* Mints a token and transfers to the recipient */
    function createTokenForOffer(
        uint256 _listedLicenseId,
        string memory _newTokenURI,
        address _buyerAddress,
        uint256 _price
    ) public payable {
        tokenIds.increment();
        uint256 newTokenId = tokenIds.current();
        _mint(_buyerAddress, newTokenId);
        _setTokenURI(newTokenId, _newTokenURI);
        createMarketSale(_buyerAddress, _listedLicenseId, newTokenId, _price, _newTokenURI, 1);
        approve(marketOwner, newTokenId);
    }

    /* Mints the several token and transfers to the recipient */
    function createTokens(
        uint256[] memory _ids,
        string[] memory _newTokenURIs,
        string memory _discountCode,
        address _buyerAddress
    ) public payable {
        NitrilityMarketplace marketplaceInstance = NitrilityMarketplace(nitrilityMarketplace);

        for(uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            tokenIds.increment();
            uint256 newTokenId = tokenIds.current();
            _mint(_buyerAddress, newTokenId);
            _setTokenURI(newTokenId, _newTokenURIs[i]);
            uint256 price = marketplaceInstance.fetchDiscountedPrice(id, _discountCode);
            marketplaceInstance.addBalanceForArtist(id, price);
            createMarketSale(_buyerAddress, id, newTokenId, price, _newTokenURIs[i], 0);
            approve(marketOwner, newTokenId);
        }
    }

    /* Mints the several token and transfers to the recipient */
    function purchaseRecommendedLicense(
        uint256 _id,
        string memory _newTokenURI,
        address _buyerAddress
    ) public payable {
        NitrilityMarketplace marketplaceInstance = NitrilityMarketplace(nitrilityMarketplace);
        (, uint256 recommendedPrice) = marketplaceInstance.fetchPriceForListedLicense(_id);
        require(msg.value == recommendedPrice, "Purchasing License: Not enough ETH");

        tokenIds.increment();
        uint256 newTokenId = tokenIds.current();
        _mint(_buyerAddress, newTokenId);
        _setTokenURI(newTokenId, _newTokenURI);
        marketplaceInstance.addBalanceForArtist(_id, recommendedPrice);
        payable(nitrilityMarketplace).transfer(msg.value);
        createMarketSale(_buyerAddress, _id, newTokenId, recommendedPrice, _newTokenURI, 3);
        approve(marketOwner, newTokenId);
    }

    /* Mints a token and transfers to the recipient */
    function reCreateBurnedToken(
        address _ownerAddress,
        uint256 _listedLicenseId,
        uint256 _price,
        string memory _newTokenURI
    ) public payable {
        tokenIds.increment();
        uint256 newTokenId = tokenIds.current();
        _mint(_ownerAddress, newTokenId);
        _setTokenURI(newTokenId, string(abi.encodePacked(_newTokenURI)));
        createMarketSale(_ownerAddress, _listedLicenseId, newTokenId, _price, _newTokenURI, 4);
        approve(marketOwner, newTokenId);
    }
    /* Creates the sale of a marketplace item */
    /* Transfers ownership of the item, as well as funds between parties */

    function emitSoldLicenseCreated (
        uint256 _tokenId,
        uint256 _listedLicenseId,
        string memory _newTokenURI,
        string memory _artistId,
        address _seller,
        address _owner,
        uint256 _price,
        uint256 _saleType
    ) internal{
        NitrilityFactory factoryInstance = NitrilityFactory(nitrilityFactory);
        factoryInstance.emitSoldLicenseCreated(_tokenId, _listedLicenseId, _newTokenURI, _artistId, _seller, _owner, _price, _saleType);
    }

    function createMarketSale(
        address ownerAddress,
        uint256 _listedLicenseId,
        uint256 _tokenId,
        uint256 _price,
        string memory _newTokenURI,
        uint256 _saleType
    ) private {
        NitrilityMarketplace marketplaceInstance = NitrilityMarketplace(nitrilityMarketplace);
        (address seller, string memory artistId) = marketplaceInstance.fetchSellerAddressForListedLicense(_listedLicenseId);
        idToSoldLicense[_tokenId] = SoldLicense(
            _tokenId,
            _newTokenURI,
            artistId,
            payable(seller),
            payable(ownerAddress),
            _price
        );
        soldLicenseIds.increment();
        emitSoldLicenseCreated(_tokenId, _listedLicenseId, _newTokenURI, artistId, seller, ownerAddress, _price, _saleType);
    }

    /* Returns all unsold market items */
    function fetchSoldLicenses(address _seller) public view returns (SoldLicense[] memory) {
        uint256 itemCount = tokenIds.current();
        uint256 soldItemCount = soldLicenseIds.current();
        uint256 currentIndex = 0;

        SoldLicense[] memory items = new SoldLicense[](soldItemCount);
        for (uint256 i = 1; i <= itemCount; i++) {
            if (idToSoldLicense[i].seller == _seller) {
                SoldLicense storage currentItem = idToSoldLicense[i];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Returns only items that a creator has purchased */
    function fetchOwnedNFTs(address _address)
        public
        view
        returns (SoldLicense[] memory)
    {
        uint256 totalItemCount = tokenIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToSoldLicense[i + 1].owner == payable(_address)) {
                itemCount += 1;
            }
        }

        SoldLicense[] memory items = new SoldLicense[](itemCount);
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (idToSoldLicense[i + 1].owner == payable(_address)) {
                uint256 currentId = i + 1;
                SoldLicense storage currentItem = idToSoldLicense[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Transfer the nft from one wallet to the another wallet */
    function transferNFT(address to, uint256 _tokenId, address _caller) external payable {
        require(idToSoldLicense[_tokenId].owner == _caller, "Only owner can transfer the nft");
        _transfer(_caller, to, _tokenId);
        idToSoldLicense[_tokenId].owner = payable(to);
        // emit NFTtransfer(_tokenId, _caller, to);
        NitrilityFactory factoryInstance = NitrilityFactory(nitrilityFactory);
        factoryInstance.emitNftTransfer(idToSoldLicense[_tokenId].artistId, _tokenId, _caller, to);
    }

    /* Burns the expired NFT/SoldLicense */
    function burnSoldNFT(uint256 _tokenId) public {
        require(
            _isApprovedOrOwner(msg.sender, _tokenId),
            "ERC721Burnable: caller is not owner nor approved"
        );
        delete idToSoldLicense[_tokenId];
        _burn(_tokenId);
        // emit NFTburnt(_tokenId);
        NitrilityFactory factoryInstance = NitrilityFactory(nitrilityFactory);
        factoryInstance.emitNftburnt(idToSoldLicense[_tokenId].artistId, _tokenId);
    }

    // giving gifts
    function givingGift(
        uint256 _listedLicenseId,
        address _receiver,
        string memory _newTokenURI,
        uint256 _amount
    ) external{
        require(_amount > 0, "should be greater than 0");
        for(uint256 i = 0; i < _amount; i++){
            tokenIds.increment();
            uint256 newTokenId = tokenIds.current();
            _mint(_receiver, newTokenId);
            _setTokenURI(newTokenId, string(abi.encodePacked(_newTokenURI)));
            createMarketSale(_receiver, _listedLicenseId, newTokenId, 0, _newTokenURI, 2);
        }
    }
}
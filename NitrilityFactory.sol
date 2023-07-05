// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./NitrilityMarketplace.sol";
import "./NitrilityNft.sol";

contract NitrilityFactory is Ownable, ReentrancyGuard {
    
    using EnumerableSet for EnumerableSet.Bytes32Set;
    EnumerableSet.Bytes32Set artistIdSet;

    address payable nitrilityMarketplace;

    // artist id => collection
    mapping(string => address) private idToArtistCollectionAddress;

    // collection
    event CollectionCreated(
        string artistId,
        address collectionAddress
    );

    // license
    event SoldLicenseCreated(
        uint256 tokenId,
        uint256 listedLicenseId,
        string tokenURI,
        string artistId,
        address seller,
        address owner,
        uint256 price,
        uint256 saleType // 0 - sale, 1 - offer, 2 - gifting, 3 - recommended, 4 - recreated token
    );

    event NFTburnt(string artistId, uint256 tokenId);

    event NFTtransfer(string artistId, uint256 tokenId, address from, address to);
    
    modifier onlyMarketplace() {
        require(msg.sender == nitrilityMarketplace, "Only marketplace can do this");
        _;
    }

    modifier onlyNft() {
        bool bCollection = false;
        for (uint256 i = 0; i < artistIdSet.length(); i++) {
            if(msg.sender == idToArtistCollectionAddress[bytes32ToString(artistIdSet.at(i))]){
                bCollection = true;
                break;
            }
        }
        require(bCollection, "Only collection can do this");
        _;
    }
    
    function setNitrilityMarketplace(address _marketplace) external onlyOwner {
        nitrilityMarketplace = payable(_marketplace);
    }

    function stringToBytes32(string memory str) public pure returns (bytes32 result) {
        require(bytes(str).length <= 32, "String too long for conversion to bytes32");
        assembly {
            result := mload(add(str, 32))
        }
    }

    function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function emitSoldLicenseCreated(
        uint256 _tokenId,
        uint256 _listedLicenseId,
        string memory _newTokenURI,
        string memory _artistId,
        address _seller,
        address _owner,
        uint256 _price,
        uint256 _saleType
    ) external onlyNft {
        emit SoldLicenseCreated(_tokenId, _listedLicenseId, _newTokenURI, _artistId, _seller, _owner, _price, _saleType);
    }

    function emitNftburnt(
        string memory artistId,
        uint256 tokenId
    ) external onlyNft {
        emit NFTburnt(artistId, tokenId);
    }

    function emitNftTransfer(
        string memory artistId, 
        uint256 tokenId, 
        address from, 
        address to
    ) external onlyNft {
        emit NFTtransfer(artistId, tokenId, from, to);
    }

    function createCollection(string memory _artistId) external onlyMarketplace {
        if(idToArtistCollectionAddress[_artistId] == address(0)){
            // Create a new instance of NitrilityNFT

            NitrilityNFT newContract = new NitrilityNFT(nitrilityMarketplace, address(this));

            // store address for artist id
            idToArtistCollectionAddress[_artistId] = address(newContract);

            artistIdSet.add(stringToBytes32(_artistId));

            // Emit an event indicating that a new instance has been created
            emit CollectionCreated(_artistId, address(newContract));
        }
    }

    function fetchCollectionAddressOfArtist(string memory _artistId) public view returns(address){
        return idToArtistCollectionAddress[_artistId];
    }

    function createTokens(
        string[] memory _artistIds,
        uint256[] memory _listedIds,
        string[] memory _newTokenURIs,
        string memory _discountCode,
        address _buyerAddress
    ) public payable {
        require(_listedIds.length == _artistIds.length && _artistIds.length == _newTokenURIs.length, "Invalid Parameters");
        uint256 totalPrice;
        bool bApplied;
        NitrilityMarketplace marketplaceInstance = NitrilityMarketplace(nitrilityMarketplace);
        (totalPrice, bApplied) = marketplaceInstance.fetchTotalDiscountedPrice(_listedIds, _discountCode);
        require(msg.value == totalPrice, "Purchasing License: Not enough ETH");

        for(uint256 i = 0; i < _artistIds.length; i++){
            NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[_artistIds[i]]);
            nftContract.createTokens(
                _listedIds,
                _newTokenURIs,
                _discountCode,
                _buyerAddress
            );
        }
        payable(nitrilityMarketplace).transfer(msg.value);
    }

    function purchaseRecommendedLicense(
        string memory _artistId,
        uint256 _listedId,
        string memory _newTokenURI,
        address _buyerAddress
    ) public payable {
        NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[_artistId]);
        nftContract.purchaseRecommendedLicense(
            _listedId,
            _newTokenURI,
            _buyerAddress
        );
    }

    /* Mints a token and transfers to the recipient */
    function reCreateBurnedToken(
        string memory _artistId,
        address _ownerAddress,
        uint256 _listedLicenseId,
        uint256 _price,
        string memory _newTokenURI
    ) public payable onlyOwner{
        NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[_artistId]);
        nftContract.reCreateBurnedToken(
            _ownerAddress,
            _listedLicenseId,
            _price,
            _newTokenURI
        );
    }

    function fetchSoldLicenses(string memory _artistId, address _seller) public view returns (NitrilityNFT.SoldLicense[] memory) {
        NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[_artistId]);
        return nftContract.fetchSoldLicenses(_seller);
    }

    function fetchOwnedNFTs(address _address)
        public
        view
        returns (NitrilityNFT.SoldLicense[] memory)
    {
        uint256 totalNFTs = 0;
        for (uint256 i = 0; i < artistIdSet.length(); i++) {
            NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[bytes32ToString(artistIdSet.at(i))]);
            NitrilityNFT.SoldLicense[] memory ownedNFTs = nftContract.fetchOwnedNFTs(_address);
            totalNFTs += ownedNFTs.length;
        }
        NitrilityNFT.SoldLicense[] memory allOwnedNFTs = new NitrilityNFT.SoldLicense[](totalNFTs);
        uint256 index;
        for (uint256 i = 0; i < artistIdSet.length(); i++) {
            NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[bytes32ToString(artistIdSet.at(i))]);
            NitrilityNFT.SoldLicense[] memory ownedNFTs = nftContract.fetchOwnedNFTs(_address);
            for (uint256 j = 0; j < ownedNFTs.length; j++) {
                allOwnedNFTs[index] = ownedNFTs[j];
                index++;
            }
        }
        return allOwnedNFTs;
    }

    function transferNFT(string memory _artistId, address _to, uint256 _tokenId) external payable {
        NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[_artistId]);
        nftContract.transferNFT(_to, _tokenId, msg.sender);
    }

    function burnSoldNFT(string memory _artistId, uint256 _tokenId) public {
        NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[_artistId]);
        nftContract.burnSoldNFT(_tokenId);
    }

    function givingGift(
        uint256 _listedLicenseId,
        address _receiver,
        string memory _newTokenURI,
        uint256 _amount
    ) external{
        NitrilityMarketplace marketplaceInstance = NitrilityMarketplace(nitrilityMarketplace);
        NitrilityMarketplace.ListedLicense memory license = marketplaceInstance.fetchListedLicenseForListedId(_listedLicenseId);
        require(marketplaceInstance.checkOwner(msg.sender, _listedLicenseId), "caller is not owner");

        NitrilityNFT nftContract = NitrilityNFT(idToArtistCollectionAddress[license.artistId]);
        nftContract.givingGift(
            _listedLicenseId,
            _receiver,
            _newTokenURI,
            _amount
        );
    }
}
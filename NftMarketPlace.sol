// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract NitrilityNFTMarketplace is ERC721URIStorage {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    EnumerableSet.UintSet listedLicenseSet;
    EnumerableSet.UintSet offerSet;
    
    Counters.Counter private listedLicenseIds;
    Counters.Counter private tokenIds;
    Counters.Counter private soldLicenseIds;
    Counters.Counter private offerIds;
    uint256 gasFee = 1000000000000000;

    address payable marketOwner;
    address public nitrility;
    uint256 public nitriltiyRevenue;

    mapping(uint256 => ListedLicense) private idToListedLicense;
    mapping(uint256 => SoldLicense) private idToSoldLicense;
    
    mapping(uint256 => Offer) private idToOffer;
    // license id => offer id
    mapping(uint256 => EnumerableSet.UintSet) private offerIdsForLicense;
    mapping(address => EnumerableSet.UintSet) private offerIdsForBuyer;
    // revenue splitter
    mapping(bytes32 => address) private idToAddress; //artist id
    mapping(address => uint256) private addressToBalanceOfUser;

    // license id => revenue percentages
    mapping(uint256 => mapping(bytes32 => Revenue)) private listedIdToRevenues;
    mapping(uint256 => EnumerableSet.Bytes32Set) private listedIdToArtistIds;
    // license id => discount codes
    mapping(uint256 => mapping(uint256 => DiscountCode)) private listedIdToDiscountCodes;
    mapping(uint256 => uint256) private listedIdToDiscountCodeCount;

    struct DiscountCode {
        bytes name;
        uint256 percentage;
    }

    struct Revenue {
        address artistAddress;
        bytes artistName;
        uint256 percentage;
        bool isAdmin;
        uint256 status; // 0 - pending, 1 - approved, 2 - rejected
    }

    struct ListedLicense {
        uint256 listedLicenseId;
        uint256 price;
        bytes tokenURI;
        address payable seller;
        uint256 listedTime;
        uint256 bidCount;
    }

    struct SoldLicense {
        uint256 tokenId;
        bytes tokenURI;
        address payable seller;
        address payable owner;
        uint256 price;
    }

    // Aution
    struct Offer {
        address _seller;
        address _buyer;
        uint256 offerId;
        uint256 status; //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        uint256 listedLicenseId;
        bytes tokenURI;
        uint256 offerPrice;
        uint256 offerDuration;
        uint256 offerTime;
    }

    event OfferCreated (
        address _seller,
        address _buyer,
        uint256 offerId,
        uint256 listedLicenseId,
        uint256 status
    );

    event ListedLicenseCreated(
        uint256 listedLicenseId,
        uint256 price,
        bytes tokenURI,
        address seller,
        uint256 listedTime,
        uint256 bidCount
    );

    event SoldLicenseCreated(
        uint256 indexed tokenId,
        bytes tokenURI,
        address seller,
        address owner,
        uint256 price
    );

    // event NFTburnt(uint256 tokenId);

    // event NFTtransfer(uint256 tokenId, address from, address to);


    constructor() ERC721("Nitrility NFT", "NNFT") {
        marketOwner = payable(msg.sender);
        nitrility = msg.sender;
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || _msgSender() == marketOwner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not token owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual override returns (bool) {
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender || spender == marketOwner);
    }

    function burn(uint256 tokenId) public virtual {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner or approved, market owner");
        _burn(tokenId);
    }

    modifier onlyOwner() {
        require(msg.sender == marketOwner || msg.sender == nitrility, "Only owners can mint");
        _;
    }

    function setNitrility(address _nitrility) public onlyOwner{
        nitrility = _nitrility;
    }
    
    function setArtistAddress(bytes memory _artistId, address _artistAddress) external onlyOwner {
        idToAddress[bytes32(bytes(_artistId))] = _artistAddress;
        for(uint256 i = 0; i < listedLicenseSet.length(); i++){
            listedIdToRevenues[listedLicenseSet.at(i)][bytes32(bytes(_artistId))].artistAddress = _artistAddress;
        }
    }

    function fetchArtistAddressForArtistId(bytes memory artistId) public view returns(address){
        return idToAddress[bytes32(bytes(artistId))];
    }
    /* Returns listedLicenses count */
    function getListedLicensesCount() public view returns (uint256) {
        return listedLicenseSet.length();
    }

    /* Creates a listedLicense */
    function listLicense(
        uint256 _price,
        bytes memory _tokenURI, 
        bytes[] memory _ids,
        bytes[] memory _artistNames,
        uint256[] memory _percentages,
        bool[] memory _admins,
        uint256[] memory _statuses,
        bytes[] memory _discountCodeNames,
        uint256[] memory _discountCodePercentages
    ) public payable {
        bool bExisting = false;
        uint256 totalPercentage;
        for(uint256 i = 0; i < _ids.length; i++){
            if(idToAddress[bytes32(bytes(_ids[i]))] == msg.sender) bExisting = true;
            totalPercentage = totalPercentage + _percentages[i];
        }
        require(bExisting, "RevenueSplitter: Only Artist who own this license can list");
        require(_ids.length == _percentages.length && _percentages.length == _admins.length && _admins.length == _statuses.length && _artistNames.length == _statuses.length, "RevenueSplitter: artist ids, percentages mismatch");
        require(_ids.length > 0, "RevenueSplitter: no artists provided");
        require(totalPercentage == 100, "RevenueSplitter: total revenue percentage should be 100%");

        require(_discountCodeNames.length == _discountCodePercentages.length, "DiscountCode: discount name, percentages mismatch");

        listedLicenseIds.increment();
        uint256 _newListedLicenseId = listedLicenseIds.current();

        for(uint256 p = 0; p < _discountCodeNames.length; p++){
            listedIdToDiscountCodes[_newListedLicenseId][p].name = _discountCodeNames[p];
            listedIdToDiscountCodes[_newListedLicenseId][p].percentage = _discountCodePercentages[p];
        }
        listedIdToDiscountCodeCount[_newListedLicenseId] = _discountCodeNames.length;

        for(uint256 j = 0; j < _ids.length; j++){
            listedIdToRevenues[_newListedLicenseId][bytes32(bytes(_ids[j]))].artistAddress = idToAddress[bytes32(bytes(_ids[j]))];
            listedIdToRevenues[_newListedLicenseId][bytes32(bytes(_ids[j]))].artistName = _artistNames[j];
            listedIdToRevenues[_newListedLicenseId][bytes32(bytes(_ids[j]))].percentage = _percentages[j];
            listedIdToRevenues[_newListedLicenseId][bytes32(bytes(_ids[j]))].isAdmin = _admins[j];
            listedIdToRevenues[_newListedLicenseId][bytes32(bytes(_ids[j]))].status = _statuses[j];
            listedIdToArtistIds[_newListedLicenseId].add(bytes32(bytes(_ids[j])));
        }

        listedLicenseSet.add(_newListedLicenseId);
        idToListedLicense[_newListedLicenseId] = ListedLicense(
            _newListedLicenseId,
            _price,
            _tokenURI,
            payable(msg.sender),
            block.timestamp,
            0
        );
        emit ListedLicenseCreated(_newListedLicenseId, _price, _tokenURI, msg.sender, block.timestamp, 0);
    }

    function fetchDiscountCodeForListedid(uint256 listedId) public view returns(DiscountCode[] memory){
        uint256 count = listedIdToDiscountCodeCount[listedId];
        mapping(uint256 => DiscountCode) storage discounts = listedIdToDiscountCodes[listedId];

        DiscountCode[] memory result = new DiscountCode[](count);

        // Loop over revenues by keys to extract each revenue object
        for (uint256 i = 0; i < count; i++) {
            DiscountCode storage discount = discounts[i];
            // Set extracted revenue object in result array at respective index
            result[i] = discount;
        }
        return result;
    }

    function updateDiscountCodeForListedId(
        uint256 listedId, 
        bytes[] memory _discountCodeNames,
        uint256[] memory _discountCodePercentages
    ) external {
        require(_discountCodeNames.length == _discountCodePercentages.length, "Updating DiscountCode: discount name, percentages mismatch");
        require(_discountCodeNames.length > 0, "Updating DiscountCode: no discountcode provided");
        require(listedLicenseSet.contains(listedId), "Updating DiscountCode: we dont have this license");

        for(uint256 p = 0; p < _discountCodeNames.length; p++){
            listedIdToDiscountCodes[listedId][p].name = _discountCodeNames[p];
            listedIdToDiscountCodes[listedId][p].percentage = _discountCodePercentages[p];
        }
        listedIdToDiscountCodeCount[listedId] = _discountCodeNames.length;
    }

    function removeDiscountCodeForListedId(
        uint256 listedId
    ) external {
        require(listedLicenseSet.contains(listedId), "Updating DiscountCode: we dont have this license");
        for(uint256 i = 0; i < listedIdToDiscountCodeCount[listedId]; i++){
            delete listedIdToDiscountCodes[listedId][i];
        }
    }

    function fetchRevenueForListedId(uint256 listedId) public view returns (Revenue[] memory) {
        uint256 revenueLength = listedIdToArtistIds[listedId].length();
        mapping(bytes32 => Revenue) storage revenues = listedIdToRevenues[listedId];

        Revenue[] memory result = new Revenue[](revenueLength);

        // Loop over revenues by keys to extract each revenue object
        for (uint256 i = 0; i < revenueLength; i++) {
            bytes32 revenueKey = listedIdToArtistIds[listedId].at(i);
            Revenue storage revenue = revenues[revenueKey];
            
            // Set extracted revenue object in result array at respective index
            result[i] = revenue;
        }
        return result;
    }

    function updateRevenueForListedId(
        uint256 listedid, 
        bytes32[] memory _ids,
        uint256[] memory _percentages,
        bool[] memory _admins,
        uint256[] memory _statuses
    ) external {
        require(_ids.length == _percentages.length && _percentages.length == _admins.length && _admins.length == _statuses.length, "RevenueSplitter: artist ids, percentages mismatch");
        require(_ids.length > 0, "RevenueSplitter: no artists provided");
        for(uint256 j = 0; j < _ids.length; j++){
            listedIdToRevenues[listedid][_ids[j]].artistAddress = idToAddress[_ids[j]];
            listedIdToRevenues[listedid][_ids[j]].percentage = _percentages[j];
            listedIdToRevenues[listedid][_ids[j]].isAdmin = _admins[j];
            listedIdToRevenues[listedid][_ids[j]].status = _statuses[j];
            listedIdToArtistIds[listedid].add(_ids[j]);
        }
    }

    /* Returns all the listedLicenses available */
    function fetchAllListedLicenses() public view returns (ListedLicense[] memory) {
        uint256 itemCount = listedLicenseSet.length();
        uint256 currentIndex = 0;

        ListedLicense[] memory items = new ListedLicense[](itemCount);

        for (uint256 index = 0; index < itemCount; index++) {
            uint256 currentId = listedLicenseSet.at(index);
            ListedLicense storage currentItem = idToListedLicense[currentId];
            items[currentIndex] = currentItem;
            currentIndex++;
        }
        return items;
    }

    /* Mints a token and transfers to the recipient */
    // function createToken(
    //     uint256 _listedLicenseId,
    //     bytes memory _newTokenURI
    // ) public payable {
    //     uint256 price = idToListedLicense[_listedLicenseId].price;
    //     require(msg.value == price, "Not enough ETH");
    //     uint256 fee = msg.value.mul(25).div(1000);
    //     nitriltiyRevenue += fee;
        
    //     for(uint256 i = 0; i < listedIdToArtistIds[_listedLicenseId].length(); i++){
    //         bytes32 artistId = listedIdToArtistIds[_listedLicenseId].at(i);
    //         address accountAddress = listedIdToRevenues[_listedLicenseId][artistId].artistAddress;
    //         addressToBalanceOfUser[accountAddress] += msg.value - 2 * fee;
    //     }
    //     // payable(company).transfer(fee);
    //     // payable(nitrilityPool).transfer(msg.value - fee);
    //     tokenIds.increment();
    //     uint256 newTokenId = tokenIds.current();
    //     _mint(msg.sender, newTokenId);
    //     _setTokenURI(newTokenId, _newTokenURI);
    //     createMarketSale(msg.sender, _listedLicenseId, newTokenId, price, _newTokenURI);
    //     approve(marketOwner, newTokenId);
    // }

    function fetchPriceForListedLicenses(
        uint256[] memory _ids, 
        bytes memory _discountCode
    ) public view returns(uint256, bool) {
        uint256 totalPrice = 0;
        bool bApplied = false;
        for(uint256 i = 0; i < _ids.length; i++){
            uint256 count = listedIdToDiscountCodeCount[_ids[i]];
            for(uint256 j = 0; j < count; j++){
                DiscountCode memory discount = listedIdToDiscountCodes[_ids[i]][j];
                if(keccak256(bytes(discount.name)) == keccak256(bytes(_discountCode))){
                    totalPrice += idToListedLicense[_ids[i]].price.mul(discount.percentage).div(100);
                    bApplied = true;
                    break;
                }
            }
            if(!bApplied){
                totalPrice += idToListedLicense[_ids[i]].price;
            }
        }
        return (totalPrice, bApplied);
    }

    /* Mints the several token and transfers to the recipient */
    function createTokens(
        uint256[] memory _ids,
        bytes[] memory _newTokenURIs,
        bytes memory _discountCode,
        address _buyerAddress
    ) public payable {
        uint256 totalPrice;
        bool bApplied;
        (totalPrice, bApplied) = fetchPriceForListedLicenses(_ids, _discountCode);
        require(msg.value == totalPrice, "Purchasing License: Not enough ETH");

        uint256 fee = msg.value.mul(25).div(1000);
        nitriltiyRevenue += fee;

        for(uint256 i = 0; i < _ids.length; i++) {
            uint256 id = _ids[i];
            uint256 price = 0;
            tokenIds.increment();
            uint256 newTokenId = tokenIds.current();
            _mint(_buyerAddress, newTokenId);
            _setTokenURI(newTokenId, string(abi.encodePacked(_newTokenURIs[i])));
            uint256 count = listedIdToDiscountCodeCount[id];
            for(uint256 j = 0; j < count; j++){
                DiscountCode memory discount = listedIdToDiscountCodes[id][j];
                if(keccak256(bytes(discount.name)) == keccak256(bytes(_discountCode))){
                    totalPrice += idToListedLicense[id].price.mul(discount.percentage).div(100);
                    price = idToListedLicense[id].price.mul(discount.percentage).div(100);
                    bApplied = true;
                    break;
                }
            }
            if(!bApplied){
                totalPrice += idToListedLicense[id].price;
                price = idToListedLicense[id].price;
            }
            addressToBalanceOfUser[idToListedLicense[id].seller] += price - 2 * fee;
            createMarketSale(_buyerAddress, id, newTokenId, price, _newTokenURIs[i]);
            approve(marketOwner, newTokenId);
        }
    }

    /* Mints a token and transfers to the recipient */
    function reCreateBurnedToken(
        address _ownerAddress,
        uint256 _listedLicenseId,
        uint256 _price,
        bytes memory _newTokenURI
    ) public payable {
        tokenIds.increment();
        uint256 newTokenId = tokenIds.current();
        _mint(_ownerAddress, newTokenId);
        _setTokenURI(newTokenId, string(abi.encodePacked(_newTokenURI)));
        createMarketSale(_ownerAddress, _listedLicenseId, newTokenId, _price, _newTokenURI);
        approve(marketOwner, newTokenId);
    }
    /* Creates the sale of a marketplace item */
    /* Transfers ownership of the item, as well as funds between parties */
    function createMarketSale(
        address ownerAddress,
        uint256 _listedLicenseId,
        uint256 _tokenId,
        uint256 _price,
        bytes memory _newTokenURI
    ) private {
        address payable seller = idToListedLicense[_listedLicenseId].seller;
        idToSoldLicense[_tokenId] = SoldLicense(
            _tokenId,
            _newTokenURI,
            seller,
            payable(ownerAddress),
            _price
        );
        soldLicenseIds.increment();
        emit SoldLicenseCreated(_tokenId, _newTokenURI, seller, msg.sender, _price);
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

    /* Returns only items a user has listed */
    function fetchListedLicenses(address _address) public view returns (ListedLicense[] memory) {
        uint256 totalListedLicenseCount = listedLicenseIds.current();
        uint256 listedLicenseCount = 0;
        uint256 currentIndex = 0;

        for (uint256 i = 0; i < totalListedLicenseCount; i++) {
            if (idToListedLicense[i + 1].seller == payable(_address)) {
                listedLicenseCount += 1;
            }
        }

        ListedLicense[] memory items = new ListedLicense[](listedLicenseCount);
        for (uint256 i = 0; i < totalListedLicenseCount; i++) {
            if (idToListedLicense[i + 1].seller == payable(_address)) {
                uint256 currentId = i + 1;
                ListedLicense storage currentItem = idToListedLicense[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }

    /* Transfer the nft from one wallet to the another wallet */
    function TransferNFT(address to, uint256 _tokenId) external payable {
        _transfer(msg.sender, to, _tokenId);
        idToSoldLicense[_tokenId].owner = payable(to);
        // emit NFTtransfer(_tokenId, msg.sender, to);
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
    }

    /* Burns the expired NFT/ListedLicense */
    function burnListedNFT(uint256 _listedLicenseId) public {
        require(
            (msg.sender == idToListedLicense[_listedLicenseId].seller || msg.sender == marketOwner),
            "ERC721Burnable: caller is not owner nor approved"
        );
        listedLicenseSet.remove(_listedLicenseId);
        delete idToListedLicense[_listedLicenseId];
    }

    // make the offer
    function makeOffer(
        uint256 _listedLicenseId,
        uint256 _offerPrice,
        uint256 _offerDuration,
        uint256 _offerTime
    ) external payable {
        require(_offerPrice == msg.value, 'offer price should be same with your funds');
        // make the license ids for buyer
        uint256 offerCount = offerIdsForBuyer[msg.sender].length();
        bool bFound = false;
        for(uint256 i = 0; i < offerCount; i++){
            uint256 offerId = offerIdsForBuyer[msg.sender].at(i);
            if(idToOffer[offerId].listedLicenseId == _listedLicenseId && idToOffer[offerId].status == 0){
                bFound = true;
            }
        }

        require(!bFound, 'already bid on this license');

        offerIds.increment();
        uint256 currentOfferId = offerIds.current();
        address _seller = idToListedLicense[_listedLicenseId].seller;
        offerSet.add(currentOfferId);
        // make the offers
        idToOffer[currentOfferId] = Offer(
            _seller,
            msg.sender,
            currentOfferId,
            0, //pending when bid on the license
            _listedLicenseId,
            idToListedLicense[_listedLicenseId].tokenURI,
            _offerPrice,
            _offerDuration,
            _offerTime
        );
        //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        emit OfferCreated(_seller, msg.sender, currentOfferId, _listedLicenseId, 0);
        // increase the bid count
        idToListedLicense[_listedLicenseId].bidCount+=1;

        // make the offer ids for license
        offerIdsForLicense[_listedLicenseId].add(currentOfferId);
        //  make the offer ids for buyer
        offerIdsForBuyer[msg.sender].add(currentOfferId);
    }

    // fetch the offers by seller address
    function fetchAllOffers() public view returns (Offer[] memory) {
        uint256 itemCount = offerSet.length();
        uint256 currentIndex = 0;
        Offer[] memory offers = new Offer[](itemCount);
        for(uint256 i = 0; i < itemCount; i++){
            Offer storage currentItem = idToOffer[offerSet.at(i)];
            offers[currentIndex] = currentItem;
            currentIndex += 1;
        }
        return offers;
    }

    // fetch the offers by seller address
    function fetchOffersOfSeller(uint256 _licenseId) public view returns (Offer[] memory) {
        uint256 itemCount = offerIdsForLicense[_licenseId].length();
        uint256 currentIndex = 0;
        Offer[] memory offers = new Offer[](itemCount);
        for(uint256 i = 0; i < itemCount; i++){
            if(idToOffer[offerIdsForLicense[_licenseId].at(i)].status == 0){
                Offer storage currentItem = idToOffer[offerIdsForLicense[_licenseId].at(i)];
                offers[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return offers;
    }

    function fetchOffersOfBuyer(address _buyer) public view returns (Offer[] memory) {
        uint256 bidCount = offerIdsForBuyer[_buyer].length();
        uint256 currentIndex = 0;
        Offer[] memory offers = new Offer[](bidCount);
        for(uint256 i = 0; i < bidCount; i++){  
            if(idToOffer[offerIdsForBuyer[_buyer].at(i)].status == 0){
                Offer storage currentItem = idToOffer[offerIdsForBuyer[_buyer].at(i)];
                offers[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return offers;
    }

    function acceptOffer(uint256 _offerId, bytes memory _newTokenURI) external {
        Offer storage offer = idToOffer[_offerId];
        require(msg.sender == offer._seller, 'only owner can accept the offer');
        
        idToListedLicense[offer.listedLicenseId].bidCount -= 1;
        idToOffer[_offerId].status = 1;

        uint256 fee = offer.offerPrice.mul(25).div(1000);
        nitriltiyRevenue += fee;
        
        for(uint256 i = 0; i < listedIdToArtistIds[offer.listedLicenseId].length(); i++){
            bytes32 artistId = listedIdToArtistIds[offer.listedLicenseId].at(i);
            address accountAddress = listedIdToRevenues[offer.listedLicenseId][artistId].artistAddress;
            addressToBalanceOfUser[accountAddress] += offer.offerPrice - 2 * fee;
        }
        

        tokenIds.increment();
        uint256 newTokenId = tokenIds.current();
        _mint(offer._buyer, newTokenId);
        _setTokenURI(newTokenId, string(abi.encodePacked(_newTokenURI)));
        createMarketSale(offer._buyer, offer.listedLicenseId, newTokenId, offer.offerPrice, _newTokenURI);

        //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        emit OfferCreated(offer._seller, offer._buyer, _offerId, offer.listedLicenseId, 1);
    }

    function denyOffer(uint256 _offerId) external {
        Offer storage offer = idToOffer[_offerId];
        require(msg.sender == offer._seller, 'only owner can call');
        idToListedLicense[offer.listedLicenseId].bidCount -= 1;
        idToOffer[_offerId].status = 2;
        
        //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        emit OfferCreated(offer._seller, offer._buyer, _offerId, offer.listedLicenseId, 2);
        payable(address(idToOffer[_offerId]._buyer)).transfer(idToOffer[_offerId].offerPrice);
    }

    function removeOffer(uint256 _offerId) external {
        Offer storage offer = idToOffer[_offerId];
        require(msg.sender == offer._buyer, 'only bidder can call');
        for(uint256 j = 0; j < listedLicenseSet.length(); j++){
            if(idToListedLicense[j].listedLicenseId == offer.listedLicenseId){
                idToListedLicense[j].bidCount -= 1;
            }
        }
        idToOffer[_offerId].status = 3;
        //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        emit OfferCreated(offer._seller, offer._buyer, _offerId, offer.listedLicenseId, 3);
        payable(address(msg.sender)).transfer(idToOffer[_offerId].offerPrice - gasFee);
    }

    // giving gifts
    function GivingGift(
        uint256 _listedLicenseId,
        address _receiver,
        bytes memory _newTokenURI,
        uint256 _amount
    ) external{
        require(
            (msg.sender == idToListedLicense[_listedLicenseId].seller),
            "caller is not owner"
        );
        require(_amount > 0, 'should be greater than 0');
        for(uint256 i = 0; i < _amount; i++){
            tokenIds.increment();
            uint256 newTokenId = tokenIds.current();
            _mint(_receiver, newTokenId);
            _setTokenURI(newTokenId, string(abi.encodePacked(_newTokenURI)));
            createMarketSale(_receiver, _listedLicenseId, newTokenId, 0, _newTokenURI);
        }
    }

    function checkOwner(address _owner, uint256 _listedLicenseId) public view returns (bool) {
        if(_owner == idToListedLicense[_listedLicenseId].seller){
            return true;
        }else{
            return false;
        }
    }

    function withdrawMarketRevenue() external onlyOwner {
        require(nitriltiyRevenue > 0, "Market Revenue: there is no funds for marketplace revenue");
        payable(msg.sender).transfer(nitriltiyRevenue);
    }

    function fetchBalanceOfArtist() public view returns (uint256){
        return addressToBalanceOfUser[msg.sender];
    }

    function withdrawFund() external {
        require(addressToBalanceOfUser[msg.sender] > 0, "Withdraw Funds: Balance should be larger than 0");
        payable(msg.sender).transfer(addressToBalanceOfUser[msg.sender]);
        addressToBalanceOfUser[msg.sender] = 0;
    }
}
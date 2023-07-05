// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./NitrilityNft.sol";
import "./NitrilityFactory.sol";

contract NitrilityMarketplace is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    address payable marketOwner;
    address public nitrilityFactory;

    EnumerableSet.UintSet listedLicenseSet;
    EnumerableSet.UintSet offerSet;
    EnumerableSet.AddressSet addressSet;

    Counters.Counter private listedLicenseIds;
    Counters.Counter private offerIds;

    uint256 gasFee = 1000000000000000;
    uint256 marketplaceFee = 25; // 2.5 %n

    uint256 public nitriltiyRevenue;
    uint256 public socialRevenue;
    // artist id => balance
    mapping(string => uint256) private idToBalanceOfUser;

    mapping(uint256 => ListedLicense) private idToListedLicense;
    // offer
    mapping(uint256 => Offer) private idToOffer;
    // license id => offer id
    mapping(uint256 => EnumerableSet.UintSet) private offerIdsForLicense;
    mapping(address => EnumerableSet.UintSet) private offerIdsForBuyer;

    // revenue splitter
    mapping(string => EnumerableSet.AddressSet) private artistIdToAddresses; //artist id

    // license id => revenue percentages
    mapping(uint256 => mapping(bytes32 => Revenue)) private listedIdToRevenues;
    mapping(uint256 => EnumerableSet.Bytes32Set) private listedIdToArtistIds;
    // license id => discount codes
    mapping(uint256 => mapping(uint256 => DiscountCode)) private listedIdToDiscountCodes;
    mapping(uint256 => uint256) private listedIdToDiscountCodeCount;

    struct DiscountCode {
        string name;
        uint256 percentage;
    }

    struct Revenue {
        address artistAddress;
        string artistId;
        string artistName;
        uint256 percentage;
        bool isAdmin;
        uint256 status; // 0 - pending, 1 - approved, 2 - rejected
    }

    struct ListedLicense {
        uint256 listingFormat; // 0 - only bid, 1 - only price, 2 - bid and price
        uint256 listedLicenseId;
        uint256 price;
        uint256 recommendedPrice;
        string tokenURI;
        address payable seller;
        string artistId;
        uint256 listedTime;
        uint256 bidCount;
    }

    event ListedLicenseCreated(
        uint256 listingFormat,
        uint256 listedLicenseId,
        uint256 price,
        string tokenURI,
        address seller,
        string artistId,
        uint256 listedTime
    );

    event ListedLicenseRemoved(
        uint256 listedLicenseId,
        address seller
    );

    event ListedLicenseChanged(
        uint256 listedLicenseId,
        address seller
    );

    // Aution
    struct Offer {
        address _seller;
        address _buyer;
        uint256 offerId;
        uint256 status; //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        uint256 listedLicenseId;
        string tokenURI;
        uint256 offerPrice;
        uint256 offerDuration;
        uint256 offerTime;
    }

    event OfferCreated (
        address _seller,
        address _buyer,
        uint256 offerId,
        uint256 offerPrice,
        uint256 listedLicenseId,
        uint256 status
    );

    constructor() {
        marketOwner = payable(msg.sender);
    }

    receive() external payable {
    }

    function setNitirlityFactory(address _nitrilityFactory) external onlyOwner {
        nitrilityFactory = _nitrilityFactory;
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

    function setArtistAddress(string memory _artistId, address _artistAddress) external onlyOwner {
        if(!artistIdToAddresses[_artistId].contains(_artistAddress)){
            artistIdToAddresses[_artistId].add(_artistAddress);
        }
        NitrilityFactory nitrilityFactoryInstance = NitrilityFactory(nitrilityFactory);
        nitrilityFactoryInstance.createCollection(_artistId);
        for(uint256 i = 0; i < listedLicenseSet.length(); i++){
            listedIdToRevenues[listedLicenseSet.at(i)][stringToBytes32(_artistId)].artistAddress = _artistAddress;
        }
    }

    function fetchArtistAddressForArtistId(string memory artistId) public view returns(address[] memory){
        uint256 count = artistIdToAddresses[artistId].length();
        address[] memory addresses = new address[](count);
        for(uint256 i = 0; i < count; i++){
            addresses[i] = artistIdToAddresses[artistId].at(i);
        }
        return addresses;
    }

    /* Returns listedLicenses count */
    function getListedLicensesCount() public view returns (uint256) {
        return listedLicenseSet.length();
    }

    /* Creates a listedLicense */
    function listLicense(
        uint256 _listingFormat,
        uint256 _price,
        uint256 _recommendedPrice,
        string memory _tokenURI, 
        string memory _listedArtistId,
        string[] memory _artistIds,
        string[] memory _artistNames,
        uint256[] memory _percentages,
        bool[] memory _admins,
        uint256[] memory _statuses,
        string[] memory _discountCodeNames,
        uint256[] memory _discountCodePercentages
    ) public payable {
        require(artistIdToAddresses[_listedArtistId].contains(msg.sender), "RevenueSplitter: Only Artist who own this license can list");

        uint256 totalPercentage;
        for(uint256 i = 0; i < _artistIds.length; i++){
            totalPercentage = totalPercentage + _percentages[i];
        }
        require(_artistIds.length == _percentages.length && _percentages.length == _admins.length && _admins.length == _statuses.length && _artistNames.length == _statuses.length, "RevenueSplitter: artist ids, percentages mismatch");
        require(_artistIds.length > 0, "RevenueSplitter: no artists provided");
        require(totalPercentage == 100, "RevenueSplitter: total revenue percentage should be 100%");

        require(_discountCodeNames.length == _discountCodePercentages.length, "DiscountCode: discount name, percentages mismatch");

        listedLicenseIds.increment();
        uint256 _newListedLicenseId = listedLicenseIds.current();

        if(_discountCodeNames.length > 0){
            for(uint256 p = 0; p < _discountCodeNames.length; p++){
                listedIdToDiscountCodes[_newListedLicenseId][p].name = _discountCodeNames[p];
                listedIdToDiscountCodes[_newListedLicenseId][p].percentage = _discountCodePercentages[p];
            }
            listedIdToDiscountCodeCount[_newListedLicenseId] = _discountCodeNames.length;
        }
        
        for(uint256 j = 0; j < _artistIds.length; j++){
            bytes32 _artistId = stringToBytes32(_artistIds[j]);
            listedIdToRevenues[_newListedLicenseId][_artistId].artistAddress = msg.sender;
            listedIdToRevenues[_newListedLicenseId][_artistId].artistName = _artistNames[j];
            listedIdToRevenues[_newListedLicenseId][_artistId].artistId = _artistIds[j];
            listedIdToRevenues[_newListedLicenseId][_artistId].percentage = _percentages[j];
            listedIdToRevenues[_newListedLicenseId][_artistId].isAdmin = _admins[j];
            listedIdToRevenues[_newListedLicenseId][_artistId].status = _statuses[j];
            listedIdToArtistIds[_newListedLicenseId].add(_artistId);
        }

        listedLicenseSet.add(_newListedLicenseId);
        idToListedLicense[_newListedLicenseId] = ListedLicense(
            _listingFormat,
            _newListedLicenseId,
            _price,
            _recommendedPrice,
            _tokenURI,
            payable(msg.sender),
            _listedArtistId,
            block.timestamp,
            0
        );
        emit ListedLicenseCreated(_listingFormat, _newListedLicenseId, _price, _tokenURI, msg.sender, _listedArtistId, block.timestamp);
    }

    function fetchListedLicenseForListedId(uint256 listedId) public view returns(ListedLicense memory){
        ListedLicense memory license = idToListedLicense[listedId];
        return license;
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

    // function updateDiscountCodeForListedId(
    //     uint256 listedId, 
    //     string[] memory _discountCodeNames,
    //     uint256[] memory _discountCodePercentages
    // ) external {
    //     require(_discountCodeNames.length == _discountCodePercentages.length, "Updating DiscountCode: discount name, percentages mismatch");
    //     require(_discountCodeNames.length > 0, "Updating DiscountCode: no discountcode provided");
    //     require(listedLicenseSet.contains(listedId), "Updating DiscountCode: we dont have this license");

    //     for(uint256 p = 0; p < _discountCodeNames.length; p++){
    //         listedIdToDiscountCodes[listedId][p].name = _discountCodeNames[p];
    //         listedIdToDiscountCodes[listedId][p].percentage = _discountCodePercentages[p];
    //     }
    //     listedIdToDiscountCodeCount[listedId] = _discountCodeNames.length;
    // }

    // function removeDiscountCodeForListedId(
    //     uint256 listedId
    // ) external {
    //     require(listedLicenseSet.contains(listedId), "Updating DiscountCode: we dont have this license");
    //     for(uint256 i = 0; i < listedIdToDiscountCodeCount[listedId]; i++){
    //         delete listedIdToDiscountCodes[listedId][i];
    //     }
    // }

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
        uint256 _listedId, 
        string[] memory _artistIds,
        uint256[] memory _percentages,
        bool[] memory _admins,
        uint256[] memory _statuses
    ) internal {
        bool bExisting = false;
        for(uint256 i = 0; i < _artistIds.length; i++){
            if(artistIdToAddresses[_artistIds[i]].contains(msg.sender)) bExisting = true;
        }
        require(bExisting, "RevenueSplitter: Only Artist who own this license can update");

        require(_artistIds.length == _percentages.length && _percentages.length == _admins.length && _admins.length == _statuses.length, "RevenueSplitter: artist ids, percentages mismatch");
        require(_artistIds.length > 0, "RevenueSplitter: no artists provided");

        for(uint256 j = 0; j < _artistIds.length; j++){
            bytes32 _artistId = stringToBytes32(_artistIds[j]);
            listedIdToRevenues[_listedId][_artistId].artistAddress = msg.sender;
            listedIdToRevenues[_listedId][_artistId].percentage = _percentages[j];
            listedIdToRevenues[_listedId][_artistId].isAdmin = _admins[j];
            listedIdToRevenues[_listedId][_artistId].status = _statuses[j];
            listedIdToArtistIds[_listedId].add(_artistId);
        }
    }

    function updateLicenseSetting(
        uint256 _listedId,
        uint256 _listingFormat,
        uint256 _price,
        uint256 _recommendedPrice,
        string[] memory _artistIds,
        uint256[] memory _percentages,
        bool[] memory _admins,
        uint256[] memory _statuses,
        string[] memory _discountCodeNames,
        uint256[] memory _discountCodePercentages
    ) external {
        require(_artistIds.length == _percentages.length && _percentages.length == _admins.length && _admins.length == _statuses.length, "RevenueSplitter: artist ids, percentages mismatch");
        require(_artistIds.length > 0, "RevenueSplitter: no artists provided");

        require(_discountCodeNames.length == _discountCodePercentages.length, "Discount Code: artist ids, percentages mismatch");

        if(_listingFormat != 0){
            require(_price > 0, "License Price: price should be not zero");
            require(_recommendedPrice > 0, "License Price: recommended price should be not zero");
            require(_price < _recommendedPrice, "License Price: recommended price should be greater than marketplace price");
        }


        updateRevenueForListedId(_listedId, _artistIds, _percentages, _admins, _statuses);

        if(_discountCodeNames.length > 0){
            for(uint256 p = 0; p < _discountCodeNames.length; p++){
                listedIdToDiscountCodes[_listedId][p].name = _discountCodeNames[p];
                listedIdToDiscountCodes[_listedId][p].percentage = _discountCodePercentages[p];
            }
            listedIdToDiscountCodeCount[_listedId] = _discountCodeNames.length;
        }

        if(_price != idToListedLicense[_listedId].price){
            idToListedLicense[_listedId].price = _price;
        }

        if(_recommendedPrice != idToListedLicense[_listedId].recommendedPrice){
            idToListedLicense[_listedId].recommendedPrice = _recommendedPrice;
        }

        if(_listingFormat != idToListedLicense[_listedId].listingFormat){
            idToListedLicense[_listedId].listingFormat = _listingFormat;
        }

        emit ListedLicenseChanged(_listedId, idToListedLicense[_listedId].seller);
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

    // Returns only out going licenses
    function fetchListedLicenses(string memory _artistId) public view returns (ListedLicense[] memory) {
        uint256 itemCount = listedLicenseSet.length();
        uint256 currentIndex = 0;

        ListedLicense[] memory items = new ListedLicense[](itemCount);

        for (uint256 index = 0; index < itemCount; index++) {
            uint256 currentId = listedLicenseSet.at(index);
            if(artistIdToAddresses[_artistId].contains(idToListedLicense[currentId].seller)){
                ListedLicense storage currentItem = idToListedLicense[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }
        return items;
    }
    
    // Returns only out going licenses
    function fetchOutGoingLicenses(string memory _artistId) public view returns (ListedLicense[] memory) {
        uint256 itemCount = listedLicenseSet.length();
        uint256 currentIndex = 0;

        ListedLicense[] memory items = new ListedLicense[](itemCount);

        for (uint256 index = 0; index < itemCount; index++) {
            uint256 currentId = listedLicenseSet.at(index);
            uint256 artistCounts = listedIdToArtistIds[currentId].length();

            if(artistCounts > 1){
                bool isApproved = true;
                for(uint256 j = 0; j < artistCounts; j++){
                    if(listedIdToRevenues[currentId][listedIdToArtistIds[currentId].at(j)].status != 1){
                        isApproved = false;
                        break;
                    }
                }
                
                if(artistIdToAddresses[_artistId].contains(idToListedLicense[currentId].seller) && !isApproved){
                    ListedLicense storage currentItem = idToListedLicense[currentId];
                    items[currentIndex] = currentItem;
                    currentIndex += 1;
                }
            }
            
        }
        return items;
    }

    // Returns only in coming licenses
    function fetchInComingLicenses(string memory _artistId)  public view returns (ListedLicense[] memory) {
        uint256 itemCount = listedLicenseSet.length();
        uint256 currentIndex = 0;

        ListedLicense[] memory items = new ListedLicense[](itemCount);

        for (uint256 index = 0; index < itemCount; index++) {
            uint256 currentId = listedLicenseSet.at(index);
            uint256 artistCounts = listedIdToArtistIds[currentId].length();

            if(artistCounts > 1){
                if(artistIdToAddresses[_artistId].contains(idToListedLicense[currentId].seller) && listedIdToRevenues[currentId][stringToBytes32(_artistId)].status != 1){
                    ListedLicense storage currentItem = idToListedLicense[currentId];
                    items[currentIndex] = currentItem;
                    currentIndex += 1;
                }
            }
        }
        return items;
    }
    
    /* Burns the expired NFT/ListedLicense */
    function burnListedNFT(uint256 _listedLicenseId) public {
        require(
            (msg.sender == idToListedLicense[_listedLicenseId].seller || msg.sender == marketOwner),
            "ERC721Burnable: caller is not owner nor approved"
        );
        emit ListedLicenseRemoved(_listedLicenseId, idToListedLicense[_listedLicenseId].seller);
        listedLicenseSet.remove(_listedLicenseId);
        delete idToListedLicense[_listedLicenseId];
    }

    function fetchTotalDiscountedPrice(
        uint256[] memory _artistIds, 
        string memory _discountCode
    ) public view returns(uint256, bool) {
        uint256 totalPrice = 0;
        bool bApplied = false;
        for(uint256 i = 0; i < _artistIds.length; i++){
            uint256 _artistId = _artistIds[i];
            uint256 count = listedIdToDiscountCodeCount[_artistId];
            bool bFound = false;
            for(uint256 j = 0; j < count; j++){
                DiscountCode memory discount = listedIdToDiscountCodes[_artistId][j];
                if(keccak256(bytes(discount.name)) == keccak256(bytes(_discountCode))){
                    require(idToListedLicense[_artistId].listingFormat != 0, "There is license for only Bid");
                    totalPrice += idToListedLicense[_artistId].price.mul(discount.percentage).div(100);
                    bApplied = true;
                    bFound = true;
                }
            }
            if(!bFound){
                totalPrice += idToListedLicense[_artistId].price;
            }
        }
        return (totalPrice, bApplied);
    }

    function fetchDiscountedPrice(
        uint256 _listedLicenseId, 
        string memory _discountCode
    ) public view returns(uint256) {
        uint256 price = 0;
        bool bFound = false;
        uint256 count = listedIdToDiscountCodeCount[_listedLicenseId];
        for(uint256 j = 0; j < count; j++){
            DiscountCode memory discount = listedIdToDiscountCodes[_listedLicenseId][j];
            if(keccak256(bytes(discount.name)) == keccak256(bytes(_discountCode))){
                price += idToListedLicense[_listedLicenseId].price.mul(discount.percentage).div(100);
                bFound = true;
                break;
            }
        }
        if(!bFound){
            price = idToListedLicense[_listedLicenseId].price;
        }
        return price;
    }

    function fetchPriceForListedLicense(uint256 _listedLicenseId) public view returns(uint256, uint256){
        return (idToListedLicense[_listedLicenseId].price, idToListedLicense[_listedLicenseId].recommendedPrice);
    }

    function fetchSellerAddressForListedLicense(uint256 _listedLicenseId) public view returns(address, string memory) {
        return (idToListedLicense[_listedLicenseId].seller, idToListedLicense[_listedLicenseId].artistId);
    }

    function checkOwner(address _owner, uint256 _listedLicenseId) public view returns (bool) {
        if(artistIdToAddresses[idToListedLicense[_listedLicenseId].artistId].contains(_owner)){
            return true;
        }else{
            return false;
        }
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

    // make the offer
    function makeOffer(
        uint256 _listedLicenseId,
        uint256 _offerPrice,
        uint256 _offerDuration,
        uint256 _offerTime
    ) external payable {
        require(idToListedLicense[_listedLicenseId].listingFormat != 1, "This license is for only Price");
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
        emit OfferCreated(_seller, msg.sender, currentOfferId, _offerPrice,_listedLicenseId, 0);
        // increase the bid count
        idToListedLicense[_listedLicenseId].bidCount+=1;

        // make the offer ids for license
        offerIdsForLicense[_listedLicenseId].add(currentOfferId);
        //  make the offer ids for buyer
        offerIdsForBuyer[msg.sender].add(currentOfferId);
    }

    function acceptOffer(uint256 _offerId, string memory _newTokenURI) external {
        Offer storage offer = idToOffer[_offerId];
        require(artistIdToAddresses[idToListedLicense[offer.listedLicenseId].artistId].contains(msg.sender), "only owner can accept the offer");
        
        idToListedLicense[offer.listedLicenseId].bidCount -= 1;
        idToOffer[_offerId].status = 1;

        uint256 fee = offer.offerPrice.mul(25).div(1000);
        nitriltiyRevenue += fee;
        
        for(uint256 i = 0; i < listedIdToArtistIds[offer.listedLicenseId].length(); i++){
            bytes32 artistId = listedIdToArtistIds[offer.listedLicenseId].at(i);
            // address accountAddress = listedIdToRevenues[offer.listedLicenseId][artistId].artistAddress;
            idToBalanceOfUser[bytes32ToString(artistId)] += offer.offerPrice - 2 * fee;
        }
        NitrilityFactory nitrilityFactoryInstance = NitrilityFactory(nitrilityFactory);
        address collection = nitrilityFactoryInstance.fetchCollectionAddressOfArtist(idToListedLicense[offer.listedLicenseId].artistId);
        NitrilityNFT nftContract = NitrilityNFT(collection);
        nftContract.createTokenForOffer(
            offer.listedLicenseId,
            _newTokenURI,
            offer._buyer,
            offer.offerPrice
        );
        //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        emit OfferCreated(offer._seller, offer._buyer, _offerId, offer.offerPrice, offer.listedLicenseId, 1);
    }

    function denyOffer(uint256 _offerId) external {
        Offer storage offer = idToOffer[_offerId];
        require(artistIdToAddresses[idToListedLicense[offer.listedLicenseId].artistId].contains(msg.sender), "only owner can deny the offer");
        idToListedLicense[offer.listedLicenseId].bidCount -= 1;
        idToOffer[_offerId].status = 2;
        
        //0 - pending, 1 - accpeted, 2 : deny, 3 - deleted
        emit OfferCreated(offer._seller, offer._buyer, _offerId, offer.offerPrice, offer.listedLicenseId, 2);
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
        emit OfferCreated(offer._seller, offer._buyer, _offerId, offer.offerPrice, offer.listedLicenseId, 3);
        payable(address(msg.sender)).transfer(idToOffer[_offerId].offerPrice - gasFee);
    }

    function fetchBestOffer(uint256 _licenseId) public view returns (Offer memory){
        uint256 itemCount = offerIdsForLicense[_licenseId].length();
        uint256 currentIndex = 0;
        Offer memory bestOffer;
        uint256 maxPrice = 0;
        for(uint256 i = 0; i < itemCount; i++){
            Offer memory curOffer = idToOffer[offerIdsForLicense[_licenseId].at(i)];
            if(curOffer.status == 0){
                if(maxPrice < curOffer.offerPrice){
                    bestOffer = curOffer;
                    maxPrice = curOffer.offerPrice;
                }
                currentIndex += 1;
            }
        }
        return bestOffer;
    }

    function fetchTokenUri(uint256 _listedLicenseId) public view returns (string memory){
        return idToListedLicense[_listedLicenseId].tokenURI;
    }
    
    function fetchBalanceOfArtist(string memory _artistId) public view returns (uint256){
        // require(artistIdToAddresses[_artistId].contains(msg.sender) || msg.sender == marketOwner, "Only Artist can call");
        return idToBalanceOfUser[_artistId];
    }

    function addBalanceForArtist(uint256 _listedLicenseId, uint256 _price) external { //consider
        uint256 fee = _price.mul(marketplaceFee).div(1000);
        nitriltiyRevenue += fee;
        idToBalanceOfUser[idToListedLicense[_listedLicenseId].artistId] += _price - 2 * fee;
    }

    function withdrawMarketRevenue() external onlyOwner {
        require(nitriltiyRevenue > 0, "Market Revenue: there is no funds for marketplace revenue");
        payable(msg.sender).transfer(nitriltiyRevenue);
    }

    function withdrawFund(string memory _artistId) external {
        require(artistIdToAddresses[_artistId].contains(msg.sender), "Withdraw Funds: Only Artist can withdraw");
        require(idToBalanceOfUser[_artistId] > 0, "Withdraw Funds: Balance should be larger than 0");
        payable(msg.sender).transfer(idToBalanceOfUser[_artistId]);
        idToBalanceOfUser[_artistId] = 0;
    }
}
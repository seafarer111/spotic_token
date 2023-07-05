// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract SocialMedia is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.UintSet _tagSet;
    EnumerableSet.UintSet _reportSet;

    Counters.Counter private _tagId;
    Counters.Counter private _reportId;

    string public name="SocialMedia Database";
    string public symbol="SocialMedia";

    address private company;
    
    mapping(uint256 => ReportItem) private idToReportItem;
    mapping(uint256 => TagItem) private idToTagItem;
    

    struct BurnedLicenseInfo {
        string ownerAddress;
        string sellerAddress;
        string licenseName;
        string artistName;
        string price;
    }

    struct ReportItem {
        string claimId;
        string contentId;
        string userId;
        string licenseName;
        string creatorName;
        string decisionOfRuling;
        BurnedLicenseInfo burnedLicense;
        string socialMediaType;
        uint256 active; // 0 - default, if social media reported the inappropriate, should be 1, again if they reported the appeal, should be 2
        uint256 storedTime;
    }

    event ReportItemCreated (
        string claimId,
        string contentId,
        string userId,
        string licenseName,
        string creatorName,
        string decisionOfRuling,
        BurnedLicenseInfo burnedLicense,
        string socialMediaType,
        uint256 active,
        uint256 storedTime
    );

    struct TagItem {
        string contentId;
        string licenseName;
        string socialMediaType;
        bool isSafe;
    }

    event TagItemCreated (
        string contentId,
        string licenseName,
        string socialMediaType,
        bool isSafe
    );

    constructor() {
    }
    
    receive() external payable {
    }

    modifier onlyDev() {
      require(msg.sender == owner() || msg.sender == company , "Error: Require developer or Owner");
      _;
    }

    function setCompanyAddress(address _company) external onlyOwner{
        company = _company;
    }

    // socialmedia database
    function createSocialMediaDatabase(
        string memory _claimId, 
        string memory _contentId, 
        string memory _userId, 
        string memory _licenseName, 
        string memory _creatorName, 
        string memory _socialMediaType,
        string memory _decisionOfRuling,
        BurnedLicenseInfo memory _burnedLicense,
        uint256 _active
    ) external payable nonReentrant returns (
        ReportItem memory
    )   {
        _reportId.increment();
        _reportSet.add(_reportId.current());

        uint256 _itemId = _reportId.current();
        idToReportItem[_itemId] = ReportItem(
            _claimId,
            _contentId,
            _userId,
            _licenseName,
            _creatorName,
            _decisionOfRuling,
            _burnedLicense,
            _socialMediaType,
            _active,
            block.timestamp
        );

        emit ReportItemCreated(
            _claimId,
            _contentId,
            _userId,
            _licenseName,
            _creatorName,
            _decisionOfRuling,
            _burnedLicense,
            _socialMediaType,
            _active,
            block.timestamp
        );

        return idToReportItem[_itemId];
    }

    function fetchReportItemsByUserId(string memory _userId, string  memory _socialMediaType) external view returns (
        ReportItem[] memory
    ){
        uint256 reportCount = _reportId.current();
        uint256 currentIndex = 0;

        ReportItem[] memory reportItems = new ReportItem[](reportCount);

        for (uint256 j = 0; j < reportCount; j++) {
            uint256 currentReportId = j + 1;
            ReportItem memory currentReportItem = idToReportItem[currentReportId];
            if(
                keccak256(bytes(currentReportItem.userId)) == keccak256(bytes(_userId)) &&
                keccak256(bytes(currentReportItem.socialMediaType)) == keccak256(bytes(_socialMediaType))
            ){
                reportItems[currentIndex] = currentReportItem;
                currentIndex++;
            }
        }
        return reportItems;
    }

    function fetchReportItems() external view returns (
        ReportItem[] memory
    ){
        uint256 reportCount = _reportId.current();
        uint256 currentIndex = 0;

        ReportItem[] memory reportItems = new ReportItem[](reportCount);

        for (uint256 j = 0; j < reportCount; j++) {
            uint256 currentReportId = j + 1;
            ReportItem memory currentReportItem = idToReportItem[currentReportId];
            reportItems[currentIndex] = currentReportItem;
            currentIndex++;
        }
        return reportItems;
    }

    function checkTagItem(
        string memory _contentId, 
        string memory _socialMediaType,
        string memory _licenseName
    ) external view returns (
        bool contentExisted,
        bool licenseExisted,
        bool isSafe
    ){
        uint256 tagCount = _tagId.current();

        for (uint256 j = 0; j < tagCount; j++) {
            uint256 currentTagId = j + 1;
            TagItem memory currentTagItem = idToTagItem[currentTagId];
            if(
                keccak256(bytes(_contentId)) == keccak256(bytes(currentTagItem.contentId)) && 
                keccak256(bytes(_socialMediaType)) == keccak256(bytes(currentTagItem.socialMediaType))
            ){
                contentExisted = true;
                if(
                    keccak256(bytes(_licenseName)) == keccak256(bytes(currentTagItem.licenseName))
                ){
                    licenseExisted = true;
                    isSafe = currentTagItem.isSafe;
                }
            }
        }
        return (contentExisted, licenseExisted, isSafe);
    }

    function getReportItem(
        string memory _contentId, 
        string memory _socialMediaType
    ) external view returns (
        ReportItem memory, TagItem[] memory, bool isReported
    ){
        uint256 mediaCount = _reportId.current();
        uint256 tagCount = _tagId.current();
        uint256 currentIndex = 0;

        ReportItem memory reportItem;
        TagItem[] memory tagItems = new TagItem[](tagCount);

        for (uint256 i = 0; i < mediaCount; i++) {
            uint256 currentReportId = i + 1;
            ReportItem memory currentreportItem = idToReportItem[currentReportId];
            if(keccak256(bytes(_contentId)) == keccak256(bytes(currentreportItem.contentId)) && keccak256(bytes(_socialMediaType)) == keccak256(bytes(currentreportItem.socialMediaType))){
                reportItem = currentreportItem;
                if(currentreportItem.storedTime + 7 days > block.timestamp){
                    isReported = true;
                }
            }
        }

        for (uint256 j = 0; j < tagCount; j++) {
            uint256 currentTagId = j + 1;
            TagItem memory currentTagItem = idToTagItem[currentTagId];
            if(
                keccak256(bytes(_contentId)) == keccak256(bytes(currentTagItem.contentId)) && 
                keccak256(bytes(_socialMediaType)) == keccak256(bytes(currentTagItem.socialMediaType))
            ){
                tagItems[currentIndex] = currentTagItem;
            }
            currentIndex++;
        }

        return (reportItem, tagItems, isReported);
    }

    function createEmptyTag(
        string memory _contentId, 
        string memory _socialMediaType
    ) external {
        _tagId.increment();
        _tagSet.add(_tagId.current());
        uint256 tagCount = _tagId.current();
        
        idToTagItem[tagCount] = TagItem(
            _contentId,
            "",
            _socialMediaType,
            false
        );

        emit TagItemCreated(
            _contentId,
            "",
            _socialMediaType,
            false
        );
    }
    
    function fetchTagItems() external view returns (
        TagItem[] memory
    ){
        uint256 tagCount = _tagId.current();
        uint256 currentIndex = 0;

        TagItem[] memory tagItems = new TagItem[](tagCount);

        for (uint256 j = 0; j < tagCount; j++) {
            uint256 currentTagId = j + 1;
            TagItem memory currentTagItem = idToTagItem[currentTagId];
            tagItems[currentIndex] = currentTagItem;
            currentIndex++;
        }
        return tagItems;
    }

    function addTag(
        string memory _contentId, 
        string memory _socialMediaType, 
        string memory _licenseName, 
        bool _isSafe
    ) external {
        uint256 tagCount = _tagId.current();
        uint256 currentId = 1;

        while(currentId <= tagCount) {
            if(
                keccak256(bytes(_contentId)) == keccak256(bytes(idToTagItem[currentId].contentId)) && 
                keccak256(bytes(_socialMediaType)) == keccak256(bytes(idToTagItem[currentId].socialMediaType)) &&
                keccak256(bytes("")) == keccak256(bytes(idToTagItem[currentId].licenseName))
            ){
                idToTagItem[currentId].licenseName = _licenseName;
                idToTagItem[currentId].isSafe = _isSafe;
                break;
            }
            currentId++;
        }
    }

    function setStatusOfTag(
        string memory _contentId, 
        string memory _socialMediaType, 
        string memory _licenseName, 
        bool _isSafe
    ) external {
        uint256 tagCount = _tagId.current();

        for (uint256 i = 0; i < tagCount; i++) {
            uint256 currentId = i + 1;
            if(
                keccak256(bytes(_contentId)) == keccak256(bytes(idToTagItem[currentId].contentId)) && 
                keccak256(bytes(_socialMediaType)) == keccak256(bytes(idToTagItem[currentId].socialMediaType)) &&
                keccak256(bytes(_licenseName)) == keccak256(bytes(idToTagItem[currentId].licenseName))
            ){
                idToTagItem[currentId].isSafe = _isSafe;
            }
        }
    }

    function setStatusOfReportItem(
        string memory _contentId, 
        string memory _socialMediaType, 
        uint256 _active
    ) external {
        uint256 itemCount = _reportId.current();
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < itemCount; i++) {
            uint256 currentId = i + 1;
            if(
                keccak256(bytes(_contentId)) == keccak256(bytes(idToReportItem[currentId].contentId)) && 
                keccak256(bytes(_socialMediaType)) == keccak256(bytes(idToReportItem[currentId].socialMediaType))
            ){
                idToReportItem[currentId].active = _active;
            }
            currentIndex += 1;
        }
    }

    function setDecisionOfRulingOfReportItem(
        string memory _contentId, 
        string memory _socialMediaType, 
        string memory _decisionOfRuling
    ) external {
        uint256 itemCount = _reportId.current();
        for (uint256 i = 0; i < itemCount; i++) {
            uint256 currentId = i + 1;
            if(
                keccak256(bytes(_contentId)) == keccak256(bytes(idToReportItem[currentId].contentId)) && 
                keccak256(bytes(_socialMediaType)) == keccak256(bytes(idToReportItem[currentId].socialMediaType))
            ){
                idToReportItem[currentId].decisionOfRuling = _decisionOfRuling;
            }
        }
    }

    function setBurnedLicenseOfReportItem(
        string memory _contentId, 
        string memory _socialMediaType, 
        BurnedLicenseInfo memory _burnedLicense
    ) external {
        uint256 itemCount = _reportId.current();
        for (uint256 i = 0; i < itemCount; i++) {
            uint256 currentId = i + 1;
            if(
                keccak256(bytes(_contentId)) == keccak256(bytes(idToReportItem[currentId].contentId)) && 
                keccak256(bytes(_socialMediaType)) == keccak256(bytes(idToReportItem[currentId].socialMediaType))
            ){
                idToReportItem[currentId].burnedLicense = _burnedLicense;
            }
        }
    }

    function refundLicenses(string memory _licenseName) external onlyDev returns (
        ReportItem[] memory
    ) {
        uint256 itemCount = 0;
        ReportItem[] memory deletedReports = new ReportItem[](_reportId.current());

        for (uint256 index = 0; index < _tagSet.length();){
            uint256 _id = _tagSet.at(index);
            if(keccak256(bytes(idToTagItem[_id].licenseName)) == keccak256(bytes(_licenseName))){
                delete idToTagItem[_id];
                _tagSet.remove(_id);
                continue;
            }
            index++;
        }

        for (uint256 index = 0; index < _reportSet.length(); index++){
            uint256 _id = _reportSet.at(index);
             if(keccak256(bytes(idToReportItem[_id].licenseName)) == keccak256(bytes(_licenseName))){
                 deletedReports[itemCount] = idToReportItem[_id];
                 delete idToReportItem[_id];
                _reportSet.remove(_id);
                itemCount++;
                continue;
            }
            index++;
        }

        return deletedReports;
    }
}

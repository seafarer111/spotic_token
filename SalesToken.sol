// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./Spotic.sol";

contract SalesToken is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    address payable public ownerAddr;

    EnumerableSet.AddressSet tokenAddresses;

    AggregatorV3Interface internal priceFeed;

    uint256 public bnbRate = 3136;
    uint256 public stableRate = 245;
    uint256 public dogeRate = 245;
    uint256 public etherRate = 245;
    uint256 public solRate = 245;
    uint256 public hardCap = 1500000000000000000000000000;
    uint256 public startTime;
    uint256 public endTime = 1750222493;
    uint256 public purchaseLimit = 8000000000000000000000000000;
    uint256 public referralPercent = 1000; // 10% = 1000 / 10000

    bool private paused = false;
    bool private unlimited = false;
    bool private preSale = false;

    uint256 curDecimal = 10 ** 18;

    address public spoticAddr;

    address usdcAddr = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address usdtAddr = 0x55d398326f99059fF775485246999027B3197955;
    address busdAddr = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address dogeAddr = 0xbA2aE424d960c26247Dd6c32edC70B295c744C43;
    address wethAddr = 0x4DB5a66E937A9F4473fA95b1cAF1d1E1D62E29EA;
    address solAddr = 0xFEa6aB80cd850c3e63374Bc737479aeEC0E8b9a1;

    address public bnbPriceFeedAddress = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; //bnb/usd
    address public dogePriceFeedAddress = 0x3AB0A0d137D4F946fBB19eecc6e92E64660231C8; //doge/usd
    address public solPriceFeedAddress = 0x0E8a53DD9c13589df6382F13dA6B3Ec8F919B323; // sol/usd
    address public etherPriceFeedAddress = 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e; // ether/usd

    mapping(address => uint256) purchasedAmount;

    constructor() {
        startTime = block.timestamp;
        ownerAddr = payable(msg.sender);
        // get rate bnb/usd
        stableRate = getInternalStableRate();
        dogeRate = getInternalDogeRate();
        solRate = getInternalSolRate();
        etherRate = getInternalEtherRate();
    }

    function getBnbPrice() internal returns(uint256) {
        priceFeed = AggregatorV3Interface(bnbPriceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        // convert the price from 8 decimal places to 18 decimal places
        uint256 decimals = uint256(priceFeed.decimals());
        uint256 bnbPrice = uint256(price) * 10**(18 - decimals);
        return bnbPrice;
    }

    function getInternalDogeRate() internal returns(uint256) {
        uint256 _bnbPrice = getBnbPrice();

        priceFeed = AggregatorV3Interface(dogePriceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        // convert the price from 8 decimal places to 18 decimal places
        uint256 decimals = uint256(priceFeed.decimals());
        uint256 dogePrice = uint256(price) * 10**(18 - decimals);
        uint256 _dogeRate = dogePrice.mul(bnbRate).mul(curDecimal).div(_bnbPrice);
        return _dogeRate;
    }

    function getInternalEtherRate() internal returns(uint256) {
        uint256 _bnbPrice = getBnbPrice();

        priceFeed = AggregatorV3Interface(etherPriceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        // convert the price from 8 decimal places to 18 decimal places
        uint256 decimals = uint256(priceFeed.decimals());
        uint256 etherPrice = uint256(price) * 10**(18 - decimals);
        uint256 _etherRate = etherPrice.mul(bnbRate).mul(curDecimal).div(_bnbPrice);
        return _etherRate;
    }

    function getInternalSolRate() internal returns(uint256) {
        uint256 _bnbPrice = getBnbPrice();

        priceFeed = AggregatorV3Interface(solPriceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        // // convert the price from 8 decimal places to 18 decimal places
        uint256 decimals = uint256(priceFeed.decimals());
        uint256 solPrice = uint256(price) * 10**(18 - decimals);
        uint256 _solRate = solPrice.mul(bnbRate).mul(curDecimal).div(_bnbPrice);
        return _solRate;
    }

    function getInternalStableRate() internal returns(uint256) {
        priceFeed = AggregatorV3Interface(bnbPriceFeedAddress);
        (, int256 price, , , ) = priceFeed.latestRoundData();
        
        // convert the price from 8 decimal places to 18 decimal places
        uint256 decimals = uint256(priceFeed.decimals());
        uint256 bnbPrice = uint256(price) * 10**(18 - decimals);
        uint256 _statbleRate = bnbRate.mul(curDecimal).div(bnbPrice);
        return _statbleRate;
    }

    function checkIfOwner() public view returns(bool){
        return msg.sender == ownerAddr;
    }

    function contractStarted() internal view returns (bool){
        return block.timestamp >= startTime;
    }

    function getExchangeOwner() public view returns(address){
        return ownerAddr;
    }

    function getBnbRate() public view returns(uint256){
        return bnbRate;
    }

    function getSolRate() public view returns(uint256){
        // uint256 _solRate = getInternalSolRate();
        return solRate;
    }

    function getEtherRate() public view returns(uint256){
        // uint256 _etherRate = getInternalEtherRate();
        return etherRate;
    }

    function getDogeRate() public view returns(uint256){
        // uint256 _dogeRate = getInternalDogeRate();
        return dogeRate;
    }

    function getStableRate() public view returns(uint256){
        // uint256 _stableRate = getInternalStableRate();
        return stableRate;
    }

    function getPurchaseLimit() public view returns(uint256){
        return purchaseLimit;
    }

    function getStatusOfLimit() public view returns(bool){
        return unlimited;
    }

    function getStartedTime() public view returns(uint256){
        return startTime;
    }

    function getEndTime() public view returns(uint256){
        return endTime;
    }

    function getStatus() public view returns(bool){
        return paused;
    }

    function getHardCap() public view returns(uint256){
        return hardCap;
    }

    function getReferralPercent() public view returns(uint256){
        return referralPercent;
    }

    function setBnbRate(uint256 _bnbRate) external onlyInvestor {
        bnbRate = _bnbRate;
    }

    function setOwner(address _ownerAddr) external onlyInvestor {
        ownerAddr = payable(_ownerAddr);
    }

    function setHardCap(uint256 _hardCap) external onlyInvestor {
        hardCap = _hardCap;
    }

    function setStartTime(uint256 _startTime) external onlyInvestor {
        startTime = _startTime;
    }

    function setEndTime(uint256 _endTime) external onlyInvestor {
        endTime = _endTime;
    }

    function setPurchaseLimit(uint256 _purchaseLimit) external onlyInvestor {
        purchaseLimit = _purchaseLimit;
        unlimited = false;
    }

    function setReferralPercent(uint256 _referralPercent) external onlyInvestor {
        referralPercent = _referralPercent;
    }

    function setSpoticAddr(address _spoticAddr) external onlyInvestor {
        spoticAddr = _spoticAddr;
    }

    function setPaused(bool _paused) external onlyInvestor {
        paused = _paused;
    }

    function setUnlimited() external onlyInvestor {
        unlimited = true;
    }

    function mint(uint256 amount) public onlyInvestor returns (bool) {
        Spotic spoticInstance = Spotic(spoticAddr);
        spoticInstance.mint(amount);
        return true;
    }

    function burn(uint256 amount) public onlyInvestor returns (bool) {
        Spotic spoticInstance = Spotic(spoticAddr);
        spoticInstance.burn(amount);
        return true;
    }

    function purchaseWithBnb() external payable isPaused existedSpotic{
        IBEP20 spoticInstance = IBEP20(spoticAddr);
        uint256 balance = spoticInstance.balanceOf(address(this));
        uint256 amount = msg.value * bnbRate;
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");
        if(!unlimited){
            require(purchaseLimit > purchasedAmount[msg.sender] + amount, "You cant purchase more than limit");
        }

        spoticInstance.transfer(msg.sender, amount);

        purchasedAmount[msg.sender] += amount;
        hardCap -= amount;
    }

    function referralPurchaseWithBnb(address _referrencedAddress) external payable isPaused existedSpotic{
        IBEP20 spoticInstance = IBEP20(spoticAddr);
        uint256 balance = spoticInstance.balanceOf(address(this));
        uint256 amount = msg.value * bnbRate;
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");
        if(!unlimited){
            require(purchaseLimit > purchasedAmount[msg.sender] + amount, "You cant purchase more than limit");
        }
        require(_referrencedAddress != address(0), "Referrenced Address should not zero");
        uint256 referrencedAmount = amount.mul(referralPercent).div(10000);

        spoticInstance.transfer(msg.sender, amount - referrencedAmount);

        purchasedAmount[msg.sender] += amount - referrencedAmount;
        hardCap -= amount;
    }

    function purchaseBnbWithSpotic(uint256 spoticAmount) external payable isPaused existedSpotic approvedPreSale{
        IBEP20 spoticInstance = IBEP20(spoticAddr);
        uint256 balance = spoticInstance.balanceOf(msg.sender);
        uint256 amount = spoticAmount.mul(curDecimal).div(bnbRate);
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");

        spoticInstance.transferFrom(msg.sender, address(this), spoticAmount);
        payable(msg.sender).transfer(amount);
    }

    function referralPurchaseBnbWithSpotic(address _referrencedAddress, uint256 spoticAmount) external payable isPaused existedSpotic approvedPreSale{
        IBEP20 spoticInstance = IBEP20(spoticAddr);
        uint256 balance = spoticInstance.balanceOf(msg.sender);
        uint256 amount = spoticAmount.mul(curDecimal).div(bnbRate);
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");
        
        require(_referrencedAddress != address(0), "Referrenced Address should not zero");
        uint256 referrencedAmount = amount.mul(referralPercent).div(10000);

        payable(_referrencedAddress).transfer(referrencedAmount);
        payable(msg.sender).transfer(amount - referrencedAmount);

        spoticInstance.transferFrom(msg.sender, address(this), spoticAmount);

        // purchasedAmount[msg.sender] -= spoticAmount;
        // hardCap += spoticAmount;
    }

    function getTokenRate(address tokenAddress) internal returns (uint256) {
        uint256 tokenRate = 1;

        if(tokenAddress == usdcAddr || tokenAddress == usdtAddr || tokenAddress == busdAddr){
                tokenRate = getInternalStableRate();
        }else{
            if(tokenAddress == solAddr){
                tokenRate = getInternalSolRate();
            }else{
                if(tokenAddress == wethAddr){
                    tokenRate == getInternalEtherRate();
                }else{
                    if(tokenAddress == dogeAddr){
                        tokenRate = getInternalDogeRate();
                    }else{
                        revert("This token is not approved yet");
                    }
                }
            }
        }

        return tokenRate;
    }

    function purchaseWithToken(uint256 tokenAmount, address tokenAddress) external payable isPaused existedSpotic{
        IBEP20 tokenInstance = IBEP20(tokenAddress);
        IBEP20 spoticInstance = IBEP20(spoticAddr);

        uint256 balance = tokenInstance.balanceOf(msg.sender);
        uint256 tokenRate = getTokenRate(tokenAddress);
        
        uint256 amount = tokenAmount * tokenRate;
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");

        if(!unlimited){
            require(purchaseLimit > purchasedAmount[msg.sender] + amount, "You cant purchase more than limit");
        }

        spoticInstance.transfer(msg.sender, amount);
        tokenInstance.transferFrom(msg.sender, address(this), tokenAmount);

        purchasedAmount[msg.sender] += amount;
        hardCap -= amount;
    }

    function referralPurchaseWithToken(address _referrencedAddress, uint256 tokenAmount, address tokenAddress) external isPaused existedSpotic{
        IBEP20 tokenInstance = IBEP20(tokenAddress);
        IBEP20 spoticInstance = IBEP20(spoticAddr);
        uint256 balance = tokenInstance.balanceOf(msg.sender);
        uint256 tokenRate = getTokenRate(tokenAddress);

        uint256 amount = tokenAmount * tokenRate;
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");

        if(!unlimited){
            require(purchaseLimit > purchasedAmount[msg.sender] + amount, "You cant purchase more than limit");
        }
        require(_referrencedAddress != address(0), "Referrenced Address should not zero");
        uint256 referrencedAmount = amount.mul(referralPercent).div(10000);

        spoticInstance.transfer(msg.sender, amount - referrencedAmount);
        spoticInstance.transfer(_referrencedAddress, referrencedAmount);
        tokenInstance.transferFrom(msg.sender, address(this), tokenAmount);

        purchasedAmount[msg.sender] += amount - referrencedAmount;
        hardCap -= amount;
    }

    function purchaseTokenWithSpotic(uint256 spoticAmount, address tokenAddress) external payable isPaused existedSpotic approvedPreSale{
        IBEP20 tokenInstance = IBEP20(tokenAddress);
        IBEP20 spoticInstance = IBEP20(spoticAddr);
        uint256 balance = spoticInstance.balanceOf(msg.sender);
        uint256 tokenRate = getTokenRate(tokenAddress);

        uint256 amount = spoticAmount.div(tokenRate);
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");

        spoticInstance.transferFrom(msg.sender, address(this), spoticAmount);
        tokenInstance.transfer(msg.sender, amount);

        // purchasedAmount[msg.sender] -= spoticAmount;
        // hardCap += spoticAmount;
    }

    function referralPurchaseTokenWithSpotic(address _referrencedAddress, uint256 spoticAmount, address tokenAddress) external payable isPaused existedSpotic approvedPreSale{
        IBEP20 tokenInstance = IBEP20(tokenAddress);
        IBEP20 spoticInstance = IBEP20(spoticAddr);
        uint256 balance = tokenInstance.balanceOf(msg.sender);
        uint256 tokenRate = getTokenRate(tokenAddress);

        uint256 amount = spoticAmount.div(tokenRate);
        require(amount > 0, "You have to purchase more than zero");
        require(amount < balance, "You cant purchase more than balance");
        
        
        if(!unlimited){
            require(purchaseLimit > purchasedAmount[msg.sender] + amount, "You cant purchase more than limit");
        }
        require(_referrencedAddress != address(0), "Referrenced Address should not zero");
        uint256 referrencedAmount = amount.mul(referralPercent).div(10000);

        tokenInstance.transfer(msg.sender, amount - referrencedAmount);
        tokenInstance.transfer(_referrencedAddress, referrencedAmount);
        spoticInstance.transferFrom(msg.sender, address(this), spoticAmount);

        // purchasedAmount[msg.sender] += spoticAmount;
        // hardCap += spoticAmount;
    }

    function withdrawBnb() external onlyInvestor onlyInvestor{
        payable(address(msg.sender)).transfer(address(this).balance);
    }

    function withdrawAll() external onlyInvestor onlyInvestor{

        for(uint256 i = 0; i < tokenAddresses.length(); i++){
            IBEP20 tokenInstance = IBEP20(tokenAddresses.at(i));

            tokenInstance.transfer(msg.sender, tokenInstance.balanceOf(address(this)));
            tokenInstance.transfer(msg.sender, tokenInstance.balanceOf(address(this)));
        }
        
        payable(address(msg.sender)).transfer(address(this).balance);
    }

    function getBnbBalance() public view returns(uint256 bnbAmount) {
        return address(this).balance;
    }

    function getTokenBalance(address tokenAddress) public view returns(uint256 bnbAmount) {
        IBEP20 tokenInstance = IBEP20(tokenAddress);
        return tokenInstance.balanceOf(address(this));
    }

    modifier onlyInvestor() {
        require(msg.sender == ownerAddr, 'not owner');
        _;
    }

    modifier isPaused() {
        require(!paused, "purchasing is paused");
        _;
    }

    modifier approvedPreSale() {
        require(preSale, "this function is not approved");
        _;
    }

    modifier existedSpotic() {
        require(spoticAddr != address(0), "Spotic Address is not set");
        _;
    }
}
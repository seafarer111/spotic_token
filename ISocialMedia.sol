// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ISocialMedia {
    function depositFunds(address _seller, uint256 _amount) payable external;
}
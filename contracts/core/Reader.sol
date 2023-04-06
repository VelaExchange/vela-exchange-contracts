// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IPositionVault.sol";
import "./interfaces/IOrderVault.sol";

import {Constants} from "../access/Constants.sol";
import {OrderStatus} from "./structs.sol";

contract Reader is Constants {
    IOrderVault private orderVault;
    IPositionVault private positionVault;

    bool private isInitialized;
    constructor() {}

    function initialize(
        IPositionVault _positionVault,
        IOrderVault _orderVault
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_positionVault)), "vault invalid");
        require(Address.isContract(address(_orderVault)), "vaultUtils address is invalid");
        positionVault = _positionVault;
        orderVault = _orderVault;
        isInitialized = true;
    } 
    function getUserAlivePositions(
        address _user
    ) public view returns (uint256[] memory, Position[] memory, Order[] memory) {
        uint256[] memory posIds = positionVault.getUserPositionIds(_user);
        uint256 length = posIds.length;
        Position[] memory positions_ = new Position[](length);
        Order[] memory orders_ = new Order[](length);
        for (uint i; i < length; i++) {
            uint256 posId = posIds[i];
            positions_[i] = positionVault.getPosition(posId);
            orders_[i] = orderVault.getOrder(posId);
        }
        return (posIds, positions_, orders_);
    }
}

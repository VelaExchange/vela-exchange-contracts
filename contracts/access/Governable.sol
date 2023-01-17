// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

contract Governable {
    address public gov;

    event UpdateGov(address indexed oldGov, address indexed newGov);

    constructor() {
        gov = msg.sender;
    }

    modifier onlyGov() {
        require(msg.sender == gov, "Governable: forbidden");
        _;
    }

    function setGov(address _gov) external onlyGov {
        require(_gov != address(0), "Governable: zero address is invalid");
        emit UpdateGov(gov, _gov);
        gov = _gov;
    }
}

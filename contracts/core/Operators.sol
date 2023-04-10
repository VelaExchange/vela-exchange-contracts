// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Context.sol";

contract Operators is Context {
    // level 1: normal operator
    // level 2: admin
    // level 3: owner
    mapping(address => uint256) operatorLevel;

    address public oldOwner;
    address public pendingOwner;

    modifier onlyOperator(uint256 level) {
        require(operatorLevel[_msgSender()] >= level, "invalid operator");
        _;
    }

    constructor() {
        operatorLevel[_msgSender()] = 3;
    }


    function setOperator(address op, uint8 level) onlyOperator(level) external {
        require(operatorLevel[_msgSender()] > operatorLevel[op], "Cannot set operator");
        operatorLevel[op] = level;
    }

    function getOperatorLevel(address op) public view returns (uint256) {
        return operatorLevel[op];
    }

    function transferOwnership(address newOwner) external onlyOperator(3) {
        require(newOwner != address(0), "zero address");

        oldOwner = _msgSender();
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        require(_msgSender() == pendingOwner, "not pendingOwner");

        operatorLevel[_msgSender()] = 3;
        operatorLevel[oldOwner] = 0;

        pendingOwner = address(0);
        oldOwner = address(0);
    }
}

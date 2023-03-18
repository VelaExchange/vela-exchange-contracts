// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ExchangeOperators is Ownable {

  enum OperatorLevel { NONE, ONE, TWO, THREE }

  mapping(address => uint8) isOperator;

  modifier onlyOperator(uint8 level) {
      require(isOperator[_msgSender()] > uint8(OperatorLevel.NONE), "Not an operator");
      require(isOperator[_msgSender()] >= level, "Invalid operator");
      _;
  }

  constructor() {
    isOperator[_msgSender()] = uint8(OperatorLevel.THREE);
  }

  function setOperator(address op, uint8 level) onlyOperator(uint8(OperatorLevel.ONE)) external {
      require(isOperator[_msgSender()] > isOperator[op], "Cannot set operator");
      require(level <= uint8(OperatorLevel.TWO), "Invalid operator level");
      isOperator[op] = level;
  }

  function getOperatorLevel(address op) public view returns (uint8) {
      return uint8(isOperator[op]);
  }

  function transferOwnership(address newOwner) public virtual override onlyOwner {
    require(newOwner != address(0), "Ownable: new owner is the zero address");
    isOperator[_msgSender()] = uint8(OperatorLevel.NONE);
    isOperator[newOwner] = uint8(OperatorLevel.THREE);
    _transferOwnership(newOwner);
  }

  function renounceOwnership() public view override onlyOwner {
      revert("Cannot renounce ownership");
  }

}

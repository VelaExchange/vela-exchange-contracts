// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./BaseToken.sol";
import "./interfaces/IMintable.sol";

contract MintableBaseToken is BaseToken, IMintable {
    uint8 public constant MAX_MINTER_COUNT = 2;

    uint8 public mintersCount;
    mapping(address => bool) public override isMinter;

    modifier onlyMinter() {
        require(isMinter[msg.sender], "MintableBaseToken: forbidden");
        _;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) BaseToken(_name, _symbol, _initialSupply) {}

    function burn(address _account, uint256 _amount) external override onlyMinter {
        _burn(_account, _amount);
    }

    function mint(address _account, uint256 _amount) external override onlyMinter {
        _mint(_account, _amount);
    }

    function setMinter(address _minter, bool _isActive) external override onlyOwner {
        require(mintersCount < MAX_MINTER_COUNT, "cant exceed max count");
        isMinter[_minter] = _isActive;
        mintersCount += 1;
    }
}

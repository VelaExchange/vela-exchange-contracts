// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./interfaces/IVUSDC.sol";
import "../access/Governable.sol";

contract vUSDC is IVUSDC, Governable {
    uint8 public constant decimals = 30;
    uint8 public constant MAX_ADMIN_COUNT = 2;

    string public name;
    string public symbol;
    uint256 public totalSupply;
    uint256 public adminsCount;

    mapping(address => uint256) public balances;
    mapping(address => bool) public admins;

    modifier onlyAdmin() {
        require(admins[msg.sender], "VUSD: forbidden");
        _;
    }

    event Burn(address indexed account, uint256 value);
    event Mint(address indexed beneficiary, uint256 value);

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _initialSupply);
    }

    function addAdmin(address _account) external onlyGov {
        require(adminsCount < MAX_ADMIN_COUNT, "VUSD: cant exceed max count");
        admins[_account] = true;
        adminsCount += 1;
    }

    function burn(
        address _account,
        uint256 _amount
    ) external override onlyAdmin {
        _burn(_account, _amount);
    }

    function mint(
        address _account,
        uint256 _amount
    ) external override onlyAdmin {
        _mint(_account, _amount);
    }

    function setInfo(
        string memory _name,
        string memory _symbol
    ) external onlyGov {
        name = _name;
        symbol = _symbol;
    }

    function balanceOf(
        address _account
    ) external view override returns (uint256) {
        return balances[_account];
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "VUSD: burn from the zero address");

        require(
            balances[_account] >= _amount,
            "VUSD: burn amount exceeds balance"
        );
        balances[_account] -= _amount;
        totalSupply -= _amount;
        emit Burn(_account, _amount);
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "VUSD: mint to the zero address");
        totalSupply += _amount;
        balances[_account] += _amount;
        emit Mint(_account, _amount);
    }
}

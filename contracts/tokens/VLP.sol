// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./MintableBaseToken.sol";

contract VLP is MintableBaseToken {
    constructor() MintableBaseToken("Vela LP", "VLP", 0) {}

    function id() external pure returns (string memory _name) {
        return "VLP";
    }
}

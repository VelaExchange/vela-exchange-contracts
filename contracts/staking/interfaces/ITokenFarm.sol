// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/**
 * @dev Interface of the VeDxp
 */
interface ITokenFarm {
    function getTier(uint256 _pid, address _account) external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

/**
 * @dev Interface of the VeDxp
 */
interface ITokenFarm {
    function getTierVela(address _account) external view returns (uint256);
    function depositVlpForAccount(address _account, uint256 _amount) external;
    function withdrawVlpForAccount(address _account, uint256 _amount) external;
}

// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IVault {
    function accountDeltaAndFeeIntoTotalUSDC(bool _hasProfit, uint256 _adjustDelta, uint256 _fee) external;

    function distributeFee(address _account, address _refer, uint256 _fee) external;

    function takeVUSDIn(address _account, address _refer, uint256 _amount, uint256 _fee) external;

    function takeVUSDOut(address _account, address _refer, uint256 _fee, uint256 _usdOut) external;

    function transferBounty(address _account, uint256 _amount) external;
}

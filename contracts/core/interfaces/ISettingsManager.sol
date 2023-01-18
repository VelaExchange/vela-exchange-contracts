// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface ISettingsManager {
    function decreaseBorrowedUsd(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external;

    function increaseBorrowedUsd(
        address _token,
        address _sender,
        bool _isLong,
        uint256 _amount
    ) external;

    function setCustomFeeForUser(
        address _account,
        uint256 _feePoints,
        bool _isEnabled
    ) external;

    function updateCumulativeFundingRate(address _token, bool _isLong) external;

    function borrowedUsdPerAsset(
        address _token
    ) external view returns (uint256);

    function borrowedUsdPerSide(bool _isLong) external view returns (uint256);

    function borrowedUsdPerUser(
        address _sender
    ) external view returns (uint256);

    function bountyPercent() external view returns (uint256);

    function checkDelegation(
        address _master,
        address _delegate
    ) external view returns (bool);

    function closeDeltaTime() external view returns (uint256);

    function collectMarginFees(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta,
        uint256 _size,
        uint256 _entryFundingRate
    ) external view returns (uint256);

    function cooldownDuration() external view returns (uint256);

    function cumulativeFundingRates(
        address _token,
        bool _isLong
    ) external view returns (uint256);

    function delayDeltaTime() external view returns (uint256);

    function depositFee() external view returns (uint256);

    function feeManager() external view returns (address);

    function feeRewardBasisPoints() external view returns (uint256);

    function fundingInterval() external view returns (uint256);

    function fundingRateFactor(
        address _token,
        bool _isLong
    ) external view returns (uint256);

    function getFundingFee(
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _entryFundingRate
    ) external view returns (uint256);

    function getPositionFee(
        address _indexToken,
        bool _isLong,
        uint256 _sizeDelta
    ) external view returns (uint256);

    function getDelegates(
        address _master
    ) external view returns (address[] memory);

    function isDeposit(address _token) external view returns (bool);

    function isManager(address _account) external view returns (bool);

    function isStaking(address _token) external view returns (bool);

    function lastFundingTimes(
        address _token,
        bool _isLong
    ) external view returns (uint256);

    function liquidationFeeUsd() external view returns (uint256);

    function liquidateThreshold(address) external view returns (uint256);

    function marginFeeBasisPoints(
        address _token,
        bool _isLong
    ) external view returns (uint256);

    function positionManager() external view returns (address);

    function priceMovementPercent() external view returns (uint256);

    function referFee() external view returns (uint256);

    function referEnabled() external view returns (bool);

    function stakingFee() external view returns (uint256);

    function triggerGasFee() external view returns (uint256);

    function validatePosition(
        address _account,
        address _indexToken,
        bool _isLong,
        uint256 _size,
        uint256 _collateral
    ) external view;
}

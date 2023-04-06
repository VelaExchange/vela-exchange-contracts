// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../tokens/interfaces/IMintable.sol";
import "./interfaces/IPositionVault.sol";
import "../tokens/interfaces/IVUSD.sol";
import "./interfaces/ILiquidateVault.sol";
import "./interfaces/ISettingsManager.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IVaultUtils.sol";

import {Constants} from "../access/Constants.sol";

contract LiquidateVault is Constants, ReentrancyGuard, ILiquidateVault {
    uint256 public lastPosId;
    ISettingsManager private settingsManager;
    IVault private vault;
    IVaultUtils private vaultUtils;
    IPositionVault private positionVault;

    bool private isInitialized;
    mapping(uint256 => address) public liquidateRegistrant;
    mapping(uint256 => uint256) public liquidateRegisterTime;
    event RegisterLiquidation(
        uint256 posId,
        address caller,
        uint256 marginFees
    );
    constructor() {}

    function registerLiquidatePosition(uint256 _posId) external nonReentrant {
        require(liquidateRegistrant[_posId] == address(0), "not the firstCaller");
        (uint256 liquidationState, uint256 marginFees) = vaultUtils.validateLiquidation(_posId, false);
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "not exceed or allowed");
        liquidateRegistrant[_posId] = msg.sender;
        liquidateRegisterTime[_posId] = block.timestamp;
        emit RegisterLiquidation(_posId, msg.sender, marginFees);
    }


     function liquidatePosition(uint256 _posId) external nonReentrant {
        require(
            settingsManager.isManager(msg.sender) ||
                (msg.sender == liquidateRegistrant[_posId] &&
                    liquidateRegisterTime[_posId] + settingsManager.liquidationPendingTime() <= block.timestamp),
            "not manager or not allowed before pendingTime"
        );

        Position memory position = positionVault.getPosition(_posId);
        settingsManager.updateFunding(position.indexToken);
        (uint256 liquidationState, uint256 marginFees) = vaultUtils.validateLiquidation(_posId, false);
        require(liquidationState != LIQUIDATE_NONE_EXCEED, "not exceed or allowed");

        (uint32 teamPercent, uint32 firstCallerPercent, uint32 resolverPercent) = settingsManager.bountyPercent();
        uint256 bountyTeam = (marginFees * teamPercent) / BASIS_POINTS_DIVISOR;
        //uint256 bounty = bountyTeam; //this can be used in log, leave to future
        vault.transferBounty(settingsManager.feeManager(), bountyTeam);
        if (msg.sender == liquidateRegistrant[_posId] || liquidateRegistrant[_posId] == address(0)) {
            // same address to receive firstCaller bounty and resolver bounty
            uint256 bountyCaller = (marginFees * (firstCallerPercent + resolverPercent)) / BASIS_POINTS_DIVISOR;
            vault.transferBounty(msg.sender, bountyCaller);
            //bounty += bountyCaller;
        } else {
            uint256 bountyCaller = (marginFees * firstCallerPercent) / BASIS_POINTS_DIVISOR;
            vault.transferBounty(liquidateRegistrant[_posId], bountyCaller);
            //bounty += bountyCaller;
            uint256 bountyResolver = (marginFees * resolverPercent) / BASIS_POINTS_DIVISOR;
            vault.transferBounty(msg.sender, bountyResolver);
            //bounty += bountyResolver;
        }

        if (liquidationState == LIQUIDATE_THRESHOLD_EXCEED) {
            vaultUtils.emitLiquidatePositionEvent(
                _posId,
                marginFees
            );
            positionVault.decreasePosition(_posId, position.owner, position.size);
            return;
        }
        vault.accountDeltaAndFeeIntoTotalUSD(true, 0, marginFees);
        settingsManager.decreaseOpenInterest(position.indexToken, position.owner, position.isLong, position.size);
        vaultUtils.emitLiquidatePositionEvent(_posId, marginFees);
        positionVault.removeUserAlivePosition(position.owner, _posId);
    }

    function initialize(
        IPositionVault _positionVault,
        ISettingsManager _settingsManager,
        IVault _vault,
        IVaultUtils _vaultUtils
    ) external {
        require(!isInitialized, "Not initialized");
        require(Address.isContract(address(_positionVault)), "positionVault invalid");
        require(Address.isContract(address(_settingsManager)), "settingsManager invalid");
        require(Address.isContract(address(_vault)), "vault invalid");
        require(Address.isContract(address(_vaultUtils)), "vaultUtils address is invalid");
        positionVault = _positionVault;
        settingsManager = _settingsManager;
        vault = _vault;
        vaultUtils = _vaultUtils;
        isInitialized = true;
    }
}

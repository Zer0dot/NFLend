// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// struct ReserveConfigurationMap {
//     uint256 data;
// }

// struct ReserveData {
//     //stores the reserve configuration
//     ReserveConfigurationMap configuration;
//     //the liquidity index. Expressed in ray
//     uint128 liquidityIndex;
//     //variable borrow index. Expressed in ray
//     uint128 variableBorrowIndex;
//     //the current supply rate. Expressed in ray
//     uint128 currentLiquidityRate;
//     //the current variable borrow rate. Expressed in ray
//     uint128 currentVariableBorrowRate;
//     //the current stable borrow rate. Expressed in ray
//     uint128 currentStableBorrowRate;
//     uint40 lastUpdateTimestamp;
//     //tokens addresses
//     address aTokenAddress;
//     address stableDebtTokenAddress;
//     address variableDebtTokenAddress;
//     //address of the interest rate strategy
//     address interestRateStrategyAddress;
//     //the id of the reserve. Represents the position in the list of the active reserves
//     uint8 id;
// }

interface ILendingPool {
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;

    //function getReserveData(address asset) external view returns (ReserveData memory);
 
    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);
}
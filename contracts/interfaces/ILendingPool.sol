pragma solidity 0.6.12;

interface ILendingPool {
    function borrow(address asset,
        uint256 amount,
        uint256 interestRateMode,
        uint16 referralCode,
        address onBehalfOf
    ) external;
}
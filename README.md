# NFLend
(Working name, contract repo)

NFLend is a platform that allows for peer-to-peer NFT-collateralized borrowing using [Aave V2's native credit delegation.](https://docs.aave.com/developers/guides/credit-delegation)  

It allows lenders to browse borrow requests and opt to delegate credit (stable or variable) to a contract in exchange for a fixed interest rate on
behalf of the borrower. Should the loan become overdue or under-collateralized, the lender can claim the NFT collateral.

---
## Setup

Install with ```npm i``` and run the test suite with ```npx hardhat test```, that's all!

---
## Functions

#### getTotalRequestCount()
Returns the total amount of requests created, whether they're unfulfilled, closed, open or fulfilled.

#### borrowRequestById(uint256 _id)
Returns a struct with the following data for a given borrow request id, returns an empty struct if the request is closed or nonexistant.

```
address currency;           // The currency the borrower wishes to receive from the loan.
address borrower;           // The initiator of the borrow request.
address lender;             // The lender who fulfilled, address(0) if the request is open.
address nft;                // The address of the NFT the borrower is willing to lock.
uint256 nftId;              // The NFT id the borrower is willing to lock.
uint256 amount;             // The amount the borrower is requesting.
uint256 coupon;             // The yearly amount the borrower must repay in addition to the base rate by endTimeStamp.
uint256 liqThreshold;       // The liquidation threshold after which the collateralized NFT can be claimed.
uint256 cancelTimestamp;    // The timestamp after which the borrow request cannot be filled.
uint256 repayTimestamp;     // The timestamp of the latest repayment
uint256 endTimestamp;       // The ending timestamp by which the borrower must have fully repaid the loan.
```

To verify if a request is valid, these are the conditions, to be checked in order:  
1. IF borrower == address(0): The request is null (fulfilled & closed or nonexistant)  
2. IF endTimestamp < block.timestamp: The request is overdue, and can be liquidated  
3. IF cancelTimestamp < block.timestamp: The request is not null, but can no longer be filled  

#### getRequestDebtBalance(uint256 _id)
Returns the real-time accumulating debt of a given borrow request.

#### createBorrowRequest(params)
Creates a borrow request, requires NFT approval of the contract and takes the following params:
```
address _currency,
address _nft,
uint256 _nftId,
uint256 _amount,
uint256 _coupon,
uint256 _liqThreshold,
uint256 _cancelTimestamp,
uint256 duration
```
#### repay(uint256 _id, uint256 _amount)
This function repays a given borrow request's debt. An amount greater than the total debt associated will repay the entire debt and 
delete the borrow request.

#### removeRequest(uint256 _id)
This function simply closes an open, unfulfilled borrow request initiated by msg.sender.

#### liquidate(uint256 _id)
This function claims the locked collateral NFT to the lender as long as one of following criteria is respected:  
1. The current time is past the end timestamp or...  
2. The current debt amount is greater than the liquidation  

There is also a cut of the coupon rate that goes to a given address, but this is not final and the "business model"
design is not 100% set in stone.

This is intended to eventually be able to be run as a DAO too.




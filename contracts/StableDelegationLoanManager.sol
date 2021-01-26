pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol'; 
import { SafeMath } from '@openzeppelin/contracts/math/SafeMath.sol';
import { Counters } from '@openzeppelin/contracts/utils/Counters.sol';
import { console } from 'hardhat/console.sol';
import { ILendingPool } from './interfaces/ILendingPool.sol';
// import { WadRayMath } from './libraries/WadRayMath.sol';

/**
 * @dev This struct contains all the necessary data to create a borrow request.
 *
 * @param currency The currency the borrower wishes to receive from the loan.
 * @param borrower The initiator of the borrow request.
 * @param lender The lender who fulfilled, address(0) if the request is open.
 * @param nft The address of the NFT the borrower is willing to lock.
 * @param nftId The id of the NFT the borrower is willing to lock.
 * @param amount The amount the borrower is requesting.
 * @param coupon The yearly amount the borrower must repay
 * @param liqThreshold The liquidation threshold after which the collateralized NFT can be claimed.
 * @param cancelTimestamp The timestamp after which the borrow request cannot be filled.
 * @param endTimestamp The ending timestamp by which the borrower must have fully repaid the loan.
 */
struct BorrowRequest {
    address currency;
    address borrower;
    address lender;
    address nft;
    uint256 nftId;
    uint256 amount;
    uint256 coupon;       
    uint256 liqThreshold;
    uint256 cancelTimestamp;
    uint256 repayTimestamp;
    uint256 endTimestamp;
}

contract StableDelegationLoanManager {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    ILendingPool constant LENDING_POOL = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    uint256 constant MINIMUM_DURATION = 604800;     // (Currently 1 week) Does not affect repayment, just loan duration.
    uint256 constant ONE_YEAR = 31556952;           // One year (365.2425 days).
    uint16 constant REF_CODE = 0;                   // Should be the team referral code.
    uint256 feeBps = 1000;                          // (Currently 10%) The fee levied on coupon payments in bps.

    address public feeTo;

    /**
     * @dev This is a mapping from borrow request ids to borrow request structs.
     */
    mapping(uint256 => BorrowRequest) public borrowRequestById;

    Counters.Counter requestCount;

    /**
     * @dev Emitted when a new borrow request is created.
     * 
     * @param id The unique id of the borrow request.
     */
    event RequestCreated(uint256 id);

    /**
     * @dev Emitted when a borrow request is fulfilled.
     *
     * @param id The unique id of the borrow request.
     */
    event RequestFulfilled(uint256 id);

    /**
     * @dev Emitted when a borrow request is fully repaid and closed.
     * 
     * @param id The unique id of the borrow request.
     */
    event RequestFullyRepaid(uint256 id);

    /**
     * @dev Emitted when a request is liquidated and closed.
     */
    event RequestLiquidated(uint256 id);

    /**
     * @dev This modifier checks that there is no lender and no repayTimestamp associated
     * with a given borrow request id. This means the request was never fulfilled.
     * This does NOT check that the borrow request exists.
     *
     * @param id The id of the borrow request to verify.
     */
    modifier unfulfilled(uint256 id) {
        require(
            borrowRequestById[id].lender == address(0) &&
            borrowRequestById[id].repayTimestamp == 0, 
            "StableLoanManager: Fulfilled"
        );
        _;
    }

    /**
     * @dev The constructor just initializes the fee recipient address.
     *
     * @param _feeTo The address to initialize the fee recipient to.
     */
    constructor(address _feeTo) public {
        feeTo = _feeTo;
    }

    /**
     * @dev This function creates a borrow request.
     *
     * @param _currency The reserve currency to request.
     * @param _nft The address of the NFT to offer as collateral.
     * @param _nftId The id of the NFT to offer as collateral.
     * @param _amount The amount to request a loan for.
     * @param _coupon The yearly amount added to the interest.
     * @param _liqThreshold The liquidation threshold.
     * @param _cancelTimestamp The timestamp after which to cancel the request.
     * @param duration The duration the loan will be valid for.
     */
    function createBorrowRequest(
        address _currency,
        address _nft,
        uint256 _nftId,
        uint256 _amount,
        uint256 _coupon,
        uint256 _liqThreshold,
        uint256 _cancelTimestamp,
        uint256 duration
    ) 
        external 
    {
        IERC721 nftContract = IERC721(_nft);
        uint256 minimumTimestamp = block.timestamp.add(MINIMUM_DURATION);
        uint256 _endTimestamp = block.timestamp.add(duration);
        require(_amount > 0, "StableLoanManager: Zero amount");
        require(_liqThreshold > _amount, "StableLoanManager: Invalid liquidation threshold");
        require(nftContract.ownerOf(_nftId) == msg.sender, "StableLoanManager: Not the NFT owner");
        require(nftContract.getApproved(_nftId) == address(this), "StableLoanManager: Not approved");
        require(_endTimestamp >= minimumTimestamp, "StableLoanManager: Insufficient duration");

        BorrowRequest memory request = BorrowRequest({
            currency: _currency,
            borrower: msg.sender,
            lender: address(0),
            nft: _nft,
            nftId: _nftId,
            amount: _amount,
            coupon: _coupon,
            liqThreshold: _liqThreshold,
            cancelTimestamp: _cancelTimestamp,
            repayTimestamp: 0,
            endTimestamp: _endTimestamp
        });

        borrowRequestById[requestCount.current()] = request;
        IERC721(_nft).transferFrom(msg.sender, address(this), _nftId);

        console.log("Contract Log: Request created with Id:", requestCount.current());
        requestCount.increment();

        emit RequestCreated(requestCount.current());
    }

    /**
     * @dev This function removes a currently active, but unfulfilled request. Msg.sender
     * must be the borrow request creator (borrower).
     *
     * @param id The borrow request id to remove.
     */
    function removeRequest(uint256 id) external unfulfilled(id) {
        require(borrowRequestById[id].borrower == msg.sender, "StableLoanManager: Not the borrower");
        IERC721(borrowRequestById[id].nft).transferFrom(address(this), msg.sender, borrowRequestById[id].nftId);
        closeRequest(id);
        console.log("Contract Log: Removal succeeded for request with Id:", id);
    }

    /**
     * @dev This function fulfills an active, unfulfilled borrow request. msg.sender
     * must have approved the appropriate amount in the right currency.
     * 
     * @param id The id of the borrow request to fulfill.
     * @param rateMode the interest rate mode to use when borrowing.
     */
    function fulfillRequest(uint256 id, uint256 rateMode) external unfulfilled(id) {
        require(borrowRequestById[id].cancelTimestamp > block.timestamp, "StableLoanManager: Request expired");
        address _currency = borrowRequestById[id].currency;
        address _borrower = borrowRequestById[id].borrower; 
        uint256 _amount = borrowRequestById[id].amount;

        LENDING_POOL.borrow(_currency, _amount, rateMode, REF_CODE, msg.sender);
        IERC20(_currency).safeTransferFrom(address(this), _borrower, _amount);
        borrowRequestById[id].lender = msg.sender;
        borrowRequestById[id].repayTimestamp = block.timestamp;

        emit RequestFulfilled(id);
    }

    /**
     * @dev This function repays any given borrow request for a given amount.
     *
     * @param id The id of the borrow request to repay.
     * @param _amount The amount to repay, if it's greater than the whole debt, repay the entire loan.
     */
    function repay(uint256 id, uint256 _amount) external {
        uint256 debt = getRequestDebtBalance(id);
        address _currency = borrowRequestById[id].currency;
        bool full = false;
        uint256 repayment;

        if (_amount < debt) {
            repayment = _amount;
        } else {
            repayment = debt;
            full = true;
        }

        address _lender = borrowRequestById[id].lender;
        uint256 accumulatedCoupon = debt.sub(borrowRequestById[id].amount);
        uint256 feeAmount = accumulatedCoupon.mul(feeBps).div(10000);
        uint256 lenderAmount = repayment.sub(feeAmount);
        IERC20(_currency).safeTransferFrom(msg.sender, feeTo, feeAmount);
        IERC20(_currency).safeTransferFrom(msg.sender, _lender, lenderAmount);

        // Calculate the new debt balance, or close the request if repayment was total.
        if (!full) {
            uint256 debtRemaining = debt.sub(repayment);
            borrowRequestById[id].repayTimestamp = block.timestamp;
            borrowRequestById[id].amount = debtRemaining;
        } else {
            uint256 _nftId = borrowRequestById[id].nftId;
            address _borrower = borrowRequestById[id].borrower;
            IERC721(borrowRequestById[id].nft).transferFrom(address(this), _borrower, _nftId);  
            closeRequest(id);

            emit RequestFullyRepaid(id);
        }
    }

    /**
     * @dev This function allows a borrow request lender to liquidate the request as long as
     * the request is either overdue or undercollateralized.
     * 
     * @param id The id of the borrow request to liquidate.
     */
    function liquidate(uint256 id) external {
        address _lender = borrowRequestById[id].lender;
        address _nft = borrowRequestById[id].nft;
        uint256 _nftId = borrowRequestById[id].nftId;
        uint256 _endTimestamp = borrowRequestById[id].endTimestamp;
        uint256 _liqThreshold = borrowRequestById[id].liqThreshold;
        require(_lender == msg.sender, "StableLoanManager: Not the lender");
        require(
            _endTimestamp < block.timestamp ||
            getRequestDebtBalance(id) > _liqThreshold,
            "StableLoanManager: Request valid"
        );
        IERC721(_nft).transferFrom(address(this), _lender, _nftId);  
        closeRequest(id);

        emit RequestLiquidated(id);
    }

    /** 
     * @dev This function changes the feeTo address and must be called by the current
     * feeTo address.
     *
     * @param newFeeTo The new address to set as the fee recipient.
     */
    function changeFeeTo(address newFeeTo) external {
        require(msg.sender == feeTo, "LoanManager: Must be feeTo address");
        feeTo = newFeeTo;
    }

    /**
     * @dev This function changes the fee BPS.
     *
     * @param newFeeBps the new fee BPS, cannot be greater than 5000 (50%).
     */
    function changeFeeBps(uint256 newFeeBps) external {
        require(msg.sender == feeTo, "LoanManager: Must be feeTo address");
        require(newFeeBps < 5000, "LoanManager: Fee cannot exceed 50%");
        feeBps = newFeeBps;
    }

    /** 
     * @dev This function returns the total request count. Requests are 0-indexed, so
     * the latest request created is at index getTotalRequestCount()-1.
     *
     * @return A uint256 holding the total request count.
     */
    function getTotalRequestCount() external view returns (uint256) {
        return requestCount.current();
    }

    /**
     * @dev This function returns the actual debt balance of a given borrow request, taking
     * into consideration both the accumulated coupon stable and Aave variable debt.
     *
     * @param id The id of the borrow request to query.
     * 
     * @return A uint256 holding the total debt associated with a borrow request.
     */
    function getRequestDebtBalance(uint256 id) public view returns (uint256) {
        uint256 _repayTimestamp = borrowRequestById[id].repayTimestamp;
        require(_repayTimestamp > 0, "StableLoanManager: Unfulfilled");
        uint256 _coupon = borrowRequestById[id].coupon;
        uint256 currentCoupon = _coupon.div(ONE_YEAR).mul(block.timestamp.sub(_repayTimestamp));
        uint256 _amount = borrowRequestById[id].amount;
        return _amount.add(currentCoupon);
    }

    /**
     * @dev This private function deletes a borrow request, clearing all associated data.
     * It is only executed either post-liquidation, post-full repayment or after removing
     * an unfulfilled request. 
     */
    function closeRequest(uint256 id) private {
        delete(borrowRequestById[id]);
    }
}
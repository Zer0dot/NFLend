pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol'; 
import { SafeMath } from '@openzeppelin/contracts/math/SafeMath.sol';
import { Counters } from '@openzeppelin/contracts/utils/Counters.sol';
import { console } from 'hardhat/console.sol';
import { ILendingPool } from './interfaces/ILendingPool.sol';
import { WadRayMath } from './libraries/WadRayMath.sol';

// Notes
// Add a timestamp after which the borrow request CANNOT BE FILLED
// Instead of passing a timestamp, pass a duration

/**
 * @dev This struct contains all the necessary data to create a borrow request.
 *
 * @param currency The currency the borrower wishes to receive from the loan.
 * @param borrower The initiator of the borrow request.
 * @param lender The lender who fulfilled, address(0) if the request is open.
 * @param nft The address of the NFT the borrower is willing to lock.
 * @param nftId The id of the NFT the borrower is willing to lock.
 * @para requestId The borrow request's unique identifier.
 * @param amount The amount the borrower is requesting.
 * @param coupon The yearly amount the borrower must repay in addition to the base rate by endTimeStamp.
 * @param liqThreshold The liquidation threshold after which the collateralized NFT can be claimed.
 * @param cancelTimestamp The timestamp after which the borrow request cannot be filled.
 * @param endTimestamp The ending timestamp by which the borrower must have fully repaid the loan.
 */
struct BorrowRequest {
    //bool open; unnecessary              // Whether the request is open or filled, true if available.
    address currency;           // The currency the borrower wishes to receive from the loan.
    // uint256 rateMode;           // The Aave interest 
    address borrower;           // The initiator of the borrow request.
    address lender;             // The lender who fulfilled, address(0) if the request is open.
    address nft;                // The address of the NFT the borrower is willing to lock.
    uint256 nftId;              // The NFT id the borrower is willing to lock.
    //uint256 requestId;          // The borrow request's unique identifier.
    uint256 amount;             // The amount the borrower is requesting.
    uint256 coupon;             // The yearly amount the borrower must repay in addition to the base rate by endTimeStamp.
    uint256 liqThreshold;       // The liquidation threshold after which the collateralized NFT can be claimed.
    uint256 cancelTimestamp;    // The timestamp after which the borrow request cannot be filled.
    uint256 repayTimestamp;     // The timestamp of the latest repayment
    uint256 endTimestamp;       // The ending timestamp by which the borrower must have fully repaid the loan.
}

/**
 * The first iteration will adhere to the following structure:
 *      1. Borrowers can create a borrow request
 *      2. Front ends can fetch all borrow requests
 *      3. The full loan is paid back at the end of the term (rate can be computed offchain)
 * This design is simplified on purpose. It is not final.
 * The necessary functions are:
 *      External (non view/pure):
 *          1. Create borrow request
 *          2. Fulfill borrow request
 *          3. Claim uncollateralized NFT
 *          4. Repay borrow request
 *      External (view/pure):
 *          1. Retrieve all open borrow requests
 *          2. (from PUBLIC variable) Retrieve borrow request
 * Currently, for gas efficiency, a reserve is validated by checking that its normalized debt
 * is different than 0. This may not be fool-proof.
 *
 * TODO:
 *      
 */
contract LoanManager {
    using Counters for Counters.Counter;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    ILendingPool constant LENDING_POOL = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    uint256 constant MINIMUM_DURATION = 2592000;    // 30 Days 
    uint256 constant ONE_YEAR = 31556952;           // One year (365.2425 days)
    uint16 constant REF_CODE = 0;                   // Should be team referral code


    // The below mapping maps NFT addresses and Ids to their associated request Id.
    // The counter starts at 1, so, if the borrowRequestIdByNft is 0, there is no active request.
    // mapping(address => mapping(uint256 => uint256)) public borrowRequestIdByNft;
    mapping(uint256 => BorrowRequest) public borrowRequestById;

    mapping(uint256 => uint256) private scaledPrincipalById;

    Counters.Counter requestCount;
    //BorrowRequest[] private borrowRequests;
    
    event RequestCreated(uint256 id);

    event RequestFulfilled(uint256 id);

    event RequestClosed(uint256 id);

    event RequestLiquidated(uint256 id);

    modifier unfulfilled(uint256 _id) {
        require(
            borrowRequestById[_id].lender == address(0) &&
            borrowRequestById[_id].repayTimestamp == 0, 
            "LoanManager: Fulfilled"
        );
        _;
    }

    constructor() public {
        //requestCount.increment(); // Sets the counter to 1 by default
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
        //uint256 _rateMode,
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
        uint256 borrowIndex = LENDING_POOL.getReserveNormalizedVariableDebt(_currency);
        IERC721 nftContract = IERC721(_nft);
        uint256 minimumTimestamp = block.timestamp.add(MINIMUM_DURATION);
        uint256 _endTimestamp = block.timestamp.add(duration);
        require(_amount > 0, "LoanManager: Zero amount");
        require(borrowIndex != 1e27, "LoanManager: Invalid reserve");
        require(_liqThreshold > _amount, "LoanManager: Invalid liquidation threshold");
        require(nftContract.ownerOf(_nftId) == msg.sender, "LoanManager: Not the NFT owner");
        require(nftContract.getApproved(_nftId) == address(this), "LoanManager: Not approved");
        require(_endTimestamp >= minimumTimestamp, "LoanManager: Insufficient duration");
        // require(
        //     borrowRequestIdByNft[_nft][_nftId] == 0 ||
        //     borrowRequestById[borrowRequestIdByNft[_nft][_nftId]].endTimestamp < block.timestamp ||
        //     (borrowRequestById[borrowRequestIdByNft[_nft][_nftId]].cancelTimestamp < block.timestamp &&
        //     borrowRequestById[borrowRequestIdByNft[_nft][_nftId]].lender == address(0)),
        //     "LoanManager: Request with this NFT exists"
        // );

        BorrowRequest memory request = BorrowRequest({
            //open: true,
            currency: _currency,
            //rateMode: _rateMode,
            borrower: msg.sender,
            lender: address(0),
            nft: _nft,
            nftId: _nftId,
            //requestId: requestCount.current(),
            amount: _amount,
            coupon: _coupon,
            liqThreshold: _liqThreshold,
            cancelTimestamp: _cancelTimestamp,
            repayTimestamp: 0,
            endTimestamp: _endTimestamp
        });

        //borrowRequestIdByNft[_nft][_nftId] = requestCount.current();
        borrowRequestById[requestCount.current()] = request;
        IERC721(_nft).transferFrom(msg.sender, address(this), _nftId);
        //repayTimestamp[requestCount.current()] = block.timestamp;

        console.log("Contract Log: Request created with Id:", requestCount.current());
        requestCount.increment();

        emit RequestCreated(requestCount.current());
    }

    function removeRequest(uint256 _id) external unfulfilled(_id) {
        require(borrowRequestById[_id].borrower == msg.sender, "LoanManager: Not the requester");
        IERC721(borrowRequestById[_id].nft).transferFrom(address(this), msg.sender, borrowRequestById[_id].nftId);
        closeRequest(_id);
        console.log("Contract Log: Removal succeeded for request with Id:", _id);
    }

    function fulfillRequest(uint256 _id) external unfulfilled(_id) {
        require(borrowRequestById[_id].cancelTimestamp > block.timestamp, "LoanManager: Request expired");
        address _currency = borrowRequestById[_id].currency;
        address _borrower = borrowRequestById[_id].borrower; 
        uint256 _amount = borrowRequestById[_id].amount;
        uint256 borrowIndex = LENDING_POOL.getReserveNormalizedVariableDebt(_currency);
        require(borrowIndex != 0, "LoanManager: Invalid reserve");

        // Transfer in NFT
        // uint256 _nftId = borrowRequestById[_id].nftId;
        // IERC721(borrowRequestById[_id].nft).transferFrom(_borrower, address(this), _nftId);
        LENDING_POOL.borrow(_currency, _amount, 2, REF_CODE, msg.sender);
        IERC20(_currency).safeTransfer(_borrower, _amount);
        uint256 scaledPrincipal = borrowRequestById[_id].amount.rayDiv(borrowIndex);
        scaledPrincipalById[_id] = scaledPrincipal;
        borrowRequestById[_id].lender = msg.sender;
        borrowRequestById[_id].repayTimestamp = block.timestamp;

        emit RequestFulfilled(_id);
    }

    // Repay and liquidate left
    function repay(uint256 _id, uint256 _amount) external {
        uint256 debt = getRequestDebtBalance(_id);
        address _currency = borrowRequestById[_id].currency;
        bool full = false;
        //uint256 repayment = _amount < debt ? _amount : debt;
        uint256 repayment;
        if (_amount < debt) {
            repayment = _amount;
        } else {
            repayment = debt;
            full = true;
        }
        address _lender = borrowRequestById[_id].lender;
        IERC20(_currency).safeTransferFrom(msg.sender, _lender, repayment);

        // Calculate the new scaled debt balance
        if (!full) {
            uint256 debtRemaining = debt.sub(repayment);
            uint256 borrowIndex = LENDING_POOL.getReserveNormalizedVariableDebt(_currency);
            uint256 scaledPrincipal = debtRemaining.rayDiv(borrowIndex);
            scaledPrincipalById[_id] = scaledPrincipal;
            borrowRequestById[_id].repayTimestamp = block.timestamp;
        } else {
            uint256 _nftId = borrowRequestById[_id].nftId;
            address _borrower = borrowRequestById[_id].borrower;
            IERC721(borrowRequestById[_id].nft).transferFrom(address(this), _borrower, _nftId);  
            closeRequest(_id);

            emit RequestClosed(_id);
        }
    }

    function liquidate(uint256 _id) external {
        address _lender = borrowRequestById[_id].lender;
        address _nft = borrowRequestById[_id].nft;
        uint256 _nftId = borrowRequestById[_id].nftId;
        uint256 _endTimestamp = borrowRequestById[_id].endTimestamp;
        uint256 _liqThreshold = borrowRequestById[_id].liqThreshold;
        require(_lender == msg.sender, "LoanManager: Not the lender");
        require(
            _endTimestamp < block.timestamp ||
            getRequestDebtBalance(_id) > _liqThreshold,
            "LoanManager: Request valid"
        );
        IERC721(_nft).transferFrom(address(this), _lender, _nftId);  
        closeRequest(_id);

        emit RequestLiquidated(_id);
    }

    function getTotalRequestCount() external view returns (uint256) {
        return requestCount.current().sub(1);
    }

    function getRequestDebtBalance(uint256 _id) public view returns (uint256) {
        address _currency = borrowRequestById[_id].currency;
        uint256 borrowIndex = LENDING_POOL.getReserveNormalizedVariableDebt(_currency);
        uint256 _repayTimestamp = borrowRequestById[_id].repayTimestamp;
        require(borrowIndex != 0, "LoanManager: Invalid reserve");
        require(_repayTimestamp > 0, "LoanManager: Unfulfilled");
        uint256 _coupon = borrowRequestById[_id].coupon;
        uint256 currentCoupon = _coupon.div(ONE_YEAR).mul(block.timestamp.sub(_repayTimestamp));
        return scaledPrincipalById[_id].rayMul(borrowIndex).add(currentCoupon);
    }

    function closeRequest(uint256 _id) private {
        address _nft = borrowRequestById[_id].nft;
        uint256 _nftId = borrowRequestById[_id].nftId;
        //delete(borrowRequestIdByNft[_nft][_nftId]);
        delete(borrowRequestById[_id]);
        delete(scaledPrincipalById[_id]);
    }
}
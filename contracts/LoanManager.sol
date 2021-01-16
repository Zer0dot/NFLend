pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import { IERC721 } from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import { SafeMath } from '@openzeppelin/contracts/math/SafeMath.sol';
import { Counters } from '@openzeppelin/contracts/utils/Counters.sol';
import { console } from 'hardhat/console.sol';
import { ILendingPool } from './interfaces/ILendingPool.sol';

// Notes
// Add a timestamp after which the borrow request CANNOT BE FILLED
// Instead of passing a timestamp, pass a duration

/**
 * @dev This struct contains all the necessary data to create a borrow request.
 */
struct BorrowRequest {
    //bool open; unnecessary              // Whether the request is open or filled, true if available.
    address currency;           // The currency the borrower wishes to receive from the loan.
    address borrower;           // The initiator of the borrow request.
    address lender;             // The lender who fulfilled, address(0) if the request is open.
    address nft;                // The address of the NFT the borrower is willing to lock.
    uint256 nftId;              // The NFT id the borrower is willing to lock.
    uint256 requestId;          // The borrow request's unique identifier.
    uint256 amount;             // The amount the borrower is requesting.
    uint256 payment;            // The amount the borrower must repay by endTimeStamp.
    uint256 cancelTimestamp;    // The timestamp after which the borrow request cannot be filled.
    uint256 endTimestamp;       // The ending timestamp by which the borrower must repay the loan.
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
 */
contract LoanManager {
    using Counters for Counters.Counter;
    using SafeMath for uint256;

    ILendingPool constant LENDING_POOL = ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    uint256 constant MINIMUM_DURATION = 2592000; // 30 Days 

    // The below mapping maps NFT addresses and Ids to their associated request Id.
    // The counter starts at 1, so, if the nftRequestId is 0, there is no active request.
    mapping(address => mapping(uint256 => uint256)) public nftRequestId;
    mapping(uint256 => BorrowRequest) public borrowRequestById;
    Counters.Counter requestCount;
    //BorrowRequest[] private borrowRequests;
    
    event RequestCreated(uint256 id);

    modifier unfulfilled(uint256 _id) {
        require(borrowRequestById[_id].lender == address(0), "LoanManager: Request fulfilled");
        _;
    }

    constructor() public {
        requestCount.increment(); // Sets the counter to 1 by default
    }

    function createBorrowRequest(
        address _currency,
        address _nft,
        uint256 _nftId,
        uint256 _amount,
        uint256 _payment,
        uint256 _cancelTimestamp,
        uint256 duration
    ) 
        external 
    {
        IERC721 nftContract = IERC721(_nft);
        uint256 minimumTimestamp = block.timestamp.add(MINIMUM_DURATION);
        uint256 _endTimestamp = block.timestamp.add(duration);
        require(nftContract.ownerOf(_nftId) == msg.sender, "LoanManager: Not the NFT owner");
        require(nftContract.getApproved(_nftId) == address(this), "LoanManager: Not approved");
        require(_endTimestamp >= minimumTimestamp, "LoanManager: Insufficient duration");
        require(
            nftRequestId[_nft][_nftId] == 0 ||
            borrowRequestById[nftRequestId[_nft][_nftId]].endTimestamp < block.timestamp ||
            (borrowRequestById[nftRequestId[_nft][_nftId]].cancelTimestamp < block.timestamp &&
            borrowRequestById[nftRequestId[_nft][_nftId]].lender == address(0)),
            "LoanManager: Request exists"
        );

        BorrowRequest memory request = BorrowRequest({
            //open: true,
            currency: _currency,
            borrower: msg.sender,
            lender: address(0),
            nft: _nft,
            nftId: _nftId,
            requestId: requestCount.current(),
            amount: _amount,
            payment: _payment,
            cancelTimestamp: _cancelTimestamp,
            endTimestamp: _endTimestamp
        });

        nftRequestId[_nft][_nftId] = requestCount.current();
        borrowRequestById[requestCount.current()] = request;
        
        console.log("Contract Log: Request created with Id:", requestCount.current());
        emit RequestCreated(requestCount.current());
        requestCount.increment();
    }

    function removeRequest(uint256 _id) external unfulfilled(_id) {
        require(borrowRequestById[_id].borrower == msg.sender, "LoanManager: Not the requester");
        delete(borrowRequestById[_id]);
        console.log("Contract Log: Removal succeeded for request with Id:", _id);
    }

    function fulfillRequest(uint256 _id) external unfulfilled(_id) {
        require(borrowRequestById[_id].cancelTimestamp > block.timestamp, "LoanManager: Request expired");
        // borrow on behalf of msg.sender and transfer to the borrower, then...
        // set the appropriate values in the borrowRequest
    }

    function getTotalRequestCount() external view returns (uint256) {
        return requestCount.current().sub(1);
    }

    // Will need to sort out empty structs
    // function getBorrowRequests() public view returns ( uint256[] memory/*BorrowRequest[] memory*/){
    //     BorrowRequest[] memory borrowRequests = new BorrowRequest[](requestCount.current().sub(1));
    //     for (uint256 i = 1; i <= requestCount.current(); i ++) {
    //         borrowRequests[i-1] = borrowRequestById[i];
    //         console.log(borrowRequests[i-1].requestId);
    //     }
    //     return borrowRequests;
    // }


}
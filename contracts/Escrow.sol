pragma solidity 0.6.12;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
/**
 * @dev This contract holds the aTokens to redirect. These funds can only be accessed
 * through the approved factory, where its parameters are managed.
 */
contract Escrow {

    constructor(IERC20 token) public {
        // token.approve(msg.sender, uint256(-1));
        selfdestruct(msg.sender);
    }
}
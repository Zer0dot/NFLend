// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '@openzeppelin/contracts/token/ERC20/SafeERC20.sol';
import { SafeMath } from '@openzeppelin/contracts/math/SafeMath.sol';
import { Escrow } from './Escrow.sol';
import { console } from 'hardhat/console.sol';

/**
 * @title MasterRedirector contract.
 * @author Zer0dot
 *
 * @dev This contract is the link between redirector, redirectee & escrow. 
 * This contract allows for all basic functions tied to interest redirection.
 */
contract MasterRedirector {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    mapping(address => address[]) public redirectorEscrows;
    mapping(address => address[]) public redirecteeEscrows;
    mapping(address => uint256) public escrowDeposits;
    mapping(address => address) public escrowTokens;

    event CreatedEscrow(address escrow);

    modifier isEscrowOwner(address _escrow) {
        bool isOwner;
        for (uint256 i; i < redirectorEscrows[msg.sender].length; i ++) {
            if (redirectorEscrows[msg.sender][i] == _escrow) {
                isOwner = true;
                break;
            }
        }
        require(isOwner, "MasterRedirector: Not the owner.");
        _;
    }

    function createRedirection(address _aToken, uint256 amount, address redirectee) external {
        IERC20 aToken = IERC20(_aToken);
        Escrow escrow = new Escrow(aToken);
        aToken.safeTransferFrom(msg.sender, address(escrow), amount);
        
        // Initialize mappings
        redirectorEscrows[msg.sender].push(address(escrow));
        redirecteeEscrows[redirectee].push(address(escrow));
        escrowTokens[address(escrow)] = _aToken;
        escrowDeposits[address(escrow)] = amount;
        console.log(address(escrow));
        console.log(aToken.balanceOf(address(escrow)));

        emit CreatedEscrow(address(escrow));
    }

    function changeDeposit(address _escrow, uint256 newAmount) external isEscrowOwner(_escrow) {
        IERC20 aToken = IERC20(escrowTokens[_escrow]);
        uint256 balance = aToken.balanceOf(_escrow);

        if (newAmount < balance) {
            uint256 diff = balance.sub(newAmount);
            aToken.safeTransferFrom(_escrow, msg.sender, diff);
            escrowDeposits[_escrow] = newAmount;
        } else {
            uint256 diff = newAmount.sub(balance);
            aToken.safeTransferFrom(msg.sender, _escrow, diff);
            escrowDeposits[_escrow] = newAmount;
        }
    }

    function claimRedirectedInterest() external {
        for (uint256 i = 0; i < redirecteeEscrows[msg.sender].length; i ++) {
            address _escrow = redirecteeEscrows[msg.sender][i];
            IERC20 aToken = IERC20(escrowTokens[_escrow]);
            uint256 claimableBalance = getClaimableInterest(_escrow);
            aToken.safeTransferFrom(_escrow, msg.sender, claimableBalance);
        }
    }

    function getClaimableInterest(address _escrow) public view returns (uint256) {
        IERC20 aToken = IERC20(escrowTokens[_escrow]);
        uint256 balance = aToken.balanceOf(_escrow);
        return (balance.sub(escrowDeposits[_escrow]));
    }

    function getFirstEscrow(address query) public view returns (address) {
        return redirecteeEscrows[query][0];
    }
    // Change escrow deposit V
    // Withdraw redirection
    // Claim redirected interest from all deposits

}
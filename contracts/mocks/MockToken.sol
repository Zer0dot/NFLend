pragma solidity 0.6.12;

import { SafeMath } from '@openzeppelin/contracts/math/SafeMath.sol';


/**
 * @dev Token contract for testing
 */
contract MockToken {
    using SafeMath for uint256;
    mapping(address => uint256) balances;
    mapping(address => uint256) gotTimestamp;

    function transferFrom(address from, address to, uint256 amount) external {
        uint256 fromBalance = balanceOf(from);
        uint256 toBalance = balanceOf(to);
        require(amount <= fromBalance);
        balances[from] = fromBalance - amount;
        balances[to] = toBalance + amount;
        gotTimestamp[from] = block.timestamp;
        gotTimestamp[to] = block.timestamp;
        //addbalancesss[to] += amount;
        //subbalancesss[from] -= amount;
    }

    function mint(address to, uint256 amount) public {
        balances[to] += amount;
        gotTimestamp[to] = block.timestamp;
    }

    function balanceOf(address query) public view returns (uint256) {
        if (balances[query] == 0) {
            return 0;
        } else if (gotTimestamp[query] == block.timestamp) {
            return balances[query];
        } else {
            uint256 timePassed = block.timestamp - gotTimestamp[query];
            uint256 updatedBalance = balances[query];
            for (uint256 i = 1; i <= timePassed; i++) {
                updatedBalance = updatedBalance.mul(101e8).div(100e8);
            }
            return updatedBalance;
        }
    }

    
}
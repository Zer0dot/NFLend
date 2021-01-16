pragma solidity 0.6.12;

import { ERC721 } from '@openzeppelin/contracts/token/ERC721/ERC721.sol';

contract MockNFT is ERC721("Mock NFT", "mNFT") {
    function mint(address to, uint256 id) external {
        _mint(to, id);
    }
}
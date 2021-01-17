import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract, ContractFactory, Signer } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

const AWETH_ADDRESS = "0x030bA81f1c18d280636F32af80b9AAd02Cf0854e";
const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const LENDINGPOOL_ADDRESS = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9";
const WETHGATEWAY_ADDRESS = "0xDcD33426BA191383f1c9B431A342498fdac73488";
const MAX_UINT256 = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const LENDINGPOOL_ABI = [
    "function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)"
]

const WETHGATEWAY_ABI = [
    "function depositETH(address onBehalfOf, uint16 referralCode) payable"
]

const ERC20_ABI = [
    "function balanceOf(address owner) view returns (uint)",
    "function approve(address spender, uint256 amount) returns (bool)"
];

describe("LoanManager persistent instance", function () {
    let accounts: SignerWithAddress[];
    let LoanManager: ContractFactory;
    let loanManager: Contract;
    let MockNFT: ContractFactory;
    let mockNFT: Contract;
    let lendingPool: Contract;
    let DAI: Contract;
    let aWETH: Contract;
    let WETHGateway: Contract;

    before(async function () {
        accounts = await ethers.getSigners();
        LoanManager = await ethers.getContractFactory("LoanManager");
        MockNFT = await ethers.getContractFactory("MockNFT");
        loanManager = await LoanManager.deploy();
        mockNFT = await MockNFT.deploy();
        lendingPool = new ethers.Contract(LENDINGPOOL_ADDRESS, LENDINGPOOL_ABI, accounts[0]);
        DAI = new ethers.Contract(DAI_ADDRESS, ERC20_ABI, accounts[0]);
        aWETH = new ethers.Contract(AWETH_ADDRESS, ERC20_ABI, accounts[0]);
        //console.log(await aWETH.balanceOf(accounts[0].address));
        WETHGateway = new ethers.Contract(WETHGATEWAY_ADDRESS, WETHGATEWAY_ABI, accounts[0]);
    });

    it("Account 1 Should mint mock NFT 0 to itself", async function () {
        await expect(mockNFT.mint(accounts[0].address, "0")).to.not.be.reverted;
    });

    it("Account 1 should approve the loanManager with nft 0", async function () {
        await expect(mockNFT.approve(loanManager.address, "0")).to.not.be.reverted;
    });

    it("Addr2 should deposit 10 ETH into aWETH", async function () {
        await expect(WETHGateway.connect(accounts[1]).depositETH(
            accounts[1].address,
            "0",
            { value: ethers.utils.parseUnits("10", "ether")}
        )).to.not.be.reverted;
    });

    it("Addr2 should have 10 aWETH", async function () {
        await expect(BigNumber.from(await aWETH.balanceOf(accounts[1].address)))
            .to.eq(BigNumber.from(ethers.utils.parseUnits("10", "ether")));
    });

    it("Account 1 should create a borrow request ", async function () {
        console.log("Gas cost for borrow request creation:", ethers.utils.commify((await loanManager.estimateGas.createBorrowRequest(
            DAI_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseUnits("1", "ether"),
            ethers.utils.parseUnits("1.1", "ether"),
            "999999999999999999999",
            "999999999999999999999"
        )).toString()));
        await expect(loanManager.createBorrowRequest(
            DAI_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseUnits("1", "ether"),
            ethers.utils.parseUnits("1.1", "ether"),
            "999999999999999999999",
            "999999999999999999999"
        )).to.not.be.reverted;
    });

    it("Total borrow requests should equal 1", async function () {
        await expect(await loanManager.getTotalRequestCount()).to.eq(BigNumber.from(1));
    });

    it("Account 1 should remove their borrow request", async function () {
        await expect(loanManager.removeRequest("1")).to.not.be.reverted;
        console.log("Should be an empty struct:", await loanManager.borrowRequestById("1"));
    });

    it("Account 1 should create another, identical borrow request", async function () {
        console.log("Gas cost for SECOND borrow request creation:", ethers.utils.commify((await loanManager.estimateGas.createBorrowRequest(
            DAI_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseUnits("1", "ether"),
            ethers.utils.parseUnits("1.1", "ether"),
            "999999999999999999999",
            "999999999999999999999"
        )).toString()));
        await expect(loanManager.createBorrowRequest(
            DAI_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseUnits("1", "ether"),
            ethers.utils.parseUnits("1.1", "ether"),
            "999999999999999999999",
            "999999999999999999999"
        )).to.not.be.reverted;
    });

    it("Account 1 should NOT be able to create another, identical borrow request", async function () {
        await expect(loanManager.createBorrowRequest(
            DAI_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseUnits("1", "ether"),
            ethers.utils.parseUnits("1.1", "ether"),
            "999999999999999999999",
            "999999999999999999999"
        )).to.be.revertedWith("LoanManager: Request exists");
    });

});
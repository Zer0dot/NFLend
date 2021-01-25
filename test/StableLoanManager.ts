import { expect } from "chai";
import { ethers } from "hardhat";
import { BigNumber, Contract, ContractFactory } from "ethers";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import hre = require("hardhat");
const alchemyProjectId  = require("../secrets.json");

const AWETH_ADDRESS = "0x030bA81f1c18d280636F32af80b9AAd02Cf0854e";
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const LENDINGPOOL_ADDRESS = "0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9";
const WETHGATEWAY_ADDRESS = "0xDcD33426BA191383f1c9B431A342498fdac73488";
const VARIABLE_DEBT_WETH_ADDRESS = "0xF63B34710400CAd3e044cFfDcAb00a0f32E33eCf";
const MAX_UINT256 = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

const LENDINGPOOL_ABI = [
    "function deposit(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)"
];

const WETHGATEWAY_ABI = [
    "function depositETH(address onBehalfOf, uint16 referralCode) payable"
];

const ERC20_ABI = [
    "function balanceOf(address owner) view returns (uint)",
    "function approve(address spender, uint256 amount) returns (bool)"
];

const WETH_ABI = [
    "function approve(address guy, uint wad) public returns (bool)",
    "function deposit() external payable",
    "function balanceOf(address arg1) public view returns (uint256)"
]

const DEBT_TOKEN_ABI = [
    "function approveDelegation(address delegatee, uint256 amount) external",
    "function balanceOf(address account) public view returns (uint256)"
];
//CURRENTLY DOESN'T WORK- RUN TESTS INDIVIDUALLY
// async function resetFork () {
//     await hre.network.provider.request({
//         method: "hardhat_reset",
//         params: [{
//           forking: {
//             jsonRpcUrl: `https://eth-mainnet.alchemyapi.io/v2/${alchemyProjectId}`,
//             blockNumber: 11689738
//           }
//         }]
//     });
// }

describe("StableLoanManager persistent instance", function () {
    let accounts: SignerWithAddress[];
    let StableLoanManager: ContractFactory;
    let stableLoanManager: Contract;
    let MockNFT: ContractFactory;
    let mockNFT: Contract;
    let WETH: Contract;
    let balanceBefore: BigNumber;
    let balanceAfter: BigNumber;

    async function sendDummyTx() {
        accounts[0].sendTransaction({ to: accounts[1].address, value: BigNumber.from(1) });
    }

    before(async function () {
        //await resetFork(); // CURRENTLY DOESN'T WORK- RUN TESTS INDIVIDUALLY
        accounts = await ethers.getSigners();
        StableLoanManager = await ethers.getContractFactory("StableLoanManager");
        MockNFT = await ethers.getContractFactory("MockNFT");
        stableLoanManager = await StableLoanManager.deploy();
        mockNFT = await MockNFT.deploy();
        WETH = new ethers.Contract(WETH_ADDRESS, WETH_ABI, accounts[0]);
    });

    beforeEach(async function () {
        // Advances block between each test
        // await expect(accounts[0].sendTransaction({ to: accounts[1].address, value: BigNumber.from(1) }))
        // .to.not.be.reverted;
        await sendDummyTx();
    });

    ///////////////////////////
    ///        SETUP        ///
    ///////////////////////////

    it("Account 0 Should mint mock NFT 0 to itself", async function () {
        await expect(mockNFT.mint(accounts[0].address, "0")).to.not.be.reverted;
    });

    it("Account 0 should approve the stableLoanManager with nft 0", async function () {
        await expect(mockNFT.approve(stableLoanManager.address, "0")).to.not.be.reverted;
    });

    it("Account 1 should deposit 10 ETH into WETH", async function () {
        await expect(WETH.connect(accounts[1]).deposit({ value: ethers.utils.parseEther("10")})).to.not.be.reverted;
    });

    it("Account 1 should have 10 WETH", async function () {
        await expect(BigNumber.from(await WETH.balanceOf(accounts[1].address)))
            .to.eq(BigNumber.from(ethers.utils.parseEther("10")));
    });

    ///////////////////////////
    ///       REMOVAL       ///
    ///////////////////////////

    it("Account 0 should create a borrow request ", async function () {
        console.log("First borrow request creation gas cost:", ethers.utils.commify((await stableLoanManager.estimateGas.createBorrowRequest(
            WETH_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.1"),
            ethers.utils.parseEther("1.2"),
            "999999999999999999999",
            "999999999999999999999"
        )).toString()));
        await expect(stableLoanManager.createBorrowRequest(
            WETH_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.1"),
            ethers.utils.parseEther("1.2"),
            "999999999999999999999",
            "999999999999999999999"
        )).to.not.be.reverted;
    });

    it("Total borrow requests should equal 1", async function () {
        await expect(await stableLoanManager.getTotalRequestCount()).to.eq(BigNumber.from(1));
    });

    it("Account 0 should remove their borrow request", async function () {
        await expect(stableLoanManager.removeRequest("0")).to.not.be.reverted;
        //console.log("Should be an empty struct:", await stableLoanManager.borrowRequestById("1"));
    });

    ///////////////////////////
    ///      REPAYMENT      ///
    ///////////////////////////

    it("Account 0 should approve the stableLoanManager with nft 0", async function () {
        await expect(mockNFT.approve(stableLoanManager.address, "0")).to.not.be.reverted;
    });

    it("Account 0 should create another, identical borrow request", async function () {
        console.log("Second borrow request creation gas cost:", ethers.utils.commify((await stableLoanManager.estimateGas.createBorrowRequest(
            WETH_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.1"),
            ethers.utils.parseEther("1.2"),
            "999999999999999999999",
            "999999999999999999999"
        )).toString()));
        await expect(stableLoanManager.createBorrowRequest(
            WETH_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.1"),
            ethers.utils.parseEther("1.2"),
            "999999999999999999999",
            "999999999999999999999"
        )).to.not.be.reverted;
    });

    it("Account 0 should NOT be able to create another, identical borrow request", async function () {
        await expect(stableLoanManager.createBorrowRequest(
            WETH_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("0.1"),
            ethers.utils.parseEther("1.2"),
            "999999999999999999999",
            "999999999999999999999"
        )).to.be.revertedWith("StableLoanManager: Not the NFT owner");
    });

    it("Account 1 should approve the StableLoanManager with WETH", async function () {
        await expect(WETH.connect(accounts[1]).approve(stableLoanManager.address, MAX_UINT256))
            .to.not.be.reverted;
    });

    it("Account 1 should fulfill the recently created request with id 1", async function () {
        console.log("Fulfill gas cost:", ethers.utils.commify((
            await stableLoanManager.connect(accounts[1]).estimateGas.fulfillRequest("1")
        ).toString()));
        await expect(stableLoanManager.connect(accounts[1]).fulfillRequest("1")).to.not.be.reverted;
    });

    it("Account 1 should not be able to fulfill the request a second time", async function () {
        await expect(stableLoanManager.connect(accounts[1]).fulfillRequest("1")).to.be.revertedWith("StableLoanManager: Fulfilled");
    });

    it("Account 0 should have 1 WETH", async function () {
        await expect(await WETH.balanceOf(accounts[0].address))
            .to.eq(ethers.utils.parseEther("1"));
    });

    it("Should have accumulating debt", async function () {
        balanceBefore = await stableLoanManager.getRequestDebtBalance("1");
        await sendDummyTx();
        balanceAfter = await stableLoanManager.getRequestDebtBalance("1");
        expect(balanceAfter).to.be.gt(balanceBefore);
    });

    it("Account 0 should approve the StableLoanManager with WETH", async function () {
        await expect(WETH.approve(stableLoanManager.address, MAX_UINT256))
            .to.not.be.reverted;
    });

    it("Account 1 should not be able to liquidate borrow request with id 1", async function () {
        await expect(stableLoanManager.connect(accounts[1]).liquidate("1"))
            .to.be.revertedWith("StableLoanManager: Request valid");
    });

    it("Account 0 should repay borrow request with id 1 for 0.5 WETH", async function () {
        console.log("Old debt balance:", (await stableLoanManager.getRequestDebtBalance("1")).toString());
        console.log("Repayment gas:", ethers.utils.commify((await stableLoanManager.estimateGas.repay(
            "1",
            ethers.utils.parseEther("0.5")
        )).toString()));
        await expect(stableLoanManager.repay(
            "1",
            ethers.utils.parseEther("0.5")
        )).to.not.be.reverted;
        console.log("New debt balance:", (await stableLoanManager.getRequestDebtBalance("1")).toString());
    });

    it("Account 0 should deposit 1 ETH into WETH", async function () {
        await expect(WETH.deposit({ value: ethers.utils.parseEther("1")})).to.not.be.reverted;
    });

    it("Account 0 should repay the entirety of borrow request with id 1", async function () {
        console.log("Full repayment gas:", ethers.utils.commify((await stableLoanManager.estimateGas.repay(
            "1",
            MAX_UINT256
        )).toString()));
        await expect(stableLoanManager.repay(
            "1",
            MAX_UINT256
        )).to.not.be.reverted;
        //console.log("Should be an empty struct:", await stableLoanManager.borrowRequestById("2"));
    });

    it("Account 1 should have > 1 WETH from the repayment", async function () {
        await expect(await WETH.balanceOf(accounts[1].address)).to.be.gt(ethers.utils.parseEther("1"));
    });

    it("Account 0 should be the owner of NFT with id 0", async function () {
        await expect(await mockNFT.ownerOf("0")).to.equal(accounts[0].address);
    });

    ///////////////////////////
    ///     LIQUIDATION     ///
    ///////////////////////////

    it("Account 0 should approve the stableLoanManager with nft 0", async function () {
        await expect(mockNFT.approve(stableLoanManager.address, "0")).to.not.be.reverted;
    });

    it("Account 0 should create another borrow request with minimal liq. threshold (id 2)", async function () {
        await expect(stableLoanManager.createBorrowRequest(
            WETH_ADDRESS,
            mockNFT.address,
            "0",
            ethers.utils.parseEther("1"),
            ethers.utils.parseEther("10"),
            ethers.utils.parseEther("1.000000000000000001"),
            "999999999999999999999",
            "999999999999999999999"
        )).to.not.be.reverted;
    });

    it("Account 1 should fulfill the recently created request with id 2", async function () {
        console.log("Fulfill gas cost:", ethers.utils.commify((
            await stableLoanManager.connect(accounts[1]).estimateGas.fulfillRequest("2")
        ).toString()));
        await expect(stableLoanManager.connect(accounts[1]).fulfillRequest("2")).to.not.be.reverted;
    });

    it("Borrow request with id 2 should have higher debt than liq. threshold", async function () {
        await expect(BigNumber.from((await stableLoanManager.borrowRequestById("2")).liqThreshold))
            .to.be.lt(await stableLoanManager.getRequestDebtBalance("2"));
        //console.log("Should be an empty struct:", await stableLoanManager.borrowRequestById("2"));
        console.log("Liq. threshold:", (await stableLoanManager.borrowRequestById("2")).liqThreshold.toString());
        console.log("Debt balance:", (await stableLoanManager.getRequestDebtBalance("2")).toString());
    });

    it("Account 2 should not be able to liquidate request with id 2", async function () {
        await expect(stableLoanManager.connect(accounts[2]).liquidate("2"))
            .to.be.revertedWith("StableLoanManager: Not the lender");
    });

    it("Account 1 should be able to liquidate request with id 2", async function () {
        await expect(stableLoanManager.connect(accounts[1]).liquidate("2")).to.not.be.reverted;
        //console.log("Should be an empty struct:", await stableLoanManager.borrowRequestById("2"));
    });

    it("Account 1 should be the owner of NFT with id 0", async function () {
        await expect(await mockNFT.ownerOf("0")).to.equal(accounts[1].address);
    });

});
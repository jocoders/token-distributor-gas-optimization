// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILooksRareToken} from "../interfaces/ILookRareToken.sol";
import {TokenDistributor} from "../src/TokenDistributor.sol";

contract TokenSplitter is ERC20 {
    constructor() ERC20("Token Splitter", "SPLITTER") {
        _mint(msg.sender, 1_000_000e18);
    }
}

contract TokenLooksRare is ERC20, ILooksRareToken, Ownable {
    uint256 private constant _SUPPLY_CAP = 1_000_000e18;

    constructor() ERC20("Token LooksRare", "LOOKS") Ownable(msg.sender) {}

    function SUPPLY_CAP() external pure returns (uint256) {
        return _SUPPLY_CAP;
    }

    function mint(address account, uint256 amount) external returns (bool) {
        require(msg.sender == owner(), "LooksRare: Only owner");
        require(totalSupply() + amount <= _SUPPLY_CAP, "LooksRare: Cap exceeded");

        _mint(account, amount);
        return true;
    }
}

contract TokenDistributorTest is Test {
    TokenDistributor tokenDistributor;
    TokenLooksRare tokenLooksRare;
    TokenSplitter tokenSplitter;

    address Alice = makeAddr("Alice");

    function setUp() public {
        uint256[] memory rewardsPerBlockForStaking = new uint256[](2);
        rewardsPerBlockForStaking[0] = 1_000e18; // 1,000 tokens per block
        rewardsPerBlockForStaking[1] = 2_000e18; // 2,000 tokens per block

        uint256[] memory rewardsPerBlockForOthers = new uint256[](2);
        rewardsPerBlockForOthers[0] = 8_000e18; // 8,000 tokens per block
        rewardsPerBlockForOthers[1] = 3_000e18; // Adjusted to 3,000 tokens per block

        uint256[] memory periodLengthesInBlocks = new uint256[](2);
        periodLengthesInBlocks[0] = 100; // 100 blocks
        periodLengthesInBlocks[1] = 20; // 20 blocks

        tokenLooksRare = new TokenLooksRare();
        tokenSplitter = new TokenSplitter();
        tokenDistributor = new TokenDistributor(
            address(tokenLooksRare),
            address(tokenSplitter),
            1,
            rewardsPerBlockForStaking,
            rewardsPerBlockForOthers,
            periodLengthesInBlocks,
            2
        );

        tokenLooksRare.mint(Alice, 100_000e18);
        tokenLooksRare.transferOwnership(address(tokenDistributor));
    }

    function test_deposit() public {
        _deposit();
    }

    function test_harvestAndCompound() public {
        uint256 totalAmountStakedBefore = tokenDistributor.totalAmountStaked();
        vm.roll(block.number + 10);
        _deposit();
        vm.roll(block.number + 15);

        vm.startPrank(Alice);
        tokenDistributor.harvestAndCompound();
        vm.stopPrank();

        uint256 totalAmountStakedAfter = tokenDistributor.totalAmountStaked();
        assertNotEq(totalAmountStakedAfter, totalAmountStakedBefore);
    }

    function test_withdraw() public {
        _deposit();
        uint256 totalAmountStaked1 = tokenDistributor.totalAmountStaked();
        uint256 rewardPerBlockForOthers1 = tokenDistributor.rewardPerBlockForOthers();
        uint256 rewardPerBlockForStaking1 = tokenDistributor.rewardPerBlockForStaking();

        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 10);
        vm.startPrank(Alice);
        tokenDistributor.harvestAndCompound();
        tokenDistributor.withdraw(50e18);
        vm.stopPrank();

        uint256 totalAmountStaked2 = tokenDistributor.totalAmountStaked();
        uint256 rewardPerBlockForOthers2 = tokenDistributor.rewardPerBlockForOthers();
        uint256 rewardPerBlockForStaking2 = tokenDistributor.rewardPerBlockForStaking();
    }

    function _deposit() private {
        uint256 amount = 100e18;
        uint256 balanceBefore = tokenLooksRare.balanceOf(Alice);

        vm.startPrank(Alice);
        tokenLooksRare.approve(address(tokenDistributor), amount);
        tokenDistributor.deposit(amount);
        vm.stopPrank();

        uint256 balanceAfter = tokenLooksRare.balanceOf(Alice);
        assertEq(balanceAfter, balanceBefore - amount);

        uint256 totalAmountStaked = tokenDistributor.totalAmountStaked();
        assertEq(totalAmountStaked, amount);
    }

    function test_calculatePendingRewards() public {
        _deposit();
        vm.roll(block.number + 10);
        vm.warp(block.timestamp + 10);
        uint256 reward = tokenDistributor.calculatePendingRewards(Alice);
        assertNotEq(reward, 0);
    }
}

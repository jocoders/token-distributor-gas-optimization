// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILooksRareToken} from "../interfaces/ILookRareToken.sol";
import {TokenDistributorOptimized} from "../src/TokenDistributorOptimized.sol";

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
    TokenDistributorOptimized tokenDistributor;
    TokenLooksRare tokenLooksRare;
    TokenSplitter tokenSplitter;

    address Alice = makeAddr("Alice");
    uint256 private constant rewardsPerBlockForStaking = 1_000e18;
    uint256 private constant rewardsPerBlockForOthers = 8_000e18;
    uint256 private constant periodLengthesInBlocks = 100;

    uint256 private constant SALT = 8230383043340;

    function setUp() public {
        tokenLooksRare = new TokenLooksRare();
        tokenSplitter = new TokenSplitter();

        tokenDistributor = new TokenDistributorOptimized(
            tokenLooksRare,
            address(tokenSplitter),
            rewardsPerBlockForStaking,
            rewardsPerBlockForOthers,
            periodLengthesInBlocks,
            1,
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

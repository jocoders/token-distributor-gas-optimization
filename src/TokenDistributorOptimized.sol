// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeTransferLib} from "../lib/solady/src/utils/SafeTransferLib.sol";
import {ILooksRareToken} from "../interfaces/ILookRareToken.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title TokenDistributor
 * @notice It handles the distribution of LOOKS token.
 * It auto-adjusts block rewards over a set number of periods.
 */
contract TokenDistributorOptimized {
    using SafeTransferLib for address;

    struct StakingPeriod {
        uint256 rewardPerBlockForStaking;
        uint256 rewardPerBlockForOthers;
        uint256 periodLengthInBlock;
    }

    struct UserInfo {
        uint256 amount; // Amount of staked tokens provided by user
        uint256 rewardDebt; // Reward debt
    }

    uint256 public constant PRECISION_FACTOR = 10 ** 12;
    ILooksRareToken public immutable tokenLooksRare;

    address public immutable tokenSplitter;
    uint256 public immutable NUMBER_PERIODS;
    uint256 public immutable START_BLOCK;

    uint256 public accTokenPerShare;
    uint256 public currentPhase;
    uint256 public endBlock;
    uint256 public lastRewardBlock;
    uint256 public rewardPerBlockForOthers;
    uint256 public rewardPerBlockForStaking;
    uint256 public totalAmountStaked;

    mapping(uint256 => StakingPeriod) public stakingPeriod;
    mapping(address => UserInfo) public userInfo;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    event Compound(address indexed user, uint256 harvestedAmount);
    event Deposit(address indexed user, uint256 amount, uint256 harvestedAmount);
    event NewRewardsPerBlock(
        uint256 indexed currentPhase,
        uint256 startBlock,
        uint256 rewardPerBlockForStaking,
        uint256 rewardPerBlockForOthers
    );
    event Withdraw(address indexed user, uint256 amount, uint256 harvestedAmount);

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor(
        ILooksRareToken _tokenLooksRare,
        address _tokenSplitter,
        uint256 _rewardsPerBlockForStaking,
        uint256 _rewardsPerBlockForOthers,
        uint256 _periodLengthesInBlocks,
        uint256 _startBlock,
        uint256 _numberPeriods
    ) {
        tokenLooksRare = _tokenLooksRare;
        tokenSplitter = _tokenSplitter;

        rewardPerBlockForStaking = _rewardsPerBlockForStaking;
        rewardPerBlockForOthers = _rewardsPerBlockForOthers;

        endBlock = _startBlock + _periodLengthesInBlocks;
        lastRewardBlock = _startBlock;

        START_BLOCK = _startBlock;
        NUMBER_PERIODS = _numberPeriods;
    }

    function deposit(uint256 amount) external nonReentrant {
        require(amount > 0, "Deposit: Amount must be > 0");

        _updatePool();

        address(tokenLooksRare).safeTransferFrom(msg.sender, address(this), amount);

        uint256 pendingRewards;
        uint256 userAmount = userInfo[msg.sender].amount;

        uint256 _accTokenPerShare = accTokenPerShare;

        if (userAmount > 0) {
            pendingRewards = ((userAmount * _accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;
        }

        // Adjust user information
        userAmount += (amount + pendingRewards);

        userInfo[msg.sender].rewardDebt = (userAmount * _accTokenPerShare) / PRECISION_FACTOR;
        userInfo[msg.sender].amount += userAmount;

        // Increase totalAmountStaked
        totalAmountStaked += (amount + pendingRewards);

        emit Deposit(msg.sender, amount, pendingRewards);
    }

    /**
     * @notice Compound based on pending rewards
     */
    function harvestAndCompound() external nonReentrant {
        _updatePool();
        uint256 _accTokenPerShare = accTokenPerShare;
        uint256 userAmount = userInfo[msg.sender].amount;
        uint256 pendingRewards = ((userAmount * _accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;

        if (pendingRewards == 0) return;

        userAmount += pendingRewards;
        totalAmountStaked += pendingRewards;

        userInfo[msg.sender].rewardDebt = (userAmount * _accTokenPerShare) / PRECISION_FACTOR;
        userInfo[msg.sender].amount += pendingRewards;

        emit Compound(msg.sender, pendingRewards);
    }

    /**
     * @notice Update pool rewards
     */
    function updatePool() external nonReentrant {
        _updatePool();
    }

    /**
     * @notice Withdraw staked tokens and compound pending rewards
     * @param amount amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        uint256 userAmount = userInfo[msg.sender].amount;
        require((userAmount >= amount) && (amount > 0), "Withdraw: Amount must be > 0 or lower than user balance");
        uint256 _accTokenPerShare = accTokenPerShare;

        _updatePool();

        uint256 pendingRewards = ((userAmount * _accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;

        // Adjust user information
        userInfo[msg.sender].amount = userAmount + pendingRewards - amount;
        userInfo[msg.sender].rewardDebt = (userInfo[msg.sender].amount * _accTokenPerShare) / PRECISION_FACTOR;

        // Adjust total amount staked
        totalAmountStaked = totalAmountStaked + pendingRewards - amount;

        // Transfer LOOKS tokens to the sender
        address(tokenLooksRare).safeTransfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount, pendingRewards);
    }

    /**
     * @notice Withdraw all staked tokens and collect tokens
     */
    function withdrawAll() external nonReentrant {
        uint256 userAmount = userInfo[msg.sender].amount;
        require(userAmount > 0, "Withdraw: Amount must be > 0");

        // Update pool
        _updatePool();

        // Calculate pending rewards and amount to transfer (to the sender)
        uint256 pendingRewards = ((userAmount * accTokenPerShare) / PRECISION_FACTOR) - userInfo[msg.sender].rewardDebt;
        uint256 amountToTransfer = userAmount + pendingRewards;

        // Adjust total amount staked
        totalAmountStaked = totalAmountStaked - userAmount;

        // Adjust user information
        userInfo[msg.sender].amount = 0;
        userInfo[msg.sender].rewardDebt = 0;

        address(tokenLooksRare).safeTransfer(msg.sender, amountToTransfer);
        emit Withdraw(msg.sender, amountToTransfer, pendingRewards);
    }

    function calculatePendingRewards(address user) external view returns (uint256 reward) {
        uint256 blockNumber = block.number;
        uint256 _lastRewardBlock = lastRewardBlock;
        uint256 _totalAmountStaked = totalAmountStaked;

        if ((blockNumber > _lastRewardBlock) && (_totalAmountStaked != 0)) {
            uint256 multiplier = _getMultiplier(_lastRewardBlock, blockNumber);
            uint256 tokenRewardForStaking = multiplier * rewardPerBlockForStaking;
            uint256 adjustedEndBlock = endBlock;
            uint256 adjustedCurrentPhase = currentPhase;

            // Check whether to adjust multipliers and reward per block
            while ((blockNumber > adjustedEndBlock) && (adjustedCurrentPhase < (NUMBER_PERIODS - 1))) {
                // Update current phase
                adjustedCurrentPhase++;

                // Update rewards per block
                uint256 adjustedRewardPerBlockForStaking = stakingPeriod[adjustedCurrentPhase].rewardPerBlockForStaking;

                // Calculate adjusted block number
                uint256 previousEndBlock = adjustedEndBlock;
                uint256 periodLengthInBlock = stakingPeriod[adjustedCurrentPhase].periodLengthInBlock;

                // Update end block
                adjustedEndBlock = previousEndBlock + periodLengthInBlock;

                // Calculate new multiplier
                uint256 newMultiplier =
                    (blockNumber <= adjustedEndBlock) ? (blockNumber - previousEndBlock) : periodLengthInBlock;

                // Adjust token rewards for staking
                tokenRewardForStaking += (newMultiplier * adjustedRewardPerBlockForStaking);
            }

            uint256 adjustedTokenPerShare =
                accTokenPerShare + (tokenRewardForStaking * PRECISION_FACTOR) / _totalAmountStaked;

            reward = (userInfo[user].amount * adjustedTokenPerShare) / PRECISION_FACTOR - userInfo[user].rewardDebt;
        } else {
            reward = (userInfo[user].amount * accTokenPerShare) / PRECISION_FACTOR - userInfo[user].rewardDebt;
        }
    }

    /**
     * @notice Update reward variables of the pool
     */
    function _updatePool() internal {
        uint256 blockNumber = block.number;
        uint256 _lastRewardBlock = lastRewardBlock;
        uint256 _totalAmountStaked = totalAmountStaked;

        if (blockNumber <= _lastRewardBlock) {
            return;
        }

        if (_totalAmountStaked == 0) {
            lastRewardBlock = blockNumber;
            return;
        }

        // Calculate multiplier
        uint256 multiplier = _getMultiplier(_lastRewardBlock, blockNumber);

        uint256 _rewardPerBlockForStaking = rewardPerBlockForStaking;
        uint256 _rewardPerBlockForOthers = rewardPerBlockForOthers;

        // Calculate rewards for staking and others
        uint256 tokenRewardForStaking = multiplier * _rewardPerBlockForStaking;
        uint256 tokenRewardForOthers = multiplier * _rewardPerBlockForOthers;
        uint256 _endBlock = endBlock;
        uint256 _currentPhase = currentPhase;

        // Check whether to adjust multipliers and reward per block
        while ((blockNumber > _endBlock) && (_currentPhase < (NUMBER_PERIODS - 1))) {
            // Update rewards per block
            _updateRewardsPerBlock(_endBlock);

            uint256 previousEndBlock = _endBlock;

            // Adjust the end block
            _endBlock += stakingPeriod[_currentPhase].periodLengthInBlock;

            // Adjust multiplier to cover the missing periods with other lower inflation schedule
            uint256 newMultiplier = _getMultiplier(previousEndBlock, block.number);

            // Adjust token rewards
            tokenRewardForStaking += (newMultiplier * _rewardPerBlockForStaking);
            tokenRewardForOthers += (newMultiplier * _rewardPerBlockForOthers);
        }

        // Mint tokens only if token rewards for staking are not null
        if (tokenRewardForStaking > 0) {
            // It allows protection against potential issues to prevent funds from being locked
            bool mintStatus = tokenLooksRare.mint(address(this), tokenRewardForStaking);
            if (mintStatus) {
                accTokenPerShare = accTokenPerShare + ((tokenRewardForStaking * PRECISION_FACTOR) / _totalAmountStaked);
            }

            tokenLooksRare.mint(tokenSplitter, tokenRewardForOthers);
        }

        // Update last reward block only if it wasn't updated after or at the end block
        if (_lastRewardBlock <= _endBlock) {
            lastRewardBlock = blockNumber;
        }

        endBlock = _endBlock;
    }

    function _updateRewardsPerBlock(uint256 _newStartBlock) internal {
        currentPhase++;
        uint256 _currentPhase = currentPhase;

        rewardPerBlockForStaking = stakingPeriod[_currentPhase].rewardPerBlockForStaking;
        rewardPerBlockForOthers = stakingPeriod[_currentPhase].rewardPerBlockForOthers;

        emit NewRewardsPerBlock(_currentPhase, _newStartBlock, rewardPerBlockForStaking, rewardPerBlockForOthers);
    }

    function _getMultiplier(uint256 from, uint256 to) internal view returns (uint256 multiplier) {
        if (to <= endBlock) {
            multiplier = to - from;
        } else if (from >= endBlock) {
            multiplier = 0;
        } else {
            multiplier = endBlock - from;
        }
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ILooksRareToken is IERC20 {
  function SUPPLY_CAP() external view returns (uint256);

  function mint(address account, uint256 amount) external returns (bool);
}

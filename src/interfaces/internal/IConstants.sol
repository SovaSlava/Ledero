// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

uint8 constant LENDING_PREFIX = 0x1;
uint8 constant FLASH_PREFIX = 0x2;
uint8 constant SWAP_PREFIX = 0x3;
uint256 constant PREFIX_SHIFT = 140;
uint256 constant MIN_SAFE_HF = 1.05e18;
bytes32 constant _PARAMS_SLOT = keccak256("ledero.transient.params");
bytes32 constant _OPERATION_SLOT = keccak256("ledero.transient.operation");

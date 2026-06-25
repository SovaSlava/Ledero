// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {AaveHelper} from "./AaveHelper.t.sol";
import {CompoundHelper} from "./CompoundHelper.t.sol";

abstract contract LederoHelper is AaveHelper, CompoundHelper {}

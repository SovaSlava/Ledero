// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IFlashLoanAdapter} from "../../interfaces/internal/IFlashLoanAdapter.sol";
import {ILedero} from "../../interfaces/ILedero.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IBalancerVault {
    function unlock(bytes calldata data) external;
    function settle(address token, uint256 amount) external;
    function sendTo(address token, address to, uint256 amount) external;
    function getFlashLoanFee(address token, uint256 amount) external view returns (uint256);
}

// https://docs.balancer.fi/concepts/vault/flash-loans.html
contract BalancerV3Adapter is IFlashLoanAdapter {
    using SafeERC20 for IERC20;
    IBalancerVault public immutable VAULT;
    address public immutable LEDERO;
    address transient _token;
    uint256 transient _amount;

    error OnlyLedero();
    error OnlyVault();
    modifier onlyLedero() {
        require(msg.sender == LEDERO, OnlyLedero());
        _;
    }

    constructor(address _vault, address _ledero) {
        VAULT = IBalancerVault(_vault);
        LEDERO = _ledero;
    }

    function getFullRepayAmount(address token, uint256 amount) external pure override returns (uint256) {
        uint256 repayAmount;
        // No fee
        return amount;
    }

    function executeFlashLoan(address token, uint256 amount) external override onlyLedero {
        _token = token;
        _amount = amount;
        bytes memory callbackData = abi.encodeWithSelector(this.balancerCallback.selector);

        VAULT.unlock(callbackData);
    }

    function balancerCallback() external {
        require(msg.sender == address(VAULT), OnlyVault());
        address token = _token;
        uint256 amount = _amount;
        _token = address(0);
        _amount = 0;
        VAULT.sendTo(token, LEDERO, amount);
        ILedero(LEDERO).receiveFlashLoan();
    }

    function repayFunds(address token, uint256 amount) external override onlyLedero {
        IERC20(token).safeTransferFrom(LEDERO, address(VAULT), amount);
        VAULT.settle(token, amount);
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}

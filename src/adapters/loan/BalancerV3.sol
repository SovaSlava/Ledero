// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {IFlashLoanAdapter} from "../../interfaces/internal/IFlashLoanAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AdapterAction} from "../../interfaces/internal/ILederoTypes.sol";

interface IBalancerVault {
    function unlock(bytes calldata data) external;
    function settle(address token, uint256 amount) external;
    function sendTo(address token, address to, uint256 amount) external;
    function getFlashLoanFee(address token, uint256 amount) external view returns (uint256);
}

///  https://docs.balancer.fi/concepts/vault/flash-loans.html
contract BalancerV3Adapter is IFlashLoanAdapter {
    address public immutable VAULT;

    constructor(address _vault) {
        VAULT = _vault;
    }

    function getFullRepayAmount(address, uint256 amount) external pure override returns (uint256) {
        // No fee
        return amount;
    }

    function takeFundsFirstStep(
        address,
        /* token */
        uint256,
        /* amount */
        bytes calldata userData
    )
        external
        view
        override
        returns (AdapterAction[] memory actions)
    {
        actions = new AdapterAction[](1);
        actions[0] = AdapterAction({
            target: VAULT,
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IBalancerVault.unlock.selector, userData)
        });
    }

    function takeFundsSecondStep(address token, uint256 amount)
        external
        view
        override
        returns (AdapterAction[] memory actions)
    {
        actions = new AdapterAction[](1);

        actions[0] = AdapterAction({
            target: VAULT,
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IBalancerVault.sendTo.selector, token, msg.sender, amount)
        });
    }

    function repayFunds(address token, uint256 amount) external view override returns (AdapterAction[] memory actions) {
        actions = new AdapterAction[](2);

        actions[0] = AdapterAction({
            target: token,
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IERC20.transfer.selector, VAULT, amount)
        });

        actions[1] = AdapterAction({
            target: VAULT,
            approveToken: address(0),
            approveAmount: 0,
            callData: abi.encodeWithSelector(IBalancerVault.settle.selector, token, amount)
        });
    }

    function getVersion() external pure returns (uint256) {
        return 1;
    }
}

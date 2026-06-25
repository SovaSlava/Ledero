pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockAavePool {
    function supply(address asset, uint256 amount, address, uint16) external {
        bool success = IERC20(asset).transferFrom(msg.sender, address(this), amount);
        require(success, "TransferFrom failed in MockPool");
    }
}

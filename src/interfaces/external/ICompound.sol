// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

interface IComet {
    function supply(address asset, uint256 amount) external;
    function withdraw(address asset, uint256 amount) external;
    function collateralBalanceOf(address account, address asset) external view returns (uint256);
    function isBorrowCollateralized(address account) external view returns (bool);
    function borrowBalanceOf(address account) external view returns (uint256);
    function baseTokenPriceFeed() external view returns (address);
    function getPrice(address priceFeed) external view returns (uint256);
    function baseScale() external view returns (uint256);

    struct AssetInfo {
        uint8 offset;
        address asset;
        address priceFeed;
        uint64 scale;
        uint64 borrowCollateralFactor;
        uint64 liquidateCollateralFactor;
        uint64 liquidationFactor;
        uint128 supplyCap;
    }

    function getAssetInfoByAddress(address asset) external view returns (AssetInfo memory);
}

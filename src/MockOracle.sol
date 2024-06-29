// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract MockOracle {
    int256 private _price;
    uint8 private _decimals;

    constructor(int256 initialPrice, uint8 initialDecimals) {
        _price = initialPrice;
        _decimals = initialDecimals;
    }

    function setLatestPrice(int256 price) external {
        _price = price;
    }

    function getLatestPrice() external view returns (int256) {
        return _price;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

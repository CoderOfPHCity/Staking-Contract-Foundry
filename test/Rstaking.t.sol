// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Rstaking} from "../src/Rstaking.sol";
import {MockOracle} from "../src/MockOracle.sol";

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// interface MockOracle {
//     function getLatestPrice() external view returns (int256);
//     function decimals() external view returns (uint8);
// }
contract StakeToken is ERC20 {
    constructor() ERC20("Stak Token", "STK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

contract CounterTest is Test {
    Rstaking public rstaking;
    StakeToken public stakeToken;
    MockOracle public mockOracle;

    address daoWallet = makeAddr("Fake Address");
    address agantem = makeAddr("Agantem");
    //address daoWalle = mkdir("stakingtoken");
    address penaltyAddress = address(0);
    address deployer = address(0xA);

    function setUp() public {
        vm.prank(deployer);
        stakeToken = new StakeToken();
        mockOracle = new MockOracle(1, 1);

        rstaking = new Rstaking(deployer, address(stakeToken), address(mockOracle), daoWallet, penaltyAddress);
    }

    function testMIN_LOCKUP_PERIOD() public {
        uint256 amount = 0;
        uint256 lockupPeriod = 1 days;
        uint256 apy = 1;

        vm.expectRevert("Cannot stake 0");
        rstaking.stake(amount, 1);
    }

    function teststakeStateChange() public {
        vm.startPrank(deployer);
        uint256 amount = 1000;
        uint256 lockupPeriod = 5 days;
        uint256 apy = 1;
        uint256 balanceBefore = stakeToken.balanceOf(address(rstaking));
        stakeToken.approve(address(rstaking), amount);

        rstaking.stake(1000, 1);
        uint256 balanceAfter = stakeToken.balanceOf(address(rstaking));
        assertLt(balanceBefore, balanceAfter);
    }

    function testMultipleStakeOption() public {
        vm.startPrank(deployer);
        uint256 amount = 10000;
        stakeToken.approve(address(rstaking), amount);
        rstaking.stake(2000, 1);
        rstaking.stake(1500, 2);
    }

    function testMultipleStakeOptionStakeAmont() public {
        vm.startPrank(deployer);
        uint256 amount = 1000;
        stakeToken.approve(address(rstaking), amount);
        rstaking.stake(1000, 1);
        vm.expectRevert("Allowance not enough");
        rstaking.stake(10000000, 2);
    }

    function testINVALIDSTAKEOPTION() public {
        vm.startPrank(agantem);
        uint256 amount = 1000;
        stakeToken.approve(address(rstaking), amount);
        vm.expectRevert("Invalid staking option");
        rstaking.stake(10000000, 10);
    }

    function testWithdraw() public {
        vm.startPrank(deployer);
        uint256 amount = 1000;
        stakeToken.approve(address(rstaking), amount);
        rstaking.stake(1000, 1);
        vm.warp(block.timestamp + 10 days);
        rstaking.withdraw(1, 100);
    }

    function testMultipleWithdraw() public {
        vm.startPrank(deployer);
        uint256 amount = 1000;
        stakeToken.approve(address(rstaking), amount);
        rstaking.stake(1000, 1);
        vm.warp(block.timestamp + 10 days);
        rstaking.withdraw(1, 100);
        rstaking.withdraw(1, 100);
    }
}

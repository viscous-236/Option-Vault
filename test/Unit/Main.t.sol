// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Main} from "../../src/main.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Create simple mocks
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MainTest is Test {
    Main private main;
    MockERC20 private usdc;
    MockERC20 private weth;

    function setUp() public {
        // Deploy mock tokens
        usdc = new MockERC20("USD Coin", "USDC");
        weth = new MockERC20("Wrapped Ether", "WETH");

        // Deploy your main contract with token addresses
        main = new Main(address(usdc), address(weth));

        // Mint some test tokens to this test contract
        usdc.mint(address(this), 1_000_000e6); // 1 million USDC (assuming 6 decimals)
        weth.mint(address(this), 100 ether);
    }

    function testInitialSetup() public {
        console.log("Main deployed at:", address(main));
        console.log("USDC balance:", usdc.balanceOf(address(this)));
        console.log("WETH balance:", weth.balanceOf(address(this)));
    }
}

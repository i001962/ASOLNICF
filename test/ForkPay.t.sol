// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GeneralizedMetalogTable.sol";

/// @notice Fork test against Base mainnet: verifies minting pays the REAL
///         revnet (project 13) through the real terminal, with the minter
///         as beneficiary. Run: forge test --match-contract ForkPay --fork-url https://mainnet.base.org
contract ForkPay is Test {
    GeneralizedMetalogTable table;
    address constant TERMINAL = 0x130f5Dd2bD8805443Cf41755253D778a75a67f53;
    bytes32 constant ROOT = 0x8881e0a19020bfa3fd40c9e9f00242dc4d9e9b87af47e9b9a7e97191008847a4;
    uint256 constant PRICE = 0.005 ether;

    function setUp() public {
        table = new GeneralizedMetalogTable(ROOT, PRICE, TERMINAL);
    }

    function testMintPaysRealRevnet() public {
        string memory json = vm.readFile("test/fixture.json");
        int256[] memory vals = abi.decode(vm.parseJson(json, ".sections[0].values"), (int256[]));
        bytes32[] memory proof = abi.decode(vm.parseJson(json, ".sections[0].proof"), (bytes32[]));
        int256[9] memory arr;
        for (uint256 i = 0; i < 9; i++) arr[i] = vals[i];

        address minter = address(0xBEEF);
        vm.deal(minter, 1 ether);

        uint256 terminalBefore = TERMINAL.balance;
        vm.prank(minter);
        table.mint{value: PRICE}(0, arr, proof);

        assertEq(table.ownerOf(0), minter);
        assertTrue(TERMINAL.balance >= terminalBefore + PRICE, "revnet did not receive funds");
        emit log_named_uint("terminal balance increase (wei)", TERMINAL.balance - terminalBefore);
    }
}

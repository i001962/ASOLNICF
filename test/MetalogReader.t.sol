// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GeneralizedMetalogTable.sol";
import "../src/MetalogReader.sol";

contract MockTerminal2 {
    function pay(
        uint256,
        address,
        uint256,
        address,
        uint256,
        string calldata,
        bytes calldata
    ) external payable returns (uint256) {
        return 0;
    }
}

/// @notice Verifies the on-chain reader against a float64 Python reference that
///         implements the identical algorithm (bilinear interp + metalog eval).
contract MetalogReaderTest is Test {
    GeneralizedMetalogTable table;
    MetalogReader reader;
    uint256 constant PRICE = 0.005 ether;

    function setUp() public {
        string memory json = vm.readFile("test/reader_fixture.json");
        bytes32 root = abi.decode(vm.parseJson(json, ".merkleRoot"), (bytes32));
        table = new GeneralizedMetalogTable(root, PRICE, address(new MockTerminal2()));

        uint256[] memory ids = abi.decode(vm.parseJson(json, ".sections[*].id"), (uint256[]));
        address minter = address(0xBEEF);
        vm.deal(minter, 100 ether);
        for (uint256 s = 0; s < ids.length; s++) {
            string memory base = string.concat(".sections[", vm.toString(s), "]");
            uint256 id = abi.decode(vm.parseJson(json, string.concat(base, ".id")), (uint256));
            int256[] memory v = abi.decode(vm.parseJson(json, string.concat(base, ".values")), (int256[]));
            bytes32[] memory proof =
                abi.decode(vm.parseJson(json, string.concat(base, ".proof")), (bytes32[]));
            int256[9] memory arr;
            for (uint256 i = 0; i < 9; i++) arr[i] = v[i];
            vm.prank(minter);
            table.mint{value: PRICE}(id, arr, proof);
        }
        reader = new MetalogReader(address(table));
    }

    function testQuantilesMatchReference() public view {
        string memory json = vm.readFile("test/reader_fixture.json");
        uint256 n = abi.decode(vm.parseJson(json, ".nCases"), (uint256));
        for (uint256 i = 0; i < n; i++) {
            string memory base = string.concat(".cases[", vm.toString(i), "]");
            uint256 sigma1e12 = abi.decode(vm.parseJson(json, string.concat(base, ".sigma1e12")), (uint256));
            uint256 nn = abi.decode(vm.parseJson(json, string.concat(base, ".n")), (uint256));
            uint256 p50Wad = abi.decode(vm.parseJson(json, string.concat(base, ".p50Wad")), (uint256));
            uint256 yWad = abi.decode(vm.parseJson(json, string.concat(base, ".yWad")), (uint256));
            uint256 expected = abi.decode(vm.parseJson(json, string.concat(base, ".expectedWad")), (uint256));

            uint256 got = reader.quantileOfSum(sigma1e12, nn, p50Wad, yWad);
            uint256 diff = got > expected ? got - expected : expected - got;
            uint256 tol = expected / 1e6 + 1; // 1e-6 relative
            assertLe(diff, tol, string.concat("case ", vm.toString(i), " out of tolerance"));
        }
    }

    function testAvgIsSumOverN() public view {
        // sigma=0.5e12, n=30, p50=1, y=0.25
        uint256 s = reader.quantileOfSum(500000000000, 30, 1e18, 0.25e18);
        uint256 a = reader.quantileOfAvg(500000000000, 30, 1e18, 0.25e18);
        assertApproxEqRel(a * 30, s, 1e12); // 1e-6 relative
    }

    function testRevertsOutOfRange() public {
        vm.expectRevert(MetalogReader.OutOfRange.selector);
        reader.quantileOfSum(2e12, 10, 1e18, 0.5e18); // sigma > 1.8
        vm.expectRevert(MetalogReader.OutOfRange.selector);
        reader.quantileOfSum(0.5e12, 1001, 1e18, 0.5e18); // n > 1000
    }

    function testRevertsBadProbability() public {
        vm.expectRevert(MetalogReader.BadProbability.selector);
        reader.quantileOfSum(0.5e12, 10, 1e18, 0);
        vm.expectRevert(MetalogReader.BadProbability.selector);
        reader.quantileOfSum(0.5e12, 10, 1e18, 1e18);
    }
}

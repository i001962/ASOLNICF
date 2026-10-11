// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GeneralizedMetalogTable.sol";
import "../src/MetalogArt.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract MockTerminalArt {
    uint256 public totalReceived;
    function pay(
        uint256, address, uint256 amount, address, uint256, string calldata, bytes calldata
    ) external payable returns (uint256) {
        totalReceived += msg.value;
        return 0;
    }
}

contract MetalogArtTest is Test {
    GeneralizedMetalogTable table;
    MetalogArt art;
    MockTerminalArt terminal;
    uint256 constant TABLE_PRICE = 0.005 ether;
    uint256 constant ART_PRICE = 0.002 ether;

    // section ids from fixture: 0 (sigma 0.04, N 1), 1000, 2203
    function setUp() public {
        string memory json = vm.readFile("test/fixture.json");
        bytes32 root = abi.decode(vm.parseJson(json, ".merkleRoot"), (bytes32));
        terminal = new MockTerminalArt();
        table = new GeneralizedMetalogTable(root, TABLE_PRICE, address(terminal));
        art = new MetalogArt(address(table), ART_PRICE, address(terminal));

        address minter = address(0xBEEF);
        vm.deal(minter, 10 ether);
        for (uint256 s = 0; s < 3; s++) {
            string memory base = string.concat(".sections[", vm.toString(s), "]");
            uint256 id = abi.decode(vm.parseJson(json, string.concat(base, ".id")), (uint256));
            int256[] memory v = abi.decode(vm.parseJson(json, string.concat(base, ".values")), (int256[]));
            bytes32[] memory proof =
                abi.decode(vm.parseJson(json, string.concat(base, ".proof")), (bytes32[]));
            int256[9] memory arr;
            for (uint256 i = 0; i < 9; i++) arr[i] = v[i];
            vm.prank(minter);
            table.mint{value: TABLE_PRICE}(id, arr, proof);
        }
    }

    function testMintArt() public {
        address collector = address(0xCAFE);
        vm.deal(collector, 1 ether);
        uint256 sectionId = 0; // sigma 0.04, N 1

        vm.prank(collector);
        art.mintArt{value: ART_PRICE}(sectionId);

        assertEq(art.ownerOf(sectionId), collector);
        assertTrue(art.artMinted(sectionId));
        assertEq(art.artBy(sectionId), collector);
        assertEq(art.totalArtMinted(), 1);
        assertEq(terminal.totalReceived(), 3 * TABLE_PRICE + ART_PRICE);
    }

    function testMintArtBatch() public {
        address collector = address(0xCAFE);
        vm.deal(collector, 1 ether);
        uint256[] memory ids = new uint256[](3);
        ids[0] = 0;
        ids[1] = 1000;
        ids[2] = 2203;

        vm.prank(collector);
        art.mintArtBatch{value: ART_PRICE * 3}(ids);

        assertEq(art.totalArtMinted(), 3);
        assertEq(art.ownerOf(1000), collector);
        assertEq(terminal.totalReceived(), 3 * TABLE_PRICE + 3 * ART_PRICE);
    }

    function testMintArtRevertsIfNotInscribed() public {
        address collector = address(0xCAFE);
        vm.deal(collector, 1 ether);
        vm.prank(collector);
        vm.expectRevert(MetalogArt.NotInscribed.selector);
        art.mintArt{value: ART_PRICE}(5); // not inscribed in setUp
    }

    function testMintArtRevertsIfAlreadyMinted() public {
        address collector = address(0xCAFE);
        vm.deal(collector, 1 ether);
        vm.prank(collector);
        art.mintArt{value: ART_PRICE}(0);
        vm.prank(collector);
        vm.expectRevert(MetalogArt.AlreadyMinted.selector);
        art.mintArt{value: ART_PRICE}(0);
    }

    function testTokenUriIsValidSvg() public {
        address collector = address(0xCAFE);
        vm.deal(collector, 1 ether);
        vm.prank(collector);
        art.mintArt{value: ART_PRICE}(2203); // sigma 1.8, N 1000 (high vol)

        string memory uri = art.tokenURI(2203);
        // data:application/json;base64,
        bytes memory uriBytes = bytes(uri);
        assertTrue(_startsWith(uri, "data:application/json;base64,"));

        // Decode the JSON and check it contains an SVG image
        string memory jsonB64 = _substring(uri, 29, uriBytes.length);
        string memory jsonStr = string(Base64.decode(jsonB64));
        assertTrue(_contains(jsonStr, '"name":"Metalog Portrait #2203"'));
        assertTrue(_contains(jsonStr, "data:image/svg+xml;base64,"));

        // Extract and decode the SVG, verify structure
        uint256 imgStart = _indexOf(jsonStr, "data:image/svg+xml;base64,") + 26;
        uint256 imgEnd = _indexOfFrom(jsonStr, '"', imgStart);
        string memory svgB64 = _substring(jsonStr, imgStart, imgEnd);
        string memory svg = string(Base64.decode(svgB64));
        assertTrue(_startsWith(svg, "<svg"));
        assertTrue(_contains(svg, "</svg>"));
        assertTrue(_contains(svg, "<path"));
        assertTrue(_contains(svg, "METALOG DISTRIBUTION"));
        // High sigma -> warm palette (hue 40-90)
        assertTrue(_contains(svg, "hsl(40,") || _contains(svg, "hsl(5"));
    }

    function testTableMintBatch() public {
        string memory json = vm.readFile("test/fixture.json");
        address minter = address(0xBEEF);
        vm.deal(minter, 10 ether);

        // mintBatch tested via a fresh table to avoid double-inscribe
        MockTerminalArt t2 = new MockTerminalArt();
        bytes32 root = abi.decode(vm.parseJson(json, ".merkleRoot"), (bytes32));
        GeneralizedMetalogTable table2 = new GeneralizedMetalogTable(root, TABLE_PRICE, address(t2));

        uint256[] memory ids = new uint256[](2);
        int256[9][] memory vals = new int256[9][](2);
        bytes32[][] memory proofs = new bytes32[][](2);
        for (uint256 s = 0; s < 2; s++) {
            string memory base = string.concat(".sections[", vm.toString(s), "]");
            ids[s] = abi.decode(vm.parseJson(json, string.concat(base, ".id")), (uint256));
            int256[] memory v = abi.decode(vm.parseJson(json, string.concat(base, ".values")), (int256[]));
            for (uint256 i = 0; i < 9; i++) vals[s][i] = v[i];
            proofs[s] = abi.decode(vm.parseJson(json, string.concat(base, ".proof")), (bytes32[]));
        }
        vm.prank(minter);
        table2.mintBatch{value: TABLE_PRICE * 2}(ids, vals, proofs);
        assertEq(table2.totalInscribed(), 2);
        assertEq(table2.ownerOf(ids[0]), minter);
        assertEq(t2.totalReceived(), TABLE_PRICE * 2);
    }

    // --- string helpers ---
    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(prefix);
        if (sb.length < pb.length) return false;
        for (uint256 i = 0; i < pb.length; i++) if (sb[i] != pb[i]) return false;
        return true;
    }
    function _contains(string memory s, string memory sub) internal pure returns (bool) {
        return _indexOf(s, sub) < bytes(s).length;
    }
    function _indexOf(string memory s, string memory sub) internal pure returns (uint256) {
        return _indexOfFrom(s, sub, 0);
    }
    function _indexOfFrom(string memory s, string memory sub, uint256 from)
        internal pure returns (uint256)
    {
        bytes memory sb = bytes(s);
        bytes memory pb = bytes(sub);
        for (uint256 i = from; i + pb.length <= sb.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < pb.length; j++) {
                if (sb[i + j] != pb[j]) { found = false; break; }
            }
            if (found) return i;
        }
        return sb.length;
    }
    function _substring(string memory s, uint256 start, uint256 end)
        internal pure returns (string memory)
    {
        bytes memory sb = bytes(s);
        bytes memory out = new bytes(end - start);
        for (uint256 i = start; i < end; i++) out[i - start] = sb[i];
        return string(out);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/GeneralizedMetalogTable.sol";

/// @notice Mock Juicebox terminal: records pay calls instead of forwarding.
contract MockTerminal {
    struct PayCall {
        uint256 projectId;
        address token;
        uint256 amount;
        address beneficiary;
        uint256 value;
    }
    PayCall[] public pays;

    function pay(
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        uint256 minReturnedTokens,
        string calldata,
        bytes calldata
    ) external payable returns (uint256) {
        pays.push(PayCall(projectId, token, amount, beneficiary, msg.value));
        return 0;
    }
}

contract GeneralizedMetalogTableTest is Test {
    GeneralizedMetalogTable table;
    MockTerminal terminal;
    bytes32 root;
    uint256 constant PRICE = 0.005 ether;

    struct Section {
        uint256 id;
        int256[] values;
        bytes32[] proof;
    }
    Section[3] sections;

    function setUp() public {
        string memory json = vm.readFile("test/fixture.json");
        root = abi.decode(vm.parseJson(json, ".merkleRoot"), (bytes32));
        for (uint256 i = 0; i < 3; i++) {
            string memory base = string.concat(".sections[", vm.toString(i), "]");
            sections[i].id = abi.decode(vm.parseJson(json, string.concat(base, ".id")), (uint256));
            int256[] memory vals = abi.decode(
                vm.parseJson(json, string.concat(base, ".values")), (int256[])
            );
            sections[i].values = vals;
            bytes32[] memory proof = abi.decode(
                vm.parseJson(json, string.concat(base, ".proof")), (bytes32[])
            );
            sections[i].proof = proof;
        }
        terminal = new MockTerminal();
        table = new GeneralizedMetalogTable(root, PRICE, address(terminal));
    }

    function _asFixed(int256[] memory v) internal pure returns (int256[9] memory out) {
        for (uint256 i = 0; i < 9; i++) out[i] = v[i];
    }

    function testMintVerifiesProofAndForwardsToRevnet() public {
        address minter = address(0xBEEF);
        vm.deal(minter, 1 ether);
        int256[9] memory values = _asFixed(sections[0].values);

        vm.prank(minter);
        table.mint{value: PRICE}(sections[0].id, values, sections[0].proof);

        // NFT minted to the minter
        assertEq(table.ownerOf(sections[0].id), minter);
        // values stored on chain
        (int256[9] memory stored,) = _getCoeffs(sections[0].id);
        for (uint256 i = 0; i < 9; i++) assertEq(stored[i], values[i]);
        // provenance recorded
        assertEq(table.inscribedBy(sections[0].id), minter);
        assertEq(table.totalInscribed(), 1);
        // revnet got the full payment, minter is beneficiary
        (uint256 pid, address tok, uint256 amt, address bene, uint256 val) = terminal.pays(0);
        assertEq(pid, 13);
        assertEq(tok, 0x000000000000000000000000000000000000EEEe);
        assertEq(amt, PRICE);
        assertEq(bene, minter);
        assertEq(val, PRICE);
    }

    function testMintRejectsBadProof() public {
        address minter = address(0xBEEF);
        vm.deal(minter, 1 ether);
        int256[9] memory values = _asFixed(sections[1].values);
        values[0] += 1; // tamper: proof no longer matches
        vm.prank(minter);
        vm.expectRevert(GeneralizedMetalogTable.InvalidProof.selector);
        table.mint{value: PRICE}(sections[1].id, values, sections[1].proof);
    }

    function testMintRejectsDoubleInscription() public {
        address minter = address(0xBEEF);
        vm.deal(minter, 2 ether);
        int256[9] memory values = _asFixed(sections[2].values);
        vm.prank(minter);
        table.mint{value: PRICE}(sections[2].id, values, sections[2].proof);
        vm.prank(minter);
        vm.expectRevert(GeneralizedMetalogTable.AlreadyInscribed.selector);
        table.mint{value: PRICE}(sections[2].id, values, sections[2].proof);
    }

    function testMintRejectsUnderpayment() public {
        address minter = address(0xBEEF);
        vm.deal(minter, 1 ether);
        int256[9] memory values = _asFixed(sections[0].values);
        vm.prank(minter);
        vm.expectRevert(GeneralizedMetalogTable.InsufficientPayment.selector);
        table.mint{value: PRICE - 1}(sections[0].id, values, sections[0].proof);
    }

    function testBitmapAndLookup() public {
        address minter = address(0xBEEF);
        vm.deal(minter, 2 ether);
        for (uint256 s = 0; s < 3; s++) {
            vm.prank(minter);
            table.mint{value: PRICE}(sections[s].id, _asFixed(sections[s].values), sections[s].proof);
        }
        uint256[35] memory bitmap = table.inscribedBitmap();
        for (uint256 s = 0; s < 3; s++) {
            uint256 id = sections[s].id;
            assertTrue((bitmap[id >> 8] & (1 << (id & 255))) != 0);
        }
        // untouched cell reads zero
        uint256 other = (sections[0].id + 7) % 2204;
        assertTrue((bitmap[other >> 8] & (1 << (other & 255))) == 0);
        // grid lookup
        (uint256 si, uint256 ni) = table.sectionCoords(sections[1].id);
        (int256[9] memory c,) = _getCoeffs(sections[1].id);
        int256[9] memory via = table.getCoeffs(si, ni);
        for (uint256 i = 0; i < 9; i++) assertEq(via[i], c[i]);
    }

    function _getCoeffs(uint256 sectionId)
        internal
        view
        returns (int256[9] memory c, bool ok)
    {
        (uint256 si, uint256 ni) = table.sectionCoords(sectionId);
        try table.getCoeffs(si, ni) returns (int256[9] memory v) {
            return (v, true);
        } catch {
            return (c, false);
        }
    }
}

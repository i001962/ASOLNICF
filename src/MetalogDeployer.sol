// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./GeneralizedMetalogTable.sol";
import "./MetalogReader.sol";
import "./MetalogArt.sol";

/// @notice One-transaction deployer for the metalog table project.
///         Deploys the table, reader, and art contracts in order.
///         Used via a txlink so the user signs a single contract creation.
contract MetalogDeployer {
    GeneralizedMetalogTable public immutable table;
    MetalogReader public immutable reader;
    MetalogArt public immutable art;

    bytes32 public constant MERKLE_ROOT =
        0x8881e0a19020bfa3fd40c9e9f00242dc4d9e9b87af47e9b9a7e97191008847a4;
    address public constant REVNET_TERMINAL =
        0x130f5Dd2bD8805443Cf41755253D778a75a67f53;
    uint256 public constant MINT_PRICE = 0.005 ether;
    uint256 public constant ART_PRICE = 0.002 ether;

    constructor() {
        table = new GeneralizedMetalogTable(MERKLE_ROOT, MINT_PRICE, REVNET_TERMINAL);
        reader = new MetalogReader(address(table));
        art = new MetalogArt(address(table), ART_PRICE, REVNET_TERMINAL);
    }
}

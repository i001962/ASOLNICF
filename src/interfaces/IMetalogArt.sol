// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Consumer-facing interface for MetalogArt: generative on-chain SVG
///         portraits of the table's distributions. One portrait per section,
///         minted only after the section is inscribed. Token ID = section ID.
interface IMetalogArt is IERC721 {
    /// @notice Mint the portrait for an inscribed section.
    function mintArt(uint256 sectionId) external payable;

    /// @notice Mint portraits for several sections in one transaction.
    function mintArtBatch(uint256[] calldata sectionIds) external payable;

    /// @notice True once a section's portrait has been minted.
    function artMinted(uint256 sectionId) external view returns (bool);

    /// @notice The address that minted a section's portrait.
    function artBy(uint256 sectionId) external view returns (address);

    /// @notice Total portraits minted.
    function totalArtMinted() external view returns (uint256);

    /// @notice Price per portrait mint, forwarded to the revnet.
    function artPrice() external view returns (uint256);

    /// @notice The table contract this art reads from.
    function table() external view returns (address);
}

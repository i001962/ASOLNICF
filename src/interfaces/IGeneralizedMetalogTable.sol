// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice Consumer-facing interface for GeneralizedMetalogTable.
///         2,204 ERC-721 section NFTs; each inscription permanently stores the
///         9 metalog a-coefficients (scaled 1e12) for one (sigma, N) cell,
///         verified by merkle proof against an immutable root.
interface IGeneralizedMetalogTable is IERC721 {
    /// @notice Inscribe a cell's 9 a-coefficients. Forwards msg.value to the revnet.
    /// @param sectionId sigmaIdx * 116 + nIdx
    /// @param values 9 a-coefficients, scaled 1e12
    /// @param proof merkle proof against merkleRoot()
    function mint(uint256 sectionId, int256[9] calldata values, bytes32[] calldata proof)
        external
        payable;

    /// @notice Inscribe several cells in one transaction. One revnet payment for the total.
    function mintBatch(
        uint256[] calldata sectionIds,
        int256[9][] calldata values,
        bytes32[][] calldata proofs
    ) external payable;

    /// @notice The 9 inscribed a-coefficients (scaled 1e12) for a grid cell.
    ///         Reverts CellNotInscribed if the cell is not yet inscribed.
    function getCoeffs(uint256 sigmaIdx, uint256 nIdx)
        external
        view
        returns (int256[9] memory);

    /// @notice True once a cell's coefficients are permanently inscribed.
    function inscribed(uint256 sectionId) external view returns (bool);

    /// @notice The address that inscribed a cell (permanent provenance).
    function inscribedBy(uint256 sectionId) external view returns (address);

    /// @notice Number of cells inscribed so far (max 2204).
    function totalInscribed() external view returns (uint256);

    /// @notice True once all 2204 cells are inscribed.
    function isComplete() external view returns (bool);

    /// @notice Packed completion bitmap, 2204 bits in 35 words. Bit i = cell i inscribed.
    function inscribedBitmap() external view returns (uint256[35] memory);

    /// @notice Immutable merkle root over all 2204 cells.
    function merkleRoot() external view returns (bytes32);

    /// @notice Price per mint, forwarded in full to the revnet.
    function mintPrice() external view returns (uint256);

    /// @notice Juicebox project id receiving mint proceeds (13).
    function revnetProjectId() external view returns (uint256);

    /// @notice Juicebox terminal receiving mint proceeds.
    function revnetTerminal() external view returns (address);

    /// @notice sigma grid value at index i, scaled 1e12 (19 values, 0.04 .. 1.8).
    function sigmaAt(uint256 i) external view returns (uint256);

    /// @notice N grid value at index i (116 values, 1 .. 1000).
    function nAt(uint256 i) external view returns (uint256);

    /// @notice Grid coordinates for a section id.
    function sectionCoords(uint256 sectionId)
        external
        view
        returns (uint256 sigmaIdx, uint256 nIdx);
}

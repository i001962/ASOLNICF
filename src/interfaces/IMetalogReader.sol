// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Consumer-facing interface for MetalogReader, the shared on-chain
///         reader for the GeneralizedMetalogTable inscription project.
///
///         All functions are view. Given (sigma, N, p50, y) the reader brackets
///         the grid, reads the 4 surrounding cells, bilinearly interpolates the
///         9 a-coefficients, and evaluates the 9-term semi-bounded metalog
///         quantile function. Fixed point is wad (1e18) throughout; sigma is
///         scaled 1e12; y is a wad probability strictly in (0, 1e18).
interface IMetalogReader {
    /// @notice The table this reader reads from.
    function table() external view returns (address);

    /// @notice Quantile of the SUM of n IID LogNormal(mu, sigma) variates, wad.
    /// @param sigma1e12 sigma of ln(x), scaled 1e12 (grid 0.04 .. 1.8)
    /// @param n number of components (grid 1 .. 1000)
    /// @param p50Wad median of each component, wad
    /// @param y probability, wad, strictly in (0, 1e18)
    function quantileOfSum(uint256 sigma1e12, uint256 n, uint256 p50Wad, uint256 y)
        external
        view
        returns (uint256);

    /// @notice Quantile of the AVERAGE of n IID lognormals (= sum / n), wad.
    function quantileOfAvg(uint256 sigma1e12, uint256 n, uint256 p50Wad, uint256 y)
        external
        view
        returns (uint256);

    /// @notice The 9 bilinearly-interpolated a-coefficients (wad) at (sigma, n).
    function interpCoeffs(uint256 sigma1e12, uint256 n)
        external
        view
        returns (int256[9] memory);
}

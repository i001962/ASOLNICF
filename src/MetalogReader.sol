// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FixedPointMathLib} from "@solady/src/utils/FixedPointMathLib.sol";
import "./GeneralizedMetalogTable.sol";
import "./MetalogMath.sol";

/// @title MetalogReader
/// @notice The utility companion to GeneralizedMetalogTable: the shared on-chain
///         reader that turns inscribed a-coefficients into usable quantiles.
///
///         Given (sigma, N, p50, y) it:
///           1. brackets sigma and N in the table grid,
///           2. reads the 4 surrounding cells,
///           3. bilinearly interpolates the 9 a-coefficients (same method as the
///              generalized-metalog reference implementation),
///           4. evaluates the 9-term semi-bounded metalog quantile function.
///
///         All functions are view: free to call off-chain. Called on-chain, the
///         caller pays only the reads (~36 cold SLOADs worst case) plus fixed-
///         point math — on the order of 100k gas cold, ~25k warm.
///
///         Fixed point: wad (1e18) throughout. Table a-coeffs arrive scaled 1e12
///         and are upscaled once. y is a wad probability in (0, 1e18).
contract MetalogReader {
    int256 private constant WAD = 1e18;
    int256 private constant TABLE_TO_WAD = 1e6; // table scale 1e12 -> wad

    GeneralizedMetalogTable public immutable table;

    error OutOfRange();
    error BadProbability();

    constructor(address _table) {
        table = GeneralizedMetalogTable(_table);
    }

    /// @notice Quantile of the SUM of n IID LogNormal(mu, sigma) variates.
    /// @param sigma1e12  sigma of ln(x), scaled 1e12 (grid 0.04 .. 1.8)
    /// @param n          number of components (grid 1 .. 1000)
    /// @param p50Wad     median of each component, wad
    /// @param y          probability, wad, strictly in (0, 1e18)
    /// @return sum quantile, wad
    function quantileOfSum(uint256 sigma1e12, uint256 n, uint256 p50Wad, uint256 y)
        external
        view
        returns (uint256)
    {
        int256 ratio = _avgRatioWad(sigma1e12, n, y); // avg/p50, wad
        int256 avg = MetalogMath.mulWad(int256(p50Wad), ratio); // wad
        return uint256(int256(n) * avg);
    }

    /// @notice Quantile of the AVERAGE of n IID lognormals (= sum / n), wad.
    function quantileOfAvg(uint256 sigma1e12, uint256 n, uint256 p50Wad, uint256 y)
        external
        view
        returns (uint256)
    {
        int256 ratio = _avgRatioWad(sigma1e12, n, y);
        return uint256(MetalogMath.mulWad(int256(p50Wad), ratio));
    }

    /// @notice Interpolated a-coefficients (wad) at (sigma, n). Exposed so other
    ///         contracts can build their own evaluators on top of the table.
    function interpCoeffs(uint256 sigma1e12, uint256 n)
        external
        view
        returns (int256[9] memory)
    {
        return _interpCoeffs(sigma1e12, n);
    }

    // ---------------- internals ----------------

    function _avgRatioWad(uint256 sigma1e12, uint256 n, uint256 y)
        internal
        view
        returns (int256)
    {
        if (y == 0 || y >= uint256(WAD)) revert BadProbability();
        int256[9] memory coeffs = _interpCoeffs(sigma1e12, n);
        return int256(MetalogMath.evalRatio(coeffs, y));
    }

    /// @dev Bilinear interpolation of the 9 a-coeffs over the (sigma, N) grid.
    function _interpCoeffs(uint256 sigma1e12, uint256 n)
        internal
        view
        returns (int256[9] memory out)
    {
        (uint256 si0, uint256 si1, int256 alpha) = _bracketSigma(sigma1e12);
        (uint256 ni0, uint256 ni1, int256 beta) = _bracketN(n);
        int256[9] memory lo = _interpN(si0, ni0, ni1, beta);
        int256[9] memory hi = _interpN(si1, ni0, ni1, beta);
        for (uint256 k = 0; k < 9; k++) {
            out[k] = lo[k] + MetalogMath.mulWad(alpha, hi[k] - lo[k]);
        }
    }

    /// @dev Interpolate along N (beta) for one sigma row. Returns wad coeffs.
    function _interpN(uint256 si, uint256 ni0, uint256 ni1, int256 beta)
        internal
        view
        returns (int256[9] memory out)
    {
        int256[9] memory c0 = table.getCoeffs(si, ni0);
        int256[9] memory c1 = table.getCoeffs(si, ni1);
        for (uint256 k = 0; k < 9; k++) {
            int256 v0 = c0[k] * TABLE_TO_WAD;
            out[k] = v0 + MetalogMath.mulWad(beta, c1[k] * TABLE_TO_WAD - v0);
        }
    }

    /// @dev Bracket sigma1e12 in the grid. Returns (loIdx, hiIdx, alphaWad).
    function _bracketSigma(uint256 s)
        internal
        view
        returns (uint256 i0, uint256 i1, int256 alpha)
    {
        uint256 lo = table.sigmaAt(0);
        uint256 hi = table.sigmaAt(18);
        if (s < lo || s > hi) revert OutOfRange();
        uint256 a = 0;
        uint256 b = 18;
        while (b - a > 1) {
            uint256 m = (a + b) >> 1;
            if (table.sigmaAt(m) <= s) a = m; else b = m;
        }
        uint256 s0 = table.sigmaAt(a);
        uint256 s1 = table.sigmaAt(b);
        alpha = s0 == s1 ? int256(0) : int256((s - s0) * uint256(WAD) / (s1 - s0));
        return (a, b, alpha);
    }

    /// @dev Bracket n in the grid. Returns (loIdx, hiIdx, betaWad).
    function _bracketN(uint256 n)
        internal
        view
        returns (uint256 i0, uint256 i1, int256 beta)
    {
        if (n < 1 || n > 1000) revert OutOfRange();
        uint256 a = 0;
        uint256 b = 115;
        while (b - a > 1) {
            uint256 m = (a + b) >> 1;
            if (table.nAt(m) <= n) a = m; else b = m;
        }
        uint256 n0 = table.nAt(a);
        uint256 n1 = table.nAt(b);
        beta = n0 == n1 ? int256(0) : int256((n - n0) * uint256(WAD) / (n1 - n0));
        return (a, b, beta);
    }
}

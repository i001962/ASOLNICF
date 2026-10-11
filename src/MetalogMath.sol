// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {FixedPointMathLib} from "@solady/src/utils/FixedPointMathLib.sol";

/// @notice Shared fixed-point math for the 9-term semi-bounded metalog.
///         Quantile (avg/p50) = exp(M(y)), where
///         M(y) = a1 + a2*g + a3*d*g + a4*d + a5*d^2 + a6*d^2*g + a7*d^3 + a8*d^3*g + a9*d^4
///         g = ln(y/(1-y)), d = y - 0.5. All wad (1e18).
library MetalogMath {
    int256 internal constant WAD = 1e18;

    /// @notice Evaluate the metalog avg/p50 quantile at probability y.
    /// @param a 9 a-coefficients, wad.
    /// @param y probability, wad, strictly in (0, 1e18).
    /// @return avg/p50 quantile, wad.
    function evalRatio(int256[9] memory a, uint256 y) internal pure returns (uint256) {
        int256 d = int256(y) - WAD / 2;
        uint256 r = FixedPointMathLib.divWad(y, uint256(WAD) - y); // y/(1-y), wad > 0
        int256 g = FixedPointMathLib.lnWad(int256(r));
        int256[4] memory pw; // pw[i] = d^(i+1), wad
        pw[0] = d;
        pw[1] = mulWad(d, d);
        pw[2] = mulWad(pw[1], d);
        pw[3] = mulWad(pw[1], pw[1]);
        int256 m = a[0] + mulWad(a[1], g) + mulWad(a[3], d);
        m += mulWad(a[2], mulWad(d, g)) + mulWad(a[4], pw[1]);
        m += mulWad(a[5], mulWad(pw[1], g)) + mulWad(a[6], pw[2]);
        m += mulWad(a[7], mulWad(pw[2], g)) + mulWad(a[8], pw[3]);
        return uint256(FixedPointMathLib.expWad(m));
    }

    /// @dev Signed wad multiplication. Domain here: |x|,|y| <= ~1e20, so x*y
    ///      cannot overflow int256 (max ~5.8e76).
    function mulWad(int256 x, int256 y) internal pure returns (int256 z) {
        unchecked {
            z = (x * y) / WAD;
        }
    }
}

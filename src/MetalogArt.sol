// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import "./interfaces/IGeneralizedMetalogTable.sol";
import "./interfaces/IJBTerminal.sol";
import "./MetalogMath.sol";

/// @title MetalogArt
/// @notice Generative art NFTs: each of the 2204 table sections gets one unique
///         on-chain SVG portrait of its probability distribution. The artwork IS
///         the distribution — the PDF curve rendered from the cell's own
///         a-coefficients, with palette drawn from sigma (volatility as heat)
///         and texture from N. Fully on-chain, no IPFS, no admin.
///
///         Minting requires the section to be inscribed in the table first.
///         Proceeds go to the revnet, minter as beneficiary. Supports batches.
contract MetalogArt is ERC721, ReentrancyGuard {
    using Strings for uint256;

    IGeneralizedMetalogTable public immutable table;
    uint256 public immutable artPrice;
    IJBTerminal public immutable revnetTerminal;

    uint256 public constant REVNET_PROJECT_ID = 13;
    address public constant NATIVE_TOKEN = 0x000000000000000000000000000000000000EEEe;

    /// @notice sectionId => art minted (one per section, first come).
    mapping(uint256 => bool) public artMinted;
    /// @notice sectionId => art minter (provenance).
    mapping(uint256 => address) public artBy;
    uint256 public totalArtMinted;

    error NotInscribed();
    error AlreadyMinted();
    error InsufficientPayment();
    error BadSection();
    error BadBatch();

    event ArtMinted(uint256 indexed sectionId, address indexed minter);

    constructor(address _table, uint256 _artPrice, address _revnetTerminal)
        ERC721("Metalog Distribution Portraits", "MDIST")
    {
        table = IGeneralizedMetalogTable(_table);
        artPrice = _artPrice;
        revnetTerminal = IJBTerminal(_revnetTerminal);
    }

    /// @notice Mint the generative portrait for an inscribed section.
    function mintArt(uint256 sectionId) external payable nonReentrant {
        if (msg.value < artPrice) revert InsufficientPayment();
        _mintArt(sectionId, msg.sender);
        _payRevnet(msg.value, msg.sender);
    }

    /// @notice Mint portraits for several sections in one transaction.
    function mintArtBatch(uint256[] calldata sectionIds) external payable nonReentrant {
        uint256 n = sectionIds.length;
        if (n == 0) revert BadBatch();
        uint256 total = artPrice * n;
        if (msg.value < total) revert InsufficientPayment();
        for (uint256 i = 0; i < n; i++) {
            _mintArt(sectionIds[i], msg.sender);
        }
        _payRevnet(total, msg.sender);
        if (msg.value > total) {
            (bool ok,) = msg.sender.call{value: msg.value - total}("");
            require(ok, "refund failed");
        }
    }

    function _mintArt(uint256 sectionId, address minter) internal {
        if (sectionId >= 2204) revert BadSection();
        if (!table.inscribed(sectionId)) revert NotInscribed();
        if (artMinted[sectionId]) revert AlreadyMinted();
        artMinted[sectionId] = true;
        artBy[sectionId] = minter;
        unchecked { totalArtMinted += 1; }
        emit ArtMinted(sectionId, minter);
        _safeMint(minter, sectionId);
    }

    function _payRevnet(uint256 amount, address beneficiary) internal {
        revnetTerminal.pay{value: amount}(
            REVNET_PROJECT_ID, NATIVE_TOKEN, amount, beneficiary, 0,
            "Metalog portrait mint", ""
        );
    }

    // ---------------- on-chain SVG ----------------

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (!artMinted[tokenId]) revert BadSection();
        string memory svg = _svg(tokenId);
        (uint256 si, uint256 ni) = table.sectionCoords(tokenId);
        string memory json = Base64.encode(
            bytes(
                string.concat(
                    '{"name":"Metalog Portrait #', tokenId.toString(), '",',
                    '"description":"Generative portrait of the sum-of-lognormals distribution ',
                    'for this table cell, rendered on-chain from its inscribed a-coefficients.",',
                    '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                    '"attributes":[',
                    '{"trait_type":"sigma","value":"', _fmtSigma(table.sigmaAt(si)), '"},',
                    '{"trait_type":"N","value":', table.nAt(ni).toString(), '},',
                    '{"trait_type":"section","value":', tokenId.toString(), '}',
                    "]}"
                )
            )
        );
        return string.concat("data:application/json;base64,", json);
    }

    /// @dev Art parameters loaded from the table.
    struct ArtParams {
        uint256 sectionId;
        uint256 sigma1e12;
        uint256 n;
        int256[9] a; // wad
        uint256 hueBg;
        uint256 hueCurve;
    }

    /// @dev Render the distribution portrait as SVG.
    function _svg(uint256 sectionId) internal view returns (string memory) {
        ArtParams memory p = _loadParams(sectionId);
        return string.concat(_svgHead(p), _svgBody(p), _svgFoot(p));
    }

    function _loadParams(uint256 sectionId) internal view returns (ArtParams memory p) {
        (uint256 si, uint256 ni) = table.sectionCoords(sectionId);
        p.sectionId = sectionId;
        p.sigma1e12 = table.sigmaAt(si);
        p.n = table.nAt(ni);
        int256[9] memory c = table.getCoeffs(si, ni);
        for (uint256 i = 0; i < 9; i++) p.a[i] = c[i] * 1e6; // to wad
        uint256 sigmaPct = (p.sigma1e12 * 100) / 1.8e12;
        p.hueBg = 240 - (200 * sigmaPct) / 100;
        p.hueCurve = (p.hueBg + 150) % 360;
    }

    function _svgHead(ArtParams memory p) internal pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">',
            "<defs>",
            '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">',
            '<stop offset="0" stop-color="hsl(', p.hueBg.toString(), ',45%,10%)"/>',
            '<stop offset="1" stop-color="hsl(', p.hueBg.toString(), ',55%,20%)"/>',
            "</linearGradient>",
            '<linearGradient id="fg" x1="0" y1="0" x2="0" y2="1">',
            '<stop offset="0" stop-color="hsl(', p.hueCurve.toString(),
                ',85%,62%)" stop-opacity="0.9"/>',
            '<stop offset="1" stop-color="hsl(', p.hueCurve.toString(),
                ',85%,62%)" stop-opacity="0.15"/>',
            "</linearGradient>",
            "</defs>",
            '<rect width="1000" height="1000" fill="url(#bg)"/>'
        );
    }

    function _svgBody(ArtParams memory p) internal view returns (string memory) {
        uint256[] memory qs = _sampleQuantiles(p.a);
        (uint256[] memory pdf, uint256 pdfMax) = _computePdf(qs);
        uint256 xmax = qs[qs.length - 1];
        string memory path = _buildPath(qs, pdf, pdfMax, xmax);
        string memory area = string.concat(path, " L 920,880 L 80,880 Z");
        uint256 q50 = MetalogMath.evalRatio(p.a, 0.5e18);
        uint256 mx = 80 + (840 * q50) / xmax;
        uint256 salt = uint256(keccak256(abi.encode(p.sectionId, block.chainid)));
        string memory dots = _buildDots(salt);
        string memory mid = string.concat(
            '<path d="', area, '" fill="url(#fg)"/>',
            '<path d="', path, '" fill="none" stroke="hsl(', p.hueCurve.toString(),
                ',95%,74%)" stroke-width="5" stroke-linecap="round"/>'
        );
        return string.concat(
            dots, mid,
            '<line x1="', mx.toString(), '" y1="120" x2="', mx.toString(),
                '" y2="880" stroke="white" stroke-width="2" stroke-dasharray="10,8" opacity="0.35"/>'
        );
    }

    function _svgFoot(ArtParams memory p) internal pure returns (string memory) {
        return string.concat(
            '<text x="80" y="70" font-family="monospace" font-size="28" fill="white" opacity="0.55" letter-spacing="6">METALOG DISTRIBUTION</text>',
            '<text x="80" y="945" font-family="monospace" font-size="26" fill="white" opacity="0.6">',
            "&#963; ", _fmtSigma(p.sigma1e12), " &#183; N ", p.n.toString(),
            "</text>",
            '<text x="920" y="945" font-family="monospace" font-size="26" fill="white" opacity="0.6" text-anchor="end">#',
            p.sectionId.toString(), "</text>",
            "</svg>"
        );
    }

    /// @dev Sample K quantiles of the avg distribution (p50 = 1).
    function _sampleQuantiles(int256[9] memory a)
        internal
        pure
        returns (uint256[] memory qs)
    {
        uint256 K = 20;
        qs = new uint256[](K);
        for (uint256 i = 0; i < K; i++) {
            uint256 y = 0.04e18 + (i * 0.92e18) / (K - 1);
            qs[i] = MetalogMath.evalRatio(a, y);
        }
    }

    /// @dev PDF via central differences; returns (pdf array, max).
    function _computePdf(uint256[] memory qs)
        internal
        pure
        returns (uint256[] memory pdf, uint256 pdfMax)
    {
        uint256 K = qs.length;
        pdf = new uint256[](K);
        pdfMax = 1;
        for (uint256 i = 0; i < K; i++) {
            uint256 i0 = i == 0 ? 0 : i - 1;
            uint256 i1 = i == K - 1 ? K - 1 : i + 1;
            uint256 dy = ((i1 - i0) * 0.92e18) / (K - 1);
            uint256 dx = qs[i1] - qs[i0];
            if (dx > 0) {
                pdf[i] = (dy * 1e18) / dx;
                if (pdf[i] > pdfMax) pdfMax = pdf[i];
            }
        }
    }

    /// @dev Build the SVG path data for the PDF curve.
    function _buildPath(
        uint256[] memory qs,
        uint256[] memory pdf,
        uint256 pdfMax,
        uint256 xmax
    ) internal pure returns (string memory path) {
        uint256 K = qs.length;
        for (uint256 i = 0; i < K; i++) {
            uint256 sx = 80 + (840 * qs[i]) / xmax;
            uint256 sy = 880 - (700 * pdf[i]) / pdfMax;
            path = string.concat(
                path, i == 0 ? "M " : " L ",
                sx.toString(), ",", sy.toString()
            );
        }
    }

    /// @dev Build the starfield dots from a deterministic salt.
    function _buildDots(uint256 salt) internal pure returns (string memory dots) {
        for (uint256 i = 0; i < 24; i++) {
            uint256 r = uint256(keccak256(abi.encode(salt, i)));
            dots = string.concat(
                dots,
                '<circle cx="', (60 + (r % 880)).toString(),
                '" cy="', (60 + ((r >> 32) % 880)).toString(),
                '" r="', (2 + ((r >> 64) % 5)).toString(),
                '" fill="white" opacity="', _pct(8 + ((r >> 96) % 18)), '"/>'
            );
        }
    }

    /// @dev Format 0-99 as "0.XX" for SVG opacity.
    function _pct(uint256 v) internal pure returns (string memory) {
        bytes memory b = bytes(v.toString());
        if (b.length == 1) return string.concat("0.0", v.toString());
        return string.concat("0.", v.toString());
    }

    /// @dev Format sigma1e12 as "0.42".
    function _fmtSigma(uint256 s) internal pure returns (string memory) {
        uint256 whole = s / 1e12;
        uint256 frac = (s % 1e12) / 1e10; // 2 decimals
        string memory fs = frac.toString();
        if (frac < 10) fs = string.concat("0", fs);
        return string.concat(whole.toString(), ".", fs);
    }
}

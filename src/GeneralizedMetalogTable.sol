// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

/// @notice Minimal Juicebox V6 terminal interface needed for native-token payments.
interface IJBTerminal {
    function pay(
        uint256 projectId,
        address token,
        uint256 amount,
        address beneficiary,
        uint256 minReturnedTokens,
        string calldata memo,
        bytes calldata metadata
    ) external payable returns (uint256 beneficiaryTokenCount);
}

/// @title GeneralizedMetalogTable
/// @notice A crowd-inscribed, on-chain lookup table for the generalized metalog
///         sum-of-IID-lognormals a-coefficients (Keelin / Chrisman / Savage 2019).
///
///         The table is a 19 x 116 grid (sigma x N) = 2204 cells. Each cell holds
///         the 9 metalog a-coefficients for that grid point, scaled by 1e12.
///
///         Each ERC-721 token represents one cell. Minting a cell requires a
///         merkle proof against the published root, so inscribed values are
///         trustlessly correct — no admin can alter the table after deploy.
///
///         All mint proceeds are forwarded in the same transaction to the
///         Juicebox revnet on Base (project 13), with the minter as beneficiary.
///         Minters are permanently recorded per cell: once the table is complete,
///         any contract can call getCoeffs() for trustless on-chain lookups.
contract GeneralizedMetalogTable is ERC721, ReentrancyGuard {
    using Strings for uint256;

    function _s(int256 v) internal pure returns (string memory) {
        return Strings.toStringSigned(v);
    }

    uint256 public constant SIGMA_COUNT = 19;
    uint256 public constant N_COUNT = 116;
    uint256 public constant SECTIONS = SIGMA_COUNT * N_COUNT; // 2204
    int256 public constant SCALE = 1e12;

    uint256 public constant REVNET_PROJECT_ID = 13;
    // Juicebox V6 convention for the native token (ETH).
    address public constant NATIVE_TOKEN = 0x000000000000000000000000000000000000EEEe;

    bytes32 public immutable merkleRoot;
    uint256 public immutable mintPrice;
    IJBTerminal public immutable revnetTerminal;

    /// @notice sectionId => true once inscribed.
    mapping(uint256 => bool) public inscribed;
    /// @notice sectionId => 9 scaled a-coefficients.
    mapping(uint256 => int256[9]) internal _coeffs;
    /// @notice sectionId => minter (permanent provenance, "part of history").
    mapping(uint256 => address) public inscribedBy;
    uint256 public totalInscribed;

    event Inscribed(uint256 indexed sectionId, address indexed minter, int256[9] coeffs);

    error BadSection();
    error AlreadyInscribed();
    error InsufficientPayment();
    error InvalidProof();
    error CellNotInscribed();

    constructor(bytes32 _merkleRoot, uint256 _mintPrice, address _revnetTerminal)
        ERC721("Generalized Metalog Table", "GMTABLE")
    {
        merkleRoot = _merkleRoot;
        mintPrice = _mintPrice;
        revnetTerminal = IJBTerminal(_revnetTerminal);
    }

    /// @notice Inscribe one table cell on chain and mint its NFT.
    /// @param sectionId  sigmaIdx * 116 + nIdx, must be < 2204.
    /// @param values     the 9 a-coefficients, scaled by 1e12.
    /// @param proof      merkle proof against the published root.
    function mint(uint256 sectionId, int256[9] calldata values, bytes32[] calldata proof)
        external
        payable
        nonReentrant
    {
        if (sectionId >= SECTIONS) revert BadSection();
        if (inscribed[sectionId]) revert AlreadyInscribed();
        if (msg.value < mintPrice) revert InsufficientPayment();

        bytes32 leaf = keccak256(abi.encode(sectionId, values));
        if (!MerkleProof.verify(proof, merkleRoot, leaf)) revert InvalidProof();

        inscribed[sectionId] = true;
        _coeffs[sectionId] = values;
        inscribedBy[sectionId] = msg.sender;
        unchecked { totalInscribed += 1; }
        emit Inscribed(sectionId, msg.sender, values);

        _safeMint(msg.sender, sectionId);

        // Forward everything to the revnet; the minter is the beneficiary.
        revnetTerminal.pay{value: msg.value}(
            REVNET_PROJECT_ID,
            NATIVE_TOKEN,
            msg.value,
            msg.sender,
            0,
            "Generalized Metalog Table inscription",
            ""
        );
    }

    /// @notice Read the 9 scaled a-coefficients for a grid cell.
    function getCoeffs(uint256 sigmaIdx, uint256 nIdx)
        external
        view
        returns (int256[9] memory coeffs)
    {
        uint256 sectionId = _sectionId(sigmaIdx, nIdx);
        if (!inscribed[sectionId]) revert CellNotInscribed();
        return _coeffs[sectionId];
    }

    /// @notice Compact completion bitmap: 2204 bits packed into 35 words. One RPC call.
    function inscribedBitmap() external view returns (uint256[35] memory bitmap) {
        for (uint256 id = 0; id < SECTIONS; id++) {
            if (inscribed[id]) bitmap[id >> 8] |= 1 << (id & 255);
        }
    }

    function isComplete() external view returns (bool) {
        return totalInscribed == SECTIONS;
    }

    function sectionCoords(uint256 sectionId)
        public
        pure
        returns (uint256 sigmaIdx, uint256 nIdx)
    {
        if (sectionId >= SECTIONS) revert BadSection();
        return (sectionId / N_COUNT, sectionId % N_COUNT);
    }

    /// @notice The sigma grid of the table, scaled by 1e12. Fixed forever.
    function sigmaAt(uint256 i) external pure returns (uint256) {
        uint256[19] memory g = [
            uint256(40000000000), uint256(70000000000), uint256(110000000000),
            uint256(160000000000), uint256(215000000000), uint256(270000000000),
            uint256(340000000000), uint256(420000000000), uint256(520000000000),
            uint256(620000000000), uint256(740000000000), uint256(880000000000),
            uint256(1040000000000), uint256(1220000000000), uint256(1440000000000),
            uint256(1500000000000), uint256(1600000000000), uint256(1700000000000),
            uint256(1800000000000)
        ];
        if (i >= SIGMA_COUNT) revert BadSection();
        return g[i];
    }

    /// @notice The N grid of the table. Fixed forever.
    function nAt(uint256 i) external pure returns (uint256) {
        uint256[116] memory g = [
            uint256(1), uint256(2), uint256(3), uint256(4), uint256(5), uint256(6),
            uint256(7), uint256(8), uint256(9), uint256(10), uint256(11), uint256(12),
            uint256(14), uint256(16), uint256(18), uint256(20), uint256(24), uint256(28),
            uint256(34), uint256(42), uint256(50), uint256(60), uint256(70), uint256(80),
            uint256(90), uint256(100), uint256(110), uint256(120), uint256(130), uint256(140),
            uint256(150), uint256(160), uint256(170), uint256(180), uint256(190), uint256(200),
            uint256(210), uint256(220), uint256(230), uint256(240), uint256(250), uint256(260),
            uint256(270), uint256(280), uint256(290), uint256(300), uint256(310), uint256(320),
            uint256(330), uint256(340), uint256(350), uint256(360), uint256(370), uint256(380),
            uint256(390), uint256(400), uint256(410), uint256(420), uint256(430), uint256(440),
            uint256(450), uint256(460), uint256(470), uint256(480), uint256(490), uint256(500),
            uint256(510), uint256(520), uint256(530), uint256(540), uint256(550), uint256(560),
            uint256(570), uint256(580), uint256(590), uint256(600), uint256(610), uint256(620),
            uint256(630), uint256(640), uint256(650), uint256(660), uint256(670), uint256(680),
            uint256(690), uint256(700), uint256(710), uint256(720), uint256(730), uint256(740),
            uint256(750), uint256(760), uint256(770), uint256(780), uint256(790), uint256(800),
            uint256(810), uint256(820), uint256(830), uint256(840), uint256(850), uint256(860),
            uint256(870), uint256(880), uint256(890), uint256(900), uint256(910), uint256(920),
            uint256(930), uint256(940), uint256(950), uint256(960), uint256(970), uint256(980),
            uint256(990), uint256(1000)
        ];
        if (i >= N_COUNT) revert BadSection();
        return g[i];
    }

    function _sectionId(uint256 sigmaIdx, uint256 nIdx) internal pure returns (uint256) {
        if (sigmaIdx >= SIGMA_COUNT || nIdx >= N_COUNT) revert BadSection();
        return sigmaIdx * N_COUNT + nIdx;
    }

    // ---- token metadata: fully on-chain ----

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (tokenId >= SECTIONS || !inscribed[tokenId]) revert BadSection();
        (uint256 si, uint256 ni) = sectionCoords(tokenId);
        int256[9] storage c = _coeffs[tokenId];

        string memory attrs = string.concat(
            '{"trait_type":"sigma index","value":', si.toString(), '},',
            '{"trait_type":"N index","value":', ni.toString(), '},',
            '{"trait_type":"inscribed by","value":"', Strings.toHexString(inscribedBy[tokenId]), '"}'
        );
        string memory coeffJson = string.concat(
            '[', _s(c[0]), ',', _s(c[1]), ',', _s(c[2]), ',',
            _s(c[3]), ',', _s(c[4]), ',', _s(c[5]), ',',
            _s(c[6]), ',', _s(c[7]), ',', _s(c[8]), ']'
        );
        string memory json = string.concat(
            '{"name":"Metalog Table Cell #', tokenId.toString(), '",',
            '"description":"One inscribed cell (sigma row ', si.toString(), ', N column ', ni.toString(), ') ',
            'of the generalized metalog sum-of-IID-lognormals lookup table. Values are the 9 metalog a-coefficients scaled by 1e12.",',
            '"attributes":[', attrs, '],',
            '"properties":{"aCoeffsScaled1e12":', coeffJson, '}}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }
}

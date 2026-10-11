# Generalized Metalog Table — crowd-inscribed on-chain lookup

NFT project that puts the generalized metalog sum-of-IID-lognormals lookup table
**on chain**, one cell per mint, with proceeds funding the Base revnet.

## The table

`../generalized-metalog/Interpolatable-aCoefficients.json` (chanceofxyz/generalized-metalog):
19 σ rows (0.04→1.8) × 116 N columns (1→1000) = **2,204 cells**, each holding the
9 metalog a-coefficients (9-term semi-bounded metalog, lower bound 0) for the
average of N IID lognormals ÷ p50. Quantile: `p50 * exp(M(y; a))`; sum = N × that.

**Independently verified** (the repo README says this hadn't been done): the
a-coefficients reproduce the Keelin/Chrisman/Savage (2019) FFT quantile table to
4+ digits at all sampled points including extremes. The source file is actually
JS (`const table = …`) with one trailing-comma syntax error — cleaned during
extraction.

## How it works

- **Sections**: one ERC-721 per (σ, N) cell — 2,204 total. Each mint permanently
  stores that cell's 9 a-coefficients (×1e12 fixed point) in contract storage.
- **Trustless correctness**: the deploy bakes in a merkle root over all 2,204
  cells (leaf = `keccak256(abi.encode(sectionId, int256[9]))`, sorted-pair tree,
  OpenZeppelin convention). `mint()` verifies the proof — wrong values revert.
  No admin, no upgrade, no trust.
- **Money**: `mint()` is payable (default 0.005 ETH) and forwards **everything**
  to the Juicebox revnet on Base (**project 13**, "Split's Bankr Bot") via the
  primary ETH terminal `0x130f5Dd2bD8805443Cf41755253D778a75a67f53`, with the
  **minter as beneficiary** (they receive the revnet tokens). Verified by fork
  test against Base mainnet.
- **Provenance**: `inscribedBy[sectionId]` permanently records who inscribed each
  cell — minters are part of history.
- **Lookup**: once cells are inscribed, any contract can call
  `getCoeffs(sigmaIdx, nIdx)` → `int256[9]`. `isComplete()` / `totalInscribed`
  track progress; `inscribedBitmap()` returns completion in one RPC call.
- **Grids**: `sigmaAt(i)` / `nAt(i)` expose the fixed sigma (×1e12) and N grids so
  consumers can bracket any (sigma, N) without hardcoding the table.

## The reader (the utility)

`src/MetalogReader.sol` — the shared on-chain reader. This is the contract other
contracts call. Given `(sigma×1e12, N, p50, y)` it brackets the grid, reads the
4 surrounding cells, bilinearly interpolates the a-coefficients (same method as
the reference JS), and evaluates the 9-term semi-bounded metalog quantile:

- `quantileOfSum(sigma1e12, n, p50Wad, yWad)` → sum quantile, wad
- `quantileOfAvg(sigma1e12, n, p50Wad, yWad)` → average quantile, wad
- `interpCoeffs(sigma1e12, n)` → the 9 interpolated coefficients, wad

All `view`: **free off-chain** via `eth_call`. Called on-chain, ~219k gas cold
(36 SLOADs + Solady fixed-point `ln`/`exp`) — trivial on Base. Verified against
a float64 Python reference to 1e-6 relative on on-grid, off-grid and extreme
points.

Example consumer:

```solidity
MetalogReader reader = MetalogReader(READER_ADDRESS);
// 99th percentile of the sum of 50 IID lognormals, sigma=0.5, median 100
uint256 q99 = reader.quantileOfSum(0.5e12, 50, 100e18, 0.99e18);
```

Trust model: reads are as good as the table — the merkle root is immutable, so a
wrong value can never be inscribed, and `getCoeffs` reverts for uninscribed
cells (loud failure, never a silent zero).

## Generative art (the collectible)

`src/MetalogArt.sol` — 2204 unique on-chain SVG portraits, one per section. Each
portrait visualizes that cell's probability distribution: the PDF curve rendered
from its own a-coefficients, palette drawn from sigma (volatility as heat —
blue for calm, ember for wild), starfield texture from a deterministic salt.
Fully on-chain, no IPFS.

- `mintArt(sectionId)` / `mintArtBatch(sectionIds[])` — requires the section to
  be inscribed first; one portrait per section (first come). Proceeds to the
  revnet, minter as beneficiary.
- `tokenURI` returns base64 JSON with base64 SVG image + traits (sigma, N).

## Batch minting

Both contracts support bundles in one transaction:
- `table.mintBatch(sectionIds, values[], proofs[])` — one revnet payment for the total.
- `art.mintArtBatch(sectionIds[])` — ditto.

## Layout

- `src/GeneralizedMetalogTable.sol` — the NFT/inscription contract (single + batch mint)
- `src/MetalogReader.sol` — the shared on-chain reader (the utility)
- `src/MetalogArt.sol` — generative on-chain SVG portraits (single + batch mint)
- `src/MetalogMath.sol` — shared fixed-point metalog math library
- `src/interfaces/` — `IGeneralizedMetalogTable`, `IMetalogReader`, `IMetalogArt`, `IJBTerminal`
- `script/Deploy.s.sol` — deploy script, deploys all three (Base)
- `script/build_sections.py` — regenerate `app/sections.json` from upstream (build artifact)
- `test/` — unit tests (mock terminal), fork test (real revnet), reader tests (vs Python reference)
- `app/index.html` — single-page minting app: full 19×116 table, completion progress, click-to-mint
- `app/sections.json` — all 2,204 cells with values + merkle proofs (2.3 MB)

Merkle root: `0x8881e0a19020bfa3fd40c9e9f00242dc4d9e9b87af47e9b9a7e97191008847a4`

## Deploy

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd ~/workspace/metalog-table-nft
forge script script/Deploy.s.sol --rpc-url $BASE_RPC --private-key $KEY --broadcast
# then set CONTRACT_ADDRESS in app/index.html and serve the app/ directory
```

## Test

```bash
forge test                                        # unit tests (mock terminal)
forge test --match-contract ForkPay --fork-url https://mainnet.base.org   # real revnet routing
```

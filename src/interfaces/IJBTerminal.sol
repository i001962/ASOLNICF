// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal Juicebox V6 terminal interface for native ETH payments.
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

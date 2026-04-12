// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./ISettlementVerifier.sol";

/// @title  StubSettlementVerifier
/// @notice Reference stub implementation for development and testing.
/// @dev    Returns true for well-structured inputs. NOT FOR PRODUCTION USE.
///
///         Production deployment MUST replace this with a Groth16 verifier contract
///         compiled from the canonical circom circuit for the corresponding service
///         category. The canonical verifier's proofFormat() should return "groth16-v1"
///         (or the versioned identifier of the audited circuit family).
///
///         The stub exists so the full contract-settlement-proof primitive can be
///         wired end-to-end against kenoodl's existing stealth door today, with the
///         real cryptographic verification substituted in as a drop-in replacement
///         the moment the audited circuit is available.
contract StubSettlementVerifier is ISettlementVerifier {
    function verifyDelivery(
        bytes calldata proof,
        bytes32 requestHash,
        bytes32 offerHash
    ) external pure returns (bool) {
        // Minimum structural checks — the stub accepts any non-empty proof with
        // non-zero hashes. A real verifier would enforce:
        //   - Groth16 proof validity under the trusted setup
        //   - Public inputs (requestHash, offerHash) match the proof's committed values
        //   - Circuit constraints satisfied: output = f(input), latency bound, retry bound
        require(proof.length > 0, "StubSettlementVerifier: empty proof");
        require(requestHash != bytes32(0), "StubSettlementVerifier: zero requestHash");
        require(offerHash != bytes32(0), "StubSettlementVerifier: zero offerHash");
        return true;
    }

    function proofFormat() external pure returns (string memory) {
        return "stub-v0";
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ISettlementVerifier
/// @notice Abstract verifier for delivery proofs attached to x402 settlement transactions.
/// @dev   Concrete implementations verify cryptographic proofs (Groth16 SNARK in the
///        reference implementation) that a response transaction correctly settles the
///        offer identified by offerHash, under the exact terms registered in OfferRegistry.
///
///        The proof attests that, without revealing payload contents:
///          1. Output hash = f(decrypted_input) where f is the registered service function
///          2. Latency stayed under maxLatency from owedBlock timestamp
///          3. retryCount never exceeded maxRetries under the registered offer
interface ISettlementVerifier {
    /// @notice Verify a delivery proof for a given request and offer.
    /// @param  proof        The serialized proof bytes (Groth16 in reference implementation).
    /// @param  requestHash  The 32-byte hash of the original request.
    /// @param  offerHash    The 32-byte hash of the offer this delivery settles.
    /// @return Whether the proof is valid under the offer's terms.
    function verifyDelivery(
        bytes calldata proof,
        bytes32 requestHash,
        bytes32 offerHash
    ) external view returns (bool);

    /// @notice Returns the proof format identifier (e.g., "groth16-v1", "stub-v0").
    function proofFormat() external view returns (string memory);
}

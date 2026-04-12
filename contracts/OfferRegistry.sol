// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title OfferRegistry
/// @notice Immutable on-chain registry mapping offerHash → canonical offer JSON terms.
/// @dev   Reference implementation for the x402 contract-settlement-proof primitive.
///        A seller registers a canonical JSON offer once; any buyer can verify the
///        exact terms via a single eth_call before committing payment.
///
///        Canonical offer JSON encodes (at minimum):
///          {
///            "amount": uint256 (wei or token units),
///            "maxLatency": uint32 (seconds from owedBlock),
///            "maxRetries": uint8,
///            "serviceType": string (e.g. "synthesis"),
///            "termsHash": bytes32 (domain-specific terms)
///          }
///
///        offerHash = keccak256(canonicalOfferJson).
contract OfferRegistry {
    /// @notice Maps offerHash to the canonical JSON bytes.
    mapping(bytes32 => bytes) private _offers;

    /// @notice Maps offerHash to the seller address that registered it.
    mapping(bytes32 => address) public sellerOf;

    /// @notice Emitted when a seller registers a new offer.
    event OfferRegistered(
        bytes32 indexed offerHash,
        address indexed seller,
        uint256 timestamp
    );

    /// @notice Register a canonical offer. Reverts if the offerHash already exists.
    /// @param  offerJson The canonical JSON bytes encoding the offer terms.
    /// @return offerHash The keccak256 digest of offerJson.
    function registerOffer(bytes calldata offerJson)
        external
        returns (bytes32 offerHash)
    {
        require(offerJson.length > 0, "OfferRegistry: empty offer");
        offerHash = keccak256(offerJson);
        require(_offers[offerHash].length == 0, "OfferRegistry: already registered");
        _offers[offerHash] = offerJson;
        sellerOf[offerHash] = msg.sender;
        emit OfferRegistered(offerHash, msg.sender, block.timestamp);
    }

    /// @notice Verify an offer by its hash and return its canonical JSON terms.
    /// @param  offerHash The 32-byte keccak256 digest of the offer JSON.
    /// @return The canonical JSON bytes, or empty bytes if not registered.
    function verifyOffer(bytes32 offerHash) external view returns (bytes memory) {
        return _offers[offerHash];
    }

    /// @notice Check if an offer exists without returning its contents.
    function offerExists(bytes32 offerHash) external view returns (bool) {
        return _offers[offerHash].length > 0;
    }
}

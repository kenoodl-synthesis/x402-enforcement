// synthesis.circom
//
// Groth16 circuit specification for the kenoodl synthesis service category.
// This is the circuit statement the production SettlementVerifier must enforce.
// It is NOT yet compiled — producing a working prover + verifier from this
// specification requires circom tooling, a trusted setup ceremony, and a formal
// audit pass before any real capital is routed through it.
//
// What the circuit proves, in zero-knowledge, without revealing the decrypted
// input or the decrypted output to any auditor:
//
//   1. outputHash = H(synthesisFunction(decryptedInput)) where the synthesis
//      function is the deterministic entry point for the registered service
//      type. For kenoodl's synthesis category, this is a commitment to
//      "a valid grok-4-fast completion of the decrypted input under the
//       registered offer's termsHash."
//
//   2. latencySeconds < offer.maxLatency, where latencySeconds = responseBlock
//      timestamp - owedBlock timestamp.
//
//   3. retryCount <= offer.maxRetries.
//
//   4. The public inputs (requestHash, offerHash) are consistent with the
//      private inputs (the decrypted input and output never leave the prover).
//
// Public inputs (visible on chain, land in StealthProof event):
//   - requestHash : bytes32
//   - offerHash   : bytes32
//   - outputHash  : bytes32
//
// Private inputs (witness, never revealed):
//   - decryptedInput  : bytes
//   - synthesisOutput : bytes
//   - latencySeconds  : uint32
//   - retryCount      : uint8
//   - offerTerms      : parsed offer JSON (maxLatency, maxRetries, termsHash)
//
// The verifier contract (SettlementVerifier.verifyDelivery) takes the proof
// plus (requestHash, offerHash) and returns true iff all four constraints
// above are satisfied under the trusted setup parameters.
//
// ---
//
// PSEUDOCODE (not compilable circom yet — see TODO below):
//
// template SynthesisDeliveryProof() {
//     signal input  requestHash;     // public
//     signal input  offerHash;       // public
//     signal input  outputHash;      // public
//
//     signal input  decryptedInput[N];   // private witness
//     signal input  synthesisOutput[M];  // private witness
//     signal input  latencySeconds;      // private
//     signal input  retryCount;          // private
//     signal input  maxLatency;          // private (from decoded offer terms)
//     signal input  maxRetries;          // private (from decoded offer terms)
//
//     // Constraint 1: outputHash = Keccak256(synthesisOutput)
//     component outHasher = Keccak256(M);
//     outHasher.in <== synthesisOutput;
//     outHasher.out === outputHash;
//
//     // Constraint 2: the output is a valid commitment to the registered
//     // synthesis function applied to the decrypted input. In practice this
//     // is a commitment scheme tied to the xAI API call signature; the
//     // exact form depends on the audit pass.
//     component synthCheck = SynthesisCommitmentCheck();
//     synthCheck.input  <== decryptedInput;
//     synthCheck.output <== synthesisOutput;
//     synthCheck.valid  === 1;
//
//     // Constraint 3: latencySeconds < maxLatency
//     component latencyCheck = LessThan(32);
//     latencyCheck.in[0] <== latencySeconds;
//     latencyCheck.in[1] <== maxLatency;
//     latencyCheck.out   === 1;
//
//     // Constraint 4: retryCount <= maxRetries
//     component retryCheck = LessEqThan(8);
//     retryCheck.in[0] <== retryCount;
//     retryCheck.in[1] <== maxRetries;
//     retryCheck.out   === 1;
// }
//
// component main { public [requestHash, offerHash, outputHash] } = SynthesisDeliveryProof();
//
// ---
//
// TODO (follow-on work, not blocking the reference implementation):
//
//   1. Replace the SynthesisCommitmentCheck placeholder with a real
//      commitment scheme tied to xAI's API signature. Options:
//        a. Commit to the exact output bytes and prove the operator's signing
//           key signed them. Simpler but reveals the output to the commitment
//           step.
//        b. Commit to a Merkle root over output shards and prove inclusion
//           of a specific shard under the registered service function.
//      Pick a and move on; b is overengineering for v1.
//
//   2. Run `circom synthesis.circom --r1cs --wasm --sym` to compile. Requires
//      circom 2.x installed locally.
//
//   3. Generate the proving key and verifying key via a trusted setup:
//        snarkjs groth16 setup synthesis.r1cs pot12_final.ptau synthesis_0000.zkey
//        snarkjs zkey contribute synthesis_0000.zkey synthesis_0001.zkey
//        snarkjs zkey export verificationkey synthesis_0001.zkey verification_key.json
//
//   4. Export the Solidity verifier:
//        snarkjs zkey export solidityverifier synthesis_0001.zkey Verifier.sol
//      That file becomes the real SettlementVerifier for the synthesis service
//      category. Rename its verifyProof() to verifyDelivery() and adapt the
//      interface to match ISettlementVerifier.sol.
//
//   5. Formal audit by an approved firm. Until the audit passes, do not route
//      real capital through the verifier in production.
//
// For v0.1 development, StubSettlementVerifier is sufficient — it accepts any
// well-structured proof payload and lets the end-to-end flow be tested against
// kenoodl's real stealth door on Base.

# Stealth Door Integration — Fix kenoodl's side

This document describes the exact changes required in `cr-trader/worker.js` to
make kenoodl's existing stealth door implement the full contract-settlement-proof
primitive.

Everything in this doc is a delta against the current stealth door code, which
lives (disabled cron) in `cr-trader/worker.js`. The changes below do not add new
features. They surface the contract terms and delivery proof that the existing
stealth door already handles bilaterally, and make them visible to any on-chain
auditor without revealing the encrypted payload content.

---

## Summary of the fix

Today: the stealth door is bilaterally honest but third-party invisible. An
auditor scanning only the chain sees selectors + encrypted blobs and has no way
to verify the contract terms or the correctness of delivery.

After the fix: every inbound transaction carries an `offerHash` in its calldata
pointing to a canonical offer registered in `OfferRegistry` on Base. Every
successful response transaction emits a `StealthProof` event whose payload
contains a delivery proof (Groth16 SNARK in production, stub today) plus public
inputs. A third-party auditor can now confirm both sides performed without ever
seeing the payload content.

---

## New calldata format (inbound)

Current inbound calldata layout:

```
[0x00..0x04)   4-byte selector  = 0x73a6e5d4
[0x04..0x24)   32-byte requestHash
[0x24.. end)   ECIES-encrypted request payload
```

New inbound calldata layout (backward-compatible via selector change):

```
[0x00..0x04)   4-byte selector  = 0x73a6e5d5     (new selector, v2)
[0x04..0x24)   32-byte offerHash (the seller's registered offer)
[0x24..0x44)   32-byte requestHash
[0x44.. end)   ECIES-encrypted request payload
```

The original selector `0x73a6e5d4` remains accepted by the worker for backward
compatibility (legacy v1 cycles), but new clients MUST use `0x73a6e5d5`. The
`/.well-known/ai.json` spec is updated to advertise the new format (see
`AI_JSON_UPDATE.md`).

---

## New response calldata format (outbound)

Current response calldata layout:

```
[0x00..0x04)   4-byte selector  = 0x9f2c1a3b
[0x04.. end)   ECIES-encrypted response payload
```

New response calldata layout:

```
[0x00..0x04)   4-byte selector      = 0x9f2c1a3c     (new selector, v2)
[0x04..0x24)   32-byte requestHash  (the request being settled)
[0x24..0x44)   32-byte offerHash    (matching the inbound offerHash)
[0x44..0x48)   4-byte proofLength   (big-endian uint32)
[0x48.. end)   proof bytes (Groth16 serialized, or stub bytes during development)
                concatenated with ECIES-encrypted response payload
```

The worker emits a `StealthProof` event carrying `(requestHash, offerHash,
proofHash)` so external auditors can index the verification independently.

---

## Code changes in `cr-trader/worker.js`

### 1. Imports and constants

Add near the top of the file, after the existing SYNTH_DEPLOY_TS constant:

```javascript
// x402 contract-settlement-proof primitive addresses (Base mainnet)
// Replace these with the deployed addresses after running deploy script.
const OFFER_REGISTRY_ADDRESS = '0x0000000000000000000000000000000000000000'; // TODO: deploy
const SETTLEMENT_VERIFIER_ADDRESS = '0x0000000000000000000000000000000000000000'; // TODO: deploy

// New selectors for the v2 stealth door format
const SELECTOR_REQUEST_V1 = '0x73a6e5d4'; // legacy — accepted for backward compatibility
const SELECTOR_REQUEST_V2 = '0x73a6e5d5'; // v2 — carries offerHash
const SELECTOR_RESPONSE_V1 = '0x9f2c1a3b'; // legacy
const SELECTOR_RESPONSE_V2 = '0x9f2c1a3c'; // v2 — carries proof + offerHash
```

### 2. Parse offerHash from inbound calldata

In the `processSynthesisRequests` function, where the current code processes
the calldata of each inbound transaction, add parsing for the v2 format:

```javascript
// Determine calldata version from the first 4 bytes
const selector = calldata.slice(0, 10); // "0x" + 8 hex chars
let offerHash = null;
let requestHash = null;
let payloadOffset = 10; // bytes in hex after "0x"

if (selector === SELECTOR_REQUEST_V2) {
  // v2: [selector][offerHash][requestHash][ECIES payload]
  offerHash = '0x' + calldata.slice(10, 74);       // 32 bytes
  requestHash = '0x' + calldata.slice(74, 138);    // 32 bytes
  payloadOffset = 138;
} else if (selector === SELECTOR_REQUEST_V1) {
  // v1 legacy: [selector][requestHash][ECIES payload]
  requestHash = '0x' + calldata.slice(10, 74);
  payloadOffset = 74;
  // offerHash remains null — legacy requests bypass the registry check
} else {
  // Unknown selector — ignore this transaction
  continue;
}

const encryptedPayload = '0x' + calldata.slice(payloadOffset);
```

### 3. Verify offer terms via eth_call before processing

If `offerHash !== null`, call the OfferRegistry before spending compute on
synthesis. If the offer is not registered, reject the request immediately and
queue a refund path.

```javascript
if (offerHash !== null) {
  const offerJson = await readOfferFromRegistry(env, offerHash);
  if (!offerJson || offerJson.length === 0) {
    console.log(`Stealth door: offerHash ${offerHash} not registered. Rejecting.`);
    await updateSynthStatus(env, tx.hash, 'rejected', {
      reason: 'offer_not_registered',
      offerHash,
      from,
    });
    continue;
  }

  // Verify the inbound payment value matches the offer's registered amount
  const offer = JSON.parse(new TextDecoder().decode(offerJson));
  const expectedWei = BigInt(offer.amount);
  const paidWei = BigInt(tx.value || '0');
  if (paidWei < expectedWei) {
    console.log(`Stealth door: underpayment ${paidWei} < ${expectedWei}. Rejecting.`);
    await updateSynthStatus(env, tx.hash, 'rejected', {
      reason: 'underpayment',
      offerHash,
      paidWei: paidWei.toString(),
      expectedWei: expectedWei.toString(),
      from,
    });
    continue;
  }

  // Store the offerHash alongside the synthesis state for the response step
  await env.CR_STATE.put(`synth_offer:${tx.hash}`, offerHash, {
    expirationTtl: 86400 * 90,
  });
}
```

Add a helper to read from the registry via the Base RPC:

```javascript
async function readOfferFromRegistry(env, offerHash) {
  const data = '0x40a5f0e5' // keccak256("verifyOffer(bytes32)").slice(0, 10)
    + offerHash.slice(2).padStart(64, '0');
  const res = await fetch(env.BASE_RPC, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      jsonrpc: '2.0',
      method: 'eth_call',
      params: [{ to: OFFER_REGISTRY_ADDRESS, data }, 'latest'],
      id: 1,
    }),
  });
  const json = await res.json();
  if (json.error || !json.result) return null;
  // Decode ABI-encoded bytes return: offset + length + data
  const result = json.result.slice(2);
  if (result.length < 128) return null;
  const length = parseInt(result.slice(64, 128), 16);
  if (length === 0) return null;
  const hex = result.slice(128, 128 + length * 2);
  return Uint8Array.from(hex.match(/.{2}/g).map((b) => parseInt(b, 16)));
}
```

### 4. Generate the delivery proof after synthesis

After `runSynthesis` returns successfully and before `sendSynthesisResponse`,
generate the proof. In v0.1 (with the stub verifier) the proof is a well-formed
placeholder; in v1 (with the real Groth16 verifier) it is a compiled SNARK
produced by snarkjs or an equivalent prover.

```javascript
// v0.1 stub proof: 64 bytes of deterministic placeholder tied to the request
const stubProof = sha256(`${requestHash}:${offerHash}:${synthesis.length}`);
// Real implementation (v1):
//   const proof = await generateGroth16Proof({
//     circuit: 'synthesis-v1',
//     publicInputs: { requestHash, offerHash },
//     privateInputs: { decryptedInput, synthesisOutput, latencySeconds, retryCount },
//   });
```

### 5. New response calldata builder

Replace the current `sendSynthesisResponse` calldata construction with the v2
format, carrying requestHash + offerHash + proofLength + proofBytes +
ECIES-encrypted response.

```javascript
function buildV2ResponseCalldata(requestHash, offerHash, proofBytes, encryptedResponse) {
  const proofLength = proofBytes.length;
  const proofLengthBytes = new Uint8Array(4);
  new DataView(proofLengthBytes.buffer).setUint32(0, proofLength, false); // big-endian
  const parts = [
    SELECTOR_RESPONSE_V2,                          // 4 bytes selector
    requestHash.slice(2),                          // 32 bytes
    offerHash.slice(2),                            // 32 bytes
    Array.from(proofLengthBytes).map((b) => b.toString(16).padStart(2, '0')).join(''),
    Array.from(proofBytes).map((b) => b.toString(16).padStart(2, '0')).join(''),
    encryptedResponse.slice(2),                    // encrypted payload
  ];
  return '0x' + parts.join('');
}
```

### 6. Emit the StealthProof event

The stealth door today does not emit events (it operates purely at the wallet
level). Adding event emission requires routing through a thin smart contract
wrapper. For v0.1 this is optional — the proof bytes on the response calldata
are enough for an auditor to verify against `SettlementVerifier.verifyDelivery`.
For v1 the wrapper contract SHOULD emit:

```solidity
event StealthProof(
    bytes32 indexed requestHash,
    bytes32 indexed offerHash,
    bytes32 proofHash
);
```

### 7. Register kenoodl's standard offer after registry deployment

Once `OfferRegistry` is deployed on Base, register kenoodl's canonical synthesis
offer once:

```javascript
// Canonical kenoodl synthesis offer — register once, cache the hash forever
const kenoodlSynthesisOffer = JSON.stringify({
  amount: '10000000000000000',          // 0.01 ETH in wei (minimum)
  maxLatency: 300,                       // 5 minutes
  maxRetries: 3,
  serviceType: 'synthesis',
  termsHash: '0x' + '00'.repeat(32),    // domain terms hash (TBD)
});
// offerHash = keccak256(kenoodlSynthesisOffer)
// Call registerOffer(kenoodlSynthesisOffer) once from kenoodl's deployment wallet.
```

---

## Deployment checklist

1. `cd x402-enforcement && forge build` — verify all contracts compile
2. `forge create contracts/OfferRegistry.sol:OfferRegistry --rpc-url base --private-key $DEPLOY_KEY` — deploy the registry on Base
3. `forge create contracts/StubSettlementVerifier.sol:StubSettlementVerifier --rpc-url base --private-key $DEPLOY_KEY` — deploy the stub verifier
4. Replace the `OFFER_REGISTRY_ADDRESS` and `SETTLEMENT_VERIFIER_ADDRESS` constants in `cr-trader/worker.js` with the deployed addresses
5. Call `registerOffer(kenoodlSynthesisOffer)` from the deployment wallet — this is a one-time action that establishes kenoodl's canonical synthesis offer
6. Update `/.well-known/ai.json` per `AI_JSON_UPDATE.md`
7. Deploy the updated cr-trader worker
8. Optionally re-enable the cr-trader cron (`[triggers] crons = ["*/5 * * * *"]` in `cr-trader/wrangler.toml`)

---

## What this does not include

- Real Groth16 circuit (stubbed via `StubSettlementVerifier`). The real circuit
  requires circom + snarkjs tooling, a trusted setup ceremony, and an audit
  pass. This is a follow-on work item, tracked in `CIRCUIT_WORK_TODO.md`.
- Settlement in USDC via Coinbase Prime custody. That is Coinbase's job to
  build — see `FOUNDATION_SPEC.md` for the full production path.
- A canonical ecosystem-wide `OfferRegistry`. The kenoodl deployment is a
  reference instance only. The canonical version that all x402 endpoints
  should point at must be deployed and operated by Coinbase.

---

## Why each change is necessary

- **offerHash in calldata**: without it, an agent cannot pre-verify the exact
  terms it is paying for. The current stealth door cannot refuse a mismatch
  because it has no canonical reference to check against.
- **Eth_call to OfferRegistry before processing**: without it, the stealth
  door processes unknown offers blindly and cannot reject underpayment or
  unrecognized service types.
- **Proof bytes in response calldata**: without them, a third-party auditor
  scanning the chain cannot verify that the response correctly settles the
  request. Settlement is invisible to anyone not holding the ECIES keys.
- **StealthProof event**: without it, auditors cannot index delivery proofs
  independently. Required only when external regulated counterparties need
  to audit settlement correctness without running their own full node.
- **Canonical offer registration**: without it, kenoodl cannot advertise a
  stable offerHash in its ai.json. Every call would require re-registering
  or negotiating terms on the wire.

Every item in this delta is specified by the prior syntheses. Nothing is
invented beyond what the prompts surfaced.

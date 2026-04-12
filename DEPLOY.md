# Deployment Checklist

This document is the exact path from "reference code in a repo" to "live
primitive on Base with kenoodl's own stealth door verifying against it."

Everything below is concrete and runnable. Nothing is theoretical.

---

## Prerequisites

- Foundry installed (`curl -L https://foundry.paradigm.xyz | bash`, then `foundryup`)
- A Base-funded deployer wallet with the private key available as an env var (`DEPLOY_KEY`)
- (Optional) A Basescan API key for verification (`BASESCAN_API_KEY`)

---

## Step 1 — Build and test the contracts

```bash
cd /Users/davidhoff/Desktop/kenoodl/x402-enforcement
forge build
```

Expected output: three contracts compile cleanly — `OfferRegistry`,
`ISettlementVerifier`, `StubSettlementVerifier`.

---

## Step 2 — Deploy to Base Sepolia first (testing)

```bash
# Registry
forge create contracts/OfferRegistry.sol:OfferRegistry \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY

# Stub verifier
forge create contracts/StubSettlementVerifier.sol:StubSettlementVerifier \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY
```

Record the two deployed addresses. Verify they are correct by reading back:

```bash
cast call $REGISTRY_ADDRESS "offerExists(bytes32)(bool)" \
  0x0000000000000000000000000000000000000000000000000000000000000000 \
  --rpc-url base_sepolia
# Should return: false
```

---

## Step 3 — Register kenoodl's canonical synthesis offer

Canonical offer JSON (kept byte-exact — any whitespace change produces a
different hash):

```json
{"amount":"10000000000000000","maxLatency":300,"maxRetries":3,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

Compute the hash:

```bash
cast keccak '{"amount":"10000000000000000","maxLatency":300,"maxRetries":3,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}'
```

Register:

```bash
cast send $REGISTRY_ADDRESS \
  "registerOffer(bytes)" \
  "0x$(echo -n '{"amount":"10000000000000000","maxLatency":300,"maxRetries":3,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}' | xxd -p | tr -d '\n')" \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY
```

Confirm registration:

```bash
cast call $REGISTRY_ADDRESS "verifyOffer(bytes32)(bytes)" $KENOODL_SYNTH_OFFER_HASH \
  --rpc-url base_sepolia
# Should return the exact JSON bytes above.
```

Record `$KENOODL_SYNTH_OFFER_HASH` — this is the hash kenoodl will advertise
in `/.well-known/ai.json` and embed in every v2 inbound calldata.

---

## Step 4 — Update `cr-trader/worker.js`

Apply the changes documented in `STEALTH_DOOR_INTEGRATION.md`:

1. Add the two contract addresses as constants near the top of the file
2. Parse `offerHash` from inbound calldata (v2 selector `0x73a6e5d5`)
3. Call `readOfferFromRegistry` before processing to verify terms
4. Reject underpayment or unregistered offers with a `rejected` status update
5. Build v2 response calldata (`0x9f2c1a3c`) with proof bytes included
6. Store `synth_offer:${tx.hash}` in `CR_STATE` alongside existing status keys

The integration doc walks the exact diff for each change.

---

## Step 5 — Deploy the updated cr-trader worker

```bash
cd /Users/davidhoff/Desktop/kenoodl/cr-trader
npx wrangler deploy
```

Leave the cron disabled for now. The worker can still be manually triggered
via its `/beacons/scan` endpoint (or an equivalent test endpoint) to verify
the registry-reading path works end to end against Sepolia.

---

## Step 6 — Test the full flow on Sepolia

From a test wallet on Base Sepolia, send a transaction to the kenoodl wallet
address with the v2 calldata format:

```
0x73a6e5d5
  + <32-byte offerHash>   (from step 3)
  + <32-byte requestHash> (any 32-byte hash)
  + <ECIES-encrypted test payload>
```

The worker should:
1. Read the offerHash from calldata
2. Call `verifyOffer(offerHash)` on the registry
3. Decode the JSON terms
4. Verify the transaction value ≥ offer amount
5. Decrypt the payload, run synthesis
6. Build v2 response calldata with a stub proof
7. Send the response transaction back to the originating wallet

Watch the chain (via BaseScan Sepolia) for the response transaction. Decode
the response calldata to confirm the format is correct.

---

## Step 7 — Promote to Base mainnet

Once Sepolia testing passes:

1. Re-run steps 2 and 3 against `--rpc-url base` (mainnet)
2. Record the mainnet registry and verifier addresses
3. Update the constants in `cr-trader/worker.js` to point at mainnet addresses
4. Redeploy the worker
5. Update `public/.well-known/ai.json` to advertise the v2 primitive — see
   the `AI_JSON_UPDATE.md` patch document (TBD — produced after mainnet
   addresses are known)
6. Rebuild and redeploy the kenoodl site: `npm run build && cd api/src && npx wrangler deploy`

---

## Step 8 — Optional: re-enable the cr-trader cron

If you want the stealth door actively polling for inbound transactions again:

In `cr-trader/wrangler.toml`, uncomment:

```toml
[triggers]
crons = ["*/5 * * * *"]
```

Then redeploy. The stealth door will now run every 5 minutes, checking for
v2 (and v1 legacy) inbound transactions and processing them through the full
contract-settlement-proof pipeline.

---

## Rollback plan

If anything breaks:

1. Comment out the `[triggers]` section again to halt the cron
2. Redeploy the worker with the old contract address constants set to
   `0x0000000000000000000000000000000000000000` (disables the registry
   lookup without breaking legacy v1 behavior)
3. Revert `public/.well-known/ai.json` to the pre-patch version and redeploy

The deployed registry and verifier contracts are immutable and cannot be
removed, but they also do not consume resources if nothing interacts with
them. Leaving them on-chain is harmless.

---

## What this does not deploy

- The real Groth16 verifier — the stub is sufficient for end-to-end testing
  but must be replaced before real capital routes through the primitive. See
  `circuits/synthesis.circom` for the circuit statement and the follow-on
  work list.
- Coinbase Prime custody integration — that is Coinbase's job to build. See
  `FOUNDATION_SPEC.md` for the full production path handed to the Foundation.

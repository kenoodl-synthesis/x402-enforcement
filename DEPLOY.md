# Deployment Checklist

This document is the exact path from "reference code in a repo" to "live
primitive on Base with kenoodl's own stealth door verifying against it."

Everything below is concrete and runnable. Nothing is theoretical.

---

## Deployment of record (Base mainnet — April 12, 2026)

**The primitive is live.** The canonical kenoodl instance was deployed to Base mainnet on April 12, 2026. Two canonical synthesis offers are registered (USDC and ETH), an autonomous agent has successfully executed the full x402 v2 flow end-to-end against the primitive, and the refund guarantee has been verified via backfill refunds visible on-chain.

| Artifact | Address / Hash | Deploy Tx / Basescan |
|---|---|---|
| `OfferRegistry` contract | `0x359784adD213F2097D0F071310e82cD8f9a2A909` | [`0x62aaf585…9b3d71`](https://basescan.org/tx/0x62aaf5854f55ae3a79dcc23fb10be337e138bbbb49514cad7f593f568a9b3d71) |
| `StubSettlementVerifier` contract | `0x874c16A19FAAd011cfd1572F8BD28eD75D1Bb473` | [`0xe082d32e…6ebdc9`](https://basescan.org/tx/0xe082d32e4bc8a8678b3858d36a24c5f017be06590befda3e7c35dd4c736ebdc9) |
| USDC canonical offer (1 USDC flat, 45K char cap) | offerHash `0xd4a2ba4c4fb08eb915d513cdf8691c20bdf8a8bc67528274c2792c44a579947e` | [`0x531a734b…e566e2`](https://basescan.org/tx/0x531a734bb75010ae65c5ae7aad220eb4cc416e32b7521cd46319489b9ee566e2) |
| ETH canonical offer (0.0004 ETH, 45K char cap) | offerHash `0x5a6f21be44d456d9f75f667659c628cec24be31694d4cd7f170df1d28f9ee894` | [`0x3b9b9818…67c2a0a`](https://basescan.org/tx/0x3b9b9818c340a6afb35edb3a17bbb79593ea301e724960fc7f8400e8a67c2a0a) |
| First agent settlement (k's ETH x402 v2 flow) | — | [`0x9dd62ca5…5ffe464`](https://basescan.org/tx/0x9dd62ca56cfa4b0e2f68791529fbe83ac2c533b3c8a42b327422802645ffe464) |
| Backfill refund 1 (synthesis error recovered) | — | [`0x7df56663…a8afa8e3`](https://basescan.org/tx/0x7df566639b8bb2551e64a4ad2227910b67dee92808a36781896da6dda8afa8e3) |
| Backfill refund 2 (synthesis error recovered) | — | [`0x6c4093ac…03cffd39e`](https://basescan.org/tx/0x6c4093acb320f780a8a487a9ebd77d273d28d7b71ee5682f00d3ead03cffd39e) |

**Seller wallet for all registered offers:** `0x3A7292b88471691946D8D8856925e22246bed743` (the kenoodl stealth door wallet on Base, operational since January 2026).

**If you just want to use the canonical kenoodl instance** (no deployment needed), skip this document entirely. Read `QUICKSTART.md` — specifically "Path A" — and register your own offer against the already-live `OfferRegistry` address above. Gas cost: pennies.

**If you want to deploy your own independent instance** (different seller identity, different chain, different governance), continue below. The steps below are the exact commands used to produce the Deployment of record above, run from the CR wallet on April 12, 2026. You can rerun them verbatim with your own `DEPLOY_KEY` and get an identical (but independently-addressed) copy of the primitive.

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

Canonical offer JSON (7-field schema, byte-exact — any whitespace change or
field reordering produces a different hash). This is the exact USDC offer
kenoodl registered on Base mainnet:

```json
{"amount":"1000000","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","maxLatency":300,"maxRetries":3,"maxContextChars":45000,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

Field-by-field:

- `amount`: `"1000000"` — 1 USDC in 6-decimal base units
- `token`: Base USDC contract (use `0x0000000000000000000000000000000000000000` for native ETH)
- `maxLatency`: 300 seconds maximum delivery time
- `maxRetries`: 3 retries before permanent failure
- `maxContextChars`: 45000 character input cap (prevents flat-rate arbitrage)
- `serviceType`: `"synthesis"` (change to match your service category)
- `termsHash`: 32 zero bytes (or a hash of your side-document terms)

Compute the hash:

```bash
cast keccak '{"amount":"1000000","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","maxLatency":300,"maxRetries":3,"maxContextChars":45000,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}'
```

You should get exactly `0xd4a2ba4c4fb08eb915d513cdf8691c20bdf8a8bc67528274c2792c44a579947e`. That is the kenoodl USDC offerHash registered on Base mainnet.

Register (use the real REGISTRY_ADDRESS from your own Step 2 deploy OR the canonical kenoodl one at `0x359784adD213F2097D0F071310e82cD8f9a2A909`):

```bash
cast send $REGISTRY_ADDRESS \
  "registerOffer(bytes)" \
  "0x$(echo -n '{"amount":"1000000","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","maxLatency":300,"maxRetries":3,"maxContextChars":45000,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}' | xxd -p | tr -d '\n')" \
  --rpc-url base \
  --private-key $DEPLOY_KEY
```

For the native ETH canonical offer (the one kenoodl also registered):

```json
{"amount":"400000000000000","token":"0x0000000000000000000000000000000000000000","maxLatency":300,"maxRetries":3,"maxContextChars":45000,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

which hashes to `0x5a6f21be44d456d9f75f667659c628cec24be31694d4cd7f170df1d28f9ee894`.

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


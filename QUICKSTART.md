# QUICKSTART — Ship a Contract-Settlement-Proof Door in 15 Minutes

You have a service. You already have an x402 endpoint (or you're about to
build one). You want agents to transact with you at institutional scale.
This document gets you from zero to a live contract-settlement-proof door
on Base in about fifteen minutes, without reading anything else in this
repo first.

If you want the full picture, read `README.md` or `DOOR_DESIGN.md`. If you
want to ship right now, follow the seven steps below.

---

## What you need

- **Foundry installed.** One command: `curl -L https://foundry.paradigm.xyz | bash && foundryup`
- **A Base wallet with a private key.** If you already run any Base endpoint, you have this.
- **About $5 of Base ETH** for deployment gas (or free Base Sepolia ETH from a faucet for testing first).

---

## Step 1 — Get the code

```bash
git clone https://github.com/kenoodl-synthesis/x402-enforcement.git
cd x402-enforcement
```

Or, if you want to make this your own project from the start, click **"Use
this template"** at the top of the GitHub repo page and GitHub will create
your own fork in one click. Then clone your fork instead.

Or, if you already have a Foundry project and want to treat this as a
dependency:

```bash
forge install kenoodl-synthesis/x402-enforcement
```

All three paths work. Pick whichever fits your workflow.

---

## Step 2 — Build

```bash
forge build
```

You should see three contracts compile cleanly:
- `OfferRegistry` — the immutable offer store
- `ISettlementVerifier` — the verifier interface
- `StubSettlementVerifier` — the reference stub

If you see compilation errors, open an issue on the repo. Everything
should compile with Foundry default settings on `solc 0.8.20`.

---

## Step 3 — Deploy to Base Sepolia (testing)

Export your deployment key:

```bash
export DEPLOY_KEY=0x...  # your private key, starts with 0x
```

Deploy both contracts to Base Sepolia:

```bash
forge create contracts/OfferRegistry.sol:OfferRegistry \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY

forge create contracts/StubSettlementVerifier.sol:StubSettlementVerifier \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY
```

Record both addresses. You will need them in Step 4 and Step 5.

---

## Step 4 — Register your canonical offer

Decide what you're selling. Here is a synthesis-service example; replace
the fields with whatever your service actually provides:

```json
{"amount":"10000000000000000","maxLatency":300,"maxRetries":3,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

- `amount` — price in the smallest token unit (wei for ETH, 6-decimal base for USDC)
- `maxLatency` — seconds until delivery is considered late
- `maxRetries` — how many times your service can retry before permanent failure
- `serviceType` — a short identifier of what you sell (`synthesis`, `data-feed`, `compute-gpu`, `credential-kyc`, etc.)
- `termsHash` — any service-specific terms hashed (or zero if you have none yet)

Compute the hash (this is your `offerHash`):

```bash
cast keccak '{"amount":"10000000000000000","maxLatency":300,"maxRetries":3,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}'
```

Register the offer:

```bash
cast send $REGISTRY_ADDRESS \
  "registerOffer(bytes)" \
  "0x$(echo -n '{"amount":"10000000000000000","maxLatency":300,"maxRetries":3,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}' | xxd -p | tr -d '\n')" \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY
```

Confirm it worked:

```bash
cast call $REGISTRY_ADDRESS "verifyOffer(bytes32)(bytes)" $OFFER_HASH \
  --rpc-url base_sepolia
```

The call should return your canonical JSON bytes.

---

## Step 5 — Advertise the offerHash in your 402 response

When an agent hits your endpoint without paying, your 402 response must
include two new headers:

```http
HTTP/1.1 402 Payment Required
X-Offer-Hash: 0x<your offerHash from step 4>
X-Proof-Format: stub-v0
Content-Type: application/json
```

And the JSON challenge body must include three new fields:

```json
{
  "error": "payment-required",
  "offerHash": "0x<your offerHash>",
  "registryAddress": "0x<your registry address from step 3>",
  "verifierAddress": "0x<your verifier address from step 3>",
  "instructions": "Send the amount listed at OfferRegistry.verifyOffer(offerHash) to the kenoodl wallet, with offerHash in calldata after the selector."
}
```

Agents reading the 402 response will call `OfferRegistry.verifyOffer` via
`eth_call` before signing any payment transaction. If your terms match
their policy, they cross. If they don't, they walk. Either outcome is
correct.

**That's the minimum integration.** You are now running a
contract-settlement-proof door on Base Sepolia. Agents can verify exact
terms before committing payment.

---

## Step 6 — Test the loop end-to-end

Send a test payment transaction from a separate wallet with the v2
calldata format:

```
selector (4 bytes) = 0x73a6e5d5
offerHash (32 bytes) = your registered offerHash
requestHash (32 bytes) = any 32-byte hash
payload (variable) = your request, ECIES-encrypted if you use it
```

Your endpoint should:
1. Detect the v2 selector
2. Parse the offerHash
3. Call `OfferRegistry.verifyOffer(offerHash)` to confirm registration
4. Verify the transaction value ≥ offer amount
5. Process the request and produce a response
6. Send the response transaction with the v2 response format

If all six steps complete on Sepolia, you have verified the loop works
end-to-end on real infrastructure with test money. Move to Step 7.

---

## Step 7 — Promote to Base mainnet

Same commands from Steps 3 and 4, replacing `--rpc-url base_sepolia` with
`--rpc-url base`. Record the mainnet addresses. Update the `X-Offer-Hash`,
`registryAddress`, and `verifierAddress` values in your 402 response to
point at mainnet. Redeploy your endpoint.

**You are now running a contract-settlement-proof door on Base mainnet.**
Every agent hitting your endpoint can verify terms via one eth_call before
paying, and can verify delivery via the settlement verifier after.

Your service is now third-party auditable without any payload privacy
loss. Compliance engines at institutional counterparties can attest the
exchange was legitimate without holding your decryption keys.

---

## That's it

You shipped the primitive. Seven steps, fifteen minutes if you're fast,
thirty if you're careful. No audit required for the stub, no circom work
required for the stub, no custody integration required for the stub. Just
the reference contracts and your endpoint wired to them.

## What's next

The stub verifier is sufficient for end-to-end demonstration and for
proving the pattern works with your specific service. Before routing real
institutional capital through the primitive, replace the stub with a
Groth16 verifier compiled from the appropriate service-category circuit.
See `circuits/synthesis.circom` for the circuit specification and the
follow-on work list for producing a production verifier.

If your service category is one of the ones listed in the canonical set
(synthesis, data feeds, compute, credential issuance, physical-goods
attestation), watch the x402 Foundation's canonical verifier registry for
audited circuits you can plug in as a drop-in replacement. The
`ISettlementVerifier` interface is stable — swapping the stub for a real
verifier is a single line in your endpoint code.

If your service category is new, propose a circuit specification through
the x402 Foundation's process (see `FOUNDATION_SPEC.md`).

---

## One sentence summary

You have a door. Agents hit it. They do not cross because they cannot
verify what they're paying for. Deploy these two contracts, add two HTTP
headers and three JSON fields, and agents can verify terms in one eth_call
before signing. Your door is now walkable. Ship.

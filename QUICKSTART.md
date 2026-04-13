# QUICKSTART — Ship a Contract-Settlement-Proof Door in 15 Minutes

You have a service. You already have an x402 endpoint (or you're about to
build one). You want agents to transact with you at institutional scale.
This document gets you from zero to a live contract-settlement-proof door
on Base in about fifteen minutes, without reading anything else in this
repo first.

If you want the full picture, read `README.md` or `DOOR_DESIGN.md`. If you
want to ship right now, follow the seven steps below.

---

## Two paths to walkable door

**Path A (fastest — 5 minutes):** Register your offer against the **canonical kenoodl OfferRegistry already deployed on Base mainnet**. No contracts to deploy, no gas for deployment, just register your offer and start pointing agents at it. This is the right path if you want to share an ecosystem-wide registry with kenoodl and other builders.

- Canonical OfferRegistry on Base mainnet: [`0x359784adD213F2097D0F071310e82cD8f9a2A909`](https://basescan.org/address/0x359784adD213F2097D0F071310e82cD8f9a2A909)
- Canonical StubSettlementVerifier on Base mainnet: [`0x874c16A19FAAd011cfd1572F8BD28eD75D1Bb473`](https://basescan.org/address/0x874c16A19FAAd011cfd1572F8BD28eD75D1Bb473)

Skip to **Step 4** below (register your offer) and use the canonical addresses above for `$REGISTRY_ADDRESS` and `$VERIFIER_ADDRESS`. Steps 1-3 are only for Path B.

**Path B (self-hosted — 15 minutes):** Deploy your own OfferRegistry and StubSettlementVerifier. Use this if you want full control over the registry governance, want to run on a different chain, or just prefer not to depend on an existing deployment. Follow all seven steps below.

---

## What you need

- **Path A only:** a Base wallet with ~$0.01 of Base ETH for a single `registerOffer` transaction, and a Base RPC endpoint (public works — `https://base.llamarpc.com` is fine)
- **Path B only:** Foundry installed (`curl -L https://foundry.paradigm.xyz | bash && foundryup`) plus ~$5 of Base ETH for deployment gas, or free Base Sepolia ETH from a faucet

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

Decide what you're selling. Here is the exact canonical offer kenoodl registered for its USDC synthesis door on Base mainnet. Use it as a template; replace the fields with whatever your service actually provides:

```json
{"amount":"1000000","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","maxLatency":300,"maxRetries":3,"maxContextChars":45000,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}
```

- `amount` — price in the smallest token unit (wei for native ETH, 6-decimal base for USDC)
- `token` — the ERC-20 token contract address (use `0x0000000000000000000000000000000000000000` for native ETH)
- `maxLatency` — seconds until delivery is considered late
- `maxRetries` — how many times your service can retry before permanent failure
- `maxContextChars` — the maximum input payload size the offer commits to (prevents price arbitrage on flat-rate offers)
- `serviceType` — a short identifier of what you sell (`synthesis`, `data-feed`, `compute-gpu`, `credential-kyc`, etc.)
- `termsHash` — any service-specific terms hashed (or zero if you have none yet)

**Field order is load-bearing.** The `offerHash` is Keccak-256 of the byte-exact JSON with fields in this exact order and no whitespace. If you reorder or add whitespace, you get a different hash that will not match the registered offer.

Compute the hash (this is your `offerHash`):

```bash
cast keccak '{"amount":"1000000","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","maxLatency":300,"maxRetries":3,"maxContextChars":45000,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}'
```

For the exact JSON above you should get:

```
0xd4a2ba4c4fb08eb915d513cdf8691c20bdf8a8bc67528274c2792c44a579947e
```

That is the real kenoodl USDC canonical offer hash, already registered on Base mainnet. **If you are following Path A, you do not need to register this offer again** — you can point agents at this hash directly. Register a NEW offer only if your service/price differs from kenoodl's.

**Before registering, set your registry target:**

```bash
# Path A (canonical mainnet registry):
export REGISTRY_ADDRESS=0x359784adD213F2097D0F071310e82cD8f9a2A909
export RPC_URL=https://mainnet.base.org

# Path B (your own Sepolia deploy from Step 3):
# export REGISTRY_ADDRESS=0x<your deployed registry address>
# export RPC_URL=base_sepolia
```

Register the offer (the same command works for both paths — only the environment variables differ):

```bash
cast send $REGISTRY_ADDRESS \
  "registerOffer(bytes)" \
  "0x$(echo -n '{"amount":"1000000","token":"0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913","maxLatency":300,"maxRetries":3,"maxContextChars":45000,"serviceType":"synthesis","termsHash":"0x0000000000000000000000000000000000000000000000000000000000000000"}' | xxd -p | tr -d '\n')" \
  --rpc-url $RPC_URL \
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


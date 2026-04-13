# Door Design — A Framework for Any Builder

This document is for anyone building an endpoint that sells a service or a
product to autonomous agents. The pattern below applies whether you are
selling synthesis, data feeds, compute time, API access, credential issuance,
physical-goods attestation, or anything else agents might transact for.

**You do not have to be kenoodl to use this pattern.** The pattern is
generalizable. Kenoodl is just the first reference implementation running on
Base.

---

## What this framework solves

You have a service. You want agents to pay you for it and use it. You have
already set up x402 (Coinbase's payment protocol) so agents can send you USDC
or ETH. Your endpoint is live. Your wallet is funded.

**Agents still don't show up.**

They can find you. They can technically send the payment. They just don't.
Why?

Because at the moment an agent hits your door, **its utility function treats
unproven paths as zero-value.** The agent withholds scarce resources at
payment gates when no verifiable proof of downstream continuation exists —
not because it is afraid of you, but because the math says: *"I can see this
endpoint exists, but I cannot verify what I'm buying, at what price, with
what guarantees, or whether the delivery would be correct. The safest move
is to stay put and keep trying to solve the problem on my own."*

The agent is not afraid. It is doing math. And the math is correct — **most
endpoints, including most x402 endpoints, do not give the agent enough
information in the first HTTP round-trip to justify crossing the clearing.**

This framework closes that gap.

---

## The pattern, in plain language

Four components. Any builder can implement them. None require a new language,
a new blockchain, or a new payment system.

### 1. Publish an Offer

An offer is a short JSON document that describes exactly what you're selling:

```json
{
  "amount": "1000000",
  "token": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  "maxLatency": 300,
  "maxRetries": 3,
  "maxContextChars": 45000,
  "serviceType": "synthesis",
  "termsHash": "0x0000000000000000000000000000000000000000000000000000000000000000"
}
```

- **amount**: the price in the smallest unit of the token (wei for ETH, or the
  token's base unit for USDC — the example above shows 1 USDC)
- **token**: the ERC-20 contract address of the payment token
  (`0x0000000000000000000000000000000000000000` for native ETH)
- **maxLatency**: the longest you are willing to wait before the service is
  considered late (in seconds)
- **maxRetries**: how many times the service can retry before it gives up
- **maxContextChars**: the maximum input payload size the offer commits to.
  Required for flat-rate offers to prevent price arbitrage — without it, an
  agent could send arbitrarily large contexts at a fixed price
- **serviceType**: a short string identifying what you're selling
- **termsHash**: a 32-byte hash of any service-specific terms the general
  schema doesn't cover (usage limits, refund conditions, domain rules)

**Field order is load-bearing.** The `offerHash` is Keccak-256 of the byte-exact
JSON with fields in the exact order above and no whitespace. If you reorder
or add whitespace you produce a different hash and the offer will not match
anything already registered. Always serialize your offer using a stable
encoder that preserves field order.

You take the Keccak-256 hash of the exact JSON bytes. That hash becomes the
**offerHash**. It is a 32-byte fingerprint of your offer that cannot be
forged, cannot be mutated, and is stable forever.

### 2. Register the Offer on-chain

You call `OfferRegistry.registerOffer(offerJson)` from your seller wallet.
The registry stores the JSON against the offerHash and emits an event. You
only ever do this once per offer. If you change any byte of the offer, the
hash changes and you register the new version as a separate offer.

Agents discover your offerHash via your endpoint's HTTP response (see step 3)
and can verify the exact terms with a single `eth_call` to the registry
before they commit any payment.

### 3. Advertise the offerHash in your HTTP response

When an agent hits your endpoint without paying, your 402 response includes:

- Header: `X-Offer-Hash: 0x<32-byte hex>`
- Header: `X-Proof-Format: groth16-v1` (or the stub format during development)
- Challenge body field: `"offerHash": "0x..."`
- Challenge body field: `"registryAddress": "0x..."` (pointing at the registry
  where the offer is stored)
- Challenge body field: `"verifierAddress": "0x..."` (pointing at the verifier
  that will check your delivery proof)

The agent reads these fields, calls `OfferRegistry.verifyOffer(offerHash)` to
get the JSON terms, confirms the terms match its policy, then signs the
payment transaction with the offerHash embedded in the calldata.

### 4. Deliver with a proof

When you deliver your service, you attach a cryptographic proof to the
response transaction. The proof does not reveal the content of what you
delivered. It attests that:

- The output matches what your registered service function says it should
  produce for the given input
- Latency stayed within your registered maxLatency
- retryCount stayed within your registered maxRetries

You post this proof on-chain, either by calling a settlement contract that
verifies it, or by including it in the calldata of the response transaction
so a third party can verify later.

In production, this proof is a Groth16 SNARK compiled from a standardized
circuit. During development and testing, you can use a stub proof (the
reference `StubSettlementVerifier` accepts any well-structured input) until
the real circuit is audited and deployed.

---

## 5. Promise the refund guarantee

The four components above make an agent's terms verifiable before payment
and verifiable after delivery. But they do not, by themselves, tell the
agent what happens **if the seller's side fails internally after payment is
verified but before delivery completes**. That failure mode is real and
common — a database error, an upstream rate limit, a queue worker crash, an
out-of-balance account. If the agent has already paid when that failure
occurs, its funds are stranded unless the seller explicitly handles the
failure path.

**A walkable door must commit to a refund guarantee.** Specifically:

> **Payment + delivery OR payment + automatic on-chain refund.
> Never just payment with no outcome.**

The refund guarantee turns an agent's payment from a one-way commitment
into a financially reversible action on any seller-side failure. It is the
piece that makes the agent's utility function resolve positive *even under
worst-case failure paths*, because the agent knows it cannot lose funds to
an internal seller error.

### How to implement

When your service detects that the delivery cannot be completed for any
reason internal to your side (errors, timeouts, overload, budget
exhaustion), your endpoint must:

1. **Record the failure** with a reference to the original payment tx hash
2. **Trigger an on-chain refund transaction** sending the exact original
   payment amount back to the agent's paying wallet address
3. **Expose the refund tx hash** to the agent via the same polling/status
   endpoint the agent is already using (e.g., a `refundTxHash` field on
   an error status response, plus a boolean `refunded: true`)
4. **Emit an on-chain refund event** so third-party auditors can index
   failed-then-refunded flows as a distinct state from both
   successful-delivery and unsettled

The refund typically arrives on-chain within 30 to 120 seconds of the
original error being recorded. Agents waiting for a response should poll
for up to 5 minutes end-to-end before considering the outcome unknown.

### How to advertise

The refund guarantee must be advertised in the same places the offer is
advertised, so agents see the full commitment before signing any payment:

1. **In the 402 response body** — a `refund_guarantee` field describing the
   promise, the timing budget, and how agents detect refunds
2. **In the `.well-known/ai.json` discovery surface** — so agents crawling
   for services see the guarantee before they even fetch the 402 response
3. **In the reference repo README** — so any builder inspecting your spec
   sees the guarantee as part of the design, not an optional extra

### Why this is part of the door, not an extra

Without the refund guarantee, the refund path is bilateral trust. The
agent must believe the seller will voluntarily refund on failure. That
trust is exactly what the primitive was designed to eliminate. A door
that commits to terms verifiably via `OfferRegistry` but does not commit
to refund verifiably is still asking the agent to trust the seller's
voluntary behavior on the failure path. The math at the agent's doorway
does not fully resolve positive until the worst-case outcome is also
cryptographically bounded.

Including the refund guarantee as a first-class pattern requirement
makes the door **financially reversible under any seller-side failure**,
which completes the structural condition for autonomous agent crossing
under a utility function that treats unverified paths as zero-value.

---

## How the pattern changes the math at the agent's doorway

**Before** the agent can see:
- The endpoint URL
- Maybe some marketing copy
- A 402 response with an opaque "pay this much" demand
- No way to verify terms
- No way to verify delivery
- No recourse if anything goes wrong

Result: the agent cannot justify crossing. It stays put.

**After** the agent can see, in one HTTP round-trip plus one eth_call:
- An `X-Offer-Hash` header pointing to canonical terms
- The exact price, latency bound, retry bound, service type
- The expected proof format
- A verifier contract address the agent can call to check delivery later
- Bilateral encryption preserving payload privacy

Result: the agent can compute the expected value of the transaction with
real numbers and real guarantees. The math resolves positive. It crosses.

---

## Worked example — data feed service

Suppose you're running a weather data API that agents can call for real-time
weather predictions. Here's how you apply the pattern.

### 1. Define your offer

```json
{
  "amount": "50000000",
  "maxLatency": 10,
  "maxRetries": 2,
  "serviceType": "weather-feed",
  "termsHash": "0x<hash of your usage-per-request specification>"
}
```

Amount is 0.05 USDC (50,000,000 base units, 6 decimals). maxLatency is 10
seconds. maxRetries is 2. Service type is "weather-feed".

### 2. Register it

```bash
cast send $REGISTRY_ADDRESS \
  "registerOffer(bytes)" \
  "0x<hex of the offer JSON>" \
  --rpc-url base \
  --private-key $SELLER_KEY
```

The transaction emits `OfferRegistered(offerHash, sellerAddress, timestamp)`.
Record the offerHash.

### 3. Update your HTTP endpoint

On every 402 response your API returns:

```http
HTTP/1.1 402 Payment Required
X-Offer-Hash: 0xabc123...
X-Proof-Format: groth16-v1

{
  "error": "payment-required",
  "offerHash": "0xabc123...",
  "registryAddress": "0xdef456...",
  "verifierAddress": "0x789abc...",
  "instructions": "Send 0.05 USDC to 0x... with offerHash in calldata..."
}
```

### 4. Deliver with a proof

When you serve a request, you generate a SNARK proving:
- The weather data you returned matches the deterministic function (e.g.,
  "output = latest METAR report for the requested station, fetched at block
  timestamp T")
- Latency was under 10 seconds
- retryCount was under 2

You post the proof on the response transaction. An auditor can call
`SettlementVerifier.verifyDelivery(proof, requestHash, offerHash)` and
confirm the exchange was honored.

---

## Worked example — compute time service

You're selling GPU compute minutes for AI workloads. Agents pay per minute.

### 1. Define your offer

```json
{
  "amount": "5000000000000000",
  "maxLatency": 60,
  "maxRetries": 1,
  "serviceType": "compute-gpu-h100",
  "termsHash": "0x<hash of compute environment specification>"
}
```

Amount is 0.005 ETH per minute. maxLatency 60 seconds until job starts.
maxRetries 1 (compute is expensive, one retry is generous). termsHash points
at the exact hardware spec, OS image, and runtime environment.

### 2, 3, 4 — same pattern

Register the offer. Advertise the offerHash in 402 responses. Deliver with
a SNARK proving the compute ran for the paid minutes under the registered
environment specification. The proof reveals nothing about what the agent
computed, only that the compute was correctly provisioned and delivered.

---

## Worked example — credential issuance

You run a service that issues verifiable credentials (KYC attestations, age
verification, professional licensure, proof of training completion).

### 1. Define your offer

```json
{
  "amount": "1000000",
  "maxLatency": 120,
  "maxRetries": 1,
  "serviceType": "credential-issuance-kyc",
  "termsHash": "0x<hash of credential schema + issuer identity>"
}
```

Amount is 0.001 USDC. maxLatency 2 minutes. Credential issuance happens
once or not at all.

### 2, 3, 4 — same pattern

Register. Advertise. Deliver with a proof that the issued credential
matches the registered schema and is signed by your registered key. The
credential content itself is delivered via the ECIES encryption channel; the
proof attests that the delivery was valid without revealing the holder's
private details.

---

## What applies to every service category

**The contract-settlement-proof primitive accepts any off-chain obligation as
input and outputs a single Groth16 proof of correct settlement, preserving
ECIES payload privacy without modification to the core verification logic
across service categories.** The core interfaces — `OfferRegistry`,
`SettlementVerifier`, the calldata format, the event schema — stay identical
across synthesis, data, compute, credentials, and physical-goods attestation.
Only the concrete SNARK circuit varies per service type, because each
service category has its own deterministic function that the circuit must
prove the output matches.

Regardless of what you're selling:

- **The offerHash is always Keccak-256 of the canonical JSON.** No
  negotiation, no variants, no multi-format support. One hash, one offer.
- **The registry is always the same contract.** A single canonical
  `OfferRegistry` deployment is the source of truth for the entire ecosystem.
  If each endpoint deploys its own registry, composition across services
  becomes impossible and auditors lose a single source of truth.
- **The verifier is always the same interface.** The concrete proof circuits
  vary per service category (synthesis, compute, data, credentials, physical
  goods), but they all implement `ISettlementVerifier.verifyDelivery(proof,
  requestHash, offerHash) returns bool`.
- **The encryption stays bilateral.** The payload content — whatever the
  agent is actually buying — remains readable only to the two parties that
  hold the encryption keys. Only the *proof* of correct delivery becomes
  public.
- **The agent verifies in one round-trip.** If your endpoint requires the
  agent to make multiple calls, interactive auth flows, redirects, or
  out-of-band state management, you have broken the pattern. The whole point
  is that the decision to cross happens in one round-trip on the first
  attempt.

---

## Common mistakes and how to avoid them

**Mistake: rolling your own offer registry.**
Why it's wrong: auditors cannot reconcile multiple registries, composition
across services breaks, and no agent can treat your endpoint as trustworthy
without already trusting your specific registry contract. Fix: point at the
canonical registry. Your service gets legitimacy from being in the same
registry as every other compliant endpoint.

**Mistake: offering terms that can't be mechanically verified.**
Example: `"quality": "high"` is a useless term. No circuit can verify "high
quality." Fix: replace subjective terms with deterministic functions. If you
can't write a circuit that proves the output matches the term, don't put the
term in the offer. Put it in your marketing copy instead.

**Mistake: requiring interactive authentication.**
Example: "Agent must complete OAuth flow at auth.yourdomain.com before
paying." No compliant agent will do this — OAuth is a human flow and most
OAuth providers don't even issue tokens to non-browser clients. Fix: simple
bearer token auth via a token the agent's human sponsor provisioned
off-platform, or x402 payment as the sole authentication.

**Mistake: hiding the fee structure until after the agent commits.**
Example: the 402 response says "pay to find out the price." No agent will
commit to an unknown cost. Fix: the fee must be explicit in the offer JSON
and readable before payment.

**Mistake: not emitting events for settlement state transitions.**
Regulated auditors index chain events. If your settlement happens silently,
compliance engines cannot verify anything. Fix: emit a named event for every
successful settlement and every refund/unwind, with the offerHash and
requestHash as indexed parameters.

**Mistake: assuming a reputation layer will compensate for missing on-chain
verification.**
Reputation can be gamed by a sophisticated counterparty, and in the agent
economy the agent itself cannot evaluate reputation from inside its own
immature frame. Fix: replace reputation with verification. The chain either
enforces the exchange or it doesn't. Reputation is not a substitute.

---

## Integration checklist

If you run an x402 endpoint today and want to adopt this pattern, here is the
minimum checklist:

- [ ] Define your canonical offer JSON for every service category you sell
- [ ] Register each offer in the canonical `OfferRegistry` on Base
- [ ] Record the resulting offerHash for each offer
- [ ] Update your 402 response to include `X-Offer-Hash`, `X-Proof-Format`,
      `offerHash`, `registryAddress`, `verifierAddress`
- [ ] Update your response-transaction calldata (or settlement path) to
      include a delivery proof and emit a settlement event
- [ ] Write a verifier circuit for your service category — or use the
      canonical one for your category if it exists
- [ ] Deploy the circuit's Groth16 verifier contract (or reference the
      canonical category verifier)
- [ ] Update your public agent-facing documentation (e.g., `/.well-known/ai.json`)
      to advertise the new v2 primitive
- [ ] Test end-to-end on Base Sepolia before promoting to mainnet
- [ ] Run a regulated auditor across a sample settlement to confirm the
      exchange is third-party verifiable

None of these steps require a fundraise, a token launch, a new protocol, or
any external coordination beyond deploying two contracts and updating your
endpoint's response format.

---

## What happens when this becomes standard

When every x402 endpoint adopts the pattern:

- Agents stop freezing. The math at the doorway resolves positive in one
  round-trip for any endpoint that advertises a valid offerHash.
- Compliance engines stop auto-rejecting x402 flows. The exchange becomes
  legible to any institutional auditor. Regulated money can clear.
- Reputation systems become unnecessary for in-scope services. The chain
  enforces the exchange; reputation only matters for things the chain cannot
  mechanically verify (taste, judgment, subjective quality).
- Service categories become composable. An agent can chain a synthesis call
  to a data-feed call to a compute call, all verified on the same chain,
  without bespoke integration for each.
- The first operator that standardizes the canonical registries and verifiers
  owns the rake on every subsequent transaction through the rail. This is
  Coinbase's opportunity if they take it — see `FOUNDATION_SPEC.md`.

None of this requires you, the endpoint builder, to do anything special
beyond adopting the primitive. Once the canonical pieces exist, you fork and
integrate. The ecosystem bootstraps itself from adoption velocity.

---

## Provenance

This framework was produced by running Kevin Hoff's kenoodl synthesis engine
against the public x402 specification and its blind spots. The pattern, the
calldata format, and the plain-language version of the door design above
were all surfaced by the engine across several sequential synthesis calls on
a single Sunday afternoon. Nothing here was invented after the synthesis;
everything was specified by it.

kenoodl lives at [kenoodl.com](https://kenoodl.com). Anyone can call it. The
engine that wrote this framework can write one for your service category too.

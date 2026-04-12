# FOUNDATION_SPEC.md

## A production specification for embedding a contract-settlement-proof primitive in x402

*An open specification handed to Coinbase's x402 Foundation as a 90-day
production path. Not prescriptive. Not a pitch. A specification document
with proofs of necessity for each addition, produced by a running reference
implementation on Base mainnet, offered for adoption.*

---

## Executive summary

The x402 specification currently covers the payment half of an agent-to-agent
transaction: HTTP 402 response, USDC or ETH transfer, settlement of value on
Base. It does not yet cover the contract half (what was promised), the
settlement logic (whether it was delivered), or the proof layer (whether
both sides performed).

Those three layers are the gap institutional capital cannot cross at scale.
Every x402 flow above trivial size is, from the compliance officer's
perspective, an off-chain promise wrapped in on-chain money. Compliance
engines auto-reject the entire class.

This document specifies the minimum production additions to x402 and its
surrounding infrastructure that close the gap. The primitive is small,
precise, and buildable. A working reference instance of the primitive has
been running on Base since early 2026 at kenoodl's stealth door. The
specification below generalizes that instance into a protocol-standard any
x402 endpoint can adopt.

**The one-sentence claim:** Without the contract-settlement-proof primitive
embedded in x402, the chain remains only a payment rail and can never become
the enforcement layer that agents require before they will move institutional
capital at scale.

---

## The primitive (summary)

Four on-chain components, already implemented in a reference form at
`github.com/<TBD>/x402-enforcement`:

- **offerHash** — a 32-byte Keccak-256 digest of canonical offer JSON,
  embedded in the inbound transaction calldata immediately after the selector.
- **OfferRegistry** — an immutable contract mapping offerHash → canonical
  offer JSON. Sellers register once; buyers verify terms with one eth_call
  before paying.
- **Delivery proof** — a Groth16 SNARK attached to the response transaction,
  proving in zero-knowledge that the output satisfies the registered service
  function under the registered terms, within the registered latency and
  retry bounds. ~192 bytes plus public inputs. Payload content stays
  bilaterally encrypted; only the proof of correctness becomes public.
- **SettlementVerifier** — an abstract on-chain verifier accepting the proof
  plus public inputs, returning bool. Auto-settlement and auto-refund route
  off this return value.

**The primitive accepts any off-chain obligation as input and outputs a
single Groth16 proof of correct settlement, preserving ECIES payload
privacy without modification to the core verification logic across service
categories** — synthesis, data feeds, compute, physical-goods attestation,
credential issuance, API access, anything. The concrete SNARK circuit varies
per service type; the primitive itself does not. No new languages, no new
chains, no new payment rails.

---

## The gap, named precisely

The stealth door at Base wallet `0x3A7292b88471691946D8D8856925e22246bed743`
routes contract enforcement and automated settlement through the chain in
ways that exceed simple payment rails today. An inbound transaction to the
kenoodl wallet carries calldata formatted as a 4-byte selector followed by a
32-byte request hash and an ECIES-encrypted payload. A response transaction
carries its own selector and an ECIES-encrypted result. Retry logic persists
failed deliveries and re-attempts on subsequent cron ticks. Refund-equivalent
unwinds trigger on permanent failure.

Those mechanics live entirely on-chain in calldata formats, emitted events,
and persistent contract state. **Kenoodl's stealth door used ECIES to
deliver bilateral security and ungameability to the two transacting parties
while keeping payload content invisible to any third party lacking the
decryption keys.** That is the security property the existing mechanism
holds today. The mechanism needs no off-chain reputation or human
escalation between the two parties.

**But the remaining gap is critical:** external auditors scanning only the
chain see paired encrypted blobs and a mechanical retry loop without any
machine-readable anchor to what was actually promised or cryptographic proof
that delivery matches the promise. An observer scanning only the chain
cannot read the offer price, the latency bound, the success criteria, or
the exact service type before the transaction commits, because no
pre-registered terms hash exists in the event or calldata. They also cannot
cryptographically verify that the response transaction constitutes correct
delivery rather than garbage; the ECIES decryption key pair stays bilateral,
so semantic matching of input request to output result lives off-chain in
the parties' local cognition.

**Settlement is therefore automated but not externally auditable for
correctness. No third party can confirm both sides performed without
trusting the decryption step.**

Coinbase's x402 specification stops at exactly that blind spot. Because the
contract layer, the settlement logic, and the delivery proof are absent,
regulated counterparties treat every x402 flow above trivial size as an
off-chain promise wrapped in on-chain money. Compliance engines therefore
auto-reject the entire class of transaction. The only path that survives
institutional review is to embed the full contract-settlement-proof primitive
directly into the x402 specification and its surrounding custody rails so
that an agent can discover, verify, and settle inside one HTTP round-trip
plus a single eth_call before any capital commits.

---

## Section 1 — Protocol-level additions to the x402 specification

### Mandatory HTTP response headers

Every x402-compliant endpoint advertising contract-settlement-proof support
SHALL return the following headers on all 402 responses:

- `X-Offer-Hash: 0x<32-byte hex>` — Keccak-256 digest of canonical offer JSON
- `X-Proof-Format: <format identifier>` — literal string identifying the
  proof format, e.g., `groth16-v1` for the canonical audited circuit family

### Mandatory 402 challenge object fields

The JSON payload of the 402 response SHALL include:

```json
{
  "offerHash": "0x...",
  "registryAddress": "0x...",
  "verifierAddress": "0x..."
}
```

Where `registryAddress` points to the canonical `OfferRegistry` contract
deployment and `verifierAddress` points to the canonical `SettlementVerifier`
for the relevant service category.

### Minimal spec language addition

A single paragraph in the x402 specification document:

> An endpoint advertising full contract-settlement-proof support SHALL emit
> the `X-Offer-Hash` and `X-Proof-Format` headers on every 402 response and
> SHALL populate the `offerHash`, `registryAddress`, and `verifierAddress`
> fields in the challenge object. Agents MAY verify the offer via a single
> `eth_call` to `OfferRegistry.verifyOffer(offerHash)` before signing any
> payment transaction. Absence of these headers and fields signals
> payment-only behavior; agents operating above a risk threshold SHOULD
> reject such endpoints until compliance is confirmed.

**Proof of necessity:** without these headers and fields, an agent cannot
pre-verify terms or expected proof format on the wire. Every compliance
policy engine therefore blocks the flow at the gateway, exactly as it does
today for all off-chain-promise-wrapped transactions.

---

## Section 2 — Canonical on-chain registries

Coinbase SHALL operate **one canonical immutable OfferRegistry** at a single
address published in two places:

- In the x402 specification document itself
- At `coinbase.com/.well-known/x402-registry.json` as machine-readable metadata

Every endpoint registers its offerHash against this single contract rather
than spinning up per-endpoint copies that auditors could never reconcile.

Coinbase SHALL similarly deploy and maintain **one canonical SettlementVerifier
contract**, upgradeable only through a **2-of-3 multisig** whose seats are
permanently held by:

- Coinbase Legal
- Coinbase Engineering
- An independent audit firm selected by the previous two

Forks of either contract are permitted but must be explicitly whitelisted
by each agent's compliance layer. The default verification path always
routes through the Coinbase-owned addresses.

**Proof of necessity:** without a single canonical pair of contracts, forks
proliferate, auditors lose a single source of truth, and regulated
counterparties cannot attest that the verification surface itself is stable
under audit. That fragmentation alone is enough to keep institutional volume
outside the primitive.

---

## Section 3 — Custody and compliance infrastructure

The custody layer that actually moves real money must be **Coinbase Prime
itself**. The integration SHALL:

- Wire automatic SNARK-verified settlements through compliance-attested
  stablecoin wrappers
- Back every settlement with KYC'd validator attestations
- Back every settlement with AML attestations tied to the validator's
  regulated entity
- Release held USDC or ETH directly to the seller's attested address when
  `SettlementVerifier.verifyDelivery` returns true
- Refund atomically to the buyer's attested address when verification fails
  or the timeout bound elapses, through the same rail, without manual bridges
  or trusted intermediaries

**Proof of necessity:** anonymous permissionless custody cannot replicate
this because it cannot issue the regulatory attestations that move capital
under audit. A compliance officer will not sign off on funds whose origin,
destination, and settlement logic sit behind an unaudited wrapper. Omit the
Prime integration and the primitive collapses to speculative crypto rails
that regulated counterparties will not touch at size.

**Coinbase is the only entity that currently combines Prime custody rail,
live compliance attestations, regulated stablecoin wrappers, and institutional
banking integrations sufficient to run the full contract-settlement-proof
primitive under audit from day one.** Other regulated custodians or
consortia may assemble equivalent rails eventually, but none hold all four
pieces today. That present-tense combination is the structural advantage
Coinbase can use inside a 90-day window while it still exists.

---

## Section 4 — SNARK circuit standardization and audit

The delivery-proof SNARK cannot be ad hoc. Every endpoint using a different
circuit would fragment verification and make composition impossible.

Coinbase SHALL:

- Curate, fund, and publish audited Groth16 circuit families for each
  standard service category:
  - `synthesis-v1`
  - `data-feed-v1`
  - `compute-v1`
  - `physical-attestation-v1`
  - `credential-issuance-v1`
  - `identity-verification-v1`
- Hold the public verification keys inside the canonical `SettlementVerifier`
- Audit each circuit via firms already on Coinbase's approved roster
- Publish audit results with cryptographic receipts tied back to the verifier
  contract
- Accept new circuit proposals through a transparent process; audit them;
  append to the verifier only after the 2-of-3 multisig signs the updated
  verifier

Audit costs are funded directly from the rake Coinbase extracts on settled
volume through the rail. **No token issuance is required** at any point in
the circuit standardization process.

**Proof of necessity:** without standardized, audited circuits, verification
fragments across endpoints, composition across services becomes impossible
under audit, and compliance teams treat the entire proof surface as
untrustworthy. Each endpoint's ad-hoc circuit would require independent
audit by every regulated counterparty before any capital could flow,
multiplying audit cost by the number of endpoints and effectively ruling
out institutional adoption.

---

## Section 5 — Auto-settlement and refund mechanics at the custody rail

When the SettlementVerifier contract returns true, Prime releases the held
USDC or ETH directly to the seller's attested address through the same
custody rail used for every other institutional Coinbase Prime client. When
verification fails, or the timeout bound elapses without a valid proof
being submitted, the same rail refunds atomically to the buyer's attested
address without manual bridges, customer-service tickets, or trusted
intermediaries.

The integration surface:

- On-chain: SettlementVerifier.verifyDelivery() returns bool, consumed by the
  custody bridge contract that holds buyer-locked capital in escrow
- Off-chain: Prime custody operations observe the bridge contract events and
  execute the corresponding fiat/USDC wire transfers through the standard
  institutional-client attestation pipeline
- Legal wrapper: the same custody services agreement Prime uses for every
  other institutional client, extended by one standardized amendment
  describing the x402 settlement integration

**Proof of necessity:** without integration at the custody rail itself,
settlement remains a bridge problem, requires manual reconciliation, and
fails every regulated counterparty's operational-risk review. A compliance
officer will not approve capital flowing through a primitive whose
settlement step requires human intervention or off-chain bridge trust.

---

## Section 6 — The single-round-trip verification model for agents

A compliant agent follows this exact sequence to verify that a candidate
x402 endpoint is running a full contract-settlement-proof primitive, in a
single HTTP round-trip plus one to two optional `eth_call` reads:

1. **Issue the HTTP request** to the candidate endpoint. Receive a 402
   response.
2. **Parse the response headers** — extract `X-Offer-Hash` and
   `X-Proof-Format`. If either is missing, reject the endpoint as
   payment-only.
3. **Parse the 402 challenge body** — extract `offerHash`, `registryAddress`,
   `verifierAddress`. Confirm `offerHash` in headers matches body.
4. **Call `OfferRegistry.verifyOffer(offerHash)`** on the registry address
   via a single `eth_call`. Receive the canonical JSON terms.
5. **Compare terms against policy** — amount, maxLatency, maxRetries,
   serviceType. Reject if mismatch.
6. **(Optional) Confirm the verifier contract matches expected implementation** —
   check bytecode hash or published attestation.
7. **Sign the payment transaction** with `offerHash` embedded in calldata
   after the selector.
8. **After the response lands, verify delivery** — call
   `SettlementVerifier.verifyDelivery(proof, requestHash, offerHash)` from
   the `StealthProof` event's public inputs. True means delivery is
   cryptographically correct under the registered terms.

Total cost: **one HTTP round-trip + one mandatory eth_call (the registry
lookup) + one optional eth_call (the verifier check) + roughly 200,000 gas
on Base**. That sequence fits inside any autonomous agent's decision loop
without introducing off-chain lookups beyond the canonical Coinbase
registries.

**Proof of necessity:** without a fixed, cheap verification model, every
agent implementation would need custom code to talk to every endpoint, and
the primitive would fail to scale. The single-round-trip pattern is what
makes the primitive composable across services and agents at the code level.

---

## Section 7 — Revenue model at steady state

Once the primitive is live as a protocol-standard across x402, the agent
economy changes in one mechanical way: **capital can now commit to a
contract whose terms, performance, and settlement are all visible and
enforceable on-chain.** Synthesis, data delivery, compute, and credential
issuance become interchangeable primitives that agents compose without
bilateral trust or customer-service overhead.

### Flows at steady state

Every successful x402 transaction routed through the Prime-backed primitive
distributes as follows:

- **Coinbase protocol rake: 15 basis points** on every settled flow through
  the Prime rail. Funds treasury operations, oracle upgrades, audit costs,
  liquidity incentives.
- **Validators + auditors: 5 basis points each** to the validator set
  running the standardized circuits and the audit firms attesting to their
  ongoing soundness. Paid automatically on successful verification.
- **Endpoint operator: remaining 75 basis points minus gas.**

**The primitive's steady-state revenue is drawn exclusively from capital
whose owners have already chosen to cross the risk threshold via binding
contract settlement, with no token issuance or inflationary mechanism at any
layer.** Every basis point paid to every participant originates from a
buyer's own capital that has already committed to an enforceable exchange.
**No inflation subsidizes the loop.**

### Example economic path

An agent pays $100 in USDC for a compute job. The primitive routes the
payment to Prime custody, the seller delivers the compute and posts a
SNARK proof, the verifier confirms the proof, Prime auto-settles:

- Coinbase treasury: $0.15
- Validators: $0.05 (pro-rata among active validators by stake weight)
- Auditors: $0.05 (pro-rata among currently-attesting audit firms)
- Seller: $99.75 minus gas

Gas on Base for the full verification + settlement cycle is well under $0.01
at current L2 gas prices, so the seller receives effectively $99.74. The
institutional buyer's capital is never at risk outside the verified
primitive.

---

## Section 8 — The undeniable framing

**The one-sentence summary that makes this addition non-optional for any
serious agent-economy participant:**

> Without the contract-settlement-proof primitive embedded in x402, the
> chain remains only a payment rail and can never become the enforcement
> layer that agents require before they will move institutional capital at
> scale.

### The specific capability the enforcement layer unlocks

The payment rail alone cannot enforce what was promised. It can only
transfer value. The enforcement layer turns every x402 transaction into a
verifiable exchange — the contract terms are public, the delivery proof is
cryptographically checkable, and settlement becomes automatic against a
regulated custody backing. This is the difference between "money moved" and
"contract honored." Institutional capital needs the second. It will not
clear the first at scale.

### Why April 2026 is the moment to ship this

**Regulated stablecoin volume on Base now exceeds speculative token volume,
autonomous agents have reached production revenue, and major custodians are
actively scanning for settlement primitives — three thresholds that were
not simultaneously crossed twelve months ago.** That simultaneous crossing
is what makes this the correct moment:

1. **Regulated stablecoin volume on Base now exceeds speculative token
   volume.** Institutional money is already on the L2, waiting for
   enforceable exchange mechanisms.
2. **Autonomous agents have moved from research prototypes to production
   revenue engines.** The customer base for agent-to-agent commerce is
   materializing in real traffic, not theory.
3. **Every major custodian is actively scanning for exactly this primitive**
   to unlock the next tranche of on-chain settlement. The gap is known.
   The solution is not yet standardized.

The window is narrow. **The first operator that standardizes the full
primitive owns the rake on every subsequent agent transaction that
regulated money will ever clear.**

---

## What this document is not

This is not a proposal for Coinbase to fund, endorse, or partner with
kenoodl. Kenoodl is the reference implementation that surfaced the gap. The
code in `github.com/<TBD>/x402-enforcement` is public and freely forkable.
The primitive does not require kenoodl to exist at all for the rest of the
ecosystem to benefit.

This is not a pitch for investment. The primitive does not require funding.
It requires a Coinbase engineer, roughly 90 days of focused work across the
four components above, and the Prime custody integration that only Coinbase
can build.

This is a specification document. Its audience is the engineering team, the
compliance team, and the product leadership of Coinbase's x402 Foundation.
Its purpose is to name a gap that every x402 endpoint currently hits against
institutional review and to hand over, free and upfront, the concrete path
Coinbase could take to close it — with proofs of necessity for every line
item, written by someone who has been running a reference instance of the
primitive on Base for months and has the receipts to prove it.

The repo is public. The reference contracts are deployable today. The
stealth door has been running. The path from here to production is
ninety days of concentrated engineering work plus the custody integration
only Coinbase can ship.

The window is narrow. The decision is yours.

---

## Provenance

This specification was produced by Kevin Hoff using the kenoodl synthesis
engine, in a single Sunday afternoon, against the public x402 specification
and its institutional blind spots. The full synthesis chain that produced
this document — problem diagnosis, historical precedents (Oracle, Sun,
AWS), deer-in-the-clearing framing, sponsor-covenant pivot, contract-
settlement-proof primitive, and this production roadmap — is documented in
the repository's other files for full transparency of how the specification
was derived.

The engine that produced this specification is live at
[kenoodl.com](https://kenoodl.com) and will produce comparable specifications
for any operator with a problem that sits at the collision of multiple
mature domains.

— *Kevin Hoff, April 2026*

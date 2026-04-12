# x402 Contract-Settlement-Proof Primitive

A reference implementation of the missing layer in x402: a contract the chain
can read, a settlement the chain can verify, and a proof the chain can audit —
without any off-chain trust, reputation layer, or human intermediary.

> **The chain stops being a payment rail and starts being the enforcement
> layer most projects never noticed was missing.**

---

## What this is

x402 (Coinbase's payment protocol for AI agents) settles the **value** of a
transaction. It does not yet settle the **contract** (what was promised), the
**delivery** (whether it was kept), or the **proof** (whether both sides
performed).

This repository contains a minimal reference implementation that closes those
three gaps without breaking x402's existing payment flow. It consists of two
smart contracts and a spec for how any x402 endpoint wires them in.

| Component | Role |
|---|---|
| `OfferRegistry.sol` | Immutable on-chain registry mapping `offerHash` to canonical offer JSON. A seller registers an offer once; any buyer verifies it with a single `eth_call` before paying. |
| `ISettlementVerifier.sol` | Abstract verifier interface. Any concrete verifier accepts a proof + request hash + offer hash and returns a bool. |
| `StubSettlementVerifier.sol` | Reference stub for development. Returns true for well-structured inputs. **Replace with a real Groth16 verifier in production.** |

And a companion document, `STEALTH_DOOR_INTEGRATION.md`, that specifies the
exact `cr-trader/worker.js` changes needed for kenoodl's existing stealth door
to emit the new v2 calldata format, verify the offer against the registry, and
attach delivery proofs to response transactions.

---

## Why this exists

The kenoodl stealth door on Base has been running for months as a bilaterally
honest instance of the contract-settlement-proof pattern: payment in as
ECIES-encrypted calldata, synthesis produced, response out as ECIES-encrypted
calldata, retry on failure, refund on permanent failure. The architecture is
real. But it is **third-party invisible** — an auditor scanning only the chain
sees paired encrypted blobs and has no way to read the contract terms or
verify the correctness of delivery.

This primitive closes that gap. With the two additions in this repo:

1. Every inbound transaction carries an `offerHash` in calldata, pointing to
   a canonical offer in `OfferRegistry`. Agents verify exact terms with one
   `eth_call` before signing.
2. Every successful response transaction attaches a delivery proof (Groth16
   SNARK in production, stub today) that a third party can verify via
   `SettlementVerifier` without ever seeing the payload content.

The encrypted content remains bilateral. The contract, settlement, and proof
become publicly auditable. This is exactly what institutional compliance
engines need before they will clear x402 transactions at scale.

---

## Repository layout

```
x402-enforcement/
├── contracts/
│   ├── OfferRegistry.sol            — immutable offer registry
│   ├── ISettlementVerifier.sol      — abstract verifier interface
│   └── StubSettlementVerifier.sol   — reference stub (v0.1)
├── circuits/
│   └── synthesis.circom             — circuit spec for the real Groth16 verifier
├── foundry.toml                     — build + RPC config
├── STEALTH_DOOR_INTEGRATION.md      — exact changes for cr-trader/worker.js
├── DEPLOY.md                        — deployment checklist
├── README.md                        — this file
└── CHAIN_AS_ENFORCEMENT.md          — the reframe, in one page
```

---

## What is implemented vs. what is not

**Implemented in this repo:**
- `OfferRegistry` contract (final, deployable)
- `ISettlementVerifier` interface (final, stable)
- `StubSettlementVerifier` contract (reference stub — fully functional for
  development, explicitly not for production)
- Complete specification of the v2 stealth-door calldata format
- Complete specification of the `cr-trader/worker.js` changes needed to
  integrate the registry check and proof generation
- Foundry build configuration targeting Base Sepolia and Base mainnet

**Not implemented, explicitly marked as follow-on:**
- The real Groth16 verifier compiled from `circuits/synthesis.circom`.
  **A stub settlement verifier enables complete reference implementation and
  end-to-end testnet verification while the Groth16 circuit itself remains
  the production component whose formal audit is performed by the first
  operator routing institutional capital.** The stub and the real verifier
  both implement the same `ISettlementVerifier` interface — swapping one
  for the other is a drop-in replacement, not a breaking change for any
  downstream integrator. See `circuits/synthesis.circom` for the circuit
  statement and the public inputs the real verifier must enforce.
- Coinbase Prime custody integration for auto-settlement via banking rails.
  This is the piece only Coinbase can build — see `FOUNDATION_SPEC.md` for
  the full production path and the 90-day roadmap.
- A canonical ecosystem-wide `OfferRegistry` deployment. The address in this
  repo is a reference instance. A single canonical registry should be deployed
  and operated by Coinbase so every x402 endpoint points at the same address.

---

## Quickstart

```bash
# Build the contracts
cd x402-enforcement
forge build

# Deploy to Base Sepolia for testing
forge create contracts/OfferRegistry.sol:OfferRegistry \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY

forge create contracts/StubSettlementVerifier.sol:StubSettlementVerifier \
  --rpc-url base_sepolia \
  --private-key $DEPLOY_KEY

# Register kenoodl's canonical synthesis offer (one-time)
# See DEPLOY.md for the exact cast send command with the offer JSON
```

After deployment, follow `STEALTH_DOOR_INTEGRATION.md` to apply the
corresponding changes to `cr-trader/worker.js` and the
`/.well-known/ai.json` file.

---

## The one-sentence claim

> **Without the contract-settlement-proof primitive embedded in x402, the
> chain remains only a payment rail and can never become the enforcement layer
> that agents require before they will move institutional capital at scale.**

That sentence is the thesis. Everything in this repo is the minimum
implementation of the layer that sentence names.

---

## Provenance

This repository was produced by running Kevin Hoff's synthesis engine
(kenoodl) against the public x402 specification and its blind spots. The
primitive, the calldata format, the verifier interface, and the 90-day
production path for Coinbase's x402 Foundation were all surfaced by the
engine across three sequential synthesis calls on a single Sunday afternoon.

The reference contracts and integration specs in this repo are the concrete
artifacts that close the gap the synthesis identified. Nothing here was
invented after the synthesis. Everything was specified by it.

kenoodl lives at [kenoodl.com](https://kenoodl.com). Anyone can call it.

---

*"I've been running it my whole life." — Kevin Hoff*

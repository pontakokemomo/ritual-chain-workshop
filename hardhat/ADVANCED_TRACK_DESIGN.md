# Advanced Track (Design Only): Ritual-Native Hidden Submissions

> **Plain-language summary:** Commit-reveal still makes every answer public
> *eventually*. This document designs a stronger (optional) alternative
> using Ritual's secure hardware (TEE): answers are submitted encrypted,
> decrypted only for a moment inside hardware nobody can look into, judged
> by the AI there, and never shown to any human at all. It also honestly
> lists the trade-offs: if no human can ever see the answers, no human can
> double-check what the AI did with them.

**Status: design document only, not implemented.** Per the assignment's own
wording, the advanced track may be submitted as a design rather than working
code. This document describes an alternative to the commit-reveal scheme in
`AIJudge.sol` that removes participant self-disclosure entirely, using
Ritual's confidential-compute primitives.

## Motivation: what commit-reveal still doesn't hide

The required track (`ARCHITECTURE_NOTE.md`) hides answer content until each
participant chooses to reveal it. Two things are still true even with
commit-reveal:

- Once revealed, the answer is permanently public on-chain, including to
  competitors who never revealed anything themselves, and to anyone browsing
  the chain after the fact.
- Revelation depends on the participant correctly performing a manual,
  off-chain step (keeping the exact `answer` + `salt`, then resubmitting them
  byte-for-byte). If they lose that data, their submission is unrecoverable
  (documented as H2 in `TEST_PLAN.md`).

This design removes both: the answer is never disclosed by the participant at
all, not even to reveal it. It stays encrypted from submission through
judging.

## Core idea

Instead of a hash commitment, participants submit an **encrypted** answer.
Decryption happens exactly once, transiently, inside Ritual's Trusted
Execution Environment (TEE), immediately before the AI judges it. The
decrypted plaintext is never written to contract storage, never emitted in an
event, and never returned to any caller, including the bounty owner.

| | Required track (commit-reveal) | Advanced track (this design) |
|---|---|---|
| What's submitted | Hash of the answer | Ciphertext of the answer |
| Who discloses the answer | The participant, manually, after the deadline | Nobody: decryption happens inside the TEE only |
| Where plaintext ever exists | On-chain, permanently, after reveal | Only transiently inside the TEE during judging; never persisted |
| Who can read the answer | Anyone, after reveal | No one, ever (not even the bounty owner) |
| Failure mode if a step is skipped | Participant loses their prize (no reveal = not judged) | N/A: there is no separate disclosure step to skip |

## Flow

```
1. Bounty creation
   contract → DKMS_PRECOMPILE (0x081B): "generate a keypair for this bounty"
   DKMS generates the keypair inside the TEE and returns only the public key
   on-chain. The private key never leaves the TEE: not to the contract,
   not to the bounty owner, not to Ritual's own operators.

2. Submission
   participant encrypts their answer locally using the bounty's public key
   → only ciphertext is submitted on-chain (submitEncryptedAnswer)

3. Judging (judgeAll-equivalent)
   contract passes all submitted ciphertexts into the TEE in one batch call
   → TEE decrypts each ciphertext using the private key it already holds
   → decrypted answers are fed directly to the LLM inference precompile
   → only the AI's verdict (e.g. winner index, review text) leaves the TEE
   → plaintext answers and the private key never leave the TEE boundary
```

## Why a single keypair per bounty (not per participant)

Using one bounty-scoped keypair (rather than a fresh key per participant)
keeps the public key a single, well-known value participants encrypt
against, and keeps the decryption step a single batched TEE call at judging
time. This mirrors the batching rationale already used for `judgeAll` in the
required track (one precompile call rather than one per participant).

## Known limitations (deliberately unresolved)

These are structural trade-offs of hiding data behind a TEE, not
implementation bugs, and would remain true even in a full implementation:

- **No external verification of correctness.** Remote attestation (a
  standard TEE feature) can prove *that* a given enclave is genuine Ritual
  TEE hardware running a specific, unmodified program, but it cannot prove
  the judging logic inside that program is bug-free or behaves as intended.
  Hiding data and being able to verify what happened to it are in tension by
  construction.
- **Single point of failure.** If the TEE-based judging call errors,
  misbehaves, or is unavailable, there is no fallback path to inspect or
  recover the encrypted answers, because no one, including the bounty
  owner, holds a decryption key outside the TEE.
- **No accountability trail for individual mistakes.** If the AI's judgment
  is wrong or a bounty is misjudged, there is no way for a human to inspect
  *why*, because the only party that ever saw the plaintext answers was the
  TEE itself. The only available explanation is "the AI decided this way,"
  with no visibility into the reasoning process against the actual hidden
  data.

These limitations directly motivate the reflection question `README.md`
answers: hiding data from every human (including the party who is supposed to
be accountable for the outcome) is not a free improvement over commit-reveal.
It trades reveal-time human oversight for a stronger secrecy guarantee.

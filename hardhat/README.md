# AIJudge: Commit-Reveal AI Bounty Judge (Ritual Academy Homework)

This folder contains my homework for the Ritual Academy workshop:
a smart contract called **AIJudge** (`contracts/AIJudge.sol`).

**What it does, in one sentence:** people compete for a prize by submitting
answers, an AI judges the answers, and nobody can peek at (or copy) anyone
else's answer before judging.

Deployed on Ritual Testnet (chain id 1979) at:
`0xcBE5e9086f53F42586d4Cbb4394Db0721512DD7f`

---

## The problem this contract solves

The original workshop version had a flaw: as soon as you submitted your
answer, it was stored on the blockchain **in plain text, visible to
everyone**. A later participant could read your answer, improve it a
little, and submit the better version. Unfair.

The fix is a classic technique called **commit-reveal**: first everyone
locks in a "sealed envelope" (a hash of their answer), and only after the
submission deadline does everyone open their envelope. You can't copy what
you can't see.

---

## Key terms (plain-language glossary)

| Term | What it means here |
|---|---|
| **Bounty** | A contest with a prize. The creator deposits the prize money into the contract when creating it. |
| **Hash** | A fingerprint of data. Same input always gives the same fingerprint, but you cannot work backwards from the fingerprint to the input. This contract uses the `keccak256` hash function. |
| **Commitment** | The "sealed envelope": a hash of your answer (plus a few extra ingredients, see below). Submitting it proves you decided your answer *before* the deadline, without showing the answer. |
| **Salt** | A random secret number you generate yourself and mix into your hash. Without it, someone could guess likely answers, hash them, and compare against your public commitment. The salt makes that impossible. |
| **Reveal** | Opening your envelope: submitting your real answer + your salt. The contract re-computes the hash and checks it matches your earlier commitment exactly. |
| **Precompile** | A special built-in service on Ritual Chain that a contract can call. This contract uses the LLM inference precompile, i.e. "ask an AI a question from inside a smart contract." |

---

## Lifecycle: the five steps of a bounty

```
create ──▶ commit ──▶ reveal ──▶ judge ──▶ finalize
(owner)   (everyone) (everyone) (owner+AI) (owner)
```

### Step 1: Create a bounty (owner)

The owner sets a title, judging criteria (the "rubric"), two deadlines,
and sends the prize money along with the call:

```solidity
aiJudge.createBounty{value: rewardInWei}(
  "Best one-paragraph explanation of X",
  "Judged on clarity and correctness",
  submissionDeadline, // timestamp in MILLISECONDS (see warning below)
  revealDeadline      // must be after submissionDeadline
);
```

> **⚠ Ritual-specific warning: timestamps are in milliseconds.**
> On most EVM chains `block.timestamp` is in seconds, but on Ritual Chain
> it is in **milliseconds** since epoch. Pass your deadlines in
> milliseconds (e.g. JavaScript's `Date.now()` already returns
> milliseconds). If you pass seconds by mistake, the deadline will look
> like it is in the distant past and `createBounty` will revert with
> "submission deadline must be in the future".

### Step 2: Submit a commitment (participants, before `submissionDeadline`)

Off-chain (on your own computer), pick your `answer` and generate a random
32-byte `salt`, then compute:

```
commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
```

Then submit **only the hash**:

```solidity
aiJudge.submitCommitment(bountyId, commitment);
```

Your actual answer does not appear on-chain at this point. Note the recipe
also mixes in your own address (`msg.sender`) and the `bountyId`; this
stops someone from copying your commitment byte-for-byte and submitting it
as their own, because the hash only verifies for *your* address on *this*
bounty.

Each address can commit only once per bounty, and a bounty accepts at most
10 commitments (`MAX_COMMITMENTS`).

### Step 3: Reveal (participants, between the two deadlines)

```solidity
aiJudge.revealAnswer(bountyId, answer, salt);
```

The contract re-computes the hash from what you send and compares it with
your stored commitment. **It must match byte-for-byte**: a different
answer, a different salt, or even an extra space causes a revert with
"commitment mismatch". Answers are limited to 2,000 bytes
(`MAX_ANSWER_LENGTH`).

Anyone who committed but never reveals is simply excluded from judging.

### Step 4: Judge (owner only, after `revealDeadline`)

```solidity
aiJudge.judgeAll(bountyId, llmInput);
```

This calls Ritual's LLM inference precompile **once**, with all revealed
answers batched into a single request (one AI call for the whole bounty,
not one per answer). The AI's review is stored on-chain.

### Step 5: Finalize (owner only, after judging)

```solidity
aiJudge.finalizeWinner(bountyId, winnerIndex);
```

The owner picks the winner (the AI's review is advice, the human decides),
the prize is paid to that participant, and the bounty closes. The winner
must be someone who actually revealed.

---

## A note on the salt

The `salt` is a random secret value the participant generates themselves.
It is not part of the answer and is never shared before the reveal phase.
Its only job is to make the commitment hash unpredictable: without it,
someone could guess a likely `answer`, hash it themselves, and check it
against the public commitment before the reveal deadline. The salt must be
generated with a cryptographically secure random number generator and kept
safely until reveal. See `TEST_PLAN.md` section 5 ("Human-input / process
risks") for what can go wrong if it isn't.

---

## Where to find everything (document map)

| File | What's inside | Homework deliverable it covers |
|---|---|---|
| `contracts/AIJudge.sol` | The commit-reveal contract itself | Updated Solidity contract |
| `README.md` (this file) | Lifecycle explanation + reflection answer | Short README |
| `TEST_PLAN.md` | Test plan: state transitions, boundary values, abuse cases, valid/invalid reveals | Test plan |
| `ARCHITECTURE_NOTE.md` | Why commit-reveal, what's public vs. hidden | Architecture note |
| `ADVANCED_TRACK_DESIGN.md` | Design (not implemented) for TEE-based fully-hidden submissions | Advanced track design document |
| `../docs/ja/` | Japanese guides to this repository | (extra, for my own reference) |

---

## How this was built and deployed

- Solidity `0.8.24`, Hardhat 3, deployed with Hardhat Ignition.
- The deployer's private key is stored with `hardhat-keystore`
  (never written into any file in this repository).
- Deploy command used:

```shell
npx hardhat ignition deploy --network ritual ignition/modules/AIJudge.ts
```

- The `ritual` network is defined in `hardhat.config.ts`
  (RPC `https://rpc.ritualfoundation.org`, chain id 1979).
- After deployment, the on-chain bytecode at the address above was
  verified to match the compiled contract via `eth_getCode`.

---

## Reflection: what should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?

Working on this assignment made me realize that letting AI handle the
technical execution and deciding how that technology should actually be
operated are two completely different things. For example, the salt
participants use to hide their answers must be generated correctly and kept
safe without being lost, and that is something code cannot enforce; it comes
down to human operation. What should be public is the judging process
itself: the record of who participated, and when each person committed and
revealed. What should stay hidden is the content of the answers until
judging is complete, which the commit-reveal scheme already achieves.
Checking whether a hash matches and comparing many answers against the same
criteria are tasks that can reasonably be left to AI. But deciding the final
winner, and taking responsibility for enforcing operational rules like
proper salt management, should remain with humans.

---

## About the project template

This folder started from the Hardhat 3 starter template (Node.js test
runner + `viem`). Template basics, kept here for reference:

```shell
npx hardhat test              # run all tests
npx hardhat keystore set KEY  # store a private key securely
npx hardhat ignition deploy --network <name> ignition/modules/<Module>.ts
```

To learn more about Hardhat 3, see the
[Getting Started guide](https://hardhat.org/docs/getting-started#getting-started-with-hardhat-3).

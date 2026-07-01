# Test Plan: AIJudge Commit-Reveal Flow

Scope: `contracts/AIJudge.sol`, focused on the commit-reveal submission flow
(`submitCommitment`, `revealAnswer`) and its downstream effects on
`judgeAll` and `finalizeWinner`. Deployed contract under test:
`0xcBE5e9086f53F42586d4Cbb4394Db0721512DD7f` (Ritual Testnet, chain id 1979).

## 1. State transition tests

The contract moves through four phases per bounty: **submission → reveal →
judged → finalized**. Each transition is gated by a deadline or an explicit
call, and out-of-order calls must revert.

| ID | Precondition | Action | Expected result |
|----|----|----|----|
| S1 | Before `submissionDeadline` | `submitCommitment` | Success |
| S2 | At/after `submissionDeadline` | `submitCommitment` | Revert: "submission phase over" |
| S3 | Before `submissionDeadline` | `revealAnswer` | Revert: "submission phase not over yet" |
| S4 | At/after `submissionDeadline`, before `revealDeadline` | `revealAnswer` (correct answer/salt) | Success |
| S5 | At/after `revealDeadline` | `revealAnswer` | Revert: "reveal phase over" |
| S6 | Before `revealDeadline` | `judgeAll` | Revert: "reveal phase not over yet" |
| S7 | At/after `revealDeadline`, not yet judged | `judgeAll` | Success |
| S8 | Already judged | `judgeAll` again | Revert: "already judged" |
| S9 | Not yet judged | `finalizeWinner` | Revert: "not judged yet" |
| S10 | Judged, not finalized | `finalizeWinner` | Success |
| S11 | Already finalized | `finalizeWinner` again | Revert: "already finalized" |

## 2. Boundary value analysis

| ID | Target | Input | Expected result |
|----|----|----|----|
| B1 | Commitment count | 10th commitment (`MAX_COMMITMENTS`) | Success |
| B2 | Commitment count | 11th commitment | Revert: "too many submissions" |
| B3 | Answer length | Exactly 2000 bytes (ASCII) | Success |
| B4 | Answer length | 2001 bytes (ASCII) | Revert: "answer too long" |
| B5 | Answer length, multi-byte | Multi-byte characters (e.g. Japanese, emoji) totalling exactly 2000 bytes | Success (limit is byte length, not character count) |
| B6 | Answer length, multi-byte | Same as B5, one character over 2000 bytes | Revert: "answer too long" |
| B7 | Answer content | Empty string (`""`) | **Currently succeeds**, documented as an intentional simplification for the required track (see Known Assumptions below), not enforced on-chain |
| B8 | Bounty deadlines | `submissionDeadline == block.timestamp` at creation | Revert: "submission deadline must be in the future" |
| B9 | Bounty deadlines | `revealDeadline == submissionDeadline` | Revert: "reveal deadline must be after submission deadline" |
| B10 | Reward | `msg.value == 0` at creation | Revert: "reward required" |

## 3. Equivalence partitioning: negative / abuse cases

| ID | Case | Expected result |
|----|----|----|
| E1 | Same address submits a commitment twice | Revert: "already committed" |
| E2 | Address with no prior commitment calls `revealAnswer` | Revert: "no commitment found" |
| E3 | Same commitment revealed twice | Revert: "already revealed" |
| E4 | `revealAnswer` with answer/salt that does not hash to the stored commitment | Revert: "commitment mismatch" |
| E5 | Non-owner calls `judgeAll` | Revert: "not bounty owner" |
| E6 | Non-owner calls `finalizeWinner` | Revert: "not bounty owner" |
| E7 | `judgeAll` called when zero commitments were revealed | Revert: "no revealed submissions" |
| E8 | `finalizeWinner` with an index that was never revealed | Revert: "winner must have revealed their answer" |
| E9 | Any function called with a non-existent `bountyId` | Revert: "bounty not found" |
| E10 | `finalizeWinner` / `getCommitment` with an out-of-range index | Revert: "invalid index" |

## 4. Happy path scenario

1. Owner creates a bounty with a reward, a submission deadline, and a reveal deadline.
2. Three participants each submit a commitment during the submission phase.
3. After the submission deadline, two participants reveal their answer and salt (one participant abstains and never reveals).
4. After the reveal deadline, the owner calls `judgeAll`, which invokes the LLM inference precompile with the revealed answers.
5. The owner calls `finalizeWinner` selecting one of the two revealed participants.
6. The reward is transferred to the winner's address; the bounty is marked finalized.

## 5. Human-input / process risks (off-chain, not enforced by the contract)

The on-chain hash comparison in `revealAnswer` is a simple, deterministic
equality check and is low-risk by construction. The real risk surface is the
off-chain process a human (or their client) must follow correctly:

| ID | Risk | Description |
|----|----|----|
| H1 | Salt strength | If a participant chooses a low-entropy/predictable `salt`, an attacker can brute-force `answer × salt` combinations against the participant's public commitment hash and recover the answer before the reveal deadline, defeating the purpose of the commit-reveal scheme. Salt must be generated with a cryptographically secure random number generator (full 32 bytes). |
| H2 | Losing the salt/answer | The participant must retain their exact `answer` and `salt` between commit and reveal (which can be hours or days apart). There is no on-chain recovery mechanism; if lost, the participant can never successfully reveal. |
| H3 | Exact re-entry of the answer | `revealAnswer` requires byte-for-byte identical input to what was hashed at commit time. Any difference (whitespace, encoding, casing) causes a hash mismatch and a revert. |

## 6. Known assumptions / limitations (documented, not fixed in the required track)

- Empty-string answers (B7) are accepted on-chain; rejection is left to the AI judging step, consistent with keeping the required track simple.
- Block timestamps (`block.timestamp`) can be influenced within a small margin by whoever proposes the block. This is a standard EVM consideration (not specific to this contract) and is not expected to be exploitable meaningfully given Ritual's ~350ms block time, but is noted as a theoretical boundary-timing risk.
- Salt strength (H1) cannot be validated on-chain; it is a client-side responsibility documented in the README.

## Appendix: on-chain verification performed during this session

- Deployed bytecode at `0xcBE5e9086f53F42586d4Cbb4394Db0721512DD7f` was confirmed to match the compiled contract via `eth_getCode`.
- `nextBountyId()` was read via `eth_call` and returned `1`, confirming correct initial state.

# Architecture Note: AIJudge Commit-Reveal Bounty

Deployed contract: `0xcBE5e9086f53F42586d4Cbb4394Db0721512DD7f` (Ritual Testnet, chain id 1979)

## Background

In a prior workshop iteration, bounty submissions were stored on-chain in
plaintext as soon as a participant submitted them. Because blockchain state
is public, any participant could read another participant's submission
before judging, copy it, improve it slightly, and resubmit it as their own.
This contract fixes that by keeping answers hidden until every participant
has locked one in.

## How it works

The contract moves each bounty through four phases:

```
create ──▶ submission phase ──▶ reveal phase ──▶ judged ──▶ finalized
           (submitCommitment)   (revealAnswer)   (judgeAll)  (finalizeWinner)
```

1. **Create** (`createBounty`): The owner funds the bounty and sets a
   submission deadline and a reveal deadline.
2. **Submission phase** (`submitCommitment`): Each participant submits only
   a hash of their answer (a "commitment"), not the answer itself. Up to 10
   participants can commit per bounty.
3. **Reveal phase** (`revealAnswer`): After the submission deadline, each
   participant submits their real answer plus the secret value ("salt") they
   used when creating their hash. The contract re-hashes it and checks it
   matches the original commitment; if not, it's rejected. Only now does the
   real answer become visible on-chain.
4. **Judged** (`judgeAll`): After the reveal deadline, the owner triggers AI
   judging. Only answers that were actually revealed are considered;
   anyone who committed but never revealed is excluded.
5. **Finalized** (`finalizeWinner`): The owner picks a winner among the
   revealed participants and the reward is paid out.

## Why commit-reveal

Splitting submission into two steps, committing a hash first and revealing
the real answer later, means no participant can see another's answer while
submissions are still open. This is the same idea used in sealed-bid
auctions: you lock in your choice before anyone can see what others chose.

## What's public vs. hidden, by phase

| Data | During submission | After reveal |
|---|---|---|
| Commitment hash | Public | Public |
| Answer content | Hidden | Public |
| Participant address | Public | Public |

Note that the participant's *address* is public from the start. This design
hides the answer's content, not who is participating.

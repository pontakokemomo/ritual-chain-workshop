# Sample Hardhat 3 Project (`node:test` and `viem`)

This project showcases a Hardhat 3 project using the native Node.js test runner (`node:test`) and the `viem` library for Ethereum interactions.

To learn more about Hardhat 3, please visit the [Getting Started guide](https://hardhat.org/docs/getting-started#getting-started-with-hardhat-3). To share your feedback, join our [Hardhat 3](https://hardhat.org/hardhat3-telegram-group) Telegram group or [open an issue](https://github.com/NomicFoundation/hardhat/issues/new) in our GitHub issue tracker.

## Project Overview

This example project includes:

- A simple Hardhat configuration file.
- Foundry-compatible Solidity unit tests.
- TypeScript integration tests using [`node:test`](nodejs.org/api/test.html), the new Node.js native test runner, and [`viem`](https://viem.sh/).
- Examples demonstrating how to connect to different types of networks, including locally simulating OP mainnet.

## Usage

### Running Tests

To run all the tests in the project, execute the following command:

```shell
npx hardhat test
```

You can also selectively run the Solidity or `node:test` tests:

```shell
npx hardhat test solidity
npx hardhat test nodejs
```

### Make a deployment to Sepolia

This project includes an example Ignition module to deploy the contract. You can deploy this module to a locally simulated chain or to Sepolia.

To run the deployment to a local chain:

```shell
npx hardhat ignition deploy ignition/modules/Counter.ts
```

To run the deployment to Sepolia, you need an account with funds to send the transaction. The provided Hardhat configuration includes a Configuration Variable called `SEPOLIA_PRIVATE_KEY`, which you can use to set the private key of the account you want to use.

You can set the `SEPOLIA_PRIVATE_KEY` variable using the `hardhat-keystore` plugin or by setting it as an environment variable.

To set the `SEPOLIA_PRIVATE_KEY` config variable using `hardhat-keystore`:

```shell
npx hardhat keystore set SEPOLIA_PRIVATE_KEY
```

After setting the variable, you can run the deployment with the Sepolia network:

```shell
npx hardhat ignition deploy --network sepolia ignition/modules/Counter.ts
```

## AIJudge: Commit-Reveal Bounty (Ritual Academy Homework)

`contracts/AIJudge.sol` is a privacy-preserving AI bounty judge, built on top of
this project template. Answers stay hidden as commitment hashes until every
participant has locked one in, then Ritual's AI judges only the answers that
were actually revealed.

Deployed on Ritual Testnet (chain id 1979) at:
`0xcBE5e9086f53F42586d4Cbb4394Db0721512DD7f`

For the design rationale, see `ARCHITECTURE_NOTE.md`. For the optional
TEE-based design that removes self-disclosure entirely, see
`ADVANCED_TRACK_DESIGN.md`. For the test plan, see `TEST_PLAN.md`.

### Lifecycle walkthrough

1. **Create a bounty**

   ```solidity
   aiJudge.createBounty{value: rewardInWei}(
     "Best one-paragraph explanation of X",
     "Judged on clarity and correctness",
     submissionDeadline, // unix timestamp
     revealDeadline       // must be after submissionDeadline
   );
   ```

2. **Submit a commitment** (submission phase, before `submissionDeadline`)

   Off-chain, each participant picks a real `answer` and a random 32-byte
   `salt`, then computes:

   ```
   commitment = keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId))
   ```

   and submits only the hash:

   ```solidity
   aiJudge.submitCommitment(bountyId, commitment);
   ```

   The answer itself never appears on-chain at this point.

3. **Reveal** (reveal phase, between `submissionDeadline` and `revealDeadline`)

   ```solidity
   aiJudge.revealAnswer(bountyId, answer, salt);
   ```

   The contract recomputes the hash and reverts on any mismatch (wrong
   answer, wrong salt, or a typo). A participant who never calls this is
   excluded from judging entirely.

4. **Judge** (after `revealDeadline`, owner only)

   ```solidity
   aiJudge.judgeAll(bountyId, llmInput);
   ```

   This calls Ritual's LLM inference precompile once with every revealed
   answer and stores the AI's output.

5. **Finalize** (owner only, after judging)

   ```solidity
   aiJudge.finalizeWinner(bountyId, winnerIndex);
   ```

   Pays the reward to the chosen (revealed) participant and closes the
   bounty.

### A note on the salt

The `salt` is a random secret value the participant generates themselves.
It is not part of the answer and is never shared before the reveal phase.
Its only job is to make the commitment hash unpredictable: without it,
someone could guess a likely `answer`, hash it themselves, and check it
against the public commitment before the reveal deadline. The salt must be
generated with a cryptographically secure random number generator and kept
safely until reveal. See `TEST_PLAN.md` section 5 for the risks if it isn't.

### Reflection: what should be public, what should stay hidden, and what should be decided by AI versus by a human in a bounty system?

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

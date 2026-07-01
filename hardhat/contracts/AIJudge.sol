// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PrecompileConsumer} from "./utils/PrecompileConsumer.sol";

interface IRitualWallet {
    function deposit(uint256 lockDuration) external payable;

    function depositFor(address user, uint256 lockDuration) external payable;

    function withdraw(uint256 amount) external;

    function balanceOf(address) external view returns (uint256);

    function lockUntil(address) external view returns (uint256);
}

/// @notice AI Bounty Judge with a commit-reveal submission flow.
/// Answers stay hidden as commitment hashes during the submission phase and
/// are only readable on-chain after each participant reveals them. Ritual AI
/// judges the bounty using only the answers that were actually revealed.
contract AIJudge is PrecompileConsumer {
    uint256 public constant MAX_COMMITMENTS = 10;
    uint256 public constant MAX_ANSWER_LENGTH = 2_000;

    uint256 public nextBountyId = 1;

    IRitualWallet wallet =
        IRitualWallet(0x532F0dF0896F353d8C3DD8cc134e8129DA2a3948);

    struct Commitment {
        address participant;
        bytes32 commitmentHash;
        bool revealed;
        string answer;
    }

    struct Bounty {
        address owner;
        string title;
        string rubric;
        uint256 reward;
        uint256 submissionDeadline;
        uint256 revealDeadline;
        bool judged;
        bool finalized;
        bytes aiReview;
        uint256 winnerIndex;
        Commitment[] commitments;
    }

    struct ConvoHistory {
        string storageType;
        string path;
        string secretsName;
    }

    mapping(uint256 => Bounty) public bounties;

    // bountyId => participant => has already committed
    mapping(uint256 => mapping(address => bool)) public hasCommitted;

    // bountyId => participant => 1-based index into bounty.commitments (0 = none)
    mapping(uint256 => mapping(address => uint256)) private commitmentIndexOf;

    event BountyCreated(
        uint256 indexed bountyId,
        address indexed owner,
        string title,
        uint256 reward,
        uint256 submissionDeadline,
        uint256 revealDeadline
    );

    event CommitmentSubmitted(
        uint256 indexed bountyId,
        uint256 indexed commitmentIndex,
        address indexed participant
    );

    event AnswerRevealed(
        uint256 indexed bountyId,
        uint256 indexed commitmentIndex,
        address indexed participant
    );

    event AllAnswersJudged(uint256 indexed bountyId, bytes aiReview);

    event WinnerFinalized(
        uint256 indexed bountyId,
        uint256 indexed winnerIndex,
        address indexed winner,
        uint256 reward
    );

    modifier onlyOwner(uint256 bountyId) {
        require(msg.sender == bounties[bountyId].owner, "not bounty owner");
        _;
    }

    modifier bountyExists(uint256 bountyId) {
        require(bounties[bountyId].owner != address(0), "bounty not found");
        _;
    }

    function createBounty(
        string calldata title,
        string calldata rubric,
        uint256 submissionDeadline,
        uint256 revealDeadline
    ) external payable returns (uint256 bountyId) {
        require(msg.value > 0, "reward required");
        require(
            submissionDeadline > block.timestamp,
            "submission deadline must be in the future"
        );
        require(
            revealDeadline > submissionDeadline,
            "reveal deadline must be after submission deadline"
        );

        bountyId = nextBountyId++;

        Bounty storage bounty = bounties[bountyId];

        bounty.owner = msg.sender;
        bounty.title = title;
        bounty.rubric = rubric;
        bounty.reward = msg.value;
        bounty.submissionDeadline = submissionDeadline;
        bounty.revealDeadline = revealDeadline;
        bounty.winnerIndex = type(uint256).max;

        emit BountyCreated(
            bountyId,
            msg.sender,
            title,
            msg.value,
            submissionDeadline,
            revealDeadline
        );
    }

    /// @notice Submit only a commitment hash. The real answer stays hidden
    /// until revealAnswer() is called in the reveal phase.
    /// commitment must equal keccak256(abi.encodePacked(answer, salt, msg.sender, bountyId)).
    function submitCommitment(
        uint256 bountyId,
        bytes32 commitment
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(
            block.timestamp < bounty.submissionDeadline,
            "submission phase over"
        );
        require(!hasCommitted[bountyId][msg.sender], "already committed");
        require(
            bounty.commitments.length < MAX_COMMITMENTS,
            "too many submissions"
        );

        hasCommitted[bountyId][msg.sender] = true;

        bounty.commitments.push(
            Commitment({
                participant: msg.sender,
                commitmentHash: commitment,
                revealed: false,
                answer: ""
            })
        );

        uint256 index = bounty.commitments.length - 1;
        commitmentIndexOf[bountyId][msg.sender] = index + 1;

        emit CommitmentSubmitted(bountyId, index, msg.sender);
    }

    /// @notice Reveal the answer and salt behind an earlier commitment.
    /// Only valid, revealed answers are eligible for AI judging.
    function revealAnswer(
        uint256 bountyId,
        string calldata answer,
        bytes32 salt
    ) external bountyExists(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(
            block.timestamp >= bounty.submissionDeadline,
            "submission phase not over yet"
        );
        require(block.timestamp < bounty.revealDeadline, "reveal phase over");
        require(bytes(answer).length <= MAX_ANSWER_LENGTH, "answer too long");

        uint256 index1 = commitmentIndexOf[bountyId][msg.sender];
        require(index1 != 0, "no commitment found");

        Commitment storage commitment = bounty.commitments[index1 - 1];
        require(!commitment.revealed, "already revealed");

        bytes32 expected = keccak256(
            abi.encodePacked(answer, salt, msg.sender, bountyId)
        );
        require(expected == commitment.commitmentHash, "commitment mismatch");

        commitment.revealed = true;
        commitment.answer = answer;

        emit AnswerRevealed(bountyId, index1 - 1, msg.sender);
    }

    function judgeAll(
        uint256 bountyId,
        bytes calldata llmInput
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(
            block.timestamp >= bounty.revealDeadline,
            "reveal phase not over yet"
        );
        require(!bounty.judged, "already judged");
        require(!bounty.finalized, "already finalized");
        require(_revealedCount(bounty) > 0, "no revealed submissions");

        bytes memory output = _executePrecompile(
            LLM_INFERENCE_PRECOMPILE,
            llmInput
        );

        (
            bool hasError,
            bytes memory completionData,
            ,
            string memory errorMessage,

        ) = abi.decode(output, (bool, bytes, bytes, string, ConvoHistory));

        require(!hasError, errorMessage);

        bounty.judged = true;
        bounty.aiReview = completionData;

        emit AllAnswersJudged(bountyId, completionData);
    }

    function finalizeWinner(
        uint256 bountyId,
        uint256 winnerIndex
    ) external bountyExists(bountyId) onlyOwner(bountyId) {
        Bounty storage bounty = bounties[bountyId];

        require(bounty.judged, "not judged yet");
        require(!bounty.finalized, "already finalized");
        require(winnerIndex < bounty.commitments.length, "invalid index");
        require(
            bounty.commitments[winnerIndex].revealed,
            "winner must have revealed their answer"
        );

        bounty.finalized = true;
        bounty.winnerIndex = winnerIndex;

        address winner = bounty.commitments[winnerIndex].participant;
        uint256 reward = bounty.reward;
        bounty.reward = 0;

        (bool ok, ) = payable(winner).call{value: reward}("");
        require(ok, "payment failed");

        emit WinnerFinalized(bountyId, winnerIndex, winner, reward);
    }

    function getBounty(
        uint256 bountyId
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address owner,
            string memory title,
            string memory rubric,
            uint256 reward,
            uint256 submissionDeadline,
            uint256 revealDeadline,
            bool judged,
            bool finalized,
            uint256 commitmentCount,
            uint256 winnerIndex,
            bytes memory aiReview
        )
    {
        Bounty storage bounty = bounties[bountyId];

        return (
            bounty.owner,
            bounty.title,
            bounty.rubric,
            bounty.reward,
            bounty.submissionDeadline,
            bounty.revealDeadline,
            bounty.judged,
            bounty.finalized,
            bounty.commitments.length,
            bounty.winnerIndex,
            bounty.aiReview
        );
    }

    /// @notice Returns commitment metadata. The answer field is empty until revealed.
    function getCommitment(
        uint256 bountyId,
        uint256 index
    )
        external
        view
        bountyExists(bountyId)
        returns (
            address participant,
            bytes32 commitmentHash,
            bool revealed,
            string memory answer
        )
    {
        Bounty storage bounty = bounties[bountyId];

        require(index < bounty.commitments.length, "invalid index");

        Commitment storage commitment = bounty.commitments[index];

        return (
            commitment.participant,
            commitment.commitmentHash,
            commitment.revealed,
            commitment.answer
        );
    }

    function _revealedCount(
        Bounty storage bounty
    ) internal view returns (uint256 count) {
        for (uint256 i = 0; i < bounty.commitments.length; i++) {
            if (bounty.commitments[i].revealed) {
                count++;
            }
        }
    }
}

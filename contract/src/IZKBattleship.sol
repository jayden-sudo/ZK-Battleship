// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

/**
 * @notice Represents the stored balance information for a player.
 * @dev `totalBalance` is the overall balance held on behalf of the user.
 *      `lockedBalance` represents funds that are currently reserved (for example, game stakes)
 *      and therefore not available for withdrawal until unlocked.
 */
struct UserBalance {
    uint256 totalBalance;
    uint256 lockedBalance;
}

enum NextTurnState {
    Blank, // 0
    Join,
    RevealRandomness,
    CreatorFire,
    JoinerFire,
    CreatorReport,
    JoinerReport,
    Completed
}

struct Game {
    address creator;
    address joiner;
    bytes32 creatorRandomnessCommitment;
    bytes32 joinerRandomnessSalt;
    bytes32 creatorBoardCommitment;
    bytes32 joinerBoardCommitment;
    uint256 stake;
    uint64 lastActiveTimestamp;
    uint64 creatorGameBoard;
    uint64 joinerGameBoard;
    NextTurnState nextTurnState;
    uint8 fireAtPosition;
}

/**
 * @title IZKBattleship
 * @notice Minimal interface for the ZK-enabled Battleship game contract.
 * @dev This interface declares events, an enum for shot outcomes, and the core
 *      functions required to manage funds, create/join games, reveal randomness,
 *      fire shots, and report shot results together with verification proofs.
 */
interface IZKBattleship {
    /**
     * @notice Emitted when a new game is created.
     * @param creator The address that created the game and posted the stake.
     * @param gameId The unique identifier assigned to the new game.
     * @param stake Amount of ETH (in wei) locked as the game stake.
     */
    event GameCreated(
        address indexed creator,
        uint256 indexed gameId,
        uint256 stake
    );

    /**
     * @notice Emitted when a player joins an existing game.
     * @param joiner The address of the player who joined the game.
     * @param gameId The identifier of the game that was joined.
     */
    event GameJoined(address indexed joiner, uint256 indexed gameId);

    /**
     * @notice Emitted when a player reveals their previously committed randomness.
     * @param gameId The identifier of the game where randomness was revealed.
     * @param initiativePlayer The address of the player who will take the first turn.
     */
    event RandomnessRevealed(uint256 indexed gameId, address initiativePlayer);

    /**
     * @notice Emitted when a player fires a shot in a game.
     * @param gameId The identifier of the game in which the shot was fired.
     * @param attacker The address of the player who fired the shot.
     * @param firePosition Encoded board position (e.g., cell index) targeted by the shot.
     */
    event ShotFired(
        uint256 indexed gameId,
        address attacker,
        uint8 firePosition
    );

    /**
     * @notice Possible outcomes for a fired shot.
     * @dev Use these values when reporting shot results: Error = invalid, Miss = no ship,
     *      Hit = ship part was hit, Sunk = ship fully destroyed.
     */
    enum ShotResult {
        Miss, // 0
        Hit, // 1
        Sunk // 2
    }

    /**
     * @notice Emitted by a defender after verifying and reporting the result of an incoming shot
     *         (typically together with a zero-knowledge proof).
     * @param gameId The identifier of the game in which the shot occurred.
     * @param defender The address of the player who defended (reported the result).
     * @param result The validated result of the shot (Error/Miss/Hit/Sunk).
     */
    event ShotResultReported(
        uint256 indexed gameId,
        address indexed defender,
        ShotResult result
    );

    /**
     * @notice Emitted when a game finishes and a winner is determined.
     * @param gameId The identifier of the completed game.
     * @param winner The address of the player who won the game.
     */
    event GameEnded(uint256 indexed gameId, address indexed winner);

    event ChatMessage(
        address indexed sender,
        address indexed recipient,
        string message
    );

    function listWaitingGames(
        uint256 from,
        uint256 limit
    ) external view returns (uint256[] memory);

    function getGameData(uint256 gameId) external view returns (Game memory);


    /**
     * @notice Deposit ETH into the caller's account held by the contract.
     * @dev The caller should send ETH with the transaction (msg.value).
     */
    function deposit() external payable;

    /**
     * @notice Withdraw unlocked ETH from the caller's account and transfer it to `recipient`.
     * @dev Implementations must ensure that only available (unlocked) funds can be withdrawn
     *      and should protect against reentrancy and other common risks.
     * @param amount The amount of ETH (in wei) to withdraw.
     * @param recipient The address that will receive the withdrawn ETH.
     */
    function withdraw(uint256 amount, address recipient) external;

    /**
     * @notice Retrieve balance information for `user`.
     * @param user The address whose balance is being queried.
     * @return UserBalance A struct containing `totalBalance` and `lockedBalance` for the user.
     */
    function getUserBalance(
        address user
    ) external view returns (UserBalance memory);

    /**
     * @notice Create a new game by committing necessary secrets and posting a stake.
     * @dev `randomnessCommitment` and `boardCommitment` are commitments (hashes) that will
     *      later be revealed and verified. `stake` is locked until the game concludes.
     * @param randomnessCommitment Commitment to per-game randomness provided by the creator.
     * @param boardCommitment Commitment to the creator's board layout (e.g., Merkle root or hash).
     * @param stake Amount of ETH (in wei) to lock as the creator's stake for the game.
     */
    function createGame(
        bytes32 randomnessCommitment,
        bytes32 boardCommitment,
        uint256 stake
    ) external payable;

    /**
     * @notice Join an existing game by providing commitments for randomness and board layout.
     * @dev The joiner must satisfy any stake or match conditions required by the game creator.
     * @param gameId The identifier of the game to join.
     * @param randomnessSalt per-game randomness.
     * @param boardCommitment Commitment to the joiner's board layout.
     */
    function joinGame(
        uint256 gameId,
        bytes32 randomnessSalt,
        bytes32 boardCommitment
    ) external payable;

    /**
     * @notice Quit or forfeit an in-progress or not-yet-started game.
     * @dev The exact behavior (refunds, penalties, state transitions) is implementation-defined
     *      and handled by the concrete contract.
     * @param gameId The identifier of the game to quit.
     */
    function quitGame(uint256 gameId) external;

    /**
     * @notice Reveal the preimage (salt) for a previously submitted randomness commitment.
     * @dev Revealing the randomness allows the contract and the opponent to verify the
     *      original commitment and resolve any randomness-dependent game mechanics.
     * @param gameId The identifier of the game for which randomness is revealed.
     * @param randomnessSalt The secret salt whose hash was previously committed.
     */
    function revealRandomness(uint256 gameId, bytes32 randomnessSalt) external;

    /**
     * @notice Fire a shot at the specified position in `gameId`.
     * @dev `firePosition` encodes the target cell; the current game state must permit the
     *      caller to act. This call typically emits `ShotFired` and advances the turn.
     * @param gameId The identifier of the game where the shot is fired.
     * @param firePosition The encoded board cell index being targeted.
     */
    function shoot(uint256 gameId, uint8 firePosition) external;

    /**
     * @notice Report the result of a shot together with a verification proof (e.g., ZK proof).
     * @dev The `proof` bytes are verified on-chain to ensure the reported result matches the
     *      defender's committed board without revealing sensitive board details.
     * @param gameId The identifier of the relevant game.
     * @param shotResult The reported outcome (Error/Miss/Hit/Sunk).
     * @param proof Serialized proof data used to validate the correctness of `shotResult`.
     */
    function reportShotResult(
        uint256 gameId,
        ShotResult shotResult,
        bytes calldata proof
    ) external;

    function sendMessage(address recipient, string calldata message) external;
}

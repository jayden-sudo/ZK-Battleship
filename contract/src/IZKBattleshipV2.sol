// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

// =================================================================================================
// Enums and Structs
// =================================================================================================

/**
 * @notice Represents the state of a player's funds within the contract.
 * @param totalBalance The entire balance held for the user.
 * @param lockedBalance The portion of the total balance currently reserved in an active game.
 */
struct UserBalance {
    uint256 totalBalance;
    uint256 lockedBalance;
}

/**
 * @notice Defines the sequence of states that a game progresses through.
 */
enum NextTurnState {
    Blank, // 0: The game is in an uninitialized or invalid state.
    Join, // 1: The game is waiting for a second player to join.
    RevealRandomness, // 2: Both players must reveal their randomness to determine initiative.
    CreatorFire, // 3: It is the creator's turn to fire a shot.
    JoinerFire, // 4: It is the joiner's turn to fire a shot.
    CreatorReport, // 5: The creator must report the result of the joiner's shot.
    JoinerReport, // 6: The joiner must report the result of the creator's shot.
    Completed // 7: The game has concluded.
}

/**
 * @notice Contains all data related to a single game instance.
 * @param creator The address of the player who created the game.
 * @param joiner The address of the player who joined the game.
 * @param creatorRandomnessCommitment The creator's committed hash for determining initiative.
 * @param joinerRandomnessSalt The joiner's revealed salt for determining initiative.
 * @param creatorBoardCommitment The creator's committed hash of their board layout.
 * @param joinerBoardCommitment The joiner's committed hash of their board layout.
 * @param stake The amount of ETH (in wei) staked by each player.
 * @param lastActiveTimestamp The timestamp of the last action taken in the game.
 * @param creatorGameBoard A bitmask representing the state of the creator's game board.
 * @param joinerGameBoard A bitmask representing the state of the joiner's game board.
 * @param nextTurnState The current state indicating whose turn it is or what action is next.
 * @param fireAtPosition The board position targeted by the last shot.
 */
struct Game {
    address creator;
    address joiner;
    bytes32 creatorRandomnessCommitment;
    bytes32 joinerRandomnessSalt;
    bytes32 creatorBoardCommitment;
    bytes32 joinerBoardCommitment;
    bytes32 previousGameStatusHash;
    bytes32 currentGameStatusHash;
    address creatorSessionKey;
    address joinerSessionKey;
    uint256 stake;
    uint64 lastActiveTimestamp;
    uint64 creatorGameBoard;
    uint64 joinerGameBoard;
    NextTurnState nextTurnState;
    uint8 fireAtPosition;
}

/**
 * @notice
 */
struct ShotResult {
    ShotStatus shotStatus;
    uint8 sunkHeadPosition;
    uint8 sunkEndPosition;
}

/**
 * @notice
 */
struct DashBoard {
    uint64 InProgress;
    uint64 Completed;
    uint64 Waiting;
}

/**
 * @notice Possible outcomes for a fired shot.
 */
enum ShotStatus {
    Miss, // 0: The shot did not hit any ship.
    Hit, // 1: The shot hit a part of a ship.
    Sunk // 2: The shot hit the final part of a ship, sinking it.
}

enum GameStatusType {
    Shot, // 0
    ShotResult // 1
}

struct GameStatus {
    GameStatusType gameStatusType;
    /**
     * if gameStatusType == Shot { value ∈ [0, 63] }
     * if gameStatusType == ShotResult { value ∈ {ShotStatus} }
     */
    uint8 value;
    /**
     * if gameStatusType == Shot { sessionKeySignature = attacker.sign(gameStatusHash  || value) }
     * if gameStatusType == ShotResult { sessionKeySignature = defender.sign(gameStatusHash || value) }
     */
    bytes sessionKeySignature;
}

/**
 * @title IZKBattleshipV2
 * @notice Interface for the ZK-Battleship game contract.
 * @dev Defines the core functions, events, and data structures for a trustless battleship game
 *      that leverages zero-knowledge proofs for move verification.
 */
interface IZKBattleshipV2 {
    // =================================================================================================
    // Events
    // =================================================================================================

    /**
     * @notice Emitted when a new game is created.
     * @param gameId The unique identifier for the new game.
     * @param creator The address of the player who created the game.
     * @param stake The amount of ETH (in wei) staked by the creator.
     */
    event GameCreated(
        bytes32 indexed gameId,
        address indexed creator,
        uint256 stake,
        address sessionKey,
        bytes p2pMessagePublicKey
    );

    /**
     * @notice Emitted when a player joins an existing game.
     * @param gameId The identifier of the game being joined.
     * @param joiner The address of the player who joined.
     */
    event GameJoined(
        bytes32 indexed gameId,
        address indexed joiner,
        address sessionKey,
        bytes p2pMessagePublicKey,
        bytes encryptedP2PUID
    );

    event P2PUIDUpdated(bytes encryptedP2PUID);

    event GameClosed(bytes32 indexed gameId);

    /**
     * @notice Emitted after both players have revealed their randomness.
     * @param gameId The identifier of the game.
     * @param initiativePlayer The address of the player who won the initiative and will fire first.
     */
    event RandomnessRevealed(bytes32 indexed gameId, address initiativePlayer);

    /**
     * @notice Emitted when a defender reports the result of a shot, backed by a ZK proof.
     * @param gameId The identifier of the game.
     * @param defender The address of the player reporting the shot result.
     * @param firePosition The board position (0-63) to target.
     * @param result The outcome of the shot (Miss, Hit, or Sunk).
     */
    event ShotResultReported(
        bytes32 indexed gameId,
        address indexed defender,
        uint8 firePosition,
        ShotResult result
    );

    /**
     * @notice Emitted when a game has been won.
     * @param gameId The identifier of the completed game.
     * @param winner The address of the player who won the game.
     */
    event GameEnded(bytes32 indexed gameId, address indexed winner);

    // =================================================================================================
    // View Functions
    // =================================================================================================

    /**
     * @notice Lists all games currently waiting for a joiner.
     * @param from The starting gameId for pagination.
     * @param limit The maximum number of game IDs to return.
     * @return An array of game IDs.
     */
    function listWaitingGames(
        bytes32 from,
        uint256 limit
    ) external view returns (bytes32[] memory);

    /**
     * @notice Retrieves the ID of the game a user is currently participating in.
     * @param user The address of the player.
     * @return gameId The ID of the active game, or 0 if the user is not in a game.
     */
    function getUserGameId(address user) external view returns (bytes32 gameId);

    /**
     * @notice Fetches the complete data structure for a specific game.
     * @param gameId The identifier of the game to retrieve.
     * @return A `Game` struct containing all on-chain data for the game.
     */
    function getGameData(bytes32 gameId) external view returns (Game memory);

    /**
     * @notice Retrieves the balance information for a specified user.
     * @param user The address to query.
     * @return A `UserBalance` struct with the user's total and locked balances.
     */
    function getUserBalance(
        address user
    ) external view returns (UserBalance memory);

    // =================================================================================================
    // State-Changing Functions
    // =================================================================================================

    /**
     * @notice Deposits ETH into the contract, crediting the caller's balance.
     * @dev The amount is determined by `msg.value`.
     */
    function deposit() external payable;

    /**
     * @notice Creates a new game and puts it in a waiting state.
     * @dev Locks the creator's stake and commits to their board layout and randomness.
     * @param boardCommitment A commitment (e.g., hash or Merkle root) of the board layout.
     * @param stake The amount of ETH (in wei) to stake on the game.
     */
    function createGame(
        bytes32 randomnessCommitment,
        bytes32 boardCommitment,
        uint256 stake,
        address sessionKey,
        bytes calldata p2pMessagePublicKey
    ) external payable returns (bytes32 gameId /* hash(msg.sender || args) */);

    /**
     * @notice Joins an existing game created by another player.
     * @dev Requires matching the creator's stake and committing to a board layout and randomness.
     * @param gameId The identifier of the game to join.
     * @param boardCommitment A commitment to the joiner's board layout.
     */
    function joinGame(
        bytes32 gameId,
        bytes32 boardCommitment,
        bytes32 randomnessSalt,
        address sessionKey,
        bytes calldata p2pMessagePublicKey,
        bytes calldata encryptedP2PUID
    ) external payable;

    /**
     * @notice Reveals the creator's secret randomness after a joiner is present.
     * @dev This action allows the contract to determine which player has the first turn.
     * @param gameId The identifier of the game.
     * @param randomnessSalt The secret value corresponding to the previously submitted commitment.
     */
    function revealRandomness(bytes32 gameId, bytes32 randomnessSalt) external;

    function updateP2PUID(bytes calldata encryptedP2PUID) external;

    function closeIdleGame(bytes32 gameId) external;

    function opponentLeave(bytes32 gameId) external;

    function surrender(
        bytes32 gameId,
        bytes calldata sessionKeySignature
    ) external;

    function submitGameStatus(
        bytes32 gameId,
        GameStatus[] calldata gameStatus
    ) external;

    function reportCheating(
        bytes32 gameId,
        GameStatus calldata gameStatus
    ) external;

    /**
     * @notice Reports the result of an opponent's shot using a zero-knowledge proof.
     * @dev The proof is verified on-chain to confirm the outcome without revealing the board state.
     * @param gameId The identifier of the game.
     * @param shotResult The reported outcome of the shot.
     * @param proof The serialized ZK proof data that validates the reported result.
     */
    function reportShotResult(
        bytes32 gameId,
        ShotResult memory shotResult,
        bytes calldata proof
    ) external;
}

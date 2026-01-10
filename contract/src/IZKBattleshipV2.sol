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
 * @param previousGameStatusHash The hash of the previous game status.
 * @param currentGameStatusHash The hash of the current game status.
 * @param creatorSessionKey The session key for the creator.
 * @param joinerSessionKey The session key for the joiner.
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
    bytes32 creatorBoardCommitment;
    bytes32 joinerBoardCommitment;
    bytes32 previousGameStatusHash;
    bytes32 currentGameStatusHash;
    address creatorSessionKey;
    address joinerSessionKey;
    uint256 stake;
    uint64 creatorGameBoard;
    uint64 joinerGameBoard;
    uint64 lastActiveTimestamp;
    NextTurnState nextTurnState;
    uint8 fireAtPosition;
}

/**
 * @notice Represents the outcome of a shot.
 * @param shotStatus The status of the shot (Miss, Hit, or Sunk).
 * @param sunkHeadPosition The head position of the ship if it was sunk.
 * @param sunkEndPosition The end position of the ship if it was sunk.
 */
struct ShotResult {
    ShotStatus shotStatus;
    uint8 sunkHeadPosition;
    uint8 sunkEndPosition;
}

/**
 * @notice A dashboard of game statistics.
 * @param InProgress The number of games in progress.
 * @param Completed The number of completed games.
 * @param Waiting The number of games waiting for a joiner.
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

/**
 * @notice The type of game status update.
 */
enum GameStatusType {
    Shot, // 0: A player fires a shot.
    Report // 1: A player reports the result of a shot.
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
     * @param sessionKey The session key registered by the creator for this game.
     * @param p2pUID The [encrypted(Not yet implemented)] peer-to-peer user ID.
     */
    event GameCreated(
        bytes32 indexed gameId,
        address indexed creator,
        uint256 stake,
        address sessionKey,
        string p2pUID
    );

    /**
     * @notice Emitted when a player joins an existing game.
     * @param gameId The identifier of the game being joined.
     * @param joiner The address of the player who joined.
     * @param sessionKey The session key registered by the joiner for this game.
     * */
    event GameJoined(
        bytes32 indexed gameId,
        address indexed joiner,
        address sessionKey
    );

    /**
     * @notice Emitted when an idle game is closed.
     * @param gameId The identifier of the closed game.
     */
    event GameClosed(bytes32 indexed gameId);

    /**
     * @notice Emitted after both players have revealed their randomness.
     * @param gameId The identifier of the game.
     * @param initiativePlayer The address of the player who won the initiative and will fire first.
     */
    event RandomnessRevealed(bytes32 indexed gameId, address initiativePlayer);

    /**
     * @notice Emitted when a player fires a shot.
     * @param gameId The identifier of the game.
     * @param attacker The address of the player who fired the shot.
     * @param firePosition The board position (0-63) targeted by the shot.
     */
    event ShotFired(
        bytes32 indexed gameId,
        address indexed attacker,
        uint8 firePosition,
        bytes32 gameStatusHash
    );

    /**
     * @notice Emitted when a defender reports the result of a shot, backed by a ZK proof.
     * @param gameId The identifier of the game.
     * @param defender The address of the player reporting the shot result.
     * @param firePosition The board position (0-63) to target.
     * @param result The outcome of the shot (Miss, Hit, or Sunk).
     */
    event ResultReported(
        bytes32 indexed gameId,
        address indexed defender,
        uint8 firePosition,
        ShotResult result,
        bytes32 gameStatusHash
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
     * @notice Lists the full game data for all games currently waiting for a joiner.
     * @param from The starting gameId for pagination.
     * @param limit The maximum number of game data objects to return.
     */
    function listWaitingGameData(
        bytes32 from,
        uint256 limit
    ) external view returns (bytes32[] memory gameIds, Game[] memory gameData);

    /**
     * @notice Retrieves the ID of the game a user is currently participating in.
     * @param user The address of the player.
     * @return gameId The ID of the active game, or zero if the user is not in a game.
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
     * @dev The amount is determined by `msg.value`. The deposited funds can be used for game stakes.
     * @dev Reverts if msg.value is 0.
     */
    function deposit() external payable;

    /**
     * @notice Withdraws ETH from the caller's available (unlocked) balance.
     * @param amount The amount of ETH (in wei) to withdraw.
     * @dev Reverts if the amount exceeds the available balance or if the transfer fails.
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Creates a new game and puts it in a waiting state.
     * @dev Locks the creator's stake and commits to their board layout and randomness.
     * @param randomnessCommitment A commitment to the creator's randomness salt.
     * @param boardCommitment A commitment (e.g., hash or Merkle root) of the board layout.
     * @param stake The amount of ETH (in wei) to stake on the game.
     * @param sessionKey A session key for signing off-chain game status updates.
     * @param p2pUID The [encrypted(Not yet implemented)] peer-to-peer user ID.
     * @return gameId The unique identifier for the new game.
     */
    function createGame(
        bytes32 randomnessCommitment,
        bytes32 boardCommitment,
        uint256 stake,
        address sessionKey,
        string calldata p2pUID
    ) external payable returns (bytes32 gameId);

    /**
     * @notice Joins an existing game created by another player.
     * @dev Requires matching the creator's stake and committing to a board layout and randomness.
     * @param gameId The identifier of the game to join.
     * @param boardCommitment A commitment to the joiner's board layout.
     * @param sessionKey A session key for signing off-chain game status updates.
     * @param endTime The timestamp when the creator's signature expires (for security).
     * @param creatorSignature The signature from the creator's session key (obtained via P2P communication).
     */
    function joinGame(
        bytes32 gameId,
        bytes32 boardCommitment,
        address sessionKey,
        uint256 endTime,
        bytes calldata creatorSignature
    ) external payable;

    /**
     * @notice Reveals the creator's secret randomness after a joiner is present.
     * @dev This action allows the contract to determine which player has the first turn.
     * @param gameId The identifier of the game.
     * @param randomnessSalt The secret value corresponding to the previously submitted commitment.
     */
    function revealRandomness(bytes32 gameId, bytes32 randomnessSalt) external;

    /**
     * @notice Closes a game that has been idle for too long.
     * @dev Allows anyone to close an inactive game and potentially claim a reward.
     * @param gameId The identifier of the idle game.
     */
    function closeIdleGame(bytes32 gameId) external;

    /**
     * @notice Allows a player to claim victory if their opponent has left or is unresponsive.
     * @param gameId The identifier of the game.
     */
    function opponentLeave(bytes32 gameId) external;

    /**
     * @notice Allows a player to surrender the game.
     * @dev The opponent is declared the winner and receives the staked funds.
     * @param gameId The identifier of the game.
     * @param sessionKeySignature A signature from the player's session key to confirm the surrender.
     */
    function surrender(
        bytes32 gameId,
        bytes calldata sessionKeySignature
    ) external;

    /**
     * @notice Submits a batch of opponent's moves to update the game state on-chain.
     * @dev Allows a player to force progress by submitting a sequence of game actions that the opponent has
     *      already signed off-chain. This is a key mechanism for resolving disputes or timeouts.
     *      The entire sequence is validated against the opponent's single signature.
     *      The update is only applied if `expectGameStatusHash` matches the current on-chain game status hash,
     *      preventing updates from being applied to the wrong state.
     * @param gameId The unique identifier for the game being updated.
     * @param expectGameStatusHash The expected game status hash before this batch of updates is applied.
     * @param gameStatus An array of game actions (e.g., shot positions or results) performed by the opponent.
     * @param opponentSessionKeySignature The opponent's session key signature that validates the entire `gameStatus` sequence.
     */
    function submitGameStatus(
        bytes32 gameId,
        bytes32 expectGameStatusHash,
        uint8[] calldata gameStatus,
        bytes calldata opponentSessionKeySignature
    ) external;

    /**
     * @notice Reports that an opponent has cheated.
     * @dev This function is used to challenge an invalid game state.
     * @param gameId The identifier of the game.
     * @param firePosition The board position (0-63) where cheating is being reported.
     * @param opponentSessionKeySignature The opponent's session key signature that is being challenged.
     */
    function reportCheating(
        bytes32 gameId,
        uint8 firePosition,
        bytes calldata opponentSessionKeySignature
    ) external;

    /**
     * @notice Reports the result of an opponent's shot using a zero-knowledge proof.
     * @dev The proof is verified on-chain to confirm the outcome without revealing the board state.
     * @param gameId The identifier of the game.
     * @param expectGameStatusHash The expected game status hash.
     * @param shotResult The reported outcome of the shot.
     * @param proof The serialized ZK proof data that validates the reported result.
     */
    function reportShotResult(
        bytes32 gameId,
        bytes32 expectGameStatusHash,
        ShotResult memory shotResult,
        bytes calldata proof
    ) external;
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {IZKBattleship, UserBalance, Game, NextTurnState, ShotResult, ShotStatus} from "./IZKBattleship.sol";
import {GameLinkedList} from "./GameLinkedList.sol";
import {IVerifier} from "./IVerifier.sol";

/**
 * @title ZKBattleship
 * @notice This contract is the main implementation of the ZK-Battleship game.
 * @dev It handles game logic, player funds, state transitions, and verification of ZK proofs.
 *      It relies on a Verifier contract to validate proofs for game actions.
 */
contract ZKBattleship is IZKBattleship {
    using GameLinkedList for mapping(uint256 => uint256);

    // =================================================================================================
    // State Variables
    // =================================================================================================

    /// @notice The grace period (in seconds) for on-chain transaction confirmation.
    uint8 public immutable SAFE_ONCHAIN_TIME;
    /// @notice The time (in seconds) allocated for a player to make a decision.
    uint8 public immutable PLAYER_DECISION_TIME;
    /// @notice The time (in seconds) allocated for generating a ZK proof.
    uint8 public immutable ZK_PROOF_TIME;
    /// @notice The contract that verifies ZK proofs.
    IVerifier public immutable VERIFIER;

    /// @notice The counter for generating unique game IDs.
    uint256 private nextGameId = 10;

    /// @notice Maps user addresses to their fund balances.
    mapping(address => UserBalance) private balances;
    /// @notice Maps game IDs to their full game data.
    mapping(uint256 => Game) private games;
    /// @notice A linked list of games waiting for a joiner, allowing for efficient pagination.
    mapping(uint256 => uint256) private waitingGames;
    /// @notice Maps user addresses to the ID of the game they are currently in.
    mapping(address => uint256) private userGameIds;

    // =================================================================================================
    // Constructor
    // =================================================================================================

    /**
     * @notice Initializes the ZKBattleship contract with necessary parameters.
     * @param verifier The address of the `Verifier` contract for ZK proofs.
     * @param safeOnchainTime The grace period (seconds) for transaction confirmation.
     * @param playerDecisionTime The time (seconds) for a player to decide their move.
     * @param zkProofTime The time (seconds) allocated for ZK proof generation.
     */
    constructor(
        IVerifier verifier,
        uint8 safeOnchainTime,
        uint8 playerDecisionTime,
        uint8 zkProofTime
    ) {
        VERIFIER = verifier;
        SAFE_ONCHAIN_TIME = safeOnchainTime;
        PLAYER_DECISION_TIME = playerDecisionTime;
        ZK_PROOF_TIME = zkProofTime;
    }

    // =================================================================================================
    // View Functions
    // =================================================================================================

    /**
     * @inheritdoc IZKBattleship
     */
    function listWaitingGames(
        uint256 from,
        uint256 limit
    ) external view override returns (uint256[] memory) {
        return waitingGames.list(from, limit);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function getUserGameId(
        address user
    ) external view override returns (uint256 gameId) {
        return userGameIds[user];
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function getGameData(
        uint256 gameId
    ) external view override returns (Game memory) {
        return games[gameId];
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function getUserBalance(
        address user
    ) external view override returns (UserBalance memory) {
        return balances[user];
    }

    // =================================================================================================
    // State-Changing Functions
    // =================================================================================================

    /**
     * @notice Fallback function to receive ETH and credit the sender's balance.
     */
    receive() external payable {
        _deposit(msg.value, msg.sender);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function deposit() external payable override {
        _deposit(msg.value, msg.sender);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function withdraw(uint256 amount, address recipient) external override {
        UserBalance storage userBalance = balances[msg.sender];
        require(
            userBalance.totalBalance - userBalance.lockedBalance >= amount,
            "ZKBattleship: Insufficient unlocked balance"
        );

        userBalance.totalBalance -= amount;

        if (recipient == address(0)) {
            recipient = msg.sender;
        }

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ZKBattleship: ETH transfer failed");
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function createGame(
        bytes32 randomnessCommitment,
        bytes32 boardCommitment,
        uint256 stake
    ) external payable override {
        if (msg.value > 0) {
            _deposit(msg.value, msg.sender);
        }
        require(
            balances[msg.sender].totalBalance -
                balances[msg.sender].lockedBalance >=
                stake,
            "ZKBattleship: Insufficient unlocked balance for stake"
        );
        balances[msg.sender].lockedBalance += stake;

        require(
            userGameIds[msg.sender] == 0,
            "ZKBattleship: User is already in a game"
        );
        uint256 gameId = _getNextGameId();
        userGameIds[msg.sender] = gameId;

        Game memory newGame = Game({
            creator: msg.sender,
            joiner: address(0),
            creatorRandomnessCommitment: randomnessCommitment,
            joinerRandomnessSalt: bytes32(0),
            creatorBoardCommitment: boardCommitment,
            joinerBoardCommitment: bytes32(0),
            stake: stake,
            lastActiveTimestamp: 0,
            creatorGameBoard: 0,
            joinerGameBoard: 0,
            nextTurnState: NextTurnState.Join,
            fireAtPosition: 0
        });

        games[gameId] = newGame;
        waitingGames.add(gameId);

        emit GameCreated(gameId, msg.sender, stake);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function joinGame(
        uint256 gameId,
        bytes32 randomnessSalt,
        bytes32 boardCommitment
    ) external payable override {
        if (msg.value > 0) {
            _deposit(msg.value, msg.sender);
        }

        require(
            userGameIds[msg.sender] == 0,
            "ZKBattleship: User is already in a game"
        );
        userGameIds[msg.sender] = gameId;

        Game storage game = games[gameId];
        require(
            game.nextTurnState == NextTurnState.Join,
            "ZKBattleship: Game is not available to join"
        );
        require(
            balances[msg.sender].totalBalance -
                balances[msg.sender].lockedBalance >=
                game.stake,
            "ZKBattleship: Insufficient unlocked balance for stake"
        );
        balances[msg.sender].lockedBalance += game.stake;
        waitingGames.remove(gameId);

        game.joiner = msg.sender;
        game.joinerRandomnessSalt = randomnessSalt;
        game.joinerBoardCommitment = boardCommitment;
        game.lastActiveTimestamp = uint64(block.timestamp);
        game.nextTurnState = NextTurnState.RevealRandomness;

        emit GameJoined(gameId, msg.sender);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function revealRandomness(
        uint256 gameId,
        bytes32 randomnessSalt
    ) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState == NextTurnState.RevealRandomness,
            "ZKBattleship: Not in RevealRandomness state"
        );
        require(
            msg.sender == game.creator,
            "ZKBattleship: Only the creator can reveal randomness"
        );
        require(
            game.creatorRandomnessCommitment ==
                keccak256(abi.encode(randomnessSalt)),
            "ZKBattleship: Invalid randomness salt"
        );
        // Determine initiative by combining both players' randomness.
        bytes32 combinedRandomness = keccak256(
            abi.encode(randomnessSalt, game.joinerRandomnessSalt)
        );
        bool creatorFirst = uint256(combinedRandomness) % 2 == 1;

        game.nextTurnState = creatorFirst
            ? NextTurnState.CreatorFire
            : NextTurnState.JoinerFire;
        game.lastActiveTimestamp = uint64(block.timestamp);

        emit RandomnessRevealed(
            gameId,
            creatorFirst ? game.creator : game.joiner
        );
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function shoot(uint256 gameId, uint8 firePosition) external override {
        require(firePosition < 36, "ZKBattleship: Invalid fire position");
        Game storage game = games[gameId];
        uint64 gameBoard;

        if (game.nextTurnState == NextTurnState.JoinerFire) {
            require(
                msg.sender == game.joiner,
                "ZKBattleship: Not joiner's turn to shoot"
            );
            gameBoard = game.creatorGameBoard;
            game.nextTurnState = NextTurnState.CreatorReport;
        } else if (game.nextTurnState == NextTurnState.CreatorFire) {
            require(
                msg.sender == game.creator,
                "ZKBattleship: Not creator's turn to shoot"
            );
            gameBoard = game.joinerGameBoard;
            game.nextTurnState = NextTurnState.JoinerReport;
        } else {
            revert("ZKBattleship: Not in a valid state to shoot");
        }

        require(
            (gameBoard >> firePosition) & 1 == 0,
            "ZKBattleship: Position already shot at"
        );
        game.lastActiveTimestamp = uint64(block.timestamp);
        game.fireAtPosition = firePosition;
        emit ShotFired(gameId, msg.sender, firePosition);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function reportShotResult(
        uint256 gameId,
        ShotResult memory shotResult,
        bytes calldata proof
    ) external override {
        Game storage game = games[gameId];
        bytes32 boardCommitment;
        uint64 gameBoard;

        // Determine whose turn it is to report and set next state
        if (game.nextTurnState == NextTurnState.JoinerReport) {
            require(
                msg.sender == game.joiner,
                "ZKBattleship: Not joiner's turn to report"
            );
            game.nextTurnState = NextTurnState.JoinerFire; // Attacker's turn to fire again
            gameBoard = game.joinerGameBoard;
            boardCommitment = game.joinerBoardCommitment;
        } else if (game.nextTurnState == NextTurnState.CreatorReport) {
            require(
                msg.sender == game.creator,
                "ZKBattleship: Not creator's turn to report"
            );
            game.nextTurnState = NextTurnState.CreatorFire; // Attacker's turn to fire again
            gameBoard = game.creatorGameBoard;
            boardCommitment = game.creatorBoardCommitment;
        } else {
            revert("ZKBattleship: Not in a valid state to report result");
        }

        game.lastActiveTimestamp = uint64(block.timestamp);

        // Verify the ZK proof for the reported shot result
        require(
            _zkProofVerify(
                boardCommitment,
                gameBoard,
                game.fireAtPosition,
                shotResult,
                proof
            ),
            "ZKBattleship: Invalid ZK proof for shot result"
        );

        // If the shot was a hit or sunk a ship, update the game board
        if (
            shotResult.shotStatus == ShotStatus.Hit ||
            shotResult.shotStatus == ShotStatus.Sunk
        ) {
            uint64 newGameBoard = gameBoard |
                (uint64(1) << ((36) - 1 - game.fireAtPosition));

            // Check for winner: 6 total hits are required to win.
            if (_hitedObjectCount(newGameBoard) >= 6) {
                address winner;
                address loser;
                if (game.nextTurnState == NextTurnState.JoinerFire) {
                    // Joiner was reporting, creator shot
                    winner = game.creator;
                    loser = game.joiner;
                } else {
                    // Creator was reporting, joiner shot
                    winner = game.joiner;
                    loser = game.creator;
                }

                // Transfer stake from loser to winner
                balances[winner].lockedBalance -= game.stake;
                balances[loser].lockedBalance -= game.stake;
                balances[winner].totalBalance += game.stake;
                balances[loser].totalBalance -= game.stake;

                _gameEnded(gameId, winner);
            } else {
                // Update the defender's board with the new hit
                if (game.nextTurnState == NextTurnState.JoinerFire) {
                    // Joiner was reporting
                    game.joinerGameBoard = newGameBoard;
                } else {
                    // Creator was reporting
                    game.creatorGameBoard = newGameBoard;
                }
            }
        }

        emit ShotResultReported(gameId, msg.sender, shotResult);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function leaveGame(uint256 gameId) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState > NextTurnState.Blank &&
                game.nextTurnState < NextTurnState.Completed,
            "ZKBattleship: Game is already completed"
        );
        require(
            msg.sender == game.creator || msg.sender == game.joiner,
            "ZKBattleship: Not a player in this game"
        );

        address opponent;

        if (game.nextTurnState == NextTurnState.Join) {
            // Game has not started, creator is leaving. Refund stake.
            require(
                msg.sender == game.creator,
                "ZKBattleship: Only creator can leave at this stage"
            );
            balances[game.creator].lockedBalance -= game.stake;
            opponent = address(0); // No winner
        } else {
            // Game is in progress, leaver forfeits.
            opponent = msg.sender == game.creator ? game.joiner : game.creator;

            // Transfer stake to the opponent
            balances[msg.sender].lockedBalance -= game.stake;
            balances[opponent].lockedBalance -= game.stake;
            balances[opponent].totalBalance += game.stake;
            balances[msg.sender].totalBalance -= game.stake;
        }

        _gameEnded(gameId, opponent);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function terminateGame(uint256 gameId) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState > NextTurnState.Join &&
                game.nextTurnState < NextTurnState.Completed,
            "ZKBattleship: Game cannot be terminated in its current state"
        );

        uint64 timeout;
        bool isJoinerTerminating = false;

        // Determine the appropriate timeout based on the game state.
        if (game.nextTurnState == NextTurnState.RevealRandomness) {
            isJoinerTerminating = true;
            timeout = game.lastActiveTimestamp + SAFE_ONCHAIN_TIME;
        } else if (game.nextTurnState == NextTurnState.CreatorFire) {
            isJoinerTerminating = true;
            timeout =
                game.lastActiveTimestamp +
                PLAYER_DECISION_TIME +
                SAFE_ONCHAIN_TIME;
        } else if (game.nextTurnState == NextTurnState.JoinerFire) {
            timeout =
                game.lastActiveTimestamp +
                PLAYER_DECISION_TIME +
                SAFE_ONCHAIN_TIME;
        } else if (game.nextTurnState == NextTurnState.CreatorReport) {
            isJoinerTerminating = true;
            timeout =
                game.lastActiveTimestamp +
                ZK_PROOF_TIME +
                SAFE_ONCHAIN_TIME;
        } else if (game.nextTurnState == NextTurnState.JoinerReport) {
            timeout =
                game.lastActiveTimestamp +
                ZK_PROOF_TIME +
                SAFE_ONCHAIN_TIME;
        } else {
            revert("ZKBattleship: Invalid game state for termination");
        }

        address expectedTerminator = isJoinerTerminating
            ? game.joiner
            : game.creator;
        require(
            msg.sender == expectedTerminator,
            "ZKBattleship: Not your turn to terminate"
        );
        require(
            block.timestamp > timeout,
            "ZKBattleship: Timeout period has not passed"
        );

        // The caller (msg.sender) wins due to opponent's inactivity.
        address opponent = isJoinerTerminating ? game.creator : game.joiner;

        balances[msg.sender].lockedBalance -= game.stake;
        balances[opponent].lockedBalance -= game.stake;
        balances[msg.sender].totalBalance += game.stake;
        balances[opponent].totalBalance -= game.stake;

        _gameEnded(gameId, msg.sender);
    }

    /**
     * @inheritdoc IZKBattleship
     */
    function sendMessage(
        address recipient,
        string calldata message
    ) external override {
        emit ChatMessage(msg.sender, recipient, message);
    }

    // =================================================================================================
    // Internal Functions
    // =================================================================================================

    /**
     * @notice Increments the game ID counter and returns the new ID.
     * @return The next available game ID.
     */
    function _getNextGameId() internal returns (uint256) {
        return nextGameId++;
    }

    /**
     * @notice Credits a user's total balance with a specified amount.
     * @param amount The amount of ETH (in wei) to deposit.
     * @param user The address of the user to credit.
     */
    function _deposit(uint256 amount, address user) internal {
        balances[user].totalBalance += amount;
    }

    /**
     * @notice Verifies a ZK proof against public inputs derived from game data.
     * @param boardCommitment The hash commitment of the defender's board.
     * @param gameBoard The bitmask representing the defender's board state (hits).
     * @param firePosition The position that was fired upon.
     * @param shotResult The reported result of the shot.
     * @param proof The ZK proof data to be verified.
     * @return A boolean indicating whether the proof is valid.
     */
    function _zkProofVerify(
        bytes32 boardCommitment,
        uint64 gameBoard,
        uint8 firePosition,
        ShotResult memory shotResult,
        bytes calldata proof
    ) internal returns (bool) {
        bytes32[] memory publicInputs = new bytes32[](2);
        publicInputs[0] = boardCommitment;
        // Pack game state data into a single bytes32 public input.
        publicInputs[1] = bytes32(
            (uint256(shotResult.sunkHeadPosition) << 48) +
                (uint256(shotResult.sunkEndPosition) << 56) +
                (uint256(gameBoard) << 12) +
                (uint256(firePosition) << 4) +
                uint256(shotResult.shotStatus)
        );
        return VERIFIER.verify(proof, publicInputs);
    }

    /**
     * @notice Counts the number of set bits (1s) in a uint64.
     * @dev Implements a parallel bit counting algorithm (popcount).
     *      See: https://www.chessprogramming.org/Population_Count
     * @param gameBoard The uint64 value to count bits in.
     * @return The number of set bits.
     */
    function _hitedObjectCount(uint64 gameBoard) internal pure returns (uint8) {
        gameBoard = gameBoard - ((gameBoard >> 1) & 0x5555555555555555);
        gameBoard =
            (gameBoard & 0x3333333333333333) +
            ((gameBoard >> 2) & 0x3333333333333333);
        gameBoard = (gameBoard + (gameBoard >> 4)) & 0x0f0f0f0f0f0f0f0f;
        uint256 y = uint256(gameBoard) * 0x0101010101010101;
        return uint8(y >> 56);
    }

    /**
     * @notice Cleans up game state after a game has concluded.
     * @dev Resets game-related mappings for both players and clears the game struct.
     * @param gameId The ID of the game that has ended.
     * @param winner The address of the winning player, or address(0) if there is no winner.
     */
    function _gameEnded(uint256 gameId, address winner) internal {
        Game storage game = games[gameId];
        userGameIds[game.creator] = 0;
        if (game.joiner != address(0)) {
            userGameIds[game.joiner] = 0;
        }

        // Clean up game storage
        delete games[gameId];

        game.nextTurnState = NextTurnState.Completed;

        emit GameEnded(gameId, winner);
    }
}

// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {IZKBattleshipV2, UserBalance, Game, GameStatus, GameStatusType, NextTurnState, ShotResult, ShotStatus, DashBoard} from "./IZKBattleshipV2.sol";
import {Bytes32LinkedList} from "./Bytes32LinkedList.sol";
import {IVerifier} from "./IVerifier.sol";

/**
 * @title ZKBattleship
 * @notice This contract is the main implementation of the ZK-Battleship game.
 * @dev It handles game logic, player funds, state transitions, and verification of ZK proofs.
 *      It relies on a Verifier contract to validate proofs for game actions.
 */
contract ZKBattleshipV2 is IZKBattleshipV2 {
    using Bytes32LinkedList for mapping(bytes32 => bytes32);

    // =================================================================================================
    // State Variables
    // =================================================================================================

    uint8 public immutable ROUND_TIME_LIMIT;
    uint8 public immutable REVEAL_RANDOMNESS_TIME_LIMIT;

    /// @notice The contract that verifies ZK proofs.
    IVerifier public immutable VERIFIER;

    /// @notice Maps user addresses to their fund balances.
    mapping(address => UserBalance) private balances;
    /// @notice Maps game IDs to their full game data.
    mapping(bytes32 => Game) private games;
    /// @notice A linked list of games waiting for a joiner, allowing for efficient pagination.
    mapping(bytes32 => bytes32) private waitingGames;
    /// @notice Maps user addresses to the ID of the game they are currently in.
    mapping(address => bytes32) private userGameIds;

    // =================================================================================================
    // Constructor
    // =================================================================================================

    constructor(
        uint8 roundTimeLimit,
        uint8 revealRandomnessLimit,
        IVerifier verifier
    ) {
        require(
            roundTimeLimit > 10 && roundTimeLimit < 60,
            "Invalid time limit"
        );
        require(
            revealRandomnessLimit > 5 && revealRandomnessLimit < 15,
            "Invalid time limit"
        );
        ROUND_TIME_LIMIT = roundTimeLimit;
        REVEAL_RANDOMNESS_TIME_LIMIT = revealRandomnessLimit;
        VERIFIER = verifier;
    }

    // =================================================================================================
    // View Functions
    // =================================================================================================

    function listWaitingGames(
        bytes32 from,
        uint256 limit
    ) external view override returns (bytes32[] memory) {
        return waitingGames.list(from, limit);
    }

    function getUserGameId(
        address user
    ) external view override returns (bytes32 gameId) {
        return userGameIds[user];
    }

    function getGameData(
        bytes32 gameId
    ) external view override returns (Game memory) {
        return games[gameId];
    }

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

    function deposit() external payable override {
        _deposit(msg.value, msg.sender);
    }

    function _deposit(uint256 amount, address user) internal {
        balances[user].totalBalance += amount;
    }

    function createGame(
        bytes32 randomnessCommitment,
        bytes32 boardCommitment,
        uint256 stake,
        address sessionKey,
        bytes calldata p2pMessagePublicKey
    ) external payable override returns (bytes32 gameId) {
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
            userGameIds[msg.sender] == bytes32(0),
            "ZKBattleship: User is already in a game"
        );

        require(sessionKey != address(0), "ZKBattleship: Invalid session key");

        gameId = keccak256(
            abi.encodePacked(
                msg.sender,
                randomnessCommitment,
                boardCommitment,
                stake,
                sessionKey,
                p2pMessagePublicKey
            )
        );

        require(
            games[gameId].nextTurnState == NextTurnState.Blank,
            "Game already exists"
        );

        userGameIds[msg.sender] = gameId;

        Game memory newGame = Game({
            creator: msg.sender,
            joiner: address(0),
            creatorRandomnessCommitment: randomnessCommitment,
            joinerRandomnessSalt: bytes32(0),
            creatorBoardCommitment: boardCommitment,
            joinerBoardCommitment: bytes32(0),
            previousGameStatusHash: bytes32(0),
            currentGameStatusHash: gameId,
            creatorSessionKey: sessionKey,
            joinerSessionKey: address(0),
            stake: stake,
            lastActiveTimestamp: 0,
            creatorGameBoard: 0,
            joinerGameBoard: 0,
            nextTurnState: NextTurnState.Join,
            fireAtPosition: 0
        });

        games[gameId] = newGame;
        waitingGames.add(gameId);

        emit GameCreated(
            gameId,
            msg.sender,
            stake,
            sessionKey,
            p2pMessagePublicKey
        );
    }

    function joinGame(
        bytes32 gameId,
        bytes32 boardCommitment,
        bytes32 randomnessSalt,
        address sessionKey,
        bytes calldata p2pMessagePublicKey,
        bytes calldata encryptedP2PUID
    ) external payable override {
        if (msg.value > 0) {
            _deposit(msg.value, msg.sender);
        }

        require(
            userGameIds[msg.sender] == 0,
            "ZKBattleship: User is already in a game"
        );
        require(sessionKey != address(0), "ZKBattleship: Invalid session key");
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
        require(
            sessionKey != game.creatorSessionKey,
            "ZKBattleship: Invalid session key"
        );
        balances[msg.sender].lockedBalance += game.stake;
        waitingGames.remove(gameId);

        game.joiner = msg.sender;
        game.joinerRandomnessSalt = randomnessSalt;
        game.joinerBoardCommitment = boardCommitment;
        game.joinerSessionKey = sessionKey;
        game.lastActiveTimestamp = uint64(block.timestamp);
        game.nextTurnState = NextTurnState.RevealRandomness;

        emit GameJoined(
            gameId,
            msg.sender,
            sessionKey,
            p2pMessagePublicKey,
            encryptedP2PUID
        );
    }

    function revealRandomness(
        bytes32 gameId,
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

    function updateP2PUID(bytes calldata encryptedP2PUID) external override {
        emit P2PUIDUpdated(encryptedP2PUID);
    }

    function closeIdleGame(bytes32 gameId) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState == NextTurnState.Join,
            "ZKBattleship: Game state error"
        );

        game.nextTurnState = NextTurnState.Completed;

        require(
            msg.sender == game.creator,
            "ZKBattleship: Only creator can leave at this stage"
        );
        balances[game.creator].lockedBalance -= game.stake;

        emit GameClosed(gameId);
    }

    function gameEnded(bytes32 gameId, address winner) internal {
        Game storage game = games[gameId];
        userGameIds[game.creator] = 0;
        if (game.joiner != address(0)) {
            userGameIds[game.joiner] = 0;
        }

        address loser = game.creator == winner ? game.joiner : game.creator;
        balances[loser].lockedBalance -= game.stake;
        balances[winner].lockedBalance -= game.stake;
        balances[winner].totalBalance += game.stake;
        balances[loser].totalBalance -= game.stake;

        // Clean up game storage
        delete games[gameId];

        games[gameId].nextTurnState = NextTurnState.Completed;

        emit GameEnded(gameId, winner);
    }

    function opponentLeave(bytes32 gameId) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState > NextTurnState.Join &&
                game.nextTurnState < NextTurnState.Completed,
            "ZKBattleship: Game state error"
        );
        uint64 _now = uint64(block.timestamp);
        if (game.nextTurnState == NextTurnState.RevealRandomness) {
            require(msg.sender == game.joiner, "ZKBattleship: Invalid sender");
            require(
                _now - game.lastActiveTimestamp > REVEAL_RANDOMNESS_TIME_LIMIT,
                "ZKBattleship: Timeout period has not passed"
            );
            gameEnded(gameId, game.joiner);
        } else {
            require(
                _now - game.lastActiveTimestamp > ROUND_TIME_LIMIT,
                "ZKBattleship: Timeout period has not passed"
            );
            if (msg.sender == game.creator) {
                require(
                    game.nextTurnState == NextTurnState.JoinerFire ||
                        game.nextTurnState == NextTurnState.JoinerReport,
                    "ZKBattleship: Game state error"
                );
            } else if (msg.sender == game.joiner) {
                require(
                    game.nextTurnState == NextTurnState.CreatorFire ||
                        game.nextTurnState == NextTurnState.CreatorReport,
                    "ZKBattleship: Game state error"
                );
            } else {
                revert("ZKBattleship: Invalid sender");
            }
            gameEnded(gameId, msg.sender);
        }
    }

    function recover(
        bytes32 _hash,
        bytes calldata _signature
    ) internal view returns (address recovered) {
        // #TODO
        return address(0);
    }

    function surrender(
        bytes32 gameId,
        bytes calldata sessionKeySignature
    ) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState > NextTurnState.Join &&
                game.nextTurnState < NextTurnState.Completed,
            "ZKBattleship: Game state error"
        );
        bytes32 _hash = keccak256(abi.encodePacked(gameId, "I surrender"));
        address recovered = recover(_hash, sessionKeySignature);
        if (recovered == game.creatorSessionKey) {
            gameEnded(gameId, game.joiner);
            return;
        }
        if (recovered == game.joinerSessionKey) {
            gameEnded(gameId, game.creator);
            return;
        }

        revert("ZKBattleship: Invalid session key signature");
    }

    function submitGameStatus(
        bytes32 gameId,
        GameStatus[] calldata gameStatus
    ) external override {
        require(gameStatus.length > 0);
        Game storage game = games[gameId];
        NextTurnState nextTurnState = game.nextTurnState;
        bool senderIsCreator;
        if (msg.sender == game.creator) {
            senderIsCreator = true;
        } else if (msg.sender == game.joiner) {
            senderIsCreator = false;
        } else {
            revert("ZKBattleship: Invalid sender");
        }
        bytes32 prevGameStatusHash = game.previousGameStatusHash;
        bytes32 gameStatusHash = game.currentGameStatusHash;
        uint8 fireAtPosition = game.fireAtPosition;
        for (uint256 i; i < gameStatus.length; i++) {
            GameStatus calldata item = gameStatus[i];
            if (item.gameStatusType == GameStatusType.Shot) {
                fireAtPosition = item.value;
                require(fireAtPosition < 64);
                if (nextTurnState == NextTurnState.CreatorFire) {
                    if(senderIsCreator){

                    }else{

                    }
                    nextTurnState = NextTurnState.JoinerReport;
                } else if (nextTurnState == NextTurnState.JoinerFire) {
                    if(senderIsCreator){

                    }else{
                        
                    }
                    nextTurnState = NextTurnState.CreatorReport;
                } else {
                    revert("ZKBattleship: Game state error");
                }
            } else {
                require(item.value < 3);
                ShotStatus shotStatus = ShotStatus(item.value);
                if (nextTurnState == NextTurnState.CreatorReport) {
                    if(senderIsCreator){

                    }else{
                        
                    }
                    nextTurnState = NextTurnState.CreatorFire;
                } else if (nextTurnState == NextTurnState.JoinerReport) {
                    if(senderIsCreator){

                    }else{
                        
                    }
                    nextTurnState = NextTurnState.JoinerFire;
                } else {
                    revert("ZKBattleship: Game state error");
                }
                if(i==(gameStatus.length-1)){
                    // Check for winner: 6 total hits are required to win.

                }
            }
        }
        game.fireAtPosition = fireAtPosition;
        game.previousGameStatusHash = prevGameStatusHash;
        game.currentGameStatusHash = gameStatusHash;
        game.nextTurnState = nextTurnState;
        game.lastActiveTimestamp = uint64(block.timestamp);
    }

    function reportCheating(
        bytes32 gameId,
        GameStatus calldata gameStatus
    ) external {
        require(
            gameStatus.gameStatusType == GameStatusType.Shot,
            "ZKBattleship: Invalid report"
        );
        Game storage game = games[gameId];
        address opponentSessionKey;
        if (msg.sender == game.creator) {
            opponentSessionKey = game.joinerSessionKey;
            require(
                game.nextTurnState == NextTurnState.CreatorReport,
                "ZKBattleship: Game state error"
            );
        } else if (msg.sender == game.joiner) {
            opponentSessionKey = game.creatorSessionKey;
            require(
                game.nextTurnState == NextTurnState.JoinerReport,
                "ZKBattleship: Game state error"
            );
        } else {
            revert("ZKBattleship: Invalid sender");
        }

        require(
            gameStatus.value != game.fireAtPosition,
            "ZKBattleship: Invalid report"
        );
        bytes32 _hash = keccak256(
            abi.encodePacked(game.previousGameStatusHash, game.fireAtPosition)
        );
        address recovered = recover(_hash, gameStatus.sessionKeySignature);
        require(recovered == opponentSessionKey);

        gameEnded(gameId, msg.sender);
    }

    /**
     * @notice Counts the number of set bits (1s) in a uint64.
     * @dev Implements a parallel bit counting algorithm (popcount).
     *      See: https://www.chessprogramming.org/Population_Count
     * @param gameBoard The uint64 value to count bits in.
     * @return The number of set bits.
     */
    function hitedObjectCount(uint64 gameBoard) internal pure returns (uint8) {
        gameBoard = gameBoard - ((gameBoard >> 1) & 0x5555555555555555);
        gameBoard =
            (gameBoard & 0x3333333333333333) +
            ((gameBoard >> 2) & 0x3333333333333333);
        gameBoard = (gameBoard + (gameBoard >> 4)) & 0x0f0f0f0f0f0f0f0f;
        uint256 y = uint256(gameBoard) * 0x0101010101010101;
        return uint8(y >> 56);
    }

    function reportShotResult(
        bytes32 gameId,
        ShotResult memory shotResult,
        bytes calldata proof
    ) external override {
        Game storage game = games[gameId];
        bytes32 boardCommitment;
        uint64 gameBoard;
        if (game.nextTurnState == NextTurnState.CreatorReport) {
            require(msg.sender == game.creator, "ZKBattleship: Invalid sender");
            game.nextTurnState = NextTurnState.CreatorFire; // Attacker's turn to fire again
            gameBoard = game.creatorGameBoard;
            boardCommitment = game.creatorBoardCommitment;
        } else if (game.nextTurnState == NextTurnState.JoinerReport) {
            require(msg.sender == game.joiner, "ZKBattleship: Invalid sender");
            game.nextTurnState = NextTurnState.JoinerFire; // Attacker's turn to fire again
            gameBoard = game.joinerGameBoard;
            boardCommitment = game.joinerBoardCommitment;
        } else {
            revert("ZKBattleship: Game state error");
        }
        game.lastActiveTimestamp = uint64(block.timestamp);
        require(
            zkProofVerify(
                boardCommitment,
                gameBoard,
                game.fireAtPosition,
                shotResult,
                proof
            ),
            "ZKBattleship: Invalid ZK proof"
        );

        // If the shot was a hit or sunk a ship, update the game board
        if (
            shotResult.shotStatus == ShotStatus.Hit ||
            shotResult.shotStatus == ShotStatus.Sunk
        ) {
            uint64 newGameBoard = gameBoard |
                (uint64(1) << uint64(36 - 1 - game.fireAtPosition));

            // Check for winner: 6 total hits are required to win.
            if (hitedObjectCount(newGameBoard) >= 6) {
                address winner;
                if (game.nextTurnState == NextTurnState.JoinerFire) {
                    // Joiner was reporting, creator shot
                    winner = game.creator;
                } else {
                    // Creator was reporting, joiner shot
                    winner = game.joiner;
                }
                gameEnded(gameId, winner);
            } else {
                // Update the defender's board with the new hit
                if (game.nextTurnState == NextTurnState.JoinerFire) {
                    // Joiner was reporting
                    game.joinerGameBoard = newGameBoard;
                } else {
                    // Creator was reporting
                    game.creatorGameBoard = newGameBoard;
                }
                bytes32 gameStatusHash = game.currentGameStatusHash;
                // #TODO

                game.previousGameStatusHash = game.currentGameStatusHash;
                game.currentGameStatusHash = gameStatusHash;
            }
        }

        emit ShotResultReported(
            gameId,
            msg.sender,
            game.fireAtPosition,
            shotResult
        );
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
    function zkProofVerify(
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
}

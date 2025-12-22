// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {IZKBattleship, UserBalance, Game, NextTurnState} from "./IZKBattleship.sol";
import {GameLinkedList} from "./GameLinkedList.sol";
import {IVerifier} from "./Verifier.sol";

contract ZKBattleship is IZKBattleship {
    using GameLinkedList for mapping(uint256 => uint256);

    uint8 public immutable SAFE_ONCHAIN_TIME;
    uint8 public immutable PLAYER_DECISION_TIME;
    uint8 public immutable ZK_PROOF_TIME;
    IVerifier public immutable VERIFIER;

    uint256 private nextGameId = 10;

    mapping(address => UserBalance) private balances;
    mapping(uint256 => Game) private games;
    mapping(uint256 => uint256) private waitingGames;

    constructor(
        IVerifier verifier,
        uint8 safe_onchain_time,
        uint8 player_decision_time,
        uint8 zk_proof_time
    ) {
        VERIFIER = verifier;
        SAFE_ONCHAIN_TIME = safe_onchain_time;
        PLAYER_DECISION_TIME = player_decision_time;
        ZK_PROOF_TIME = zk_proof_time;
    }

    function listWaitingGames(
        uint256 from,
        uint256 limit
    ) external view override returns (uint256[] memory) {
        return waitingGames.list(from, limit);
    }

    function getGameData(
        uint256 gameId
    ) external view override returns (Game memory) {
        return games[gameId];
    }

    function _getNextGameId() internal returns (uint256) {
        return nextGameId++;
    }

    function _getCurrentGameId() internal view returns (uint256) {
        return nextGameId;
    }

    function _deposit(uint256 amount, address user) internal {
        balances[user].totalBalance += amount;
    }

    receive() external payable {
        _deposit(msg.value, msg.sender);
    }

    /**
     * @notice Deposit ETH into the caller's account held by the contract.
     * @dev The caller should send ETH with the transaction (msg.value).
     */
    function deposit() external payable override {
        _deposit(msg.value, msg.sender);
    }

    /**
     * @notice Withdraw unlocked ETH from the caller's account and transfer it to `recipient`.
     * @dev Implementations must ensure that only available (unlocked) funds can be withdrawn
     *      and should protect against reentrancy and other common risks.
     * @param amount The amount of ETH (in wei) to withdraw.
     * @param recipient The address that will receive the withdrawn ETH.
     */
    function withdraw(uint256 amount, address recipient) external override {
        UserBalance storage userBalance = balances[msg.sender];
        require(
            userBalance.totalBalance - userBalance.lockedBalance >= amount,
            "Insufficient unlocked balance"
        );

        userBalance.totalBalance -= amount;

        if (recipient == address(0)) {
            recipient = msg.sender;
        }

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    /**
     * @notice Retrieve balance information for `user`.
     * @param user The address whose balance is being queried.
     * @return UserBalance A struct containing `totalBalance` and `lockedBalance` for the user.
     */
    function getUserBalance(
        address user
    ) external view override returns (UserBalance memory) {
        return balances[user];
    }

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
    ) external payable override {
        if (msg.value > 0) {
            _deposit(msg.value, msg.sender);
        }
        require(
            balances[msg.sender].totalBalance -
                balances[msg.sender].lockedBalance >=
                stake,
            "Insufficient unlocked balance for stake"
        );
        balances[msg.sender].lockedBalance += stake;

        uint256 gameId = _getNextGameId();

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

        emit GameCreated(msg.sender, gameId, stake);
    }

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
    ) external payable override {
        if (msg.value > 0) {
            _deposit(msg.value, msg.sender);
        }

        Game storage game = games[gameId];
        require(
            game.nextTurnState == NextTurnState.Join,
            "Game is not available to join"
        );
        require(
            balances[msg.sender].totalBalance -
                balances[msg.sender].lockedBalance >=
                game.stake,
            "Insufficient unlocked balance for stake"
        );
        balances[msg.sender].lockedBalance += game.stake;
        waitingGames.remove(gameId);

        game.joiner = msg.sender;
        game.joinerRandomnessSalt = randomnessSalt;
        game.joinerBoardCommitment = boardCommitment;
        game.lastActiveTimestamp = uint64(block.timestamp);
        game.nextTurnState = NextTurnState.RevealRandomness;

        emit GameJoined(msg.sender, gameId);
    }

    /**
     * @notice Reveal the preimage (salt) for a previously submitted randomness commitment.
     * @dev Revealing the randomness allows the contract and the opponent to verify the
     *      original commitment and resolve any randomness-dependent game mechanics.
     * @param gameId The identifier of the game for which randomness is revealed.
     * @param randomnessSalt The secret salt whose hash was previously committed.
     */
    function revealRandomness(
        uint256 gameId,
        bytes32 randomnessSalt
    ) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState == NextTurnState.RevealRandomness,
            "Game state invalid"
        );
        require(
            msg.sender == game.creator,
            "Only the creator can reveal randomness"
        );
        require(
            game.creatorRandomnessCommitment ==
                keccak256(abi.encode(randomnessSalt)),
            "Invalid randomness salt"
        );
        bytes32 combinedRandomness = keccak256(
            abi.encode(randomnessSalt, game.joinerRandomnessSalt)
        );
        bool creatorFirst = uint256(combinedRandomness) % 2 == 1;
        if (creatorFirst) {
            // the creator goes first
            game.nextTurnState = NextTurnState.CreatorFire;
        } else {
            game.nextTurnState = NextTurnState.JoinerFire;
        }
        game.lastActiveTimestamp = uint64(block.timestamp);

        emit RandomnessRevealed(
            gameId,
            creatorFirst ? game.creator : game.joiner
        );
    }

    /**
     * @notice Fire a shot at the specified position in `gameId`.
     * @dev `firePosition` encodes the target cell; the current game state must permit the
     *      caller to act. This call typically emits `ShotFired` and advances the turn.
     * @param gameId The identifier of the game where the shot is fired.
     * @param firePosition The encoded board cell index being targeted.
     */
    function shoot(uint256 gameId, uint8 firePosition) external override {
        require(firePosition < 6 * 6, "Invalid fire position");
        Game storage game = games[gameId];
        uint64 gameBoard;
        if (game.nextTurnState == NextTurnState.JoinerFire) {
            require(
                msg.sender == game.joiner,
                "It's the joiner's turn to shoot"
            );
            gameBoard = game.creatorGameBoard;
            game.nextTurnState = NextTurnState.CreatorReport;
        } else if (game.nextTurnState == NextTurnState.CreatorFire) {
            require(
                msg.sender == game.creator,
                "It's the creator's turn to shoot"
            );
            gameBoard = game.joinerGameBoard;
            game.nextTurnState = NextTurnState.JoinerReport;
        } else {
            revert("Game state invalid");
        }
        game.lastActiveTimestamp = uint64(block.timestamp);
        require(
            (gameBoard >> firePosition) & 1 == 0,
            "Position already shot at"
        );
        game.fireAtPosition = firePosition;
        emit ShotFired(gameId, msg.sender, firePosition);
    }

    function zkProofVerify(
        bytes32 boardCommitment,
        uint64 gameBoard,
        uint8 firePosition,
        ShotResult shotResult,
        bytes calldata proof
    ) internal returns (bool) {
        bytes32[] memory publicInputs = new bytes32[](2);
        publicInputs[0] = boardCommitment;
        publicInputs[1] = bytes32(
            (uint256(gameBoard) << 12) +
                (uint256(firePosition) << 4) +
                uint256(shotResult)
        );
        return VERIFIER.verify(proof, publicInputs);
    }

    function hitedObjectCount(uint64 gameBoard) internal pure returns (uint8) {
        // https://www.chessprogramming.org/Population_Count
        gameBoard = gameBoard - ((gameBoard >> 1) & 0x5555555555555555);
        gameBoard =
            (gameBoard & 0x3333333333333333) +
            ((gameBoard >> 2) & 0x3333333333333333);
        gameBoard = (gameBoard + (gameBoard >> 4)) & 0x0f0f0f0f0f0f0f0f;
        uint256 y = uint256(gameBoard) * 0x0101010101010101;
        return uint8(y >> 56);
    }

    /**
     * @notice Report the result of a shot together with a verification proof (e.g., ZK proof).
     * @dev The `proof` bytes are verified on-chain to ensure the reported result matches the
     *      defender's committed board without revealing sensitive board details.
     * @param gameId The identifier of the relevant game.
     * @param shotResult The reported outcome (Miss/Hit/Sunk).
     * @param proof Serialized proof data used to validate the correctness of `shotResult`
     */
    function reportShotResult(
        uint256 gameId,
        ShotResult shotResult,
        bytes calldata proof
    ) external override {
        Game storage game = games[gameId];
        uint64 gameBoard;
        if (game.nextTurnState == NextTurnState.JoinerReport) {
            require(msg.sender == game.joiner, "It's the joiner's turn");
            game.nextTurnState = NextTurnState.JoinerFire;
            gameBoard = game.joinerGameBoard;
        } else if (game.nextTurnState == NextTurnState.CreatorReport) {
            require(msg.sender == game.creator, "It's the creator's turn");
            game.nextTurnState = NextTurnState.CreatorFire;
            gameBoard = game.creatorGameBoard;
        } else {
            revert("Game state invalid");
        }
        game.lastActiveTimestamp = uint64(block.timestamp);
        require(
            zkProofVerify(
                msg.sender == game.joiner
                    ? game.joinerBoardCommitment
                    : game.creatorBoardCommitment,
                gameBoard,
                game.fireAtPosition,
                shotResult,
                proof
            ),
            "Invalid ZK proof for shot result"
        );
        // update gameBoard
        if (shotResult == ShotResult.Hit || shotResult == ShotResult.Sunk) {
            // check if user wins the game (6 hits needed to win)
            if (hitedObjectCount(gameBoard) >= 5) {
                // user wins
                if (game.nextTurnState == NextTurnState.JoinerFire) {
                    balances[game.creator].lockedBalance -= game.stake;
                    balances[game.joiner].lockedBalance -= game.stake;
                    balances[game.creator].totalBalance += game.stake;
                    balances[game.joiner].totalBalance -= game.stake;
                    gameEnded(gameId, game.creator);
                } else if (game.nextTurnState == NextTurnState.CreatorFire) {
                    balances[game.joiner].lockedBalance -= game.stake;
                    balances[game.creator].lockedBalance -= game.stake;
                    balances[game.joiner].totalBalance += game.stake;
                    balances[game.creator].totalBalance -= game.stake;
                    gameEnded(gameId, game.joiner);
                }
                game.nextTurnState = NextTurnState.Completed;
            } else {
                gameBoard |= uint64(1) << ((6 * 6) - 1 - game.fireAtPosition);
                if (game.nextTurnState == NextTurnState.JoinerFire) {
                    game.joinerGameBoard = gameBoard;
                } else {
                    game.creatorGameBoard = gameBoard;
                }
            }
        }
    }

    /**
     * @notice Quit or forfeit an in-progress or not-yet-started game.
     * @dev The exact behavior (refunds, penalties, state transitions) is implementation-defined
     *      and handled by the concrete contract.
     * @param gameId The identifier of the game to quit.
     */
    function quitGame(uint256 gameId) external override {
        Game storage game = games[gameId];
        require(
            game.nextTurnState > NextTurnState.Blank &&
                game.nextTurnState < NextTurnState.Completed,
            "Game already completed"
        );
        require(
            msg.sender == game.creator || msg.sender == game.joiner,
            "Not a player in this game"
        );
        /*
            We assume the game runs on a high-performance chain (with less than 1s from transaction submission to on-chain confirmation), 
            and that users use wallets supporting “SessionKey”. This means that, apart from proof generation and player decision-making, 
            no additional time is required—the wallet will directly send transactions at the request of the game frontend.
            Therefore, the timeout for each phase is defined as follows:
             • [Safe on-chain time = 3s]
             • RevealRandomness — safe on-chain time
             • CreatorFire — player decision time + safe on-chain time
             • JoinerFire — player decision time + safe on-chain time
             • CreatorReport — zk proof generation time + safe on-chain time
             • JoinerReport — zk proof generation time + safe on-chain time
         */

        if (game.nextTurnState == NextTurnState.Join) {
            // only creator exists
            balances[game.creator].lockedBalance -= game.stake;
            gameEnded(gameId, address(0));
        } else {
            if (game.nextTurnState == NextTurnState.RevealRandomness) {
                require(msg.sender == game.joiner, "Only joiner can quit now");
                require(
                    block.timestamp >
                        game.lastActiveTimestamp + SAFE_ONCHAIN_TIME,
                    "Cannot quit during RevealRandomness phase yet"
                );
            } else if (game.nextTurnState == NextTurnState.CreatorFire) {
                require(msg.sender == game.joiner, "Only joiner can quit now");
                require(
                    block.timestamp >
                        game.lastActiveTimestamp +
                            PLAYER_DECISION_TIME +
                            SAFE_ONCHAIN_TIME,
                    "Cannot quit during CreatorFire phase yet"
                );
            } else if (game.nextTurnState == NextTurnState.JoinerFire) {
                require(
                    msg.sender == game.creator,
                    "Only creator can quit now"
                );
                require(
                    block.timestamp >
                        game.lastActiveTimestamp +
                            PLAYER_DECISION_TIME +
                            SAFE_ONCHAIN_TIME,
                    "Cannot quit during JoinerFire phase yet"
                );
            } else if (game.nextTurnState == NextTurnState.CreatorReport) {
                require(msg.sender == game.joiner, "Only joiner can quit now");
                require(
                    block.timestamp >
                        game.lastActiveTimestamp +
                            ZK_PROOF_TIME +
                            SAFE_ONCHAIN_TIME,
                    "Cannot quit during CreatorReport phase yet"
                );
            } else if (game.nextTurnState == NextTurnState.JoinerReport) {
                require(
                    msg.sender == game.creator,
                    "Only creator can quit now"
                );
                require(
                    block.timestamp >=
                        game.lastActiveTimestamp +
                            ZK_PROOF_TIME +
                            SAFE_ONCHAIN_TIME,
                    "Cannot quit during JoinerReport phase yet"
                );
            } else {
                revert("Invalid game state for quitting");
            }
            balances[game.creator].lockedBalance -= game.stake;
            balances[game.joiner].lockedBalance -= game.stake;
            balances[msg.sender].totalBalance += game.stake;
            balances[msg.sender == game.creator ? game.joiner : game.creator]
                .totalBalance -= game.stake;
            gameEnded(gameId, msg.sender);
        }

        game.nextTurnState = NextTurnState.Completed;
    }

    function gameEnded(uint256 gameId, address winner) internal {
        Game storage game = games[gameId];
        game.creatorRandomnessCommitment = bytes32(0);
        game.joinerRandomnessSalt = bytes32(0);
        game.creatorBoardCommitment = bytes32(0);
        game.joinerBoardCommitment = bytes32(0);
        game.lastActiveTimestamp = 0;
        game.creatorGameBoard = 0;
        game.joinerGameBoard = 0;
        game.fireAtPosition = 0;

        emit GameEnded(gameId, winner);
    }

    function sendMessage(
        address recipient,
        string calldata message
    ) external override {
        emit ChatMessage(msg.sender, recipient, message);
    }
}

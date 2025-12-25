// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ZKBattleship} from "../src/ZKBattleship.sol";
import {IVerifier} from "../src/IVerifier.sol";

contract TestVerifier is IVerifier {
    function verify(
        bytes calldata _proof,
        bytes32[] calldata _publicInputs
    ) external override returns (bool) {
        return true;
    }
}

contract ZKBattleshipTest is Test {
    ZKBattleship public battleship;
    TestVerifier public testVerifier;

    uint8 safeOnchainTime = 3;
    uint8 playerDecisionTime = 10;
    uint8 zkProofTime = 2;

    address creator;
    address joiner;

    function setUp() public {
        battleship = new ZKBattleship(
            testVerifier,
            safeOnchainTime,
            playerDecisionTime,
            zkProofTime
        );
        creator = makeAddr("creator");
        joiner = makeAddr("joiner");
        vm.deal(creator, 100 ether);
        vm.deal(joiner, 100 ether);
    }

    function test_game() public {
        uint256 stake = 1 ether;
        uint256 gameId = 0;
        // create game
        vm.startPrank(creator);
        /*
         function createGame(
            bytes32 randomnessCommitment,
            bytes32 boardCommitment,
            uint256 stake
        ) external payable;
         */
        bytes32 creatorRandomnessSalt = bytes32(uint(1));
        bytes32 creatorRandomnessCommitment = keccak256(
            abi.encode(creatorRandomnessSalt)
        );
        bytes32 creatorBoardCommitment = bytes32(uint(1));
        battleship.createGame{value: stake}(
            creatorRandomnessCommitment,
            creatorBoardCommitment,
            stake
        );
        uint256 SENTINEL_UINT256 = 1;
        uint256[] memory gameIds = battleship.listWaitingGames(
            SENTINEL_UINT256,
            1
        );
        require(gameIds.length == 1 && gameIds[0] > 0);
        gameId = gameIds[0];
        vm.stopPrank();

        // join game
        vm.startPrank(joiner);

        /*
        function joinGame(
            uint256 gameId,
            bytes32 randomnessSalt,
            bytes32 boardCommitment
        ) external payable;
         */
        bytes32 joinerRandomnessSalt = bytes32(uint(2));

        bytes32 joinerBoardCommitment = bytes32(uint(1));
        battleship.joinGame{value: 1 ether}(
            gameId,
            joinerRandomnessSalt,
            joinerBoardCommitment
        );

        vm.stopPrank();
    }
}

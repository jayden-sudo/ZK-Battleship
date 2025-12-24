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

    function setUp() public {
        battleship = new ZKBattleship(
            testVerifier,
            safeOnchainTime,
            playerDecisionTime,
            zkProofTime
        );
    }

    function test_1() public {
        assertTrue(battleship.getUserGameId(address(this)) == 0);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/ZKBattleship.sol";

contract ZKBattleshipDeployer is Script {
    uint256 privateKey;
    address verifier;
    uint8 safeOnchainTime;
    uint8 playerDecisionTime;
    uint8 zkProofTime;

    constructor() {
        privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        verifier = vm.envAddress("VERIFIER");
        safeOnchainTime = uint8(uint256(vm.envInt("SAFEONCHAINTIME")));
        playerDecisionTime = uint8(uint256(vm.envInt("PLAYERDECISIONTIME")));
        zkProofTime = uint8(uint256(vm.envInt("ZKPROOFTIME")));
    }

    function run() public {
        vm.startBroadcast(privateKey);
        address addr = address(
            new ZKBattleship{salt: bytes32(0)}(
                IVerifier(verifier),
                safeOnchainTime,
                playerDecisionTime,
                zkProofTime
            )
        );
        vm.stopBroadcast();
        console.log("##Deployed", "ZKBattleship", addr);
    }
}

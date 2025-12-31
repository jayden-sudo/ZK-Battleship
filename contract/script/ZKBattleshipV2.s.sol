// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/ZKBattleshipV2.sol";

contract ZKBattleshipV2Deployer is Script {
    uint256 privateKey;
    address verifier;
    uint8 roundTimeLimit;
    uint8 revealRandomnessLimit;

    constructor() {
        privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        verifier = vm.envAddress("VERIFIER");
        roundTimeLimit = uint8(uint256(vm.envInt("ROUNDTIMELIMIT")));
        revealRandomnessLimit = uint8(
            uint256(vm.envInt("REVEALRANDOMNESSLIMIT"))
        );
    }

    function run() public {
        vm.startBroadcast(privateKey);
        address addr = address(
            new ZKBattleshipV2{salt: bytes32(0)}(
                IVerifier(verifier),
                roundTimeLimit,
                revealRandomnessLimit
            )
        );
        vm.stopBroadcast();
        console.log("##Deployed", "ZKBattleshipV2", addr);
    }
}

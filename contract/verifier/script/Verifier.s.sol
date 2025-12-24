// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Verifier.sol";

contract VerifierDeployer is Script {
    uint256 privateKey;

    constructor() {
        privateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
    }

    function run() public {
        vm.startBroadcast(privateKey);
        address addr = address(new HonkVerifier{salt: bytes32(0)}());
        vm.stopBroadcast();
        console.log("##Deployed", "ZKBattleship", addr);
    }
}

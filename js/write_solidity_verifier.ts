import { UltraHonkBackend } from '@aztec/bb.js';
import { readFileSync, writeFileSync } from "fs";
import path from "path";
import { exit } from 'process';

async function main() {
    const circuitPath = path.join(__dirname, '../target/process_shot.json')
    const circuitJson = JSON.parse(readFileSync(circuitPath, 'utf8'));
    const bytecode = circuitJson.bytecode;
    const backend = new UltraHonkBackend(bytecode);
    const vk = await backend.getVerificationKey({ keccak: true });
    const source = await backend.getSolidityVerifier(vk);
    writeFileSync(path.join(__dirname, '../contract/verifier/src/Verifier.sol'), source, {
        encoding: 'utf8'
    });
    exit(0);
}

main();
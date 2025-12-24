import shell from 'shelljs';
import fs from 'fs';

async function main() {
    if (!shell.which('nargo')) {
        shell.echo('this script requires nargo');
        shell.exit(1);
    }
    if (!shell.which('bb')) {
        shell.echo('this script requires bb');
        shell.exit(1);
    }

    /*
        circuitPath ./target/process_shot.json
        vkeyPath ./target/vk 
    */
    const circuitPath = './target/process_shot.json';
    const vkeyPath = './target/vk';
    const witnessPath = './target/process_shot.gz';
    const proverTomlPath = './circuit/bin/process_shot/Prover.toml';
    const outputPath = './target';
    const proofPath = "./target/proof";
    const publicInputsPath = "./target/public_inputs";
    if (!fs.existsSync(circuitPath) || !fs.existsSync(vkeyPath)) {
        shell.exec('npm run build:circuit && npm run write_vk');
    }
    if (fs.existsSync(witnessPath)) {
        fs.unlinkSync(witnessPath);
    }
    // grenerate witness
    shell.exec(`nargo execute`);

    // generate proof
    shell.exec(`bb prove --scheme ultra_honk -b ${circuitPath} -k ${vkeyPath} -w ${witnessPath} -o ./target --oracle_hash keccak --verify`);
    if (!fs.existsSync(proofPath)) {
        throw new Error("Proof file was not created")
    }
    const proofHex = fs.readFileSync(proofPath).toString("hex");
    const _publicInputs = fs.readFileSync(publicInputsPath).toString("hex");
    const publicInputs = _publicInputs.match(/.{1,64}/g)?.map((x) => `0x${x}`) ?? [];
    let publicInputsStr = `bytes32[] memory publicInputs = new bytes32[](${publicInputs.length});`;
    for (let i = 0; i < publicInputs.length; i++) {
        publicInputsStr += `\npublicInputs[${i}] = ${publicInputs[i]};`;
    }

    debugger;


}

main();
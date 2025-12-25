import { ethers } from "ethers";
import shell from 'shelljs';
import { Player } from './player';
import path from "node:path";
import { readFileSync } from "node:fs";

async function main() {
    const bins = ['npm', 'curl', 'nargo', 'bb', 'anvil', 'cast', 'pkill'];
    for (const bin of bins) {
        if (!shell.which(bin)) {
            shell.echo('this script requires ' + bin);
            shell.exit(1);
        }
    }

    shell.exec("pkill -f anvil");
    shell.exec("anvil --block-time 0.1 --port 8545 &", { async: true, silent: true });
    shell.exec("npm run build:circuit && npm run build:contract");
    const http_rpc = 'http://127.0.0.1:8545';
    for (let i = 0; i < 10; i++) {
        await sleep(300);
        const re = shell.exec(`curl ${http_rpc} -X POST -H "Content-Type: application/json" --data '{"method":"eth_blockNumber","params":[],"id":1,"jsonrpc":"2.0"}'`);
        if (re.stdout.startsWith('{"jsonrpc":"2.0"')) {
            break;
        }
    }

    const rpc = new ethers.JsonRpcProvider(http_rpc);

    const privateKeys = [
        '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
        '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
        '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
        '0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6',
        '0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a',
        '0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba',
        '0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e',
        '0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356',
        '0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97',
        '0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6'
    ];

    let ZKBattleshipAddress;
    {
        let forgescriptout = shell.exec(
            `cd ./contract/verifier/ && forge script ./script/Verifier.s.sol --rpc-url ${http_rpc} --broadcast`,
            {
                env: {
                    ...process.env,
                    DEPLOYER_PRIVATE_KEY: privateKeys[0],
                },
            }
        ).stdout;
        let index = forgescriptout.indexOf('##Deployed ');
        if (index < 0) {
            throw new Error('deploy verifier failed!');
        }
        // get contract address
        const verifierAddress = forgescriptout.substring(index).split('\n')[0].split(' ')[2].trim();


        const safeOnchainTime = 1;
        const playerDecisionTime = 1;
        const zkProofTime = 1;
        const _ENV = {
            DEPLOYER_PRIVATE_KEY: privateKeys[0],
            VERIFIER: verifierAddress,
            SAFEONCHAINTIME: '' + safeOnchainTime,
            PLAYERDECISIONTIME: '' + playerDecisionTime,
            ZKPROOFTIME: '' + zkProofTime
        }
        console.log(`DEPLOYER_PRIVATE_KEY=${privateKeys[0]} VERIFIER=${verifierAddress} SAFEONCHAINTIME=${safeOnchainTime} PLAYERDECISIONTIME=${playerDecisionTime} ZKPROOFTIME=${zkProofTime}`);
        forgescriptout = shell.exec(
            `forge script ./contract/script/ZKBattleship.s.sol:ZKBattleshipDeployer --rpc-url ${http_rpc} --broadcast -vvvv`,
            {
                env: {
                    ...process.env,
                    ..._ENV
                },
            }
        ).stdout;
        index = forgescriptout.indexOf('##Deployed ');
        if (index < 0) {
            throw new Error('deploy ZKBattleship failed!');
        }
        // get contract address
        ZKBattleshipAddress = forgescriptout.substring(index).split('\n')[0].split(' ')[2].trim();
    }

    const ZKBattleshipABI = JSON.stringify(JSON.parse(readFileSync(path.join(__dirname, '../contract/out/ZKBattleship.sol/ZKBattleship.json'), 'utf8')).abi);


    const player1 = new Player(http_rpc, privateKeys[1], ZKBattleshipAddress, ZKBattleshipABI, path.join(__dirname, '../target/process_shot.json'), 'player1');
    const player2 = new Player(http_rpc, privateKeys[2], ZKBattleshipAddress, ZKBattleshipABI, path.join(__dirname, '../target/process_shot.json'), 'player2');

    player1.run(false);
    await player2.run(true);
}

function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

main();
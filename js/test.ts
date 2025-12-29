import { ProofData, UltraHonkBackend, BarretenbergSync, Barretenberg, Fr, deflattenFields, reconstructHonkProof, splitHonkProof } from '@aztec/bb.js';
import { InputMap, Noir } from '@noir-lang/noir_js';
import { readFileSync } from "fs";
import path from 'path';

function getVK(vk: Uint8Array) {
    const result = [];
    for (let i = 0; i < vk.length; i += 16) {
        const chunk = vk.slice(i, i + 16);
        result.push('0x' + Buffer.from(chunk).toString("hex"));
    }
    if (result.length !== 118) {
        throw new Error('vk error');
    }
    return result;
}


function uint8ArrayToHex(buffer: Uint8Array): string {
    const hex: string[] = [];

    buffer.forEach(function (i) {
        let h = i.toString(16);
        if (h.length % 2) {
            h = '0' + h;
        }
        hex.push(h);
    });

    return '0x' + hex.join('');
}

function reconstructProofWithPublicInputs(proofData: ProofData) {
    // Flatten publicInputs
    const publicInputsConcatenated = flattenUint8Arrays(proofData.publicInputs);
    // Concatenate publicInputs and proof
    const proofWithPublicInputs = Uint8Array.from([...publicInputsConcatenated, ...proofData.proof]);
    return proofWithPublicInputs;
}
function flattenUint8Arrays(arrays: any[]) {
    const totalLength = arrays.reduce((acc, val) => acc + val.length, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;
    for (const arr of arrays) {
        result.set(arr, offset);
        offset += arr.length;
    }
    return result;
}

function flattenFieldsAsArray(fields: string[]): Uint8Array {
    const flattenedPublicInputs = fields.map(hexToUint8Array);
    return flattenUint8Arrays(flattenedPublicInputs);
}

function hexToUint8Array(hex: string): Uint8Array {
    const sanitised_hex = BigInt(hex).toString(16).padStart(64, '0');

    const len = sanitised_hex.length / 2;
    const u8 = new Uint8Array(len);

    let i = 0;
    let j = 0;
    while (i < len) {
        u8[i] = parseInt(sanitised_hex.slice(j, j + 2), 16);
        i += 1;
        j += 2;
    }

    return u8;
}


const serializedBufferSize = 4;
const fieldByteSize = 32;
const publicInputOffset = 3;
const publicInputsOffsetBytes = publicInputOffset * fieldByteSize;

function reconstructProofWithPublicInputsHonk(proofData: ProofData): Uint8Array {
    // Flatten publicInputs
    const publicInputsConcatenated = flattenFieldsAsArray(proofData.publicInputs);

    const proofStart = proofData.proof.slice(0, publicInputsOffsetBytes + serializedBufferSize);
    const proofEnd = proofData.proof.slice(publicInputsOffsetBytes + serializedBufferSize);

    // Concatenate publicInputs and proof
    const proofWithPublicInputs = Uint8Array.from([...proofStart, ...publicInputsConcatenated, ...proofEnd]);

    return proofWithPublicInputs;
}

async function main() {

    let proofData_inner: ProofData;
    let vkHash: string;
    let vkAsFields: string[];

    const bb = await BarretenbergSync.initSingleton();
    const bb1 = await Barretenberg.new();
    let vk: Uint8Array;
    {
        // vk
        const circuitPath = path.join(__dirname, '../target/process_shot.json');
        const circuitJson = JSON.parse(readFileSync(circuitPath, 'utf8'));
        const bytecode = circuitJson.bytecode;
        const Backend = new UltraHonkBackend(bytecode, { threads: 1 }, { recursive: true });
        const noir = new Noir(circuitJson);
        vk = await Backend.getVerificationKey({ keccak: true });



        let cruiser = [0, 6, 12];
        let destroyer = [14, 15];
        let submarine = 21;
        let salt = 7;
        let expected_hash = '0x04df209ed0aad0968c3aa95d735485f04ed83fb29173287fda6716461da5815d';

        let pub_input =
            (BigInt(2) /* STATUS_SUNK */) +
            (BigInt(21)/*打击位置 */ << BigInt(4)) +
            (BigInt(0)/* be_bits_to_u64(grid_snapshot_bits */ << BigInt(12));
        pub_input = pub_input + ((BigInt(21) << BigInt(48)) + (BigInt(21) << BigInt(56)));
        // if i == 12 {
        //     pub_input = pub_input + ((0 << 48) + (12 << 56))
        // } else if i == 15 {
        //     pub_input = pub_input + ((14 << 48) + (15 << 56))
        // } else if i == 21 {
        //     pub_input = pub_input + ((21 << 48) + (21 << 56))
        // }

        const inputMap: InputMap = {
            cruiser: cruiser,
            destroyer: destroyer,
            submarine: submarine,
            salt: salt,
            expected_hash: expected_hash,
            pub_input: pub_input.toString()
        };
        const { witness } = await noir.execute(inputMap);
        proofData_inner = await Backend.generateProof(witness, {
            keccak: true
        });
        const proofBytes = '0x' + Buffer.from(proofData_inner.proof).toString('hex');

        const verify = await Backend.verifyProof(proofData_inner, {
            keccak: true
        })
        if (verify === false) {
            throw new Error('verifyProof failed');
        }

        // Generate the key hash using the backend method
        const artifacts = await Backend.generateRecursiveProofArtifacts(proofData_inner.proof, proofData_inner.publicInputs.length);
        vkHash = artifacts.vkHash;
        // proofAsFields = artifacts.proofAsFields;
        vkAsFields = artifacts.vkAsFields;

    }
    const circuitPath = path.join(__dirname, '../target/recursive_process_shot.json');
    const circuitJson = JSON.parse(readFileSync(circuitPath, 'utf8'));
    const bytecode = circuitJson.bytecode;
    const Backend = new UltraHonkBackend(bytecode, { threads: 4 }, { recursive: false });
    const noir = new Noir(circuitJson);

    // const inputMap: InputMap = {
    //     data: [
    //         {
    //             _is_some: true,
    //             _value: 2
    //         },
    //         {
    //             _is_some: true,
    //             _value: 8
    //         }, {
    //             _is_some: false,
    //             _value: 3
    //         }
    //     ],
    //     re: 10
    // };

    /*
    verification_key: UltraHonkVerificationKey,
    proof: UltraHonkZKProof,
    key_hash: Field,
    public_inputs: pub [Field; 2],
    */


    const _vkAsFields: string[] = [];
    for (let i = 0; i < vk.length; i += 32) {
        const chunk = vk.slice(i, i + 32);
        _vkAsFields.push(uint8ArrayToHex(chunk));
    }

    const _proofAsFields: string[] = [];
    for (let i = 0; i < proofData_inner.proof.length; i += 32) {
        const chunk = proofData_inner.proof.slice(i, i + 32);
        _proofAsFields.push(uint8ArrayToHex(chunk));
    }

    let vkFr = bb.acirVkAsFieldsUltraHonk(vk);
    let vkFields = vkFr.map(x => x.toString());

    let proofFr = bb.acirProofAsFieldsUltraHonk(proofData_inner.proof);
    let proofFields = proofFr.map(x => x.toString());

    // const proof = reconstructProofWithPublicInputs(proofData);
    // const proofAsFields = (await this.api.acirProofAsFieldsUltraHonk(proof)).slice(numOfPublicInputs);


    const proof1 = reconstructProofWithPublicInputs(proofData_inner);
    const proofAsFields1 = (await bb.acirProofAsFieldsUltraHonk(proof1)).slice(proofData_inner.publicInputs.length);


    const vkAsFields222 = await bb1.vkAsFields({ verificationKey: vk });
    const vkAsFieldsReal = vkAsFields222.fields.map((field) => {
        let fieldBigint = BigInt(0);
        for (const byte of field) {
            fieldBigint <<= BigInt(8);
            fieldBigint += BigInt(byte);
        }
        return fieldBigint.toString();
    });

    let a1 = reconstructHonkProof(flattenFieldsAsArray(proofData_inner.publicInputs), proofData_inner.proof);
    const inputMap: InputMap = {
        verification_key: vkAsFields,
        proof: a1.map(p => p.toString()),
        key_hash: vkHash,
        public_inputs: proofData_inner.publicInputs,
    };
    const { witness } = await noir.execute(inputMap);
    const proofData: ProofData = await Backend.generateProof(witness, {
        keccak: true,
    });
    const proofBytes = '0x' + Buffer.from(proofData.proof).toString('hex');

    const verify = await Backend.verifyProof(proofData, {
        keccak: true
    })
    if (verify === false) {
        throw new Error('verifyProof failed');
    }


}
main();

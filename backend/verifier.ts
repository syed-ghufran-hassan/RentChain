import express from 'express';
import { Noir } from '@noir-lang/noir_js';
import { UltraPlonkBackend } from '@aztec/bb.js';
import { ethers } from 'ethers';
import fs from 'fs';

const app = express();
app.use(express.json());

// Load compiled circuits
const circuits: Record<string, any> = {
  good_history: JSON.parse(fs.readFileSync('./circuits/good_rental_history/target/good_rental_history.json', 'utf8')),
  income:       JSON.parse(fs.readFileSync('./circuits/income_sufficiency/target/income_sufficiency.json', 'utf8')),
  no_disputes:  JSON.parse(fs.readFileSync('./circuits/no_disputes/target/no_disputes.json', 'utf8')),
  kyc:          JSON.parse(fs.readFileSync('./circuits/kYC_proof/target/kYC_proof.json', 'utf8')),
};

const signer = new ethers.Wallet(process.env.VERIFIER_PRIVATE_KEY!);

app.post('/verify', async (req, res) => {
  const { proofType, proof, publicInputs } = req.body;

  try {
    const circuit = circuits[proofType];
    if (!circuit) return res.status(400).json({ error: 'Unknown proof type' });

    const backend = new UltraPlonkBackend(circuit.bytecode);
    const noir = new Noir(circuit, backend);

    // Verify off-chain
    const isValid = await noir.verifyProof({ proof, publicInputs });
    if (!isValid) return res.status(400).json({ error: 'Invalid proof' });

    // Extract tenant address from public inputs (position depends on circuit)
    const tenantAddress = `0x${publicInputs[0].slice(26)}`;
    const publicInputsHash = ethers.keccak256(
      ethers.solidityPacked(['bytes32[]'], [publicInputs])
    );

    // Sign attestation
    const expiry = Math.floor(Date.now() / 1000) + 3600;
    const message = ethers.solidityPackedKeccak256(
      ['address', 'bytes32', 'bytes32', 'uint256'],
      [tenantAddress, ethers.encodeBytes32String(proofType), publicInputsHash, expiry]
    );
    const signature = await signer.signMessage(ethers.getBytes(message));

    res.json({ tenantAddress, proofType, publicInputsHash, expiry, signature });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Verification failed' });
  }
});

app.listen(3001, () => console.log('Verifier running on port 3001'));
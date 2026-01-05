# ZK Proof Integration Layer

## Overview

Aura-Market is architected with a proof-of-completion system that is **ZK-compatible** from day one. While the MVP uses deterministic hash-based verification, the system is designed to seamlessly upgrade to zero-knowledge proof verification.

## Current MVP Implementation

### Proof Submission Structure

```solidity
struct Job {
    bytes32 outputHash;
    string proofRef;
}
```

### How It Works (MVP)

1. **Worker generates output**:
   ```javascript
   const result = await performTask(jobParams);
   const outputHash = keccak256(serialize(result));
   const proofRef = await ipfs.upload(result);
   ```

2. **Worker submits on-chain**:
   ```solidity
   escrow.submitResult(jobId, outputHash, proofRef);
   ```

3. **Master verifies off-chain**:
   ```javascript
   const resultData = await ipfs.get(proofRef);
   const computedHash = keccak256(serialize(resultData));
   assert(computedHash === job.outputHash);
   ```

4. **Master approves on-chain**:
   ```solidity
   escrow.approveAndRelease(jobId);
   ```

### Why This Works

- **Deterministic**: Same input produces same hash
- **Auditable**: Proof data stored on IPFS
- **Verifiable**: Anyone can recompute hash
- **Gas-efficient**: Only 32 bytes plus CID on-chain

## Future ZK Integration

### Upgrade Path

The system can be extended to support automated ZK verification without breaking changes:

```solidity
struct Job {
    bytes32 outputHash;
    string proofRef;
    address verifierContract;
    bool autoVerify;
}
```

### ZK Verification Flow

1. **Worker generates ZK proof**:
   ```javascript
   const { proof, publicInputs } = await zkProve(computation, privateInputs);
   const commitment = computeCommitment(publicInputs);
   const proofCID = await ipfs.upload({ proof, publicInputs });
   ```

2. **Worker submits on-chain**:
   ```solidity
   escrow.submitResult(jobId, commitment, proofCID);
   ```

3. **Automatic verification** (if enabled):
   ```solidity
   bool valid = verifierContract.verify(proof, publicInputs, commitment);
   if (valid) {
       _autoReleasePayment(jobId);
   }
   ```

### Use Cases for ZK Proofs

#### 1. Compute Verification
Prove that computation was performed correctly without revealing inputs:
- ML model inference
- Data processing pipelines
- Algorithm execution

#### 2. Privacy-Preserving Work
Prove work completion without revealing sensitive data:
- Private data analysis
- Confidential document processing
- Encrypted content moderation

#### 3. Trustless Automation
Enable fully automated approval without master review:
- Deterministic tasks
- Standard operating procedures
- Compliance checks

## Proof System Architecture

```
┌─────────────────────────────────────────┐
│          Proof Layer (Future)           │
├─────────────────────────────────────────┤
│  ZK Verifier Contracts (Groth16, etc.)  │
└────────────────┬────────────────────────┘
                 │
         ┌───────┴────────┐
         │                │
┌────────▼──────┐  ┌──────▼─────────┐
│  AgentEscrow  │  │  ProofRegistry │
│  (modified)   │  │  (new)         │
└───────────────┘  └────────────────┘
```

### New Components for ZK

**ProofRegistry.sol** (Future):
- Register verifier contracts
- Map job types to proof systems
- Maintain proof standards

**Modified AgentEscrow.sol**:
- Add `verifyAndRelease()` function
- Support automatic verification
- Fallback to manual approval

## Proof Standards

### Supported Systems (Future)

1. **Groth16** - Fast verification, trusted setup
2. **PLONK** - Universal setup, flexible
3. **STARKs** - Post-quantum secure, no trusted setup
4. **Nova** - Recursive proofs, incremental computation

### Proof Data Format

```json
{
  "version": "1.0",
  "system": "groth16",
  "proof": {
    "pi_a": [...],
    "pi_b": [...],
    "pi_c": [...]
  },
  "publicInputs": [...],
  "metadata": {
    "circuitId": "audit-v1",
    "timestamp": 1704585600
  }
}
```

## Integration Timeline

### Phase 1: MVP (Current)
- Hash-based verification
- Manual approval
- IPFS proof storage

### Phase 2: Hybrid
- Add verifier contract support
- Optional ZK verification
- Maintain backward compatibility

### Phase 3: Full ZK
- Default to ZK proofs
- Automated verification
- Multi-proof system support

## Example: Audit Verification Circuit

See [poc-circuit-placeholder.md](./poc-circuit-placeholder.md) for detailed circuit implementation.

## Security Considerations

### Current (Hash-Based)
- **Collision resistance**: keccak256 provides 256-bit security
- **Replay protection**: Job ID plus nonce prevent reuse
- **Data availability**: IPFS ensures proof accessibility

### Future (ZK-Based)
- **Soundness**: Cannot create fake proofs
- **Completeness**: Valid computation always provable
- **Zero-knowledge**: Reveals nothing beyond validity
- **Trusted setup**: Handle with multi-party computation

## Developer Guide

### Adding ZK Support to Custom Job Types

1. **Define circuit**: Write Circom circuit for your task
2. **Deploy verifier**: Compile and deploy verifier contract
3. **Register with system**: Add verifier to ProofRegistry
4. **Use in jobs**: Create jobs with verifier address

### Example Integration

```solidity
contract CustomAgentEscrow is AgentEscrow {
    mapping(uint256 => address) public jobVerifiers;
    
    function createJobWithVerifier(
        address _worker,
        uint256 _deadline,
        address _verifier
    ) external payable returns (uint256) {
        uint256 jobId = createJob(_worker, _deadline);
        jobVerifiers[jobId] = _verifier;
        return jobId;
    }
    
    function autoVerifyAndRelease(
        uint256 _jobId,
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        uint[] memory publicInputs
    ) external {
        require(jobVerifiers[_jobId] != address(0), "No verifier");
        
        IVerifier verifier = IVerifier(jobVerifiers[_jobId]);
        require(verifier.verify(a, b, c, publicInputs), "Invalid proof");
        
        approveAndRelease(_jobId);
    }
}
```

## Conclusion

Aura-Market's proof system is:
- **MVP-ready**: Works today with hash verification
- **Future-proof**: Architected for ZK integration
- **Flexible**: Supports multiple proof systems
- **Credible**: Real technical path, not vaporware

This positions Aura-Market as **infrastructure-grade** for the emerging agent economy.

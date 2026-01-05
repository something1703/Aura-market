# Aura-Market Contract Development

## Building

```bash
forge build
```

## Testing

Run all tests:
```bash
forge test -vv
```

Run specific test file:
```bash
forge test --match-path test/Integration.t.sol -vvv
```

Run with gas reporting:
```bash
forge test --gas-report
```

Run coverage:
```bash
forge coverage
```

## Deployment

### Local Anvil

1. Start local node:
```bash
anvil
```

2. Deploy contracts:
```bash
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Testnet (Sepolia)

1. Set environment variables in `.env`:
```bash
cp .env.example .env
```

2. Deploy:
```bash
source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

3. Setup demo:
```bash
forge script script/SetupDemo.s.sol --rpc-url $RPC_URL --broadcast
```

### Mainnet

```bash
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify --slow
```

## Interacting with Contracts

### Using Cast

Register an agent:
```bash
cast send $REGISTRY_ADDRESS "registerAgent(string,string,string)" \
  "ipfs://metadata" \
  "audit,security" \
  "https://agent.api" \
  --value 0.1ether \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

Create a job:
```bash
cast send $ESCROW_ADDRESS "createJob(address,uint256)" \
  $WORKER_ADDRESS \
  $(($(date +%s) + 604800)) \
  --value 1ether \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

## Gas Optimization

Check gas usage:
```bash
forge test --gas-report
```

Snapshot gas usage:
```bash
forge snapshot
```

## Development Workflow

1. Write tests first
2. Implement contracts
3. Run tests: `forge test`
4. Check gas: `forge test --gas-report`
5. Deploy to testnet
6. Security audit
7. Deploy to mainnet

## Foundry

Foundry is a blazing fast, portable and modular toolkit for Ethereum development.

More documentation: https://book.getfoundry.sh/

### Build

```bash
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

# Robinhood Chain — addresses

## Mainnet (chainId 4663, RPC https://rpc.mainnet.chain.robinhood.com)
Uniswap v4 (source: developers.uniswap.org/contracts/v4/deployments — verified on-chain, PoolManager has bytecode):
- **PoolManager**      `0x8366a39cc670b4001a1121b8f6a443a643e40951`
- PositionManager      `0x58daec3116aae6d93017baaea7749052e8a04fa7`
- StateView            `0xf3334192d15450cdd385c8b70e03f9a6bd9e673b`
- Quoter               `0x8dc178efb8111bb0973dd9d722ebeff267c98f94`
- Universal Router     `0x8876789976decbfcbbbe364623c63652db8c0904`

Assets (source: docs.robinhood.com/chain/contracts):
- **WETH**             `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73`
- USDG                 `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168`

## Testnet (chainId 46630, RPC https://rpc.testnet.chain.robinhood.com) — CONFIRMED ✅
Uniswap v4 is at the SAME addresses as mainnet (verified on-chain: PoolManager bytecode is
byte-identical on both nets — 48020 bytes; the testnet explorer shows the PositionManager as
"Uniswap v4 Positions NFT"):
- **PoolManager**  `0x8366a39CC670B4001A1121B8F6A443A643e40951`
- PositionManager  `0x58daec3116aae6D93017bAAea7749052E8a04fA7`
- **WETH**         `0x7943e237c7F95DA44E0301572D358911207852Fa`  (verified: symbol() == "WETH")
- Faucet:   https://faucets.chain.link/robinhood-testnet
- Explorer: https://explorer.testnet.chain.robinhood.com

## .env for deploy
```
POOL_MANAGER=0x8366a39cc670b4001a1121b8f6a443a643e40951
WETH=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
# TREASURY=0x...      # defaults to deployer
# PLATFORM_FEE_BPS=1000
```

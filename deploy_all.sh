#!/usr/bin/env bash
set -euo pipefail

# ===== USER CONFIG =====
# REQUIRED:
#   PRIVATE_KEY=0x...
#   GRANTEE=0x...  (receiver / agent)
#
# OPTIONAL:
#   RPC_URL (default Base Sepolia public RPC)
#
: "${PRIVATE_KEY:?Set PRIVATE_KEY=0x...}"
: "${GRANTEE:?Set GRANTEE=0x...}"

RPC_URL="${RPC_URL:-https://sepolia.base.org}"

echo "RPC_URL=$RPC_URL"
DEPLOYER=$(cast wallet address "$PRIVATE_KEY")
echo "DEPLOYER=$DEPLOYER"
echo "GRANTEE=$GRANTEE"

# Ensure deps
if [ ! -d "lib/openzeppelin-contracts" ]; then
  echo "Installing OpenZeppelin..."
  forge install OpenZeppelin/openzeppelin-contracts --no-commit
fi

forge build

echo "Deploying MockUSD..."
TOKEN=$(forge create --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" src/MockUSD.sol:MockUSD | awk '/Deployed to:/ {print $3}')
echo "TOKEN=$TOKEN"

echo "Deploying RecurConsentRegistry (controller = DEPLOYER)..."
REGISTRY=$(forge create --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" src/RecurConsentRegistry.sol:RecurConsentRegistry --constructor-args "$DEPLOYER" | awk '/Deployed to:/ {print $3}')
echo "REGISTRY=$REGISTRY"

echo "Deploying RecurPullSafeV2..."
PULLSAFE=$(forge create --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" src/RecurPullSafeV2.sol:RecurPullSafeV2 --constructor-args "$REGISTRY" | awk '/Deployed to:/ {print $3}')
echo "PULLSAFE=$PULLSAFE"

echo "Trusting PullSafe in Registry..."
cast send "$REGISTRY" "setTrustedExecutor(address,bool)" "$PULLSAFE" true --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

GRANTOR="$DEPLOYER"

# Mint + approvals
MINT_AMT="1000000000000000000000" # 1000 mUSD (18 decimals)
echo "Minting $MINT_AMT mUSD to GRANTOR..."
cast send "$TOKEN" "mint(address,uint256)" "$GRANTOR" "$MINT_AMT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

echo "Approving PullSafe for grantor..."
cast send "$TOKEN" "approve(address,uint256)" "$PULLSAFE" "$MINT_AMT" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

# Time window (30 min starting 60s from now)
VALID_AFTER=$(($(date +%s) + 60))
VALID_BEFORE=$(($VALID_AFTER + 1800))
MAX_PER_PULL="100000000000000000000" # 100 mUSD
NONCE="0x$(openssl rand -hex 32)"

echo "VALID_AFTER=$VALID_AFTER"
echo "VALID_BEFORE=$VALID_BEFORE"
echo "MAX_PER_PULL=$MAX_PER_PULL"
echo "NONCE=$NONCE"

AUTH_HASH=$(cast keccak "$(cast abi-encode "(address,address,address,uint256,uint256,uint256,bytes32)" "$GRANTOR" "$GRANTEE" "$TOKEN" "$MAX_PER_PULL" "$VALID_AFTER" "$VALID_BEFORE" "$NONCE")")
echo "AUTH_HASH=$AUTH_HASH"

echo "Emitting observe() (optional)..."
cast send "$REGISTRY" "observe(bytes32,address,address,address)" "$AUTH_HASH" "$GRANTOR" "$GRANTEE" "$TOKEN" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null || true

# Push baseline lockbox
TOTAL_LOCK="500000000000000000000" # 500 mUSD locked
echo "Deploying PushLockbox (dead-weight push baseline)..."
PUSH_LOCKBOX=$(forge create --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" src/PushLockbox.sol:PushLockbox --constructor-args "$TOKEN" "$GRANTOR" "$GRANTEE" "$VALID_AFTER" "$VALID_BEFORE" "$TOTAL_LOCK" | awk '/Deployed to:/ {print $3}')
echo "PUSH_LOCKBOX=$PUSH_LOCKBOX"

echo "Approving Lockbox + depositing (locks capital)..."
cast send "$TOKEN" "approve(address,uint256)" "$PUSH_LOCKBOX" "$TOTAL_LOCK" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null
cast send "$PUSH_LOCKBOX" "deposit()" --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

echo ""
echo "=== COPY THESE INTO web/.env.local ==="
cat <<EOF
RPC_URL=$RPC_URL

TOKEN=$TOKEN
GRANTOR=$GRANTOR
GRANTEE=$GRANTEE

REGISTRY=$REGISTRY
PULLSAFE=$PULLSAFE
AUTH_HASH=$AUTH_HASH

MAX_PER_PULL=$MAX_PER_PULL
VALID_AFTER=$VALID_AFTER
VALID_BEFORE=$VALID_BEFORE

PUSH_LOCKBOX=$PUSH_LOCKBOX
EOF

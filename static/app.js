// ===== CONFIG (EDIT THESE AFTER DEPLOY) =====

const RPC = "https://sepolia.base.org";

const TOKEN    = "0xTOKEN";
const REGISTRY = "0xREGISTRY";
const PULLSAFE = "0xPULLSAFE";
const GRANTOR  = "0xGRANTOR";
const AUTH_HASH = "0xAUTH_HASH";

const MAX_PER_PULL = BigInt("100000000000000000000");
const VALID_AFTER  = 0;
const VALID_BEFORE = 9999999999;

// ==========================================

const BASESCAN = "https://sepolia.basescan.org";

async function rpc(method, params = []) {
  const res = await fetch(RPC, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params })
  });
  return (await res.json()).result;
}

async function call(to, data) {
  return rpc("eth_call", [{ to, data }, "latest"]);
}

const U = (h) => BigInt(h);

async function main() {
  document.getElementById("authLink").href =
    `${BASESCAN}/tx/${AUTH_HASH}`;
  document.getElementById("authLink").textContent = AUTH_HASH;

  document.getElementById("balLink").href =
    `${BASESCAN}/token/${TOKEN}?a=${GRANTOR}`;

  document.getElementById("allowLink").href =
    `${BASESCAN}/token/${TOKEN}?a=${PULLSAFE}`;

  let status = "LIVE";
  const now = Math.floor(Date.now() / 1000);

  if (now < VALID_AFTER) status = "TOO SOON";
  if (now > VALID_BEFORE) status = "EXPIRED";

  const revoked = U(await call(
    REGISTRY,
    "0x3b4da69f" + AUTH_HASH.slice(2).padStart(64, "0")
  ));
  if (revoked !== 0n) status = "REVOKED";

  const balance = U(await call(
    TOKEN,
    "0x70a08231" + GRANTOR.slice(2).padStart(64, "0")
  ));

  const allowance = U(await call(
    TOKEN,
    "0xdd62ed3e" +
    GRANTOR.slice(2).padStart(64, "0") +
    PULLSAFE.slice(2).padStart(64, "0")
  ));

  let reachable = 0n;
  if (status === "LIVE") {
    reachable = [balance, allowance, MAX_PER_PULL]
      .reduce((a, b) => a < b ? a : b);
  }

  document.getElementById("pullValue").textContent =
    reachable > 0n ? reachable.toString() : "0";

  document.getElementById("status").textContent = status;
  document.getElementById("updated").textContent =
    new Date().toISOString();
}

main();

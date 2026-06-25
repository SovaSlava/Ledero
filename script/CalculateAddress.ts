import { getCreate2Address, pad, toHex } from "viem";
import { randomBytes } from "crypto";

function findVanitySalt() {
  const deployerAddress = "0x4e59b44847b379578588920cA78FbF26c0B4956C";
  const initCodeHash = process.argv[2] as `0x${string}`;
  const prefixHex = parseInt(process.argv[3], 10);
  const targetPattern = `0x0000${prefixHex}`;

  let currentSalt = BigInt(`0x${randomBytes(32).toString("hex")}`);

  while (true) {
    const saltHex = pad(toHex(currentSalt), { size: 32 });
    const predictedAddress = getCreate2Address({
      from: deployerAddress,
      salt: saltHex,
      bytecodeHash: initCodeHash,
    });

    if (predictedAddress.toLowerCase().startsWith(targetPattern)) {
      process.stdout.write(saltHex);
      return;
    }
    currentSalt++;
  }
}

findVanitySalt();

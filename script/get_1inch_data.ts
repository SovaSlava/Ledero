import axios from "axios";

interface TransactionPayload {
  to: string;
  data: string;
  value: string;
}

interface SwapResponse {
  tx: TransactionPayload;
  dstAmount: string;
}

interface TestResult {
  tx?: TransactionPayload;
  toAmount?: string;
  error?: string;
}

async function get1inchSwapData(
  fromToken: string,
  toToken: string,
  amount: string,
  fromAddress: string,
): Promise<string> {
  const chainId = 1;
  const url = `https://api.1inch.dev/swap/v6.0/${chainId}/swap`;

  const params = {
    src: fromToken,
    dst: toToken,
    amount: amount,
    from: fromAddress,
    slippage: "1",
    disableEstimate: "true",
    allowPartialFill: "false",
    protocols:
      "UNISWAP_V3,SUSHISWAP_V3,PANCAKESWAP_V3,CURVE,CURVE_V2,BALANCER_V2,AAVE_V3",
  };

  try {
    const response = await axios.get<SwapResponse>(url, {
      params: params,
      headers: {
        Authorization: `Bearer ${process.env.INCH_API_KEY}`,
      },
    });

    const jsonData = response.data;

    const result: TestResult = {
      tx: {
        to: jsonData.tx.to,
        data: jsonData.tx.data,
        value: jsonData.tx.value || "0",
      },
      toAmount: jsonData.dstAmount || "0",
    };

    return JSON.stringify(result);
  } catch (error: any) {
    const errorMessage = error.response?.data
      ? JSON.stringify(error.response.data)
      : error.message;
    return JSON.stringify({ error: errorMessage });
  }
}

async function main() {
  if (!process.env.INCH_API_KEY) {
    console.log(JSON.stringify({ error: "INCH_API_KEY is missing." }));
    process.exit(1);
  }

  if (process.argv.length < 6) {
    console.log(
      JSON.stringify({
        error:
          "Usage: npx ts-node get_1inch_data.ts <fromToken> <toToken> <amount> <fromAddress>",
      }),
    );
    process.exit(1);
  }

  const [, , fromToken, toToken, amount, fromAddress] = process.argv;

  const result = await get1inchSwapData(
    fromToken,
    toToken,
    amount,
    fromAddress,
  );
  console.error("1inch - ", result);
  process.stdout.write(result);
}

main();

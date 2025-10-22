import { TransactionReceipt } from "ethers";

export async function runTx(prm: Promise<any>): Promise<TransactionReceipt> {
	const tx = await prm
	if (!tx.wait) return tx
	return await tx.wait()
}

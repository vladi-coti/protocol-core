export async function runTx(prm: Promise<any>): Promise<any> {
	const tx = await prm
	if (!tx.wait) return tx
	return await tx.wait()
}

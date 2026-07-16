import {ethers, run} from "hardhat"
import {sleep} from "@nomicfoundation/hardhat-verify/internal/utilities"
import {FacetNames, LibraryNames} from "../tasks/deploy/constants"

async function main() {
	const libraries: Record<string, string> = {}
	for (const libraryName of LibraryNames) {
		const Library = await ethers.getContractFactory(libraryName)
		const library = await Library.deploy()

		await library.waitForDeployment()

		const addr = await library.getAddress()
		libraries[libraryName] = addr
		console.log(`${libraryName} deployed: ${addr}`)

		await sleep(10000)
	}

	for (const facetName of FacetNames) {
		const facetLibraries =
			facetName == "AccountFacet"
				? { LibAccountEncryption: libraries.LibAccountEncryption }
				: facetName == "ForceCloseFacet" || facetName == "SettleAndForceCloseFacet"
				? { ForceActionsFacetImpl: libraries.ForceActionsFacetImpl }
				: facetName == "PartyBPositionActionsFacet" || facetName == "PartyBGroupActionsFacet"
					? { PartyBPositionActionsFacetImpl: libraries.PartyBPositionActionsFacetImpl }
					: undefined
		const Facet = facetLibraries
			? await (ethers as any).getContractFactory(facetName, { libraries: facetLibraries })
			: await ethers.getContractFactory(facetName)
		const facet = await Facet.deploy()

		await facet.waitForDeployment()

		let addr = await facet.getAddress()
		console.log(`${facetName} deployed: ${addr}`)

		await sleep(10000)

		try {
			await run("verify:verify", {
				address: addr,
				constructorArguments: [],
			})
		} catch (e) {
			console.log("Failed to verify contract", e)
		}
	}
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch(error => {
	console.error(error)
	process.exitCode = 1
})

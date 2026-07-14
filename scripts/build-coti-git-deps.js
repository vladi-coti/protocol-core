#!/usr/bin/env node
/**
 * Git installs of @coti-io/coti-ethers / coti-sdk-typescript ship source and run
 * `prepare: tsc`. That prepare often fails in this repo because a stub
 * `@types/minimatch` is pulled into the type roots, so dist is missing or stale.
 * Rebuild both packages with an empty `types` list so Wallet.encryptUint256 can
 * resolve buildUint256InputText from the exact extended-uint-support SDK.
 */
const { spawnSync } = require("child_process")
const fs = require("fs")
const path = require("path")

const root = path.resolve(__dirname, "..")
const tsc = path.join(root, "node_modules/typescript/bin/tsc")
const ethersRoot = path.join(root, "node_modules/@coti-io/coti-ethers")
const nestedSdk = path.join(ethersRoot, "node_modules/@coti-io/coti-sdk-typescript")

function hasExport(pkgRoot, exportName) {
	const indexJs = path.join(pkgRoot, "dist/index.js")
	if (!fs.existsSync(indexJs)) return false
	try {
		const mod = require(indexJs)
		return typeof mod[exportName] === "function"
	} catch {
		return false
	}
}

function buildPackage(pkgRoot, label) {
	if (!fs.existsSync(path.join(pkgRoot, "tsconfig.json"))) {
		console.warn(`[build-coti-git-deps] skip ${label}: no tsconfig`)
		return
	}
	const buildTsconfig = path.join(pkgRoot, "tsconfig.symmio-build.json")
	fs.writeFileSync(
		buildTsconfig,
		JSON.stringify(
			{
				extends: "./tsconfig.json",
				compilerOptions: {
					skipLibCheck: true,
					types: [],
				},
			},
			null,
			2,
		),
	)
	console.log(`[build-coti-git-deps] building ${label}...`)
	const result = spawnSync(tsc, ["-p", buildTsconfig], {
		cwd: pkgRoot,
		stdio: "inherit",
		env: process.env,
	})
	try {
		fs.unlinkSync(buildTsconfig)
	} catch {
		/* ignore */
	}
	if (result.status !== 0) {
		throw new Error(`[build-coti-git-deps] ${label} build failed with code ${result.status}`)
	}
}

if (!fs.existsSync(tsc)) {
	console.warn("[build-coti-git-deps] typescript not installed; skip")
	process.exit(0)
}

if (!fs.existsSync(ethersRoot)) {
	console.warn("[build-coti-git-deps] @coti-io/coti-ethers missing; skip")
	process.exit(0)
}

if (fs.existsSync(nestedSdk) && !hasExport(nestedSdk, "buildUint256InputText")) {
	buildPackage(nestedSdk, "@coti-io/coti-sdk-typescript (nested)")
} else if (fs.existsSync(nestedSdk)) {
	console.log("[build-coti-git-deps] nested SDK already exports buildUint256InputText")
}

if (!fs.existsSync(path.join(ethersRoot, "dist/wallet/Wallet.js"))) {
	buildPackage(ethersRoot, "@coti-io/coti-ethers")
} else {
	// Still rebuild ethers if nested SDK was just fixed (stale compile is fine to skip).
	console.log("[build-coti-git-deps] @coti-io/coti-ethers dist present")
}

if (fs.existsSync(nestedSdk) && !hasExport(nestedSdk, "buildUint256InputText")) {
	throw new Error("[build-coti-git-deps] nested SDK still missing buildUint256InputText after build")
}

console.log("[build-coti-git-deps] ok")

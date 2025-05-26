import { HardhatUserConfig } from "hardhat/config"

/**
 * Configuration for private variables testing
 * This file contains test-specific configurations for the COTI.io v2 private variables implementation
 */

export const privateVariablesTestConfig = {
	// Test timeouts (in milliseconds)
	timeouts: {
		unit: 30000, // 30 seconds for unit tests
		integration: 60000, // 60 seconds for integration tests
		gas: 120000, // 2 minutes for gas analysis tests
	},

	// Gas limits for different test scenarios
	gasLimits: {
		enablePrivateMode: 200000,
		privatePositionOpen: 500000,
		batchOperations: 1000000,
	},

	// Test data constants
	testData: {
		defaultQuantity: "100000000000000000000", // 100 tokens (18 decimals)
		defaultPrice: "1000000000000000000", // 1 token (18 decimals)
		maxUint64: "18446744073709551615", // Maximum uint64 value
		testAddresses: [
			"0x1234567890123456789012345678901234567890",
			"0xabcdefabcdefabcdefabcdefabcdefabcdefabcd",
			"0x0000000000000000000000000000000000000000",
		],
	},

	// Expected gas usage ranges (for performance testing)
	expectedGasUsage: {
		enablePrivateMode: {
			min: 50000,
			max: 150000,
		},
		privatePositionOpen: {
			min: 200000,
			max: 400000,
		},
		publicPositionOpen: {
			min: 150000,
			max: 300000,
		},
		batchEnable: {
			perQuote: {
				min: 30000,
				max: 80000,
			},
		},
	},

	// Test scenarios for comprehensive coverage
	testScenarios: {
		quantities: [
			"1000000000000000000", // 1 token
			"50000000000000000000", // 50 tokens
			"100000000000000000000", // 100 tokens
			"1000000000000000000000", // 1000 tokens
		],
		prices: [
			"500000000000000000", // 0.5 token
			"1000000000000000000", // 1 token
			"2000000000000000000", // 2 tokens
			"10000000000000000000", // 10 tokens
		],
		fillRatios: [
			0.25, // 25% fill
			0.5, // 50% fill
			0.75, // 75% fill
			1.0, // 100% fill
		],
	},

	// Error messages for validation
	expectedErrors: {
		unauthorized: "PrivateQuoteFacet: Only quote parties can enable private mode",
		alreadyPrivate: "PrivateQuoteFacet: Quote already in private mode",
		accessDenied: "PrivateQuoteFacet: Only quote parties can access private data",
		invalidAmount: "PartyBFacet: Invalid filledAmount",
		invalidPrice: "PartyBFacet: Opened price isn't valid",
		insufficientBalance: "LibSolvency: Available balance is lower than zero",
		paused: "Pausable: PartyB actions paused",
	},
}

/**
 * Helper function to get test configuration
 */
export function getPrivateVariablesTestConfig() {
	return privateVariablesTestConfig
}

/**
 * Helper function to validate gas usage
 */
export function validateGasUsage(operation: keyof typeof privateVariablesTestConfig.expectedGasUsage, actualGas: number): boolean {
	const expected = privateVariablesTestConfig.expectedGasUsage[operation]

	// Handle the batchEnable case which has a different structure
	if (operation === "batchEnable") {
		const batchExpected = expected as { perQuote: { min: number; max: number } }
		return actualGas >= batchExpected.perQuote.min && actualGas <= batchExpected.perQuote.max
	}

	// Handle other cases
	const standardExpected = expected as { min: number; max: number }
	return actualGas >= standardExpected.min && actualGas <= standardExpected.max
}

/**
 * Helper function to get test scenarios
 */
export function getTestScenarios() {
	return privateVariablesTestConfig.testScenarios
}

/**
 * Helper function to get expected error messages
 */
export function getExpectedErrors() {
	return privateVariablesTestConfig.expectedErrors
}

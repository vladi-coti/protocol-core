# COTI.io v2 Private Variables Integration

This implementation adds optional private variable support to the SYMM protocol using COTI.io v2's encrypted computation capabilities. The system allows sensitive quote data (quantity, closed amounts, and party addresses) to be encrypted while maintaining backward compatibility with existing public variables.

## Overview

The private variables system provides:

-   **Optional Privacy**: Quotes can operate in either public or private mode
-   **Backward Compatibility**: Existing functionality remains unchanged
-   **Selective Encryption**: Only sensitive data is encrypted (quantity, closedAmount, partyA, partyB)
-   **Access Control**: Only quote parties can decrypt their private data

## Architecture

### Core Components

1. **LibPrivateQuote.sol**: Core library for private variable operations
2. **PrivateQuoteStorage.sol**: Storage layout for encrypted variables
3. **PrivateQuoteFacet.sol**: User-facing functions for managing private quotes
4. **PartyBPositionActionsPrivateFacet.sol**: Enhanced position opening with privacy support
5. **MpcCore.sol**: COTI.io v2 MPC operations wrapper

### Storage Structure

```solidity
struct Layout {
    mapping(uint256 => utUint64) privateQuantities;      // Encrypted quantities
    mapping(uint256 => utUint64) privateClosedAmounts;   // Encrypted closed amounts
    mapping(uint256 => utUint64) privatePartyA;          // Encrypted partyA addresses
    mapping(uint256 => utUint64) privatePartyB;          // Encrypted partyB addresses
    mapping(uint256 => bool) isPrivateEnabled;           // Privacy mode flags
    mapping(address => address) userEncryptionAddress;   // User encryption preferences
}
```

## Usage

### 1. Enabling Private Mode

#### For a Single Quote

```solidity
// Enable private mode for a specific quote
privateQuoteFacet.enablePrivateMode(quoteId);
```

#### For Multiple Quotes

```solidity
// Batch enable private mode
uint256[] memory quoteIds = [1, 2, 3, 4];
privateQuoteFacet.batchEnablePrivateMode(quoteIds);
```

### 2. Opening Positions with Privacy

#### Standard Position Opening (Public)

```solidity
partyBPositionActionsFacet.openPosition(
    quoteId,
    filledAmount,
    openedPrice,
    upnlSig
);
```

#### Private Position Opening

```solidity
partyBPositionActionsPrivateFacet.openPositionWithPrivacy(
    quoteId,
    filledAmount,
    openedPrice,
    upnlSig,
    true  // usePrivateMode = true
);
```

### 3. Accessing Private Data

#### Check if Quote is Private

```solidity
bool isPrivate = privateQuoteFacet.isPrivateQuote(quoteId);
```

#### Get Private Values (Only accessible by quote parties)

```solidity
// Get encrypted quantity (decrypted for authorized parties)
uint256 quantity = privateQuoteFacet.getPrivateQuantity(quoteId);

// Get encrypted closed amount
uint256 closedAmount = privateQuoteFacet.getPrivateClosedAmount(quoteId);

// Get encrypted party addresses
address partyA = privateQuoteFacet.getPrivatePartyA(quoteId);
address partyB = privateQuoteFacet.getPrivatePartyB(quoteId);

// Get open amount (quantity - closedAmount)
uint256 openAmount = privateQuoteFacet.getPrivateOpenAmount(quoteId);
```

## Implementation Details

### Encryption Process

1. **Data Conversion**: Values are converted to `gtUint64` (garbled uint64)
2. **Encryption**: Data is encrypted using COTI's MPC operations
3. **Storage**: Encrypted values are stored alongside public fallbacks
4. **Access Control**: Only quote parties can decrypt their data

### Fallback Mechanism

The system maintains backward compatibility through fallback logic:

```solidity
function getPrivateQuantity(uint256 quoteId) internal returns (uint256) {
    if (utUint64.unwrap(layout.privateQuantities[quoteId].ciphertext) == 0) {
        // Fallback to public quantity if private not set
        return QuoteStorage.layout().quotes[quoteId].quantity;
    }
    // Return decrypted private quantity
    return uint256(MpcCore.decrypt(MpcCore.onBoard(layout.privateQuantities[quoteId].ciphertext)));
}
```

### Privacy in Events

When private mode is enabled, events emit placeholder values to prevent data leakage:

```solidity
// For private quotes, emit with encrypted or placeholder values
uint256 emitQuantity = usePrivateMode ? 0 : newQuote.quantity;
emit SendQuote(..., emitQuantity, ...);
```

## Security Considerations

### Access Control

-   Only `partyA` and `partyB` can enable private mode for their quotes
-   Only quote parties can decrypt private data
-   Unauthorized access attempts are rejected with clear error messages

### Data Integrity

-   Private and public data remain synchronized
-   Fallback mechanisms ensure system reliability
-   Encryption/decryption operations are validated

### Gas Optimization

-   Private operations are more expensive than public ones
-   Batch operations available for efficiency
-   Optional privacy allows users to choose based on needs

## Migration Strategy

### For Existing Quotes

1. Quotes remain in public mode by default
2. Users can opt-in to private mode at any time
3. Private mode copies existing public values to encrypted storage
4. No disruption to existing functionality

### For New Quotes

1. Can be created in either public or private mode
2. Private mode can be enabled during position opening
3. Mode selection is per-quote, not global

## Best Practices

### When to Use Private Mode

-   **High-value positions**: Large quantities that need privacy
-   **Sensitive trading**: When position sizes should remain confidential
-   **Institutional trading**: When regulatory requirements demand privacy

### When to Use Public Mode

-   **Small positions**: When gas costs outweigh privacy benefits
-   **Transparent trading**: When openness is preferred
-   **Testing/development**: For easier debugging and monitoring

### Gas Considerations

-   Private operations cost more gas than public ones
-   Consider batch operations for multiple quotes
-   Monitor gas usage and optimize accordingly

## Example Integration

```solidity
contract TradingBot {
    IPrivateQuoteFacet private privateQuoteFacet;
    IPartyBPositionActionsPrivateFacet private privateFacet;

    function openPrivatePosition(
        uint256 quoteId,
        uint256 amount,
        uint256 price,
        PairUpnlAndPriceSig memory sig
    ) external {
        // Enable private mode if not already enabled
        if (!privateQuoteFacet.isPrivateQuote(quoteId)) {
            privateQuoteFacet.enablePrivateMode(quoteId);
        }

        // Open position with privacy
        privateFacet.openPositionWithPrivacy(
            quoteId,
            amount,
            price,
            sig,
            true
        );
    }
}
```

## Deployment Requirements

### Dependencies

1. COTI.io v2 SDK and contracts
2. MPC-enabled blockchain environment
3. Updated diamond proxy configuration

### Configuration

1. Add new facets to diamond proxy
2. Configure access control roles
3. Set up encryption parameters
4. Test private operations thoroughly

## Testing

### Unit Tests

-   Test private variable encryption/decryption
-   Verify access control mechanisms
-   Test fallback to public variables
-   Validate gas usage patterns

### Integration Tests

-   Test position opening with privacy
-   Verify event emission with private data
-   Test batch operations
-   Validate cross-facet interactions

### Security Tests

-   Test unauthorized access attempts
-   Verify data encryption integrity
-   Test edge cases and error conditions
-   Validate privacy preservation in events

## Limitations

### Current Limitations

1. **Address Encryption**: Limited to 64-bit values (addresses truncated)
2. **Gas Costs**: Higher than public operations
3. **Complexity**: Additional complexity in system architecture

### Future Improvements

1. **Full Address Support**: Implement proper address encryption
2. **Gas Optimization**: Optimize MPC operations
3. **Advanced Privacy**: Add more sophisticated privacy features
4. **Batch Operations**: Expand batch operation support

## Support

For questions or issues related to private variables:

1. Check the test files for usage examples
2. Review the library documentation
3. Test in a development environment first
4. Monitor gas usage in production

## Conclusion

The COTI.io v2 private variables integration provides a powerful privacy layer for the SYMM protocol while maintaining full backward compatibility. Users can selectively enable privacy for sensitive positions while keeping the system accessible for all use cases.

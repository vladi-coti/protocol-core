// SPDX-License-Identifier: SYMM-Core-Business-Source-License-1.1
// This contract is licensed under the SYMM Core Business Source License 1.1
// Copyright (c) 2023 Symmetry Labs AG
// For more information, see https://docs.symm.io/legal-disclaimer/license
pragma solidity >=0.8.18;

import "@coti-io/coti-contracts/contracts/utils/mpc/MpcCore.sol";

library SharedEvents {
    enum BalanceChangeType {
        ALLOCATE,
        DEALLOCATE,
        PLATFORM_FEE_IN,
        PLATFORM_FEE_OUT,
        REALIZED_PNL_IN,
        REALIZED_PNL_OUT,
        CVA_IN,
        CVA_OUT,
        LF_IN,
        LF_OUT,
        FUNDING_FEE_IN,
        FUNDING_FEE_OUT
    }

    /// @dev `amount` semantics depend on `_type` (M-25):
    /// - ALLOCATE / DEALLOCATE: post-mutation allocated-balance snapshot ciphertext
    /// - fee / PnL / CVA / LF / funding `*_IN`/`*_OUT`: absolute delta ciphertext (sign via type)
    /// Indexers must not treat every `amount` as a delta. Dedicated Allocate/Deallocate events
    /// already carry the plaintext size when the delta is public.
    event BalanceChangePartyA(address indexed partyA, ctUint256 amount, BalanceChangeType _type);

    /// @dev Same `amount` semantics as BalanceChangePartyA (snapshot for ALLOCATE/DEALLOCATE; else delta).
    event BalanceChangePartyB(address indexed partyB, address indexed partyA, ctUint256 amount, BalanceChangeType _type);

    /// @dev Same `amount` semantics as BalanceChangePartyA (observer ciphertext).
    event ObserverBalanceChangePartyA(address indexed partyA, ctUint256 amount, BalanceChangeType _type);

    /// @dev Same `amount` semantics as BalanceChangePartyB (observer ciphertext).
    event ObserverBalanceChangePartyB(address indexed partyB, address indexed partyA, ctUint256 amount, BalanceChangeType _type);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IPERMIT2} from "../interfaces/IPERMIT2.sol";

library Permit2Logic {
    IPERMIT2 private constant PERMIT2 = IPERMIT2(0x000000000022d473030F116dDeE9F6B43AC78Ba0);

    function transferUsingPermit2(
        uint256 amount,
        uint256 nounce,
        bytes memory signature,
        address token,
        address receiver
    ) internal returns (bool) {
        PERMIT2.permitTransferFrom(
            IPERMIT2.PermitTransferFrom({
                permitted: IPERMIT2.TokenPermissions({token: token, amount: amount}),
                nonce: nounce,
                deadline: block.timestamp + 1 days
            }),
            IPERMIT2.SignatureTransferDetails({to: receiver, requestedAmount: amount}),
            msg.sender,
            signature
        );
        return true;
    }
}

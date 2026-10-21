// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ImdWindowShopper} from "../../src/ImdWindowShopper.sol";

/// @dev Test-only deployment and transfer driver; this is not a launch implementation.
contract LaunchFactory {
    function deploy(bytes32 salt) external returns (ImdWindowShopper) {
        return new ImdWindowShopper{salt: salt}();
    }

    function move(ImdWindowShopper token, address to, uint256 amount) external {
        require(token.transfer(to, amount), "transfer failed");
    }
}

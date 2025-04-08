// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title LinkToken
 * @notice Mock LINK token for local testing
 * @dev This contract extends ERC20 and adds the transferAndCall function required by Chainlink VRF
 */
contract LinkToken is ERC20 {
    constructor() ERC20("LINK", "LINK") {}

    /**
     * @notice Mints LINK tokens to the specified account
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    /**
     * @notice Transfers tokens and calls a function on the recipient
     * @dev Required for funding VRF subscriptions
     * @param to The address to transfer tokens to
     * @param value The amount of tokens to transfer
     * @param data The data to pass to the recipient's onTokenTransfer function
     * @return success Whether the operation was successful
     */
    function transferAndCall(address to, uint256 value, bytes memory data) public returns (bool success) {
        transfer(to, value);
        
        // Check if the recipient is a contract
        if (isContract(to)) {
            contractFallback(to, value, data);
        }
        
        return true;
    }

    /**
     * @notice Calls the onTokenTransfer function on a contract
     * @param to The contract address
     * @param value The amount of tokens transferred
     * @param data The data to pass to the contract
     */
    function contractFallback(address to, uint256 value, bytes memory data) private {
        (bool success, ) = to.call(abi.encodeWithSignature("onTokenTransfer(address,uint256,bytes)", msg.sender, value, data));
        require(success, "LinkToken: Contract call failed");
    }

    /**
     * @notice Checks if an address is a contract
     * @param addr The address to check
     * @return Whether the address is a contract
     */
    function isContract(address addr) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }
}

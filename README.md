
#### Key features for the permit functionality
- protected against cross-chain replay attacks: chain id is verified
- protected against contract collisions - sigs meant for contract A do not work on contract B if they share the same name/version due to separation by chainid
- Ensures replay resistance - refer to cyfrin's blog on eip712 too

- The Oz EIP712 contract/library/package automatically ensure that the signatures are replay resistant to cros-chain replays by ensuring that the chainid during signature/message hash generation is always equal to what was defined during deployment of the protocol. If that changed, then the msg hash is not formed. This is on lines 80 to 86 but specifically line 81 of the _domainSeparatorv4() in the EIP712.sol file. That's what I wanted to implement but Ozx has already. Will test it's working by writing a test for the same.====this is wrong
- Changed/revised my understanding for replay protection - as long as the chainid forms part of the final hash that gets signed, supplying a hash that has a different chainid automatically means a different hash thus sig and hash won't match - this is the protection now.
- i.e., If the chainId changes (e.g., moving from Ethereum to Polygon), the DOMAIN_SEPARATOR changes → the digest changes → the signature becomes invalid.

#### Why No Explicit chainId Check Is Needed
- Implicit Protection: When a user signs a permit, the signature is mathematically bound to the chainId used in the domain separator. If someone tries to replay the same signature on a different chain:

    - The DOMAIN_SEPARATOR on the new chain will have a different chainId.

    - The computed digest will not match the original signed digest.

    - ecrecover(digest, signature) will return address(0) or an incorrect signer, causing the permit to revert.
    - The burnFrom bug is also fixed and no user can circumvent the access control to burn tokens using the Oz burnFrom().
  
# DSCENGINE
- frob in makerDAO is simply deposit/withdraw collateral and mint/burn DSC here
- This contract defines the rules under which vaults/debt positions and balances can be manipulated.
- No debt ceiling in collateral type
- Minimum amount to mint is set - this guarantees that liquidations remain economically viable and efficient. 

# Collateral Types
- struct to hold collateral data parameters
- DSEngine - access controlled
- configure collateral type only doable by Admin.
- Cannot modify configuration is previously set.
- Admin can remove collateral configuration/support but only if there is no debt associated with that collateral. Removing means resetting the collateral config and also removing it from the allowed collateral ids array - some gem but gas intensive on this one too.
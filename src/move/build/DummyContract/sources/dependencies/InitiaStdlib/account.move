module initia_std::account {
    #[test_only]
    use std::vector;
    #[test_only]
    use std::error;
    #[test_only]
    use std::bcs;

    friend initia_std::coin;
    friend initia_std::staking;

    /// The provided authentication had an invalid length
    const EMALFORMED_AUTHENTICATION_KEY: u64 = 1;
    const ECANNOT_CREATE_ADDRESS: u64 = 2;

    native fun create_address(bytes: vector<u8>): address;

    native fun create_signer(addr: address): signer;

    public(friend) fun create_address_for_friend(addr_bytes: vector<u8>): address {
        create_address(addr_bytes)
    }

    public(friend) fun create_signer_for_friend(addr: address): signer {
        create_signer(addr)
    }

    #[test_only]
    /// Create signer for testing
    public fun create_signer_for_test(addr: address): signer { create_signer(addr) }

    #[test]
    public fun test_create_address() {
        let bob = create_address(x"0000000000000000000000000000000000000000000000000000000000000b0b");
        let carol = create_address(x"00000000000000000000000000000000000000000000000000000000000ca501");
        assert!(
            bob == @0x0000000000000000000000000000000000000000000000000000000000000b0b,
            error::invalid_argument(ECANNOT_CREATE_ADDRESS)
        );
        assert!(
            carol == @0x00000000000000000000000000000000000000000000000000000000000ca501,
            error::invalid_argument(ECANNOT_CREATE_ADDRESS)
        );
    }

    #[test(new_address = @0x42)]
    public fun test_create_signer(new_address: address) {
        let _new_account = create_signer(new_address);
        let authentication_key = bcs::to_bytes(&new_address);
        assert!(
            vector::length(&authentication_key) == 32,
            error::invalid_argument(EMALFORMED_AUTHENTICATION_KEY)
        );
    }
}

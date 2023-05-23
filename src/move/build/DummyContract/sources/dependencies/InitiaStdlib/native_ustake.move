/// This module provides the move Coin for native LP.
module initia_std::native_ustake {
     use initia_std::coin;
    use initia_std::string;
    use initia_std::signer;
    use initia_std::error;
    
    /// only 0x1 is allowed to execute functions
    const EUNAUTHORIZED: u64 = 1;
    
    /// initialized check
    const EALREADY_INITIALIZED: u64 = 2;

    struct Coin {}
    struct CapabilityStore has key {
        burn_cap: coin::BurnCapability<Coin>,
        freeze_cap: coin::FreezeCapability<Coin>,
        mint_cap: coin::MintCapability<Coin>,
    }

    fun check_chain_permission(chain: &signer) {
        assert!(signer::address_of(chain) == @initia_std, error::permission_denied(EUNAUTHORIZED));
    }

    entry fun initialize(chain: &signer, name: string::String, symbol: string::String, decimals: u8) {
        check_chain_permission(chain);

        assert!(!exists<CapabilityStore>(signer::address_of(chain)), EALREADY_INITIALIZED);

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<Coin>(chain, name, symbol, decimals);
        move_to(chain, CapabilityStore {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    entry fun burn(chain: &signer, from_addr: &signer, amount: u64) acquires CapabilityStore {
        check_chain_permission(chain);

        let c = coin::withdraw<Coin>(from_addr, amount);
        let caps = borrow_global<CapabilityStore>(signer::address_of(chain));
        
        coin::burn<Coin>(c, &caps.burn_cap);
    }

    entry fun mint(chain: &signer, to_addr: address, amount: u64) acquires CapabilityStore {
        check_chain_permission(chain);

        let caps = borrow_global<CapabilityStore>(signer::address_of(chain));
        let c = coin::mint<Coin>(amount, &caps.mint_cap);
        coin::deposit<Coin>(to_addr, c);
    }
}

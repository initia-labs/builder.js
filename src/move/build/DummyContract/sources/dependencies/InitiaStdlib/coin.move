/// This module provides the foundation for typesafe Coins.
module initia_std::coin {
    use std::string;
    use std::error;
    use std::signer;
    use std::hash;
    use std::event::{Self, EventHandle};
    use std::option;
    use std::vector;

    use initia_std::type_info;
    use initia_std::account::create_signer_for_friend;
    use initia_std::table;

    friend initia_std::staking;
    friend initia_std::dex;

    //
    // Errors.
    //

    /// Only chain can execute.
    const EUNAUTHORIZED: u64 = 1;

    /// Address of account which is used to initialize a coin `CoinType` doesn't match the deployer of module
    const ECOIN_INFO_ADDRESS_MISMATCH: u64 = 2;

    /// `CoinType` is already initialized as a coin
    const ECOIN_INFO_ALREADY_PUBLISHED: u64 = 3;

    /// `CoinType` hasn't been initialized as a coin
    const ECOIN_INFO_NOT_PUBLISHED: u64 = 4;

    /// Account already has `CoinStore` registered for `CoinType`
    const ECOIN_STORE_ALREADY_PUBLISHED: u64 = 5;

    /// Account hasn't registered `CoinStore` for `CoinType`
    const ECOIN_STORE_NOT_PUBLISHED: u64 = 6;

    /// Not enough coins to complete transaction
    const EINSUFFICIENT_BALANCE: u64 = 7;

    /// Cannot destroy non-zero coins
    const EDESTRUCTION_OF_NONZERO_TOKEN: u64 = 8;

    /// Coin amount cannot be zero
    const EZERO_COIN_AMOUNT: u64 = 9;

    /// CoinStore is frozen. Coins cannot be deposited or withdrawn
    const EFROZEN: u64 = 10;

    /// Cannot upgrade the total supply of coins to different implementation.
    const ECOIN_SUPPLY_UPGRADE_NOT_SUPPORTED: u64 = 11;

    /// Name of the coin is too long
    const ECOIN_NAME_TOO_LONG: u64 = 12;

    /// Symbol of the coin is too long
    const ECOIN_SYMBOL_TOO_LONG: u64 = 13;

    /// unauthorized
    const ECOIN_UNAUTHORIZED: u64 = 14;

    /// denom not found
    const EDENOM_NOT_FOUND: u64 = 15;

    //
    // Constants
    //

    // allow long name & symbol to allow ibc denom trace
    const MAX_COIN_NAME_LENGTH: u64 = 128;
    const MAX_COIN_SYMBOL_LENGTH: u64 = 128;

    /// Core data structures

    /// Main structure representing a coin/token in an account's custody.
    struct Coin<phantom CoinType> has store {
        /// Amount of coin this address has.
        value: u64,
    }

    /// A holder of a specific coin types and associated event handles.
    /// These are kept in a single resource to ensure locality of data.
    struct CoinStore<phantom CoinType> has key {
        coin: Coin<CoinType>,
        frozen: bool,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
    }

    /// Escrow coin store for the unregistered accounts
    struct EscrowStore<phantom CoinType> has key {
        coin: Coin<CoinType>,
        amount_table: table::Table<address, u64>,
        deposit_events: EventHandle<EscrowDepositEvent>,
        withdraw_events: EventHandle<EscrowWithdrawEvent>,
    }

    /// Store for module
    struct ModuleStore has key {
        // Denom table for (hash => struct tag) query
        denom_table: table::Table<vector<u8>, string::String>,
        // Escrow table for address => struct_tag => escrow_deposit_amount
        escrow_table: table::Table<address, table::Table<string::String, u64>>,
    }

    /// Maximum possible coin supply.
    const MAX_U128: u128 = 340282366920938463463374607431768211455;

    /// Information about a specific coin type. Stored on the creator of the coin's account.
    struct CoinInfo<phantom CoinType> has key {
        name: string::String,
        /// Symbol of the coin, usually a shorter version of the name.
        /// For example, Singapore Dollar is SGD.
        symbol: string::String,
        /// Number of decimals used to get its user representation.
        /// For example, if `decimals` equals `2`, a balance of `505` coins should
        /// be displayed to a user as `5.05` (`505 / 10 ** 2`).
        decimals: u8,
        supply: u128,
        /// whitelisted coin do not need to specifically execute `register` 
        /// to register CoinStore, it will be created automatically.
        whitelisted: bool,
        mint_events: EventHandle<MintEvent>,
        burn_events: EventHandle<BurnEvent>,
    }

    /// Event emitted when some amount of a coin is deposited into an account.
    struct DepositEvent has drop, store {
        coin_type: string::String,
        amount: u64,
    }

    /// Event emitted when some amount of a coin is withdrawn from an account.
    struct WithdrawEvent has drop, store {
        coin_type: string::String,
        amount: u64,
    }

    /// Event emitted when some amount of a coin is minted.
    struct MintEvent has drop, store {
        coin_type: string::String,
        amount: u64,
    }

    /// Event emitted when some amount of a coin is burned.
    struct BurnEvent has drop, store {
        coin_type: string::String,
        amount: u64,
    }

    /// Event emitted when some amount of a coin is deposited into an account.
    struct EscrowDepositEvent has drop, store {
        coin_type: string::String,
        recipient: address,
        amount: u64,
    }

    /// Event emitted when some amount of a coin is withdrawn from an account.
    struct EscrowWithdrawEvent has drop, store {
        coin_type: string::String,
        recipient: address,
        amount: u64,
    }

    /// Capability required to mint coins.
    struct MintCapability<phantom CoinType> has copy, store {}

    /// Capability required to freeze a coin store.
    struct FreezeCapability<phantom CoinType> has copy, store {}

    /// Capability required to burn coins.
    struct BurnCapability<phantom CoinType> has copy, store {}

    //
    // GENESIS
    //

    /// Check signer is chain
    fun check_chain_permission(chain: &signer) {
        assert!(signer::address_of(chain) == @initia_std, error::permission_denied(EUNAUTHORIZED));
    }

    fun init_module(chain: &signer) {
        move_to(chain, ModuleStore {
            denom_table: table::new<vector<u8>, string::String>(),
            escrow_table: table::new<address, table::Table<string::String, u64>>(),
        });
    }

    //
    // Getter functions
    //

    /// A helper function that returns the address of CoinType.
    fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    #[view]
    /// Returns the balance of `owner` for provided `CoinType`.
    public fun balance<CoinType>(owner: address): u64 acquires CoinStore {
        assert!(
            is_account_registered<CoinType>(owner),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );
        borrow_global<CoinStore<CoinType>>(owner).coin.value
    }

    #[view]
    public fun escrow_balance<CoinType>(owner: address): u64 acquires EscrowStore {
        let escrow_store = borrow_global<EscrowStore<CoinType>>(coin_address<CoinType>());
        if (!table::contains<address, u64>(&escrow_store.amount_table, owner)) {
            return 0
        };

        *table::borrow<address, u64>(&escrow_store.amount_table, owner)
    }

    #[view]
    public fun denom_hash<CoinType>(): vector<u8> {
        let type_name = type_info::type_name<CoinType>();
        hash::sha2_256(*string::bytes(&type_name))
    }

    #[view]
    /// Returns `true` if the type `CoinType` is an initialized coin.
    public fun is_coin_initialized<CoinType>(): bool {
        exists<CoinInfo<CoinType>>(coin_address<CoinType>())
    }

    #[view]
    /// Returns `true` if `account_addr` is registered to receive `CoinType`.
    public fun is_account_registered<CoinType>(account_addr: address): bool {
        exists<CoinStore<CoinType>>(account_addr)
    }

    #[view]
    /// Returns the name of the coin.
    public fun name<CoinType>(): string::String acquires CoinInfo {
        borrow_global<CoinInfo<CoinType>>(coin_address<CoinType>()).name
    }

    #[view]
    /// Returns the symbol of the coin, usually a shorter version of the name.
    public fun symbol<CoinType>(): string::String acquires CoinInfo {
        borrow_global<CoinInfo<CoinType>>(coin_address<CoinType>()).symbol
    }

    #[view]
    /// Returns the number of decimals used to get its user representation.
    /// For example, if `decimals` equals `2`, a balance of `505` coins should
    /// be displayed to a user as `5.05` (`505 / 10 ** 2`).
    public fun decimals<CoinType>(): u8 acquires CoinInfo {
        borrow_global<CoinInfo<CoinType>>(coin_address<CoinType>()).decimals
    }

    #[view]
    /// Returns the amount of coin in existence.
    public fun supply<CoinType>(): u128 acquires CoinInfo {
        borrow_global<CoinInfo<CoinType>>(coin_address<CoinType>()).supply
    }

    #[view]
    /// Return all escrow deposits
    public fun get_escrow(
        addr: address,
        start_after: option::Option<string::String>,
        limit: u8,
    ): vector<EscrowResponse> acquires ModuleStore{
        let limit = (limit as u64);
        let res: vector<EscrowResponse> = vector[];
        let module_store = borrow_global<ModuleStore>(@initia_std);
        if (!table::contains(&module_store.escrow_table, addr)) {
            return res
        };

        let user_table = table::borrow<address, table::Table<string::String, u64>>(
            &module_store.escrow_table,
            addr,
        );

        let iter = table::iter(
            user_table,
            option::none(),
            start_after,
            2,
        );

        while(
            vector::length(&res) < limit &&
                table::prepare<string::String, u64>(&mut iter)
        ) {
            let (coin_type, amount) = table::next<string::String, u64>(&mut iter);
            vector::push_back(&mut res, EscrowResponse { coin_type, amount: *amount });
        };

        res
    }

    struct EscrowResponse has drop {
        coin_type: string::String,
        amount: u64,
    }

    // Chain functions
    /// whitelist coin from register
    /// whitelisted coin do not need to execute `register` manually
    entry fun whitelist<CoinType>(chain: &signer) acquires CoinInfo {
        check_chain_permission(chain);

        let coin_info = borrow_global_mut<CoinInfo<CoinType>>(coin_address<CoinType>());
        coin_info.whitelisted = true;
    }

    // Public functions
    /// Burn `coin` with capability.
    /// The capability `_cap` should be passed as a reference to `BurnCapability<CoinType>`.
    public fun burn<CoinType>(
        coin: Coin<CoinType>,
        _cap: &BurnCapability<CoinType>,
    ) acquires CoinInfo {
        let Coin { value: amount } = coin;
        assert!(amount > 0, error::invalid_argument(EZERO_COIN_AMOUNT));

        let coin_info = borrow_global_mut<CoinInfo<CoinType>>(coin_address<CoinType>());
        coin_info.supply = coin_info.supply - (amount as u128);

        event::emit_event<BurnEvent>(
            &mut coin_info.burn_events,
            BurnEvent {
                coin_type: type_info::type_name<CoinType>(),
                amount,
            },
        );
    }

    /// Deposit coins into the escrow store
    fun deposit_escrow<CoinType>(account_addr: address, coin: Coin<CoinType>) acquires EscrowStore, ModuleStore {
        let escrow_store = borrow_global_mut<EscrowStore<CoinType>>(coin_address<CoinType>());
        let amount = table::borrow_mut_with_default<address, u64>(&mut escrow_store.amount_table, account_addr, 0u64);
        *amount = *amount + coin.value;

        event::emit_event<EscrowDepositEvent>(
            &mut escrow_store.deposit_events,
            EscrowDepositEvent {
                coin_type: type_info::type_name<CoinType>(),
                recipient: account_addr,
                amount: coin.value,
            },
        );

        // update escrow table
        let coin_type = type_info::type_name<CoinType>();
        let module_store = borrow_global_mut<ModuleStore>(@initia_std);
        if (!table::contains(&module_store.escrow_table, account_addr)) {
            table::add(&mut module_store.escrow_table, account_addr, table::new())
        };
        let user_table = table::borrow_mut<address, table::Table<string::String, u64>>(&mut module_store.escrow_table, account_addr);
        let escrow_table_amount = table::borrow_mut_with_default<string::String, u64>(user_table, coin_type, 0u64);
        *escrow_table_amount = *amount;

        merge<CoinType>(&mut escrow_store.coin, coin);
    }

    /// Withdraw coins from the escrow store
    fun withdraw_escrow<CoinType>(account: &signer): Coin<CoinType> acquires EscrowStore, ModuleStore {
        let account_addr = signer::address_of(account);
        let escrow_store = borrow_global_mut<EscrowStore<CoinType>>(coin_address<CoinType>());

        if (table::contains<address, u64>(&escrow_store.amount_table, account_addr)) {
            let amount = table::remove<address, u64>(&mut escrow_store.amount_table, signer::address_of(account));
            event::emit_event<EscrowWithdrawEvent>(
                &mut escrow_store.withdraw_events,
                EscrowWithdrawEvent {
                    coin_type: type_info::type_name<CoinType>(),
                    recipient: account_addr,
                    amount,
                },
            );

            // update escrow table
            let coin_type = type_info::type_name<CoinType>();
            let module_store = borrow_global_mut<ModuleStore>(@initia_std);
            let user_table = table::borrow_mut<address, table::Table<string::String, u64>>(&mut module_store.escrow_table, account_addr);
            table::remove<string::String, u64>(user_table, coin_type);

            return extract<CoinType>(&mut escrow_store.coin, amount)
        };

        return zero<CoinType>()
    }

    /// Deposit the coin balance into the recipient's account and emit an event.
    public fun deposit<CoinType>(account_addr: address, coin: Coin<CoinType>) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        if (!is_account_registered<CoinType>(account_addr)) {
            let coin_info = borrow_global<CoinInfo<CoinType>>(coin_address<CoinType>());
            if (coin_info.whitelisted) {
                register<CoinType>(&create_signer_for_friend(account_addr));
            } else {
                return deposit_escrow<CoinType>(account_addr, coin)
            };
        };

        let coin_store = borrow_global_mut<CoinStore<CoinType>>(account_addr);
        assert!(
            !coin_store.frozen,
            error::permission_denied(EFROZEN),
        );

        event::emit_event<DepositEvent>(
            &mut coin_store.deposit_events,
            DepositEvent {
                coin_type: type_info::type_name<CoinType>(),
                amount: coin.value,
            },
        );

        merge(&mut coin_store.coin, coin);
    }

    /// Destroys a zero-value coin. Calls will fail if the `value` in the passed-in `token` is non-zero
    /// so it is impossible to "burn" any non-zero amount of `Coin` without having
    /// a `BurnCapability` for the specific `CoinType`.
    public fun destroy_zero<CoinType>(zero_coin: Coin<CoinType>) {
        let Coin { value } = zero_coin;
        assert!(value == 0, error::invalid_argument(EDESTRUCTION_OF_NONZERO_TOKEN))
    }

    /// Extracts `amount` from the passed-in `coin`, where the original token is modified in place.
    public fun extract<CoinType>(coin: &mut Coin<CoinType>, amount: u64): Coin<CoinType> {
        assert!(coin.value >= amount, error::invalid_argument(EINSUFFICIENT_BALANCE));

        coin.value = coin.value - amount;
        Coin { value: amount }
    }

    /// Extracts the entire amount from the passed-in `coin`, where the original token is modified in place.
    public fun extract_all<CoinType>(coin: &mut Coin<CoinType>): Coin<CoinType> {
        let total_value = coin.value;
        coin.value = 0;
        Coin { value: total_value }
    }

    /// Freeze a CoinStore to prevent transfers
    public fun freeze_coin_store<CoinType>(
        account_addr: address,
        _freeze_cap: &FreezeCapability<CoinType>,
    ) acquires CoinStore {
        let coin_store = borrow_global_mut<CoinStore<CoinType>>(account_addr);
        coin_store.frozen = true
    }

    /// Creates a new Coin with given `CoinType` and returns minting/burning capabilities.
    /// The given signer also becomes the account hosting the information  about the coin
    /// (name, supply, etc.). Supply is initialized as non-parallelizable integer.
    public fun initialize<CoinType>(
        account: &signer,
        name: string::String,
        symbol: string::String,
        decimals: u8,
    ): (BurnCapability<CoinType>, FreezeCapability<CoinType>, MintCapability<CoinType>) acquires ModuleStore {
        initialize_internal(account, name, symbol, decimals)
    }

    fun initialize_internal<CoinType>(
        account: &signer,
        name: string::String,
        symbol: string::String,
        decimals: u8,
    ): (BurnCapability<CoinType>, FreezeCapability<CoinType>, MintCapability<CoinType>) acquires ModuleStore {
        let account_addr = signer::address_of(account);

        assert!(
            coin_address<CoinType>() == account_addr,
            error::invalid_argument(ECOIN_INFO_ADDRESS_MISMATCH),
        );

        assert!(
            !exists<CoinInfo<CoinType>>(account_addr),
            error::already_exists(ECOIN_INFO_ALREADY_PUBLISHED),
        );

        assert!(string::length(&name) <= MAX_COIN_NAME_LENGTH, error::invalid_argument(ECOIN_NAME_TOO_LONG));
        assert!(string::length(&symbol) <= MAX_COIN_SYMBOL_LENGTH, error::invalid_argument(ECOIN_SYMBOL_TOO_LONG));

        let coin_type_info = type_info::type_of<CoinType>();
        let coin_address = type_info::account_address(&coin_type_info);
        let coin_module_name = type_info::module_name(&coin_type_info);

        let is_std = coin_address == @initia_std;
        let whitelisted = is_std && (
            coin_module_name == b"native_uinit" || 
            coin_module_name == b"native_ustake"
        );

        let coin_info = CoinInfo<CoinType> {
            name,
            symbol,
            decimals,
            supply: (0 as u128),
            whitelisted,
            mint_events: event::new_event_handle<MintEvent>(account),
            burn_events: event::new_event_handle<BurnEvent>(account),
        };
        move_to(account, coin_info);

        // store escrow_store to coin address
        let escrow_store = EscrowStore<CoinType> {
            coin: zero<CoinType>(),
            amount_table: table::new<address, u64>(),
            deposit_events: event::new_event_handle<EscrowDepositEvent>(account),
            withdraw_events: event::new_event_handle<EscrowWithdrawEvent>(account),
        };
        move_to(account, escrow_store);

        // store denom hash to module denom table,
        // when the coin address is not std
        if (!is_std) {
            let type_name = type_info::type_name<CoinType>();        
            let denom_bytes = hash::sha2_256(*string::bytes(&type_name));
            let module_store = borrow_global_mut<ModuleStore>(@initia_std);
            table::add(&mut module_store.denom_table, denom_bytes, type_name);
        };

        (BurnCapability<CoinType> {}, FreezeCapability<CoinType> {}, MintCapability<CoinType> {})
    }

    /// "Merges" the two given coins.  The coin passed in as `dst_coin` will have a value equal
    /// to the sum of the two tokens (`dst_coin` and `source_coin`).
    public fun merge<CoinType>(dst_coin: &mut Coin<CoinType>, source_coin: Coin<CoinType>) {
        spec {
            assume dst_coin.value + source_coin.value <= MAX_U64;
        };
        dst_coin.value = dst_coin.value + source_coin.value;
        let Coin { value: _ } = source_coin;
    }

    /// Mint new `Coin` with capability.
    /// The capability `_cap` should be passed as reference to `MintCapability<CoinType>`.
    /// Returns minted `Coin`.
    public fun mint<CoinType>(
        amount: u64,
        _cap: &MintCapability<CoinType>,
    ): Coin<CoinType> acquires CoinInfo {
        if (amount == 0) {
            return zero<CoinType>()
        };

        let coin_info = borrow_global_mut<CoinInfo<CoinType>>(coin_address<CoinType>());
        coin_info.supply = coin_info.supply + (amount as u128);
        event::emit_event<MintEvent>(
            &mut coin_info.mint_events,
            MintEvent {
                coin_type: type_info::type_name<CoinType>(),
                amount,
            },
        );

        Coin<CoinType> { value: amount }
    }

    public entry fun register<CoinType>(account: &signer) acquires EscrowStore, ModuleStore {
        let account_addr = signer::address_of(account);
        assert!(
            !is_account_registered<CoinType>(account_addr),
            error::already_exists(ECOIN_STORE_ALREADY_PUBLISHED),
        );

        let coin_store = CoinStore<CoinType> {
            coin: withdraw_escrow<CoinType>(account),
            frozen: false,
            deposit_events: event::new_event_handle<DepositEvent>(account),
            withdraw_events: event::new_event_handle<WithdrawEvent>(account),
        };
        move_to(account, coin_store);
    }

    /// Transfers `amount` of coins `CoinType` from `from` to `to`.
    public entry fun transfer<CoinType>(
        from: &signer,
        to: address,
        amount: u64,
    ) acquires CoinInfo, EscrowStore, CoinStore, ModuleStore {
        let coin = withdraw<CoinType>(from, amount);
        deposit(to, coin);
    }

    /// Returns the `value` passed in `coin`.
    public fun value<CoinType>(coin: &Coin<CoinType>): u64 {
        coin.value
    }

    /// Withdraw specifed `amount` of coin `CoinType` from the signing account.
    public fun withdraw<CoinType>(
        account: &signer,
        amount: u64,
    ): Coin<CoinType> acquires CoinStore {
        let account_addr = signer::address_of(account);

        assert!(
            is_account_registered<CoinType>(account_addr),
            error::not_found(ECOIN_STORE_NOT_PUBLISHED),
        );

        let coin_store = borrow_global_mut<CoinStore<CoinType>>(account_addr);
        assert!(
            !coin_store.frozen,
            error::permission_denied(EFROZEN),
        );

        event::emit_event<WithdrawEvent>(
            &mut coin_store.withdraw_events,
            WithdrawEvent {
                coin_type: type_info::type_name<CoinType>(),
                amount,
            },
        );

        extract(&mut coin_store.coin, amount)
    }

    /// Create a new `Coin<CoinType>` with a value of `0`.
    public fun zero<CoinType>(): Coin<CoinType> {
        Coin<CoinType> {
            value: 0
        }
    }

    /// Destroy a freeze capability. Freeze capability is dangerous and therefore should be destroyed if not used.
    public fun destroy_freeze_cap<CoinType>(freeze_cap: FreezeCapability<CoinType>) {
        let FreezeCapability<CoinType> {} = freeze_cap;
    }

    /// Destroy a mint capability.
    public fun destroy_mint_cap<CoinType>(mint_cap: MintCapability<CoinType>) {
        let MintCapability<CoinType> {} = mint_cap;
    }

    /// Destroy a burn capability.
    public fun destroy_burn_cap<CoinType>(burn_cap: BurnCapability<CoinType>) {
        let BurnCapability<CoinType> {} = burn_cap;
    }

    #[test_only]
    struct FakeMoney {}

    #[test_only]
    struct CoinCapabilities<phantom CoinType> has key {
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
        mint_cap: MintCapability<CoinType>,
    }

    #[test_only]
    public fun init_module_for_test(
        chain: &signer
    ) {
        init_module(chain);
    }

    #[test_only]
    fun initialize_fake_money(
        account: &signer,
        decimals: u8,
    ): (BurnCapability<FakeMoney>, FreezeCapability<FakeMoney>, MintCapability<FakeMoney>) acquires ModuleStore {
        initialize<FakeMoney>(
            account,
            string::utf8(b"Fake money"),
            string::utf8(b"FMD"),
            decimals,
        )
    }

    #[test_only]
    fun initialize_and_register_fake_money(
        account: &signer,
        decimals: u8,
    ): (BurnCapability<FakeMoney>, FreezeCapability<FakeMoney>, MintCapability<FakeMoney>) acquires EscrowStore, ModuleStore {
        let (burn_cap, freeze_cap, mint_cap) = initialize_fake_money(
            account,
            decimals,
        );

        register<FakeMoney>(account);
        (burn_cap, freeze_cap, mint_cap)
    }

    #[test_only]
    public fun create_fake_money(
        source: &signer,
        destination: &signer,
        amount: u64
    ) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        let (burn_cap, freeze_cap, mint_cap) = initialize_and_register_fake_money(source, 18);

        register<FakeMoney>(destination);
        let coins_minted = mint<FakeMoney>(amount, &mint_cap);
        deposit(signer::address_of(source), coins_minted);
        move_to(source, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test(source = @0x1, destination = @0x2)]
    public fun end_to_end(
        source: signer,
        destination: signer,
    ) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        init_module(&source);

        let source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);

        let name = string::utf8(b"Fake money");
        let symbol = string::utf8(b"FMD");

        let (burn_cap, freeze_cap, mint_cap) = initialize<FakeMoney>(
            &source,
            name,
            symbol,
            18
        );
        register<FakeMoney>(&source);
        register<FakeMoney>(&destination);
        assert!(supply<FakeMoney>() == 0, 0);

        assert!(name<FakeMoney>() == name, 1);
        assert!(symbol<FakeMoney>() == symbol, 2);
        assert!(decimals<FakeMoney>() == 18, 3);

        let coins_minted = mint<FakeMoney>(100, &mint_cap);
        deposit(source_addr, coins_minted);
        transfer<FakeMoney>(&source, destination_addr, 50);

        assert!(balance<FakeMoney>(source_addr) == 50, 4);
        assert!(balance<FakeMoney>(destination_addr) == 50, 5);
        assert!(supply<FakeMoney>() == 100, 6);

        let coin = withdraw<FakeMoney>(&source, 10);
        assert!(value(&coin) == 10, 7);
        burn(coin, &burn_cap);
        assert!(supply<FakeMoney>() == 90, 8);

        move_to(&source, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test(chain = @0x1, source = @0x2)]
    #[expected_failure(abort_code = 0x10002, location = Self)]
    public fun fail_initialize(chain: signer, source: signer) acquires ModuleStore {
        init_module(&chain);

        let (burn_cap, freeze_cap, mint_cap) = initialize<FakeMoney>(
            &source,
            string::utf8(b"Fake money"),
            string::utf8(b"FMD"),
            1,
        );

        move_to(&source, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test(source = @0x1, destination = @0x2)]
    public fun unregistered_coin_escrow_deposit(
        source: signer,
        destination: signer,
    ) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        init_module(&source);

        let source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);

        let (burn_cap, freeze_cap, mint_cap) = initialize_and_register_fake_money(&source, 1);
        assert!(supply<FakeMoney>() == 0, 0);

        let coins_minted = mint<FakeMoney>(100, &mint_cap);
        deposit(source_addr, coins_minted);
        transfer<FakeMoney>(&source, destination_addr, 50);
        assert!(escrow_balance<FakeMoney>(destination_addr) == 50, 1);

        move_to(&source, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x10008, location = Self)]
    public fun test_destroy_non_zero(
        source: signer,
    ) acquires CoinInfo, EscrowStore, ModuleStore {
        init_module(&source);

        let (burn_cap, freeze_cap, mint_cap) = initialize_and_register_fake_money(&source, 1);
        let coins_minted = mint<FakeMoney>(100, &mint_cap);
        destroy_zero(coins_minted);

        move_to(&source, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test(source = @0x1)]
    public fun test_extract(
        source: signer,
    ) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        init_module(&source);

        let source_addr = signer::address_of(&source);
        let (burn_cap, freeze_cap, mint_cap) = initialize_and_register_fake_money(&source, 1);

        let coins_minted = mint<FakeMoney>(100, &mint_cap);

        let extracted = extract(&mut coins_minted, 25);
        assert!(value(&coins_minted) == 75, 0);
        assert!(value(&extracted) == 25, 1);

        deposit(source_addr, coins_minted);
        deposit(source_addr, extracted);

        assert!(balance<FakeMoney>(source_addr) == 100, 2);

        move_to(&source, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test(source = @0x1)]
    public fun test_is_coin_initialized(source: signer) acquires ModuleStore {
        init_module(&source);

        assert!(!is_coin_initialized<FakeMoney>(), 0);
        let (burn_cap, freeze_cap, mint_cap) = initialize_fake_money(&source, 1);
        assert!(is_coin_initialized<FakeMoney>(), 1);

        move_to(&source, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test]
    fun test_zero() {
        let zero = zero<FakeMoney>();
        assert!(value(&zero) == 0, 1);
        destroy_zero(zero);
    }

    #[test(account = @0x1)]
    #[expected_failure(abort_code = 0x5000A, location = Self)]
    public fun withdraw_frozen(account: signer) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        init_module(&account);

        let account_addr = signer::address_of(&account);
        let (burn_cap, freeze_cap, mint_cap) = initialize_and_register_fake_money(&account, 18);

        freeze_coin_store(account_addr, &freeze_cap);
        let coin = withdraw<FakeMoney>(&account, 10);
        deposit(account_addr, coin);

        move_to(&account, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test(account = @0x1)]
    #[expected_failure(abort_code = 0x5000A, location = Self)]
    public fun deposit_frozen(account: signer) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        init_module(&account);

        let account_addr = signer::address_of(&account);
        let (burn_cap, freeze_cap, mint_cap) = initialize_and_register_fake_money(&account, 18);

        let coins_minted = mint<FakeMoney>(100, &mint_cap);
        freeze_coin_store(account_addr, &freeze_cap);
        deposit(account_addr, coins_minted);

        move_to(&account, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }

    #[test_only]
    struct CoinA {}
    #[test_only]
    struct CoinB {}
    #[test_only]
    struct CoinC {}
    #[test_only]
    struct CoinD {}

    #[test_only]
    fun initialize_coin<CoinType>(
        account: &signer,
        decimals: u8
    ): (BurnCapability<CoinType>, FreezeCapability<CoinType>, MintCapability<CoinType>) acquires ModuleStore {
        initialize<CoinType>(
            account,
            string::utf8(b"name"),
            string::utf8(b"SYMBOL"),
            decimals,
        )
    }

    #[test(account = @0x1)]
    public fun get_escrow_test(account: signer) acquires CoinInfo, CoinStore, EscrowStore, ModuleStore {
        init_module(&account);

        let account_addr = signer::address_of(&account);
        let (burn_cap, freeze_cap, mint_cap) = initialize_coin<CoinA>(&account, 6);
        let coin_a = mint<CoinA>(100, &mint_cap);
        move_to(&account, CoinCapabilities<CoinA> { burn_cap, freeze_cap, mint_cap });
        let (burn_cap, freeze_cap, mint_cap) = initialize_coin<CoinB>(&account, 6);
        let coin_b = mint<CoinB>(100, &mint_cap);
        move_to(&account, CoinCapabilities<CoinB> { burn_cap, freeze_cap, mint_cap });
        let (burn_cap, freeze_cap, mint_cap) = initialize_coin<CoinC>(&account, 6);
        let coin_c = mint<CoinC>(100, &mint_cap);
        move_to(&account, CoinCapabilities<CoinC> { burn_cap, freeze_cap, mint_cap });
        let (burn_cap, freeze_cap, mint_cap) = initialize_coin<CoinD>(&account, 6);
        let coin_d = mint<CoinD>(100, &mint_cap);
        move_to(&account, CoinCapabilities<CoinD> { burn_cap, freeze_cap, mint_cap });

        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        let coin_c_type = type_info::type_name<CoinC>();
        let coin_d_type = type_info::type_name<CoinD>();

        assert!(get_escrow(account_addr, option::none(), 10) == vector[], 0);
        deposit(account_addr, coin_a);
        assert!(
            get_escrow(account_addr, option::none(), 10) ==
                vector[
                    EscrowResponse { coin_type: coin_a_type, amount: 100 },
                ],
            1,
        );

        deposit(account_addr, coin_b);
        deposit(account_addr, coin_c);
        deposit(account_addr, coin_d);
        assert!(
            get_escrow(account_addr, option::none(), 10) ==
                vector[
                    EscrowResponse { coin_type: coin_d_type, amount: 100 },
                    EscrowResponse { coin_type: coin_c_type, amount: 100 },
                    EscrowResponse { coin_type: coin_b_type, amount: 100 },
                    EscrowResponse { coin_type: coin_a_type, amount: 100 },
                ],
            2,
        );

        assert!(
            get_escrow(account_addr, option::some(coin_c_type), 10) ==
                vector[
                    EscrowResponse { coin_type: coin_b_type, amount: 100 },
                    EscrowResponse { coin_type: coin_a_type, amount: 100 },
                ],
            3,
        );

        assert!(
            get_escrow(account_addr, option::none(), 3) ==
                vector[
                    EscrowResponse { coin_type: coin_d_type, amount: 100 },
                    EscrowResponse { coin_type: coin_c_type, amount: 100 },
                    EscrowResponse { coin_type: coin_b_type, amount: 100 },
                ],
            3,
        );
    }

    #[test_only]
    fun initialize_with_integer(account: &signer) acquires ModuleStore {
        let (burn_cap, freeze_cap, mint_cap) = initialize<FakeMoney>(
            account,
            string::utf8(b"Fake money"),
            string::utf8(b"FMD"),
            1,
        );
        move_to(account, CoinCapabilities<FakeMoney> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });
    }
}

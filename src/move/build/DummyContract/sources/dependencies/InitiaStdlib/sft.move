module initia_std::sft {
    use std::error;
    use std::event::{Self, EventHandle};
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use std::hash;

    use initia_std::table::{Self, Table};
    use initia_std::type_info;

    //
    // Errors.
    //

    /// signer must be extension publisher
    const ESFT_ADDRESS_MISMATCH: u64 = 0;

    /// collection already exists
    const ECOLLECTION_ALREADY_EXISTS: u64 = 1;

    /// collection not found
    const ECOLLECTION_NOT_FOUND: u64 = 2;

    /// sft store already exists
    const ESFT_STORE_ALREADY_EXISTS: u64 = 3;

    /// sft store not found
    const ESFT_STORE_NOT_FOUND: u64 = 4;

    /// token_id is taken
    const ETOKEN_ID_ALREADY_EXISTS: u64 = 5;

    /// token_id not found
    const ETOKEN_ID_NOT_FOUND: u64 = 6;

    /// can not update sft that is_mutable is false
    const ENOT_MUTABLE: u64 = 7;

    /// can not query more than `MAX_LIMIT`
    const EMAX_LIMIT: u64 = 8;

    /// Not enough sfts to complete transaction
    const EINSUFFICIENT_BALANCE: u64 = 9;

    /// Can not mint more than max supply
    const EEXCEED_MAX_SUPPLY: u64 = 10;

    /// Need to add SFT info before mint
    const ESFT_INFO_NOT_PUBLISHED: u64 = 11;

    /// Token id mismatch between dst and soure
    const ETOKEN_ID_MISMATCH: u64 = 12;

    /// escrow deposit not found
    const EESCROW_DEPOSIT_NOT_FOUND: u64 = 13;

    /// Name of the collection is too long
    const ECOLLECTION_NAME_TOO_LONG: u64 = 14;

    /// Symbol of the collection is too long
    const ECOLLECTION_SYMBOL_TOO_LONG: u64 = 15;


    // constant

    /// Max length of query response
    const MAX_LIMIT: u8 = 30;

    // allow long name & symbol to allow ibc class trace
    const MAX_COLLECTION_NAME_LENGTH: u64 = 256;
    const MAX_COLLECTION_SYMBOL_LENGTH: u64 = 256;

    // Data structures

    /// Capability required to mint and update sfts.
    struct Capability<phantom Extension: store + drop + copy> has copy, store {}

    /// Collection information
    struct SftCollection<Extension: store + drop + copy> has key {
        /// Name of the collection
        name: String,
        /// Symbol of the collection
        symbol: String,
        /// collection uri
        uri: String,
        /// Mutability of extension and uri
        is_mutable: bool,
        /// All sft information
        sft_infos: Table<String, SftInfo<Extension>>,

        update_events: EventHandle<UpdateEvent>,
        mint_events: EventHandle<MintEvent>,
        burn_events: EventHandle<BurnEvent>,
    }

    /// The holder storage for specific sft collection 
    struct SftStore<phantom Extension> has key {
        sfts: Table<String, Sft<Extension>>,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
    }

    /// key for sft escrow
    struct EscrowKey has copy, drop {
        addr: address,
        token_id: String,
    }

    /// Escrow sft store for the unregistered accounts
    struct EscrowStore<phantom Extension> has key {
        sfts: Table<EscrowKey, Sft<Extension>>,
        deposit_events: EventHandle<EscrowDepositEvent>,
        withdraw_events: EventHandle<EscrowWithdrawEvent>,
    }

    /// Store for module
    struct ModuleStore has key {
        // Class table for (hash => struct tag) query
        class_table: table::Table<vector<u8>, string::String>,
        // Escrow table for address => struct_tag
        escrow_table: Table<address, Table<String, bool>>,
    }

    /// SFT Information
    struct SftInfo<Extension: store + drop + copy> has store {
        token_id: String,
        supply: u64,
        max_supply: Option<u64>,
        uri: String,
        extension: Extension,
    }

    struct Sft<phantom Extension> has store {
        token_id: String,
        amount: u64,
    }

    struct DepositEvent has drop, store {
        extension_type: String,
        token_id: String,
        amount: u64,
    }

    struct WithdrawEvent has drop, store {
        extension_type: String,
        token_id: String,
        amount: u64,
    }

    struct MintEvent has drop, store {
        extension_type: String,
        token_id: String,
        amount: u64,
    }

    struct BurnEvent has drop, store {
        extension_type: String,
        token_id: String,
        amount: u64,
    }

    /// Event emitted when sft is deposited into an account.
    struct EscrowDepositEvent has drop, store {
        extension_type: String,
        token_id: String,
        amount: u64,
        recipient: address,
    }

    /// Event emitted when sft is withdrawn from an account.
    struct EscrowWithdrawEvent has drop, store {
        extension_type: String,
        token_id: String,
        amount: u64,
        recipient: address,
    }

    struct UpdateEvent has drop, store {
        extension_type: String,
        token_id: String,
    }

    /// response structure for SftInfo
    struct SftInfoResponse<Extension> has drop {
        token_id: String,
        supply: u64,
        max_supply: Option<u64>,
        uri: String,
        extension: Extension,
    }

    /// response structure for Collection
    struct SftCollectionInfoResponse has drop {
        name: String,
        symbol: String,
        uri: String,
        is_mutable: bool,
    }

    /// response structure for get_escrow_depoist response
    struct EscrowDepositResponse has drop {
        token_id: String,
        amount: u64,
    }

    //
    // GENESIS
    //

    fun init_module(chain: &signer) {
        move_to(chain, ModuleStore {
            class_table: table::new(),
            escrow_table: table::new(),
        });
    }

    //
    // Query functions
    // 

    #[view]
    /// Return true if `SftStore` is published
    public fun is_account_registered<Extension: store + drop + copy>(addr: address): bool {
        exists<SftStore<Extension>>(addr)
    }

    #[view]
    /// Return true if collection exists
    public fun collection_exists<Extension: store + drop + copy>(): bool {
        let creator = sft_address<Extension>();
        exists<SftCollection<Extension>>(creator)
    }

    #[view]
    /// Return collection info
    public fun get_collection_info<Extension: store + drop + copy>(): SftCollectionInfoResponse acquires SftCollection {
        check_collection_exists<Extension>();

        let creator = sft_address<Extension>();
        let collection = borrow_global<SftCollection<Extension>>(creator);

        SftCollectionInfoResponse {
            name: collection.name,
            symbol: collection.symbol,
            uri: collection.uri,
            is_mutable: collection.is_mutable,
        }
    }

    #[view]
    /// Return sft_info
    public fun get_sft_info<Extension: store + drop + copy>(
        token_id: String,
    ): SftInfoResponse<Extension> acquires SftCollection {
        check_collection_exists<Extension>();
        
        let creator = sft_address<Extension>();
        let collection = borrow_global<SftCollection<Extension>>(creator);

        assert!(
            table::contains<String, SftInfo<Extension>>(&collection.sft_infos, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        let sft_info = table::borrow<String, SftInfo<Extension>>(&collection.sft_infos, token_id);

        SftInfoResponse {
            token_id: sft_info.token_id,
            supply: sft_info.supply,
            max_supply: sft_info.max_supply,
            uri: sft_info.uri,
            extension: sft_info.extension,
        }
    }

    #[view]
    /// Return SftInfos
    public fun get_sft_infos<Extension: store + drop + copy>(
        token_ids: vector<String>,
    ): vector<SftInfoResponse<Extension>> acquires SftCollection {
        check_collection_exists<Extension>();

        assert!(
            vector::length(&token_ids) <= (MAX_LIMIT as u64),
            error::invalid_argument(EMAX_LIMIT),
        );

        let creator = sft_address<Extension>();
        let collection = borrow_global<SftCollection<Extension>>(creator);

        let res: vector<SftInfoResponse<Extension>> = vector[];

        let index = 0;

        let len = vector::length(&token_ids);
        while (index < len) {
            let token_id = *vector::borrow(&token_ids, index);

            assert!(
                table::contains<String, SftInfo<Extension>>(&collection.sft_infos, token_id),
                error::not_found(ETOKEN_ID_NOT_FOUND),
            );

            let sft_info = table::borrow<String, SftInfo<Extension>>(&collection.sft_infos, token_id);

            vector::push_back(
                &mut res,
                SftInfoResponse {
                    token_id: sft_info.token_id,
                    supply: sft_info.supply,
                    max_supply: sft_info.max_supply,
                    uri: sft_info.uri,
                    extension: sft_info.extension,
                },
            );

            index = index + 1;
        };

        res
    }

    #[view]
    /// get all `token_id`
    public fun all_token_ids<Extension: store + drop + copy>(
        start_after: Option<String>,
        limit: u8,
    ): vector<String> acquires SftCollection {
        check_collection_exists<Extension>();

        let creator = sft_address<Extension>();
        let collection = borrow_global<SftCollection<Extension>>(creator);

        let sft_info_iter = table::iter(
            &collection.sft_infos,
            option::none(),
            start_after,
            2,
        );

        let res: vector<String> = vector[];

        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        while (table::prepare<String, SftInfo<Extension>>(&mut sft_info_iter) && vector::length(&res) < (limit as u64)) {
            let (token_id, _token_info) = table::next<String, SftInfo<Extension>>(&mut sft_info_iter);

            vector::push_back(&mut res, token_id);
        };

        res
    }

    #[view]
    /// get all `token_id` from `SftStore` of user
    public fun token_ids<Extension: store + drop + copy>(
        owner: address,
        start_after: Option<String>,
        limit: u8,
    ): vector<String> acquires SftStore {
        check_collection_exists<Extension>();
        check_is_registered<Extension>(owner);

        let sft_store = borrow_global<SftStore<Extension>>(owner);

        let sfts_iter = table::iter(
            &sft_store.sfts,
            option::none(),
            start_after,
            2,
        );

        let res: vector<String> = vector[];

        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        while (table::prepare<String, Sft<Extension>>(&mut sfts_iter) && vector::length(&res) < (limit as u64)) {
            let (token_id, _token) = table::next<String, SftInfo<Extension>>(&mut sfts_iter);

            vector::push_back(&mut res, token_id);
        };

        res
    }

    #[view]
    /// get all `token_id` and `amount` from `EscrowStore` of certain user
    public fun get_escrow_deposit<Extension: store + drop + copy>(
        addr: address,
    ): vector<EscrowDepositResponse> acquires EscrowStore {
        let res: vector<EscrowDepositResponse> = vector[];
        let escrow_iter = gen_escrow_iter<Extension>(addr);

        while(table::prepare<EscrowKey, Sft<Extension>>(&mut escrow_iter)) {
            let (key, sft) = table::next<EscrowKey, Sft<Extension>>(&mut escrow_iter);
            if (key.addr != addr) {
                break
            };

            vector::push_back(&mut res, EscrowDepositResponse { token_id: key.token_id, amount: sft.amount });
        };

        res
    }

    #[view]
    /// get all collection from `EscrowStore` of certain user
    /// return all collection that has escrow deposit
    public fun get_escrow_collection(
        addr: address,
        start_after: Option<String>,
        limit: u8,
    ): vector<String> acquires ModuleStore {
        let module_store = borrow_global_mut<ModuleStore>(@initia_std);
        let res: vector<String> = vector[];
        if (!table::contains(&module_store.escrow_table, addr)) {
            return res
        };
        let user_table = table::borrow_mut(&mut module_store.escrow_table, addr);

        let escrow_iter = table::iter(
            user_table,
            option::none(),
            start_after,
            2
        );

        while(vector::length(&res) < (limit as u64) && table::prepare<String, Table<String, bool>>(&mut escrow_iter)) {
            let (key, _) = table::next<String, bool>(&mut escrow_iter);
            vector::push_back(&mut res, key);
        };

        res
    }

    #[view]
    public fun get_balance<Extension: store + drop + copy>(
        owner: address,
        token_id: String,
    ): u64 acquires SftStore {
        check_collection_exists<Extension>();
        check_is_registered<Extension>(owner);

        let sft_store = borrow_global<SftStore<Extension>>(owner);

        if (table::contains(&sft_store.sfts, token_id)) {
            let sft = table::borrow(&sft_store.sfts, token_id);
            sft.amount
        } else {
            0
        }
    }

    #[view]
    /// Return balances
    public fun get_balances<Extension: store + drop + copy>(
        owner: address,
        token_ids: vector<String>,
    ): vector<u64> acquires SftStore {
        check_collection_exists<Extension>();

        assert!(
            vector::length(&token_ids) <= (MAX_LIMIT as u64),
            error::invalid_argument(EMAX_LIMIT),
        );

        let res: vector<u64> = vector[];

        let index = 0;

        let len = vector::length(&token_ids);
        while (index < len) {
            let token_id = *vector::borrow(&token_ids, index);

            
            vector::push_back(
                &mut res,
                get_balance<Extension>(owner, token_id),
            );

            index = index + 1;
        };

        res
    }

    /// query helpers

    /// get `token_id` from `SftInfoResponse`
    public fun get_token_id_from_sft_info_response<Extension: store + drop + copy>(
        sft_info_res: &SftInfoResponse<Extension>,
    ): String {
        sft_info_res.token_id
    }

    /// get `supply` from `SftInfoResponse`
    public fun get_supply_from_sft_info_response<Extension: store + drop + copy>(
        sft_info_res: &SftInfoResponse<Extension>,
    ): u64 {
        sft_info_res.supply
    }

    /// get `max_supply` from `SftInfoResponse`
    public fun get_max_supply_from_sft_info_response<Extension: store + drop + copy>(
        sft_info_res: &SftInfoResponse<Extension>,
    ): Option<u64> {
        sft_info_res.max_supply
    }

    /// get `uri` from `SftInfoResponse`
    public fun get_uri_from_sft_info_response<Extension: store + drop + copy>(
        sft_info_res: &SftInfoResponse<Extension>,
    ): String {
        sft_info_res.uri
    }

    /// get `extension` from `SftInfoResponse`
    public fun get_extension_from_sft_info_response<Extension: store + drop + copy>(
        sft_info_res: &SftInfoResponse<Extension>,
    ): Extension {
        sft_info_res.extension
    }

    /// get `token_id` from `EscrowDepositResponse`
    public fun get_token_id_from_escrow_deposit_response(
        escrow_deposit: &EscrowDepositResponse
    ): String {
        escrow_deposit.token_id
    }

    /// get `amount` from `EscrowDepositResponse`
    public fun get_amount_from_escrow_deposit_response(
        escrow_deposit: &EscrowDepositResponse
    ): u64 {
        escrow_deposit.amount
    }

    /// get `token_id` from `Sft`
    public fun get_token_id_from_sft<Extension: store + drop + copy>(
        sft: &Sft<Extension>,
    ): String {
        sft.token_id
    }

    /// get `amount` from `Sft`
    public fun get_amount_from_sft<Extension: store + drop + copy>(
        sft: &Sft<Extension>,
    ): u64 {
        sft.amount
    }

    //
    // Execute entry functions
    // 

    /// publish sft store
    public entry fun register<Extension: store + drop + copy>(account: &signer) acquires EscrowStore, ModuleStore {
        let addr = signer::address_of(account);
        assert!(
            !exists<SftStore<Extension>>(addr),
            error::not_found(ESFT_STORE_ALREADY_EXISTS),
        );

        let sfts = table::new<String, Sft<Extension>>();
        let escrow_deposits = get_escrow_deposit<Extension>(addr);
        let len = vector::length(&escrow_deposits);

        if (len != 0) {
            let index = 0;
            while(index < len) {
                let EscrowDepositResponse { token_id, amount: _ } = vector::borrow(&escrow_deposits, index);
                let sft = withdraw_escrow<Extension>(account, *token_id);
                table::add(&mut sfts, *token_id, sft);
                index = index + 1;
            };

            // update escrow table
            let struct_tag = type_info::type_name<Extension>();
            let module_store = borrow_global_mut<ModuleStore>(@initia_std);
            let user_table = table::borrow_mut(&mut module_store.escrow_table, addr);
            table::remove(user_table, struct_tag);

            if (table::length(user_table) == 0) {
                let empty_table = table::remove(&mut module_store.escrow_table, addr);
                table::destroy_empty(empty_table);
            };
        };        

        let sft_store = SftStore<Extension> {
            sfts,
            deposit_events: event::new_event_handle<DepositEvent>(account),
            withdraw_events: event::new_event_handle<WithdrawEvent>(account),
        };

        move_to(account, sft_store);
    }

    /// publish sft store
    public entry fun register_without_withdraw_escrow<Extension: store + drop + copy>(account: &signer) {
        let addr = signer::address_of(account);
        assert!(
            !exists<SftStore<Extension>>(addr),
            error::not_found(ESFT_STORE_ALREADY_EXISTS),
        );

        let sft_store = SftStore<Extension> {
            sfts: table::new(),
            deposit_events: event::new_event_handle<DepositEvent>(account),
            withdraw_events: event::new_event_handle<WithdrawEvent>(account),
        };

        move_to(account, sft_store);
    }

    /// Burn sft from sft store
    public entry fun burn_script<Extension: store + drop + copy>(
        account: &signer,
        token_id: String,
        amount: u64,
    ) acquires SftCollection, SftStore {
        let addr = signer::address_of(account);

        check_collection_exists<Extension>();
        check_is_registered<Extension>(addr);

        let creator = sft_address<Extension>();
        let collection = borrow_global_mut<SftCollection<Extension>>(creator);

        assert!(
            table::contains<String, SftInfo<Extension>>(&collection.sft_infos, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        let sft = withdraw<Extension>(account, token_id, amount);

        burn(sft);
    }

    /// Transfer sft from sft store to another sft store
    public entry fun transfer<Extension: store + drop + copy>(
        account: &signer,
        to: address,
        token_id: String,
        amount: u64,
    ) acquires EscrowStore, ModuleStore, SftStore {
        let sft = withdraw<Extension>(account, token_id, amount);
        deposit<Extension>(to, sft);
    }

    /// withdraw sfts from EscrowStore manually
    public entry fun withdraw_escrow_script<Extension: store + drop + copy>(
        account: &signer,
        token_ids: vector<String>,
    ) acquires EscrowStore, ModuleStore, SftStore {
        let addr = signer::address_of(account);
        check_is_registered<Extension>(addr);
        let len = vector::length(&token_ids);
        let index = 0;
        while(index < len) {
            let token_id = *vector::borrow(&token_ids, index);
            let sft = withdraw_escrow<Extension>(account, token_id);
            deposit(addr, sft);
            index = index + 1;
        };

        let escrow_iter = gen_escrow_iter<Extension>(addr);
        let is_prepare = table::prepare<EscrowKey, Sft<Extension>>(&mut escrow_iter);
        let escrow_exists = if (is_prepare) {
            let (key, _) = table::next<EscrowKey, Sft<Extension>>(&mut escrow_iter);
            key.addr == addr
        } else {
            false
        };
        // if there is no escrow depoist remain to this addr + collection 
        if (!escrow_exists) {
            let struct_tag = type_info::type_name<Extension>();
            let module_store = borrow_global_mut<ModuleStore>(@initia_std);
            let user_table = table::borrow_mut(&mut module_store.escrow_table, addr);
            table::remove(user_table, struct_tag);
        };
    }

    ///
    /// Public functions
    /// 

    /// Make a new collection
    public fun make_collection<Extension: store + drop + copy>(
        account: &signer,
        name: String,
        symbol: String,
        uri: String,
        is_mutable: bool
    ): Capability<Extension>  acquires ModuleStore {
        let creator = signer::address_of(account);

        assert!(
            sft_address<Extension>() == creator,
            error::invalid_argument(ESFT_ADDRESS_MISMATCH),
        );

        assert!(
            !exists<SftCollection<Extension>>(creator),
            error::already_exists(ECOLLECTION_ALREADY_EXISTS),
        );

        assert!(string::length(&name) <= MAX_COLLECTION_NAME_LENGTH, error::invalid_argument(ECOLLECTION_NAME_TOO_LONG));
        assert!(string::length(&symbol) <= MAX_COLLECTION_SYMBOL_LENGTH, error::invalid_argument(ECOLLECTION_SYMBOL_TOO_LONG));

        let collection = SftCollection<Extension> {
            name,
            symbol,
            uri,
            is_mutable,
            sft_infos: table::new<String, SftInfo<Extension>>(),
            update_events: event::new_event_handle<UpdateEvent>(account),
            mint_events: event::new_event_handle<MintEvent>(account),
            burn_events: event::new_event_handle<BurnEvent>(account),
        };

        move_to(account, collection);

        let escrow_store = EscrowStore<Extension> {
            sfts: table::new(),
            deposit_events: event::new_event_handle<EscrowDepositEvent>(account),
            withdraw_events: event::new_event_handle<EscrowWithdrawEvent>(account),
        };
        move_to(account, escrow_store);

        // add entry for class => struct tag query
        if (creator != @initia_std) {
            let type_name = type_info::type_name<Extension>();        
            let class_bytes = hash::sha2_256(*string::bytes(&type_name));
            let module_store = borrow_global_mut<ModuleStore>(@initia_std);
            table::add(&mut module_store.class_table, class_bytes, type_name);
        };

        Capability<Extension> {}
    }

    /// Add new sft info
    public fun make_token<Extension: store + drop + copy>(
        token_id: String,
        uri: String,
        max_supply: Option<u64>,
        extension: Extension,
        _capability: &Capability<Extension>,
    ) acquires SftCollection {
        check_collection_exists<Extension>();

        let creator = sft_address<Extension>();
        let collection = borrow_global_mut<SftCollection<Extension>>(creator);

        assert!(
            !table::contains<String, SftInfo<Extension>>(&collection.sft_infos, token_id),
            error::already_exists(ETOKEN_ID_ALREADY_EXISTS),
        );

        let sft_info = SftInfo<Extension> { token_id, uri, max_supply, supply: 0, extension };
        table::add<String, SftInfo<Extension>>(&mut collection.sft_infos, token_id, sft_info);
    }

    /// Mint new sft
    public fun mint<Extension: store + drop + copy>(
        token_id: String,
        amount: u64,
        _capability: &Capability<Extension>,
    ): Sft<Extension> acquires SftCollection {
        check_collection_exists<Extension>();

        let creator = sft_address<Extension>();
        let collection = borrow_global_mut<SftCollection<Extension>>(creator);

        assert!(
            table::contains<String, SftInfo<Extension>>(&collection.sft_infos, token_id),
            error::already_exists(ESFT_INFO_NOT_PUBLISHED),
        );

        let sft_info = table::borrow_mut<String, SftInfo<Extension>>(&mut collection.sft_infos, token_id);

        if (option::is_some(&sft_info.max_supply)) {
            let max_supply = option::borrow(&sft_info.max_supply);
            assert!(
                *max_supply >= sft_info.supply + amount,
                error::invalid_argument(EEXCEED_MAX_SUPPLY),
            );
        };

        sft_info.supply = sft_info.supply + amount;

        event::emit_event<MintEvent>(
            &mut collection.mint_events,
            MintEvent { token_id, extension_type: type_info::type_name<Extension>(), amount },
        );

        Sft<Extension> { token_id, amount }
    }

    /// update uri/extension
    public fun update_sft<Extension: store + drop + copy>(
        token_id: String,
        uri: Option<String>,
        extension: Option<Extension>,
        _capability: &Capability<Extension>,
    ) acquires SftCollection {
        check_collection_exists<Extension>();

        let creator = sft_address<Extension>();
        let collection = borrow_global_mut<SftCollection<Extension>>(creator);

        assert!(
            table::contains<String, SftInfo<Extension>>(&collection.sft_infos, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        assert!(
            collection.is_mutable,
            error::permission_denied(ENOT_MUTABLE),
        );

        let sft_info = table::borrow_mut<String, SftInfo<Extension>>(&mut collection.sft_infos, token_id);

        if (option::is_some<String>(&uri)) {
            let new_uri = option::extract<String>(&mut uri);
            sft_info.uri = new_uri;
        };

        if (option::is_some<Extension>(&extension)) {
            let new_extension = option::extract<Extension>(&mut extension);
            sft_info.extension = new_extension;
        };

        event::emit_event<UpdateEvent>(
            &mut collection.update_events,
            UpdateEvent { token_id, extension_type: type_info::type_name<Extension>() },
        );
    }

    /// withdraw sft from token_store
    public fun withdraw<Extension: store + drop + copy>(
        account: &signer,
        token_id: String,
        amount: u64,
    ): Sft<Extension> acquires SftStore {
        let addr = signer::address_of(account);
        check_is_registered<Extension>(addr);

        let sft_store = borrow_global_mut<SftStore<Extension>>(addr);

        event::emit_event<WithdrawEvent>(
            &mut sft_store.withdraw_events,
            WithdrawEvent { token_id, extension_type: type_info::type_name<Extension>(), amount},
        );

        assert!(
            table::contains<String, Sft<Extension>>(&sft_store.sfts, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        let sft = table::borrow_mut<String, Sft<Extension>>(&mut sft_store.sfts, token_id);
        if (sft.amount == amount) {
            table::remove<String, Sft<Extension>>(&mut sft_store.sfts, token_id)
        } else {
            extract(sft, amount)
        }
    }

    /// deposit token to token_store
    public fun deposit<Extension: store + drop + copy>(
        addr: address,
        sft: Sft<Extension>
    ) acquires EscrowStore, ModuleStore, SftStore {
        check_collection_exists<Extension>();
        if (!is_account_registered<Extension>(addr)) {
            return deposit_escrow(addr, sft)
        };

        let sft_store = borrow_global_mut<SftStore<Extension>>(addr);

        event::emit_event<DepositEvent>(
            &mut sft_store.deposit_events,
            DepositEvent {
                token_id: sft.token_id,
                extension_type: type_info::type_name<Extension>(),
                amount: sft.amount,
            },
        );

        if (table::contains(&mut sft_store.sfts, sft.token_id)) {
            let dst = table::borrow_mut(&mut sft_store.sfts, sft.token_id);
            merge(dst, sft);
        } else {
            table::add<String, Sft<Extension>>(&mut sft_store.sfts, sft.token_id, sft);
        }
    }

    /// burn sft
    public fun burn<Extension: store + drop + copy>(sft: Sft<Extension>) acquires SftCollection {
        let creator = sft_address<Extension>();

        let collection = borrow_global_mut<SftCollection<Extension>>(creator);

        let Sft { token_id, amount } = sft;

        let sft_iofo = table::borrow_mut<String, SftInfo<Extension>>(&mut collection.sft_infos, token_id);

        sft_iofo.supply = sft_iofo.supply - amount;

        event::emit_event<BurnEvent>(
            &mut collection.burn_events,
            BurnEvent { token_id, extension_type: type_info::type_name<Extension>(), amount },
        );
    }

    /// Deposit sft into the escrow store
    fun deposit_escrow<Extension: store + drop + copy>(account_addr: address, sft: Sft<Extension>) acquires EscrowStore, ModuleStore {
        let escrow_store = borrow_global_mut<EscrowStore<Extension>>(sft_address<Extension>());
        let token_id = sft.token_id;
        let amount = sft.amount;
        let key = EscrowKey { addr: account_addr, token_id };
        if (!table::contains(&escrow_store.sfts, key)) {
            table::add(&mut escrow_store.sfts, key, Sft<Extension> { token_id: sft.token_id, amount: 0 });
        };
        let escrow_deposit = table::borrow_mut(&mut escrow_store.sfts, key);
        merge(escrow_deposit, sft);

        event::emit_event<EscrowDepositEvent>(
            &mut escrow_store.deposit_events,
            EscrowDepositEvent {
                extension_type: type_info::type_name<Extension>(),
                token_id, 
                amount,
                recipient: account_addr,
            },
        );

        // update escrow table
        let struct_tag = type_info::type_name<Extension>();
        let module_store = borrow_global_mut<ModuleStore>(@initia_std);
        if (!table::contains(&module_store.escrow_table, account_addr)) {
            table::add(&mut module_store.escrow_table, account_addr, table::new())
        };
        let user_table = table::borrow_mut(&mut module_store.escrow_table, account_addr);
        if (!table::contains(user_table, struct_tag)) {
            table::add(user_table, struct_tag, true)
        };
    }

    /// Withdraw sft from the escrow store
    fun withdraw_escrow<Extension: store + drop + copy>(account: &signer, token_id: String): Sft<Extension> acquires EscrowStore {
        let account_addr = signer::address_of(account);
        let escrow_store = borrow_global_mut<EscrowStore<Extension>>(sft_address<Extension>());
        let key = EscrowKey { addr: account_addr, token_id };
        assert!(table::contains(&escrow_store.sfts, key), error::not_found(EESCROW_DEPOSIT_NOT_FOUND));
        let sft = table::remove(&mut escrow_store.sfts, key);

        event::emit_event<EscrowWithdrawEvent>(
            &mut escrow_store.withdraw_events,
            EscrowWithdrawEvent {
                extension_type: type_info::type_name<Extension>(),
                token_id,
                amount: sft.amount,
                recipient: account_addr,
            },
        );

        sft
    }

    public fun merge<Extension: store + drop + copy>(
        dst: &mut Sft<Extension>,
        source: Sft<Extension>,
    ) {
        assert!(dst.token_id == source.token_id, error::invalid_argument(ETOKEN_ID_MISMATCH));
        dst.amount = dst.amount + source.amount;
        let Sft { token_id: _, amount: _ } = source;
    }

    public fun extract<Extension: store + drop + copy>(
        sft: &mut Sft<Extension>,
        amount: u64,
    ): Sft<Extension> {
        assert!(sft.amount >= amount, error::invalid_argument(EINSUFFICIENT_BALANCE));

        sft.amount = sft.amount - amount;
        Sft { token_id: sft.token_id, amount }
    }

    fun sft_address<Extension: store + drop + copy>(): address {
        let type_info = type_info::type_of<Extension>();
        type_info::account_address(&type_info)
    }

    fun check_collection_exists<Extension: store + drop + copy>() {
        assert!(
            collection_exists<Extension>(),
            error::not_found(ECOLLECTION_NOT_FOUND),
        );
    }

    fun check_is_registered<Extension: store + drop + copy>(addr: address) {
        assert!(
            is_account_registered<Extension>(addr),
            error::not_found(ESFT_STORE_NOT_FOUND),
        );
    }

    fun gen_escrow_iter<Extension: store + drop + copy>(addr: address): table::TableIter acquires EscrowStore {
        let escrow_store = borrow_global_mut<EscrowStore<Extension>>(sft_address<Extension>());
        let start_key = EscrowKey { addr, token_id: string::utf8(b"") };

        table::iter(
            &escrow_store.sfts,
            option::some(start_key),
            option::none(),
            1
        )
    }

    #[test_only]
    public fun init_module_for_test(
        chain: &signer
    ) {
        init_module(chain);
    }

    #[test_only]
    struct Metadata has store, drop, copy {
        power: u64,
    }

    #[test_only]
    struct CapabilityStore has key {
        cap: Capability<Metadata>
    }

    #[test_only]
    fun make_collection_for_test(account: &signer): Capability<Metadata> acquires ModuleStore {
        // make collection
        let name = string::utf8(b"Collection");
        let symbol = string::utf8(b"COL");
        let uri = string::utf8(b"https://collection.com");
        let is_mutable = true;
        make_collection<Metadata>(
            account,
            name,
            symbol,
            uri,
            is_mutable,
        )
    }

    #[test(source = @0x1, destination = @0x2)]
    fun end_to_end(
        source: signer,
        destination: signer,
    ) acquires EscrowStore, ModuleStore, SftCollection, SftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);

        let name = string::utf8(b"Collection");
        let symbol = string::utf8(b"COL");
        let uri = string::utf8(b"https://collection.com");
        let is_mutable = true;

        // check collection
        let collection = borrow_global<SftCollection<Metadata>>(source_addr);
        assert!(collection.name == name, 0);
        assert!(collection.symbol == symbol, 1);
        assert!(collection.uri == uri, 2);
        assert!(collection.is_mutable == is_mutable, 3);

        // register
        register<Metadata>(&source);
        register<Metadata>(&destination);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        // add SFT info
        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(source_addr, sft);

        // check minted token
        let token_store = borrow_global<SftStore<Metadata>>(source_addr);
        let sft = table::borrow(&token_store.sfts, string::utf8(b"id:1"));

        assert!(sft.amount == 100, 4);
        assert!(sft.token_id == token_id, 5);

        transfer<Metadata>(
            &source,
            destination_addr,
            string::utf8(b"id:1"),
            10,
        );
        // check transfered
        assert!(get_balance<Metadata>(destination_addr, string::utf8(b"id:1")) == 10, 7);
        assert!(get_balance<Metadata>(source_addr, string::utf8(b"id:1")) == 90, 8);

        let sft = withdraw<Metadata>(&destination, string::utf8(b"id:1"), 5);
        // check withdrawn
        assert!(get_balance<Metadata>(destination_addr, string::utf8(b"id:1")) == 5, 9);

        let new_uri = string::utf8(b"https://new_url.com");
        let new_metadata = Metadata { power: 4321 };

        update_sft<Metadata>(
            string::utf8(b"id:1"),
            option::some<String>(new_uri),
            option::some<Metadata>(new_metadata),
            &cap,
        );

        // check token info
        let collection = borrow_global<SftCollection<Metadata>>(source_addr);
        let sft_info = table::borrow(&collection.sft_infos, string::utf8(b"id:1"));

        assert!(sft_info.uri == new_uri, 10);
        assert!(sft_info.extension == new_metadata, 11);

        deposit<Metadata>(destination_addr, sft);

        // check deposit
        let sft_store = borrow_global<SftStore<Metadata>>(destination_addr);
        assert!(table::contains(&sft_store.sfts, string::utf8(b"id:1")), 12);

        burn_script<Metadata>(&destination, string::utf8(b"id:1"), 3);
    
        assert!(get_balance<Metadata>(destination_addr, string::utf8(b"id:1")) == 7, 9);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(not_source = @0x2)]
    #[expected_failure(abort_code = 0x10000, location = Self)]
    fun fail_make_collection_address_mismatch(not_source: signer): Capability<Metadata> acquires ModuleStore {
        make_collection_for_test(&not_source)
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x80001, location = Self)]
    fun fail_make_collection_collection_already_exists(
        source: signer
    ) acquires ModuleStore {
        init_module_for_test(&source);
        let cap_1 = make_collection_for_test(&source);

        let cap_2 = make_collection_for_test(&source);

        move_to(
            &source,
            CapabilityStore { cap: cap_1 },
        );

        move_to(
            &source,
            CapabilityStore { cap: cap_2 },
        )
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x60003, location = Self)]
    fun fail_register(source: signer) acquires EscrowStore, ModuleStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        
        move_to(
            &source,
            CapabilityStore { cap: cap },
        );

        register<Metadata>(&source);
        register<Metadata>(&source);
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x60002, location = Self)]
    fun fail_mint_collection_not_found(source: signer) acquires EscrowStore, ModuleStore, SftCollection, SftStore {
        init_module_for_test(&source);
        // It is impossible to get Capability without make_collection, but somehow..
        let cap = Capability<Metadata> {};
        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(signer::address_of(&source), sft);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x80005, location = Self)]
    fun fail_make_token_token_id_exists(source: signer) acquires SftCollection, ModuleStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x50007, location = Self)]
    fun fail_mutate_not_mutable(source: signer) acquires EscrowStore, ModuleStore, SftCollection, SftStore {
        init_module_for_test(&source);
        // make collection
        let name = string::utf8(b"Collection");
        let symbol = string::utf8(b"COL");
        let collection = string::utf8(b"https://collection.com");
        let is_mutable = false;

        let cap = make_collection<Metadata>(
            &source,
            name,
            symbol,
            collection,
            is_mutable,
        );

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        register<Metadata>(&source);

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(signer::address_of(&source), sft);

        let new_uri = string::utf8(b"https://new_url.com");
        let new_metadata = Metadata { power: 4321 };

        update_sft<Metadata>(
            string::utf8(b"id:1"),
            option::some<String>(new_uri),
            option::some<Metadata>(new_metadata),
            &cap,
        );

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x60006, location = Self)]
    fun fail_mutate_token_id_not_found(source: signer) acquires EscrowStore, ModuleStore, SftCollection, SftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        register<Metadata>(&source);

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(signer::address_of(&source), sft);

        let new_uri = string::utf8(b"https://new_url.com");
        let new_metadata = Metadata { power: 4321 };

        update_sft<Metadata>(
            string::utf8(b"id:2"),
            option::some<String>(new_uri),
            option::some<Metadata>(new_metadata),
            &cap,
        );

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(source = @0x1, destination = @0x2)]
    fun test_escrow(source: signer, destination: signer) acquires EscrowStore, ModuleStore, SftCollection, SftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let _source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);
        let extension_type = type_info::type_name<Metadata>();

        register<Metadata>(&source);
        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com/1/");
        let extension = Metadata { power: 1 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(destination_addr, sft);

        let token_id = string::utf8(b"id:2");
        let uri = string::utf8(b"https://url.com/2/");
        let extension = Metadata { power: 2 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            50,
            &cap,
        );

        deposit(destination_addr, sft);

        let sft = mint<Metadata>(
            token_id,
            50,
            &cap,
        );

        deposit(destination_addr, sft);

        let token_id = string::utf8(b"id:3");
        let uri = string::utf8(b"https://url.com/3/");
        let extension = Metadata { power: 3 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(@0x3, sft);

        // check escrow deposit
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        let get_escrow_collection = get_escrow_collection(destination_addr, option::none(), 100);
        assert!(
            escrow_deposit == vector[
                EscrowDepositResponse{ token_id: string::utf8(b"id:1"), amount: 100 }, 
                EscrowDepositResponse{ token_id: string::utf8(b"id:2"), amount: 100 },
            ],
            0,
        );
        assert!(get_escrow_collection == vector[extension_type], 1);

        register<Metadata>(&destination);
        // check escrow deposit is empty after register
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        let get_escrow_collection = get_escrow_collection(destination_addr, option::none(), 100);
        assert!(escrow_deposit == vector[], 2);
        assert!(get_escrow_collection == vector[], 3);

        // check sft store after register
        let token_ids = token_ids<Metadata>(destination_addr, option::none(), 10);
        assert!(token_ids == vector[string::utf8(b"id:2"), string::utf8(b"id:1")], 4);
        let balances = get_balances<Metadata>(destination_addr, token_ids);
        assert!(balances == vector[100, 100], 5);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }


    #[test(source = @0x1, destination = @0x2)]
    fun test_withdraw_escrow_manually(source: signer, destination: signer) acquires EscrowStore, ModuleStore, SftCollection, SftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let _source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);

        register<Metadata>(&source);
                let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com/1/");
        let extension = Metadata { power: 1 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(destination_addr, sft);

        let token_id = string::utf8(b"id:2");
        let uri = string::utf8(b"https://url.com/2/");
        let extension = Metadata { power: 2 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(destination_addr, sft);

        // check escrow deposit
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        assert!(
            escrow_deposit == vector[
                EscrowDepositResponse{ token_id: string::utf8(b"id:1"), amount: 100 }, 
                EscrowDepositResponse{ token_id: string::utf8(b"id:2"), amount: 100 },
            ],
            0,
        );

        register_without_withdraw_escrow<Metadata>(&destination);
        withdraw_escrow_script<Metadata>(&destination, vector[string::utf8(b"id:1")]);
        // check escrow after withdraw
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        assert!(escrow_deposit == vector[EscrowDepositResponse{ token_id: string::utf8(b"id:2"), amount: 100 }], 1);
        let get_escrow_collection = get_escrow_collection(destination_addr, option::none(), 100);
        assert!(get_escrow_collection == vector[type_info::type_name<Metadata>()], 2);

        // check sft store after withdraw
        let token_ids = token_ids<Metadata>(destination_addr, option::none(), 10);
        assert!(token_ids == vector[string::utf8(b"id:1")], 3);
        let balances = get_balances<Metadata>(destination_addr, token_ids);
        assert!(balances == vector[100], 3);

        // after withdraw all deposit
        withdraw_escrow_script<Metadata>(&destination, vector[string::utf8(b"id:2")]);
        let get_escrow_collection = get_escrow_collection(destination_addr, option::none(), 100);
        assert!(get_escrow_collection == vector[], 4);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(source = @0x1)]
    fun test_query_functions(source: signer) acquires EscrowStore, ModuleStore, SftCollection, SftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let source_addr = signer::address_of(&source);

        assert!(!is_account_registered<Metadata>(source_addr), 0);

        register<Metadata>(&source);

        assert!(is_account_registered<Metadata>(source_addr), 1);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com/1/");
        let extension = Metadata { power: 1 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(signer::address_of(&source), sft);

        let sft_info = get_sft_info<Metadata>(token_id);
        assert!(
            sft_info == SftInfoResponse {
                token_id,
                uri,
                max_supply: option::none(),
                supply: 100,
                extension,
            },
            4,
        );

        let token_id = string::utf8(b"id:2");
        let uri = string::utf8(b"https://url.com/2/");
        let extension = Metadata { power: 2 };

        make_token<Metadata>(
            token_id,
            uri,
            option::none(),
            extension,
            &cap
        );

        let sft = mint<Metadata>(
            token_id,
            100,
            &cap,
        );

        deposit(signer::address_of(&source), sft);


        let sft_infos = get_sft_infos<Metadata>(vector[string::utf8(b"id:1"), string::utf8(b"id:2")]);

        let sft_info1 = vector::borrow(&sft_infos, 0);
        let sft_info2 = vector::borrow(&sft_infos, 1);

        assert!(
            sft_info1 == &SftInfoResponse {
                token_id: string::utf8(b"id:1"),
                uri: string::utf8(b"https://url.com/1/"),
                max_supply: option::none(),
                supply: 100,
                extension: Metadata { power: 1 },
            },
            5,
        );

        assert!(
            sft_info2 == &SftInfoResponse {
                token_id: string::utf8(b"id:2"),
                uri: string::utf8(b"https://url.com/2/"),
                max_supply: option::none(),
                supply: 100,
                extension: Metadata { power: 2 },
            },
            6,
        );

        let token_ids = all_token_ids<Metadata>(option::none(), 10);

        assert!(token_ids == vector[string::utf8(b"id:2"), string::utf8(b"id:1")], 7);

        let token_ids = all_token_ids<Metadata>(option::none(), 1);

        assert!(token_ids == vector[string::utf8(b"id:2")], 8);

        let token_ids = all_token_ids<Metadata>(option::some(string::utf8(b"id:2")), 10);

        assert!(token_ids == vector[string::utf8(b"id:1")], 9);

        let token_ids = token_ids<Metadata>(signer::address_of(&source), option::none(), 10);

        assert!(token_ids == vector[string::utf8(b"id:2"), string::utf8(b"id:1")], 7);

        let token_ids = token_ids<Metadata>(signer::address_of(&source), option::none(), 1);

        assert!(token_ids == vector[string::utf8(b"id:2")], 8);

        let token_ids = token_ids<Metadata>(signer::address_of(&source), option::some(string::utf8(b"id:2")), 10);

        assert!(token_ids == vector[string::utf8(b"id:1")], 9);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }
}
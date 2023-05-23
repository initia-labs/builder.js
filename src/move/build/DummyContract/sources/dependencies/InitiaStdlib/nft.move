module initia_std::nft {
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

    /// Only chain can execute.
    const EUNAUTHORIZED: u64 = 1;

    /// signer must be extension publisher
    const ENFT_ADDRESS_MISMATCH: u64 = 2;

    /// collection already exists
    const ECOLLECTION_ALREADY_EXISTS: u64 = 3;

    /// collection not found
    const ECOLLECTION_NOT_FOUND: u64 = 4;

    /// nft store already exists
    const ENFT_STORE_ALREADY_EXISTS: u64 = 5;

    /// nft store not found
    const ENFT_STORE_NOT_FOUND: u64 = 6;

    /// token_id is taken
    const ETOKEN_ID_ALREADY_EXISTS: u64 = 7;

    /// token_id not found
    const ETOKEN_ID_NOT_FOUND: u64 = 8;

    /// can not update nft that is_mutable is false
    const ENOT_MUTABLE: u64 = 9;

    /// can not query more than `MAX_LIMIT`
    const EMAX_LIMIT: u64 = 10;

    /// escrow deposit not found
    const EESCROW_DEPOSIT_NOT_FOUND: u64 = 11;

    /// Name of the collection is too long
    const ECOLLECTION_NAME_TOO_LONG: u64 = 12;

    /// Symbol of the collection is too long
    const ECOLLECTION_SYMBOL_TOO_LONG: u64 = 13;


    // constant

    /// Max length of query response
    const MAX_LIMIT: u8 = 30;

    // allow long name & symbol to allow ibc class trace
    const MAX_COLLECTION_NAME_LENGTH: u64 = 256;
    const MAX_COLLECTION_SYMBOL_LENGTH: u64 = 256;

    // Data structures

    /// Capability required to mint and update nfts.
    struct Capability<phantom Extension: store + drop + copy> has copy, store {}

    /// Collection information
    struct NftCollection<Extension: store + drop + copy> has key {
        /// Name of the collection
        name: String,
        /// Symbol of the collection
        symbol: String,
        /// collection uri
        uri: String,
        /// Total supply of NFT
        supply: u64,
        /// Mutability of extension and uri
        is_mutable: bool,
        /// All nft information
        nft_infos: Table<String, NftInfo<Extension>>,

        update_events: EventHandle<UpdateEvent>,
        mint_events: EventHandle<MintEvent>,
        burn_events: EventHandle<BurnEvent>,
    }

    /// The holder storage for specific nft collection 
    struct NftStore<phantom Extension> has key {
        nfts: Table<String, Nft<Extension>>,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
    }
    
    /// key for nft escrow
    struct EscrowKey has copy, drop {
        addr: address,
        token_id: String,
    }

    /// Escrow nft store for the unregistered accounts
    struct EscrowStore<phantom Extension> has key {
        nfts: Table<EscrowKey, Nft<Extension>>,
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

    /// NFT Information
    struct NftInfo<Extension: store + drop + copy> has store {
        token_id: String,
        uri: String,
        extension: Extension,
    }

    struct Nft<phantom Extension> has store {
        token_id: String,
    }

    struct DepositEvent has drop, store {
        extension_type: String,
        token_id: String,
    }

    struct WithdrawEvent has drop, store {
        extension_type: String,
        token_id: String,
    }

    struct MintEvent has drop, store {
        extension_type: String,
        token_id: String,
    }

    struct BurnEvent has drop, store {
        extension_type: String,
        token_id: String,
    }

    /// Event emitted when nft is deposited into an account.
    struct EscrowDepositEvent has drop, store {
        extension_type: String,
        token_id: String,
        recipient: address,
    }

    /// Event emitted when nft is withdrawn from an account.
    struct EscrowWithdrawEvent has drop, store {
        extension_type: String,
        token_id: String,
        recipient: address,
    }

    struct UpdateEvent has drop, store {
        extension_type: String,
        token_id: String,
    }

    /// response structure for NftInfo
    struct NftInfoResponse<Extension> has drop {
        token_id: String,
        uri: String,
        extension: Extension,
    }

    /// response structure for Collection
    struct NftCollectionInfoResponse has drop {
        name: String,
        symbol: String,
        uri: String,
        supply: u64,
        is_mutable: bool,
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
    /// Return true if `NftStore` is published
    public fun is_account_registered<Extension: store + drop + copy>(addr: address): bool {
        exists<NftStore<Extension>>(addr)
    }

    #[view]
    /// Return true if collection exists
    public fun collection_exists<Extension: store + drop + copy>(): bool {
        let creator = nft_address<Extension>();
        exists<NftCollection<Extension>>(creator)
    }

    #[view]
    /// Return `token_id` existence
    public fun is_exists<Extension: store + drop + copy>(
        token_id: String
    ): bool acquires NftCollection {
        check_collection_exists<Extension>();

        let creator = nft_address<Extension>();
        let collection = borrow_global<NftCollection<Extension>>(creator);

        table::contains<String, NftInfo<Extension>>(&collection.nft_infos, token_id)
    }

    #[view]
    /// Return collection info
    public fun get_collection_info<Extension: store + drop + copy>(): NftCollectionInfoResponse acquires NftCollection {
        check_collection_exists<Extension>();

        let creator = nft_address<Extension>();
        let collection = borrow_global<NftCollection<Extension>>(creator);

        NftCollectionInfoResponse {
            name: collection.name,
            symbol: collection.symbol,
            uri: collection.uri,
            supply: collection.supply,
            is_mutable: collection.is_mutable,
        }
    }

    #[view]
    /// Return nft_info
    public fun get_nft_info<Extension: store + drop + copy>(
        token_id: String,
    ): NftInfoResponse<Extension> acquires NftCollection {
        check_collection_exists<Extension>();

        let creator = nft_address<Extension>();
        let collection = borrow_global<NftCollection<Extension>>(creator);

        assert!(
            table::contains<String, NftInfo<Extension>>(&collection.nft_infos, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        let nft_info = table::borrow<String, NftInfo<Extension>>(&collection.nft_infos, token_id);

        NftInfoResponse {
            token_id: nft_info.token_id,
            uri: nft_info.uri,
            extension: nft_info.extension,
        }
    }

    #[view]
    /// Return NftInfos
    public fun get_nft_infos<Extension: store + drop + copy>(
        token_ids: vector<String>,
    ): vector<NftInfoResponse<Extension>> acquires NftCollection {
        check_collection_exists<Extension>();

        assert!(
            vector::length(&token_ids) <= (MAX_LIMIT as u64),
            error::invalid_argument(EMAX_LIMIT),
        );

        let creator = nft_address<Extension>();
        let collection = borrow_global<NftCollection<Extension>>(creator);

        let res: vector<NftInfoResponse<Extension>> = vector[];

        let index = 0;

        let len = vector::length(&token_ids);
        while (index < len) {
            let token_id = *vector::borrow(&token_ids, index);

            assert!(
                table::contains<String, NftInfo<Extension>>(&collection.nft_infos, token_id),
                error::not_found(ETOKEN_ID_NOT_FOUND),
            );

            let nft_info = table::borrow<String, NftInfo<Extension>>(&collection.nft_infos, token_id);

            vector::push_back(
                &mut res,
                NftInfoResponse {
                    token_id: nft_info.token_id,
                    uri: nft_info.uri,
                    extension: nft_info.extension,
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
    ): vector<String> acquires NftCollection {
        check_collection_exists<Extension>();

        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        let creator = nft_address<Extension>();
        let collection = borrow_global<NftCollection<Extension>>(creator);

        let nft_info_iter = table::iter(
            &collection.nft_infos,
            option::none(),
            start_after,
            2,
        );

        let res: vector<String> = vector[];

        while (table::prepare<String, NftInfo<Extension>>(&mut nft_info_iter) && vector::length(&res) < (limit as u64)) {
            let (token_id, _token_info) = table::next<String, NftInfo<Extension>>(&mut nft_info_iter);

            vector::push_back(&mut res, token_id);
        };

        res
    }

    #[view]
    /// get all `token_id` from `NftStore` of user
    public fun token_ids<Extension: store + drop + copy>(
        owner: address,
        start_after: Option<String>,
        limit: u8,
    ): vector<String> acquires NftStore {
        check_collection_exists<Extension>();

        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        check_is_registered<Extension>(owner);

        let nft_store = borrow_global<NftStore<Extension>>(owner);

        let nfts_iter = table::iter(
            &nft_store.nfts,
            option::none(),
            start_after,
            2,
        );

        let res: vector<String> = vector[];

        while (table::prepare<String, Nft<Extension>>(&mut nfts_iter) && vector::length(&res) < (limit as u64)) {
            let (token_id, _token) = table::next<String, NftInfo<Extension>>(&mut nfts_iter);

            vector::push_back(&mut res, token_id);
        };

        res
    }

    #[view]
    /// get all `token_id` from `EscrowStore` of certain user and collection
    public fun get_escrow_deposit<Extension: store + drop + copy>(
        addr: address,
    ): vector<String> acquires EscrowStore {
        let res: vector<String> = vector[];
        let escrow_iter = gen_escrow_iter<Extension>(addr);

        while(table::prepare<EscrowKey, Nft<Extension>>(&mut escrow_iter)) {
            let (key, _nft) = table::next<EscrowKey, Nft<Extension>>(&mut escrow_iter);
            if (key.addr != addr) {
                break
            };

            vector::push_back(&mut res, key.token_id);
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

        while(vector::length(&res) < (limit as u64) && table::prepare<String, bool>(&mut escrow_iter)) {
            let (key, _) = table::next<String, bool>(&mut escrow_iter);
            vector::push_back(&mut res, key);
        };

        res
    }

    /// query helpers

    /// get `token_id` from `NftInfoResponse`
    public fun get_token_id_from_nft_info_response<Extension: store + drop + copy>(
        nft_info_res: &NftInfoResponse<Extension>,
    ): String {
        nft_info_res.token_id
    }

    /// get `uri` from `NftInfoResponse`
    public fun get_uri_from_nft_info_response<Extension: store + drop + copy>(
        nft_info_res: &NftInfoResponse<Extension>,
    ): String {
        nft_info_res.uri
    }

    /// get `extension` from `NftInfoResponse`
    public fun get_extension_from_nft_info_response<Extension: store + drop + copy>(
        nft_info_res: &NftInfoResponse<Extension>,
    ): Extension {
        nft_info_res.extension
    }

    public fun get_token_id_from_nft<Extension: store + drop + copy>(
        nft: &Nft<Extension>,
    ): String {
        nft.token_id
    }

    //
    // Execute entry functions
    //

    /// publish nft store
    public entry fun register<Extension: store + drop + copy>(account: &signer) acquires EscrowStore, ModuleStore {
        let addr = signer::address_of(account);
        assert!(
            !exists<NftStore<Extension>>(addr),
            error::not_found(ENFT_STORE_ALREADY_EXISTS),
        );

        let nfts = table::new<String, Nft<Extension>>();
        let token_ids = get_escrow_deposit<Extension>(addr);
        let len = vector::length(&token_ids);

        if (len != 0) {
            let index = 0;
            while(index < len) {
                let token_id = *vector::borrow(&token_ids, index);
                let nft = withdraw_escrow<Extension>(account, token_id);
                table::add(&mut nfts, token_id, nft);
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


        let nft_store = NftStore<Extension> {
            nfts,
            deposit_events: event::new_event_handle<DepositEvent>(account),
            withdraw_events: event::new_event_handle<WithdrawEvent>(account),
        };

        move_to(account, nft_store);
    }

    /// publish nft store without withdrawing escrow
    /// in case that there are too many nft in escrow store, register can occur lots of gas.
    /// user can just publish nft store and withdraw escrow deposited nft manually
    public entry fun register_without_withdraw_escrow<Extension: store + drop + copy>(account: &signer) {
        let addr = signer::address_of(account);
        assert!(
            !exists<NftStore<Extension>>(addr),
            error::not_found(ENFT_STORE_ALREADY_EXISTS),
        );

        let nft_store = NftStore<Extension> {
            nfts: table::new(),
            deposit_events: event::new_event_handle<DepositEvent>(account),
            withdraw_events: event::new_event_handle<WithdrawEvent>(account),
        };

        move_to(account, nft_store);
    }

    /// Burn nft from nft store
    public entry fun burn_script<Extension: store + drop + copy>(
        account: &signer,
        token_id: String,
    ) acquires NftCollection, NftStore {
        check_collection_exists<Extension>();

        let addr = signer::address_of(account);
        check_is_registered<Extension>(addr);

        let creator = nft_address<Extension>();
        let collection = borrow_global_mut<NftCollection<Extension>>(creator);

        assert!(
            table::contains<String, NftInfo<Extension>>(&collection.nft_infos, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        let nft = withdraw<Extension>(account, token_id);

        burn(nft);
    }

    /// Transfer nft from nft store to another nft store
    public entry fun transfer<Extension: store + drop + copy>(
        account: &signer,
        to: address,
        token_id: String,
    ) acquires EscrowStore, ModuleStore, NftStore {
        let nft = withdraw<Extension>(account, token_id);
        deposit<Extension>(to, nft);
    }

    /// withdraw nfts from EscrowStore manually
    public entry fun withdraw_escrow_script<Extension: store + drop + copy>(
        account: &signer,
        token_ids: vector<String>,
    ) acquires EscrowStore, ModuleStore, NftStore {
        let addr = signer::address_of(account);
        check_is_registered<Extension>(addr);
        let len = vector::length(&token_ids);
        let index = 0;
        while(index < len) {
            let token_id = *vector::borrow(&token_ids, index);
            let nft = withdraw_escrow<Extension>(account, token_id);
            deposit(addr, nft);
            index = index + 1;
        };

        let escrow_iter = gen_escrow_iter<Extension>(addr);
        let is_prepare = table::prepare<EscrowKey, Nft<Extension>>(&mut escrow_iter);
        let escrow_exists = if (is_prepare) {
            let (key, _) = table::next<EscrowKey, Nft<Extension>>(&mut escrow_iter);
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
    ): Capability<Extension> acquires ModuleStore {
        let creator = signer::address_of(account);

        assert!(
            nft_address<Extension>() == creator,
            error::invalid_argument(ENFT_ADDRESS_MISMATCH),
        );

        assert!(
            !exists<NftCollection<Extension>>(creator),
            error::already_exists(ECOLLECTION_ALREADY_EXISTS),
        );

        assert!(string::length(&name) <= MAX_COLLECTION_NAME_LENGTH, error::invalid_argument(ECOLLECTION_NAME_TOO_LONG));
        assert!(string::length(&symbol) <= MAX_COLLECTION_SYMBOL_LENGTH, error::invalid_argument(ECOLLECTION_SYMBOL_TOO_LONG));

        let collection = NftCollection<Extension> {
            name,
            symbol,
            uri,
            supply: 0,
            is_mutable,
            nft_infos: table::new<String, NftInfo<Extension>>(),
            update_events: event::new_event_handle<UpdateEvent>(account),
            mint_events: event::new_event_handle<MintEvent>(account),
            burn_events: event::new_event_handle<BurnEvent>(account),
        };

        move_to(account, collection);

        let escrow_store = EscrowStore<Extension> {
            nfts: table::new(),
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

    /// Mint new nft
    public fun mint<Extension: store + drop + copy>(
        token_id: String,
        token_uri: String,
        token_data: Extension,
        _capability: &Capability<Extension>,
    ): Nft<Extension> acquires NftCollection, {
        check_collection_exists<Extension>();

        let creator = nft_address<Extension>();
        let collection = borrow_global_mut<NftCollection<Extension>>(creator);

        collection.supply = collection.supply + 1;

        assert!(
            !table::contains<String, NftInfo<Extension>>(&collection.nft_infos, token_id),
            error::already_exists(ETOKEN_ID_ALREADY_EXISTS),
        );

        let nft_info = NftInfo<Extension> { token_id, uri: token_uri, extension: token_data };

        let nft = Nft<Extension> { token_id };

        table::add<String, NftInfo<Extension>>(&mut collection.nft_infos, token_id, nft_info);

        event::emit_event<MintEvent>(
            &mut collection.mint_events,
            MintEvent { token_id, extension_type: type_info::type_name<Extension>() },
        );

        nft
    }

    /// update uri/extension
    public fun update_nft<Extension: store + drop + copy>(
        token_id: String,
        uri: Option<String>,
        extension: Option<Extension>,
        _capability: &Capability<Extension>,
    ) acquires NftCollection {
        check_collection_exists<Extension>();

        let creator = nft_address<Extension>();
        let collection = borrow_global_mut<NftCollection<Extension>>(creator);

        assert!(
            table::contains<String, NftInfo<Extension>>(&collection.nft_infos, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        assert!(
            collection.is_mutable,
            error::permission_denied(ENOT_MUTABLE),
        );

        let nft_info = table::borrow_mut<String, NftInfo<Extension>>(&mut collection.nft_infos, token_id);

        if (option::is_some<String>(&uri)) {
            let new_uri = option::extract<String>(&mut uri);
            nft_info.uri = new_uri;
        };

        if (option::is_some<Extension>(&extension)) {
            let new_extension = option::extract<Extension>(&mut extension);
            nft_info.extension = new_extension;
        };

        event::emit_event<UpdateEvent>(
            &mut collection.update_events,
            UpdateEvent { token_id, extension_type: type_info::type_name<Extension>() },
        );
    }

    /// withdraw nft from token_store
    public fun withdraw<Extension: store + drop + copy>(
        account: &signer,
        token_id: String,
    ): Nft<Extension> acquires NftStore {
        let account_addr = signer::address_of(account);

        assert!(
            contains<Extension>(account_addr, token_id),
            error::not_found(ETOKEN_ID_NOT_FOUND),
        );

        let nft_store = borrow_global_mut<NftStore<Extension>>(account_addr);
        event::emit_event<WithdrawEvent>(
            &mut nft_store.withdraw_events,
            WithdrawEvent { token_id, extension_type: type_info::type_name<Extension>() },
        );

        table::remove<String, Nft<Extension>>(&mut nft_store.nfts, token_id)
    }

    /// deposit token to token_store
    public fun deposit<Extension: store + drop + copy>(
        addr: address,
        nft: Nft<Extension>
    ) acquires EscrowStore, ModuleStore, NftStore {
        check_collection_exists<Extension>();
        if (!is_account_registered<Extension>(addr)) {
            return deposit_escrow(addr, nft)
        };

        let nft_store = borrow_global_mut<NftStore<Extension>>(addr);

        event::emit_event<DepositEvent>(
            &mut nft_store.deposit_events,
            DepositEvent { token_id: nft.token_id, extension_type: type_info::type_name<Extension>() },
        );

        table::add<String, Nft<Extension>>(&mut nft_store.nfts, nft.token_id, nft);
    }

    /// burn nft
    public fun burn<Extension: store + drop + copy>(nft: Nft<Extension>) acquires NftCollection {
        let creator = nft_address<Extension>();

        let collection = borrow_global_mut<NftCollection<Extension>>(creator);

        let Nft { token_id } = nft;

        let NftInfo { token_id: _, uri: _, extension: _ }
            = table::remove<String, NftInfo<Extension>>(&mut collection.nft_infos, token_id);

        collection.supply = collection.supply - 1;

        event::emit_event<BurnEvent>(
            &mut collection.burn_events,
            BurnEvent { token_id, extension_type: type_info::type_name<Extension>() },
        );
    }

    /// Deposit nft into the escrow store
    fun deposit_escrow<Extension: store + drop + copy>(
        account_addr: address,
        nft: Nft<Extension>,
    ) acquires EscrowStore, ModuleStore {
        let escrow_store = borrow_global_mut<EscrowStore<Extension>>(nft_address<Extension>());
        let token_id = nft.token_id;
        let key = EscrowKey { addr: account_addr, token_id };
        table::add(&mut escrow_store.nfts, key, nft);

        event::emit_event<EscrowDepositEvent>(
            &mut escrow_store.deposit_events,
            EscrowDepositEvent {
                extension_type: type_info::type_name<Extension>(),
                token_id, 
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

    /// Withdraw nft from the escrow store
    fun withdraw_escrow<Extension: store + drop + copy>(account: &signer, token_id: String): Nft<Extension> acquires EscrowStore {
        let account_addr = signer::address_of(account);
        let escrow_store = borrow_global_mut<EscrowStore<Extension>>(nft_address<Extension>());
        let key = EscrowKey { addr: account_addr, token_id };
        assert!(table::contains(&escrow_store.nfts, key), error::not_found(EESCROW_DEPOSIT_NOT_FOUND));

        event::emit_event<EscrowWithdrawEvent>(
            &mut escrow_store.withdraw_events,
            EscrowWithdrawEvent {
                extension_type: type_info::type_name<Extension>(),
                token_id,
                recipient: account_addr,
            },
        );

        table::remove(&mut escrow_store.nfts, key)
    }

    /// check `NftStore` has certain `token_id`
    public fun contains<Extension: store + drop + copy>(
        addr: address,
        token_id: String,
    ): bool acquires NftStore {
        check_collection_exists<Extension>();
        check_is_registered<Extension>(addr);

        let nft_store = borrow_global_mut<NftStore<Extension>>(addr);

        table::contains<String, Nft<Extension>>(&nft_store.nfts, token_id)
    }

    fun nft_address<Extension: store + drop + copy>(): address {
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
            error::not_found(ENFT_STORE_NOT_FOUND),
        );
    }

    fun gen_escrow_iter<Extension: store + drop + copy>(addr: address): table::TableIter acquires EscrowStore {
        let escrow_store = borrow_global_mut<EscrowStore<Extension>>(nft_address<Extension>());
        let start_key = EscrowKey { addr, token_id: string::utf8(b"") };

        table::iter(
            &escrow_store.nfts,
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
    ) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);

        let name = string::utf8(b"Collection");
        let symbol = string::utf8(b"COL");
        let uri = string::utf8(b"https://collection.com");
        let is_mutable = true;

        // check collection
        let collection = borrow_global<NftCollection<Metadata>>(source_addr);
        assert!(collection.name == name, 0);
        assert!(collection.symbol == symbol, 1);
        assert!(collection.uri == uri, 2);
        assert!(collection.is_mutable == is_mutable, 3);
        assert!(collection.supply == 0, 4);

        // register
        register<Metadata>(&source);
        register<Metadata>(&destination);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );

        deposit(source_addr, nft);

        // check minted token
        let token_store = borrow_global<NftStore<Metadata>>(source_addr);
        let nft = table::borrow(&token_store.nfts, string::utf8(b"id:1"));

        assert!(nft.token_id == token_id, 5);

        // check token_count
        let collection = borrow_global<NftCollection<Metadata>>(source_addr);

        assert!(collection.supply == 1, 6);

        transfer<Metadata>(
            &source,
            destination_addr,
            string::utf8(b"id:1"),
        );
        // check transfered
        let nft_store = borrow_global<NftStore<Metadata>>(destination_addr);
        assert!(table::contains(&nft_store.nfts, string::utf8(b"id:1")), 7);
        let nft_store = borrow_global<NftStore<Metadata>>(source_addr);
        assert!(!table::contains(&nft_store.nfts, string::utf8(b"id:1")), 8);

        let nft = withdraw<Metadata>(&destination, string::utf8(b"id:1"));
        // check withdrawn
        let nft_store = borrow_global<NftStore<Metadata>>(destination_addr);
        assert!(!table::contains(&nft_store.nfts, string::utf8(b"id:1")), 9);

        let new_uri = string::utf8(b"https://new_url.com");
        let new_metadata = Metadata { power: 4321 };

        update_nft<Metadata>(
            string::utf8(b"id:1"),
            option::some<String>(new_uri),
            option::some<Metadata>(new_metadata),
            &cap,
        );

        // check token info
        let collection = borrow_global<NftCollection<Metadata>>(source_addr);
        let nft_info = table::borrow(&collection.nft_infos, string::utf8(b"id:1"));

        assert!(nft_info.uri == new_uri, 10);
        assert!(nft_info.extension == new_metadata, 11);

        deposit<Metadata>(destination_addr, nft);

        // check deposit
        let nft_store = borrow_global<NftStore<Metadata>>(destination_addr);
        assert!(table::contains(&nft_store.nfts, string::utf8(b"id:1")), 12);

        burn_script<Metadata>(&destination, string::utf8(b"id:1"));

        let nft_store = borrow_global<NftStore<Metadata>>(destination_addr);
        assert!(!table::contains(&nft_store.nfts, string::utf8(b"id:1")), 13);

        // check burn

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(not_source = @0x2)]
    #[expected_failure(abort_code = 0x10002, location = Self)]
    fun fail_make_collection_address_mismatch(not_source: signer): Capability<Metadata> acquires ModuleStore {
        make_collection_for_test(&not_source)
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x80003, location = Self)]
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
    #[expected_failure(abort_code = 0x60005, location = Self)]
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
    #[expected_failure(abort_code = 0x60004, location = Self)]
    fun fail_mint_collection_not_found(source: signer) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let source_addr = signer::address_of(&source);
        // It is impossible to get Capability without make_collection, but somehow..
        let cap = Capability<Metadata> {};
        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );

        deposit(source_addr, nft);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x80007, location = Self)]
    fun fail_mint_token_id_exists(source: signer) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let source_addr = signer::address_of(&source);
        let cap = make_collection_for_test(&source);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        register<Metadata>(&source);

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(source_addr, nft);

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(source_addr, nft);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }

    #[test(source = @0x1)]
    #[expected_failure(abort_code = 0x50009, location = Self)]
    fun fail_mutate_not_mutable(source: signer) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let source_addr = signer::address_of(&source);
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

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );

        deposit(source_addr, nft);

        let new_uri = string::utf8(b"https://new_url.com");
        let new_metadata = Metadata { power: 4321 };

        update_nft<Metadata>(
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
    #[expected_failure(abort_code = 0x60008, location = Self)]
    fun fail_mutate_token_id_not_found(source: signer) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let source_addr = signer::address_of(&source);
        let cap = make_collection_for_test(&source);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com");
        let extension = Metadata { power: 1234 };

        register<Metadata>(&source);

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(source_addr, nft);

        let new_uri = string::utf8(b"https://new_url.com");
        let new_metadata = Metadata { power: 4321 };

        update_nft<Metadata>(
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
    fun test_escrow(source: signer, destination: signer) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let _source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);
        let extension_type = type_info::type_name<Metadata>();

        register<Metadata>(&source);
        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com/1/");
        let extension = Metadata { power: 1 };

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(destination_addr, nft);

        let token_id = string::utf8(b"id:2");
        let uri = string::utf8(b"https://url.com/2/");
        let extension = Metadata { power: 2 };

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(destination_addr, nft);

        let token_id = string::utf8(b"id:3");
        let uri = string::utf8(b"https://url.com/3/");
        let extension = Metadata { power: 3 };

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(@0x3, nft);

        // check escrow deposit
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        let get_escrow_collection = get_escrow_collection(destination_addr, option::none(), 100);
        assert!(escrow_deposit == vector[string::utf8(b"id:1"), string::utf8(b"id:2")], 0);
        assert!(get_escrow_collection == vector[extension_type], 1);

        register<Metadata>(&destination);
        // check escrow deposit is empty after register
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        let get_escrow_collection = get_escrow_collection(destination_addr, option::none(), 100);
        assert!(escrow_deposit == vector[], 2);
        assert!(get_escrow_collection == vector[], 3);

        // check nft store after register
        let token_ids = token_ids<Metadata>(destination_addr, option::none(), 10);
        assert!(token_ids == vector[string::utf8(b"id:2"), string::utf8(b"id:1")], 4);

        move_to(
            &source,
            CapabilityStore { cap: cap },
        )
    }


    #[test(source = @0x1, destination = @0x2)]
    fun test_withdraw_escrow_manually(
        source: signer,
        destination: signer,
    ) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let _source_addr = signer::address_of(&source);
        let destination_addr = signer::address_of(&destination);

        register<Metadata>(&source);
        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com/1/");
        let extension = Metadata { power: 1 };

        assert!(!is_exists<Metadata>(token_id), 2);

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(destination_addr, nft);

        let token_id = string::utf8(b"id:2");
        let uri = string::utf8(b"https://url.com/2/");
        let extension = Metadata { power: 2 };

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(destination_addr, nft);

        // check escrow deposit
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        assert!(escrow_deposit == vector[string::utf8(b"id:1"), string::utf8(b"id:2")], 0);

        register_without_withdraw_escrow<Metadata>(&destination);
        withdraw_escrow_script<Metadata>(&destination, vector[string::utf8(b"id:1")]);
        // check escrow after withdraw
        let escrow_deposit = get_escrow_deposit<Metadata>(destination_addr);
        assert!(escrow_deposit == vector[string::utf8(b"id:2")], 1);
        let get_escrow_collection = get_escrow_collection(destination_addr, option::none(), 100);
        assert!(get_escrow_collection == vector[type_info::type_name<Metadata>()], 2);

        // check nft store after withdraw
        let token_ids = token_ids<Metadata>(destination_addr, option::none(), 10);
        assert!(token_ids == vector[string::utf8(b"id:1")], 3);

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
    fun test_query_functions(source: signer) acquires EscrowStore, ModuleStore, NftCollection, NftStore {
        init_module_for_test(&source);
        let cap = make_collection_for_test(&source);
        let source_addr = signer::address_of(&source);

        assert!(!is_account_registered<Metadata>(source_addr), 0);

        register<Metadata>(&source);

        assert!(is_account_registered<Metadata>(source_addr), 1);

        let token_id = string::utf8(b"id:1");
        let uri = string::utf8(b"https://url.com/1/");
        let extension = Metadata { power: 1 };

        assert!(!is_exists<Metadata>(token_id), 2);

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(source_addr, nft);

        assert!(is_exists<Metadata>(token_id), 3);

        let nft_info = get_nft_info<Metadata>(token_id);
        assert!(
            nft_info == NftInfoResponse {
                token_id,
                uri,
                extension,
            },
            4,
        );

        let token_id = string::utf8(b"id:2");
        let uri = string::utf8(b"https://url.com/2/");
        let extension = Metadata { power: 2 };

        let nft = mint<Metadata>(
            token_id,
            uri,
            extension,
            &cap,
        );
        deposit(source_addr, nft);

        let nft_infos = get_nft_infos<Metadata>(vector[string::utf8(b"id:1"), string::utf8(b"id:2")]);

        let nft_info1 = vector::borrow(&nft_infos, 0);
        let nft_info2 = vector::borrow(&nft_infos, 1);

        assert!(
            nft_info1 == &NftInfoResponse {
                token_id: string::utf8(b"id:1"),
                uri: string::utf8(b"https://url.com/1/"),
                extension: Metadata { power: 1 },
            },
            5,
        );

        assert!(
            nft_info2 == &NftInfoResponse {
                token_id: string::utf8(b"id:2"),
                uri: string::utf8(b"https://url.com/2/"),
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
module initia_std::dex {
    use std::error;
    use std::event::{Self, EventHandle};
    use std::option::{Self, Option};
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use initia_std::block::get_block_info;
    use initia_std::coin::{Self, Coin};
    use initia_std::decimal128::{Self, Decimal128};
    use initia_std::table::{Self, Table};
    use initia_std::type_info;

    friend initia_std::staking;

    // Errors

    /// Event sotre is already published
    const EEVENT_STORE_ALREADY_PUBLISHED: u64 = 1;

    /// Can not withdraw zero liquidity
    const EZERO_LIQUIDITY: u64 = 2;

    /// Return amount is smaller than the `min_return`
    const EMIN_RETURN: u64 = 3;

    /// Return liquidity amount is smaller than the `min_liquidity_amount`
    const EMIN_LIQUIDITY: u64 = 4;

    /// Returning coin amount of the result of the liquidity withdraw is smaller than min return
    const EMIN_WITHDRAW: u64 = 5;

    /// Base must be in the range of 0 < base < 2
    const EOUT_OF_BASE_RANGE: u64 = 6;

    /// Only chain can execute.
    const EUNAUTHORIZED: u64 = 7;

    /// Fee rate must be smaller than 1
    const EOUT_OF_SWAP_FEE_RATE_RANGE: u64 = 8;

    /// end time must be larger than start time
    const EWEIGHTS_TIMESTAMP: u64 = 9;

    /// Wrong coin type given
    const ECOIN_TYPE: u64 = 10;

    /// Exceed max price impact
    const EPRICE_IMPACT: u64 = 11;

    /// The pair is already listed
    const EPAIR_ALREADY_LISTED: u64 = 12;

    /// The pair is not listed
    const EPAIR_NOT_LISTED: u64 = 13;

    /// LBP is not started, can not swap yet
    const ELBP_NOT_STARTED: u64 = 14;

    /// LBP is not ended, only swap allowed
    const ELBP_NOT_ENDED: u64 = 15;

    /// LBP start time must be larger than current time
    const ELBP_START_TIME: u64 = 16;

    /// All start_after must be provided or not
    const ESTART_AFTER: u64 = 17;

    /// LP token is not found from the store
    const ELIQUIDITY_TOKEN_NOT_FOUND: u64 = 18;

    // Constants
    const MAX_LIMIT: u8 = 30;

    // TODO - find the resonable percision
    /// Result Precision of `pow` and `ln` function
    const PRECISION: u128 = 100000;

    /// Pool of pair
    struct Pool<phantom CoinA, phantom CoinB, phantom LiquidityToken> has key {
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
    }

    /// Config of the pair
    struct Config<phantom CoinA, phantom CoinB, phantom LiquidityToken> has key {
        weights: Weights,
        swap_fee_rate: Decimal128,
    }

    struct Weights has copy, drop, store {
        weights_before: Weight,
        weights_after: Weight,
    }

    struct Weight has copy, drop, store {
        coin_a_weight: Decimal128,
        coin_b_weight: Decimal128,
        timestamp: u64,
    }

    /// Key for pair
    struct PairKey has copy, drop {
        coin_a_type: String,
        coin_b_type: String,
        liquidity_token_type: String,
    }

    /// Coin capabilities
    struct CoinCapabilities<phantom LiquidityToken> has key {
        burn_cap: coin::BurnCapability<LiquidityToken>,
        freeze_cap: coin::FreezeCapability<LiquidityToken>,
        mint_cap: coin::MintCapability<LiquidityToken>,
    }

    /// Module store for storing pair infos
    struct ModuleStore has key {
        pairs: Table<PairKey, PairResponse>,
        pair_count: u64,
        create_pair_event: EventHandle<CreatePairEvent>,
        swap_fee_update_event: EventHandle<SwapFeeUpdateEvent>,
    }

    struct CreatePairEvent has drop, store {
        coin_a_type: String,
        coin_b_type: String,
        liquidity_token_type: String,
        weights: Weights,
        swap_fee_rate: Decimal128,
    }

    struct SwapFeeUpdateEvent has drop, store {
        coin_a_type: String,
        coin_b_type: String,
        liquidity_token_type: String,
        swap_fee_rate: Decimal128,
    }

    /// Store for the events
    struct EventStore has key {
        provide_events: EventHandle<ProvideEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
        swap_events: EventHandle<SwapEvent>,
        single_asset_provide_events: EventHandle<SingleAssetProvideEvent>,
    }

    /// Event emitted when provide liquidity.
    struct ProvideEvent has drop, store {
        coin_a_type: String,
        coin_b_type: String,
        liquidity_token_type: String,
        coin_a_amount: u64,
        coin_b_amount: u64,
        liquidity: u64,
    }

    /// Event emitted when withdraw liquidity.
    struct WithdrawEvent has drop, store {
        coin_a_type: String,
        coin_b_type: String,
        liquidity_token_type: String,
        coin_a_amount: u64,
        coin_b_amount: u64,
        liquidity: u64,
    }

    /// Event emitted when swap token.
    struct SwapEvent has drop, store {
        offer_coin_type: String,
        return_coin_type: String,
        liquidity_token_type: String,
        offer_amount: u64,
        return_amount: u64,
        fee_amount: u64,
    }

    struct SingleAssetProvideEvent has drop, store {
        coin_a_type: String,
        coin_b_type: String,
        liquidity_token_type: String,
        provide_coin_type: String,
        provide_amount: u64,
        fee_amount: u64,
        liquidity: u64,
    }

    struct PoolInfoResponse has drop {
        coin_a_amount: u64,
        coin_b_amount: u64,
        total_share: u128,
    }

    struct ConfigResponse has drop {
        weights: Weights,
        swap_fee_rate: Decimal128,
    }

    struct CurrentWeightResponse has drop {
        coin_a_weight: Decimal128,
        coin_b_weight: Decimal128,
    }

    struct PairResponse has copy, drop, store {
        coin_a_type: String,
        coin_b_type: String,
        liquidity_token_type: String,
        weights: Weights,
        swap_fee_rate: Decimal128,
    }

    //
    // Check functions
    // 

    fun check_listed<CoinA, CoinB, LiquidityToken>() {
        assert!(
            is_listed<CoinA, CoinB, LiquidityToken>(),
            error::invalid_state(EPAIR_NOT_LISTED),
        );
    }

    //
    // Query entry functions
    //
    
    #[view]
    /// return `true` if the pair is listed on dex
    public fun is_listed<CoinA, CoinB, LiquidityToken>(): bool {
        exists<Config<CoinA, CoinB, LiquidityToken>>(coin_address<LiquidityToken>())
    }

    #[view]
    /// Returns `true` if `account_addr` is registered.
    public fun is_account_registered(account_addr: address): bool {
        exists<EventStore>(account_addr)
    }

    #[view]
    public fun pool_info<CoinA, CoinB, LiquidityToken>(lbp_assertion: bool): (u64, u64, Decimal128, Decimal128, Decimal128) acquires Config, Pool {
        let owner_addr = coin_address<LiquidityToken>();
        if (is_listed<CoinA, CoinB, LiquidityToken>()){
            let config = borrow_global<Config<CoinA, CoinB, LiquidityToken>>(owner_addr);
            if (lbp_assertion) {
                // assert LBP start time
                let (_, timestamp) = get_block_info();
                assert!(timestamp >= config.weights.weights_before.timestamp, error::invalid_state(ELBP_NOT_STARTED));
            };

            let pool = borrow_global<Pool<CoinA, CoinB, LiquidityToken>>(owner_addr);
            let (coin_a_weight, coin_b_weight) = get_weight(&config.weights);

            (coin::value(&pool.coin_a), coin::value(&pool.coin_b), coin_a_weight, coin_b_weight, config.swap_fee_rate)
        } else {
            check_listed<CoinB, CoinA, LiquidityToken>();

            let config = borrow_global<Config<CoinB, CoinA, LiquidityToken>>(owner_addr);
            if (lbp_assertion) {
                // assert LBP start time
                let (_, timestamp) = get_block_info();
                assert!(timestamp >= config.weights.weights_before.timestamp, error::invalid_state(ELBP_NOT_STARTED));
            };

            let pool = borrow_global<Pool<CoinB, CoinA, LiquidityToken>>(owner_addr);
            let (coin_a_weight, coin_b_weight) = get_weight(&config.weights);

            (coin::value(&pool.coin_b), coin::value(&pool.coin_a), coin_b_weight, coin_a_weight, config.swap_fee_rate)
        }
    }

    #[view]
    /// Calculate spot price
    /// https://balancer.fi/whitepaper.pdf (2)
    public fun get_spot_price<BaseCoin, QuoteCoin, LiquidityToken>(): Decimal128 acquires Config, Pool {
        let (base_pool, quote_pool, base_weight, quote_weight, _) = pool_info<BaseCoin, QuoteCoin, LiquidityToken>(false);

        decimal128::from_ratio_u64(
            decimal128::mul_u64(&base_weight, quote_pool), 
            decimal128::mul_u64(&quote_weight, base_pool),
        )
    }

    #[view]
    /// Return swap simulation result
    public fun get_swap_simulation<OfferCoin, ReturnCoin, LiquidityToken>(
        offer_amount: u64,
    ): u64 acquires Config, Pool {
        let (offer_pool, return_pool, offer_weight, return_weight, swap_fee_rate) = pool_info<OfferCoin, ReturnCoin, LiquidityToken>(true);
        let (return_amount, _fee_amount) = swap_simulation(
            offer_pool,
            return_pool,
            offer_weight,
            return_weight,
            offer_amount,
            swap_fee_rate,
        );

        return_amount
    }

    #[view]
    /// get pool info
    public fun get_pool_info<CoinA, CoinB, LiquidityToken>(): PoolInfoResponse acquires Pool {
        let owner_addr = coin_address<LiquidityToken>();
        let pool = borrow_global<Pool<CoinA, CoinB, LiquidityToken>>(owner_addr);
        PoolInfoResponse {
            coin_a_amount: coin::value(&pool.coin_a),
            coin_b_amount: coin::value(&pool.coin_b),
            total_share: coin::supply<LiquidityToken>(),
        }
    }

    #[view]
    /// get config
    public fun get_config<CoinA, CoinB, LiquidityToken>(): ConfigResponse acquires Config {
        let owner_addr = coin_address<LiquidityToken>();
        let config = borrow_global<Config<CoinA, CoinB, LiquidityToken>>(owner_addr);

        ConfigResponse {
            weights: config.weights,
            swap_fee_rate: config.swap_fee_rate,
        }
    }

    #[view]
    public fun get_current_weight<CoinA, CoinB, LiquidityToken>(): CurrentWeightResponse acquires Config {
        let owner_addr = coin_address<LiquidityToken>();
        let config = borrow_global<Config<CoinA, CoinB, LiquidityToken>>(owner_addr);
        let (coin_a_weight, coin_b_weight) = get_weight(&config.weights);
        CurrentWeightResponse {
            coin_a_weight,
            coin_b_weight,
        }
    }

    #[view]
    // get all kinds of pair
    // return vector of PairResponse
    public fun get_all_pairs(
        coin_a_type_start_after: Option<String>,
        coin_b_type_start_after: Option<String>,
        liquidity_token_type_start_after: Option<String>,
        limit: u8,
    ): vector<PairResponse> acquires ModuleStore {
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        assert!(
            option::is_some(&coin_a_type_start_after) == option::is_some(&coin_b_type_start_after) 
                && option::is_some(&coin_b_type_start_after) == option::is_some(&liquidity_token_type_start_after),
            ESTART_AFTER
        );

        let module_store = borrow_global<ModuleStore>(@initia_std);

        let start_after = if (option::is_some(&coin_a_type_start_after)) {
            option::some(PairKey {
                coin_a_type: option::extract(&mut coin_a_type_start_after),
                coin_b_type: option::extract(&mut coin_b_type_start_after),
                liquidity_token_type: option::extract(&mut liquidity_token_type_start_after),
            })
        } else {
            option::some(PairKey {
                coin_a_type: string::utf8(b""),
                coin_b_type: string::utf8(b""),
                liquidity_token_type: string::utf8(b""),
            })
        };

        let res = vector[];
        let pairs_iter = table::iter(
            &module_store.pairs,
            start_after,
            option::none(),
            1,
        );

        while (vector::length(&res) < (limit as u64) && table::prepare<PairKey, PairResponse>(&mut pairs_iter)) {
            let (key, value) = table::next<PairKey, PairResponse>(&mut pairs_iter);
            if (&key != option::borrow(&start_after)) {
                vector::push_back(&mut res, *value)
            }
        };

        res
    }

    #[view]
    // get pairs by coin types
    // return vector of PairResponse
    public fun get_pairs(
        coin_a_type: String,
        coin_b_type: String,
        start_after: Option<String>,
        limit: u8,
    ): vector<PairResponse> acquires ModuleStore {
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        let module_store = borrow_global<ModuleStore>(@initia_std);

        let start_after = if (option::is_some(&start_after)) {
            option::some(PairKey {
                coin_a_type,
                coin_b_type,
                liquidity_token_type: option::extract(&mut start_after),
            })
        } else {
            option::some(PairKey {
                coin_a_type,
                coin_b_type,
                liquidity_token_type: string::utf8(b""),
            })
        };

        let res = vector[];
        let pairs_iter = table::iter(
            &module_store.pairs,
            start_after,
            option::none(),
            1,
        );

        while (vector::length(&res) < (limit as u64) && table::prepare<PairKey, PairResponse>(&mut pairs_iter)) {
            let (key, value) = table::next<PairKey, PairResponse>(&mut pairs_iter);
            if (coin_a_type != key.coin_a_type || coin_b_type != key.coin_b_type) break;
            if (&key != option::borrow(&start_after)) {
                vector::push_back(&mut res, *value)
            }
        };

        res
    }

    // Query functions

    public fun get_coin_a_amount_from_pool_info_response(res: &PoolInfoResponse): u64 {
        res.coin_a_amount
    }

    public fun get_coin_b_amount_from_pool_info_response(res: &PoolInfoResponse): u64 {
        res.coin_b_amount
    }

    public fun get_total_share_from_pool_info_response(res: &PoolInfoResponse): u128 {
        res.total_share
    }

    public fun get_swap_fee_rate_from_config_response(res: &ConfigResponse): Decimal128 {
        res.swap_fee_rate
    }

    public fun get_weight_before_from_config_response(res: &ConfigResponse): Weight {
        res.weights.weights_before
    }

    public fun get_weight_after_from_config_response(res: &ConfigResponse): Weight {
        res.weights.weights_after
    }

    public fun get_coin_a_weight_from_weight(weight: &Weight): Decimal128 {
        weight.coin_a_weight
    }

    public fun get_coin_b_weight_from_weight(weight: &Weight): Decimal128 {
        weight.coin_b_weight
    }

    public fun get_timestamp_from_weight(weight: &Weight): u64 {
        weight.timestamp
    }

    /// Check signer is chain
    fun check_chain_permission(chain: &signer) {
        assert!(signer::address_of(chain) == @initia_std, error::permission_denied(EUNAUTHORIZED));
    }

    fun init_module(chain: &signer) {
        move_to(chain, ModuleStore {
            pairs: table::new<PairKey, PairResponse>(),
            pair_count: 0,
            create_pair_event: event::new_event_handle<CreatePairEvent>(chain),
            swap_fee_update_event: event::new_event_handle<SwapFeeUpdateEvent>(chain),
        });
    }

    public fun check_liquidity_token<LiquidityToken>() {
        assert!(exists<CoinCapabilities<LiquidityToken>>(coin_address<LiquidityToken>()), error::not_found(ELIQUIDITY_TOKEN_NOT_FOUND));
    }

    public(friend) fun burn_lp<LiquidityToken>(lp: coin::Coin<LiquidityToken>) acquires CoinCapabilities {
        check_liquidity_token<LiquidityToken>();

        let caps = borrow_global<CoinCapabilities<LiquidityToken>>(coin_address<LiquidityToken>());
        coin::burn<LiquidityToken>(lp, &caps.burn_cap);
    }

    //
    // Execute entry functions
    // 

    /// Create pair normally.
    /// permission check will be done in LP coin initialize
    /// only LP struct owner can initialize
    public entry fun create_pair_script<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        name: String,
        symbol: String,
        coin_a_weight: String,
        coin_b_weight: String,
        swap_fee_rate: String,
        coin_a_amount: u64,
        coin_b_amount: u64,
    ) acquires CoinCapabilities, Config, EventStore, ModuleStore, Pool {
        let coin_a_weight = decimal128::from_string(&coin_a_weight);
        let coin_b_weight = decimal128::from_string(&coin_b_weight);
        let (_, timestamp) = get_block_info();
        let weights = Weights {
            weights_before: Weight {
                coin_a_weight,
                coin_b_weight,
                timestamp
            },
            weights_after: Weight {
                coin_a_weight,
                coin_b_weight,
                timestamp
            }
        };

        let coin_a = coin::withdraw<CoinA>(account, coin_a_amount);
        let coin_b = coin::withdraw<CoinB>(account, coin_b_amount);

        let liquidity_token = create_pair<CoinA, CoinB, LiquidityToken>(account, name, symbol, swap_fee_rate, coin_a, coin_b, weights);

        // register coin store for liquidity token deposit
        if (!coin::is_account_registered<LiquidityToken>(signer::address_of(account))) {
            coin::register<LiquidityToken>(account);
        };

        coin::deposit(signer::address_of(account), liquidity_token);
    }

    /// Create LBP pair
    /// permission check will be done in LP coin initialize
    /// only LP struct owner can initialize
    public entry fun create_lbp_pair_script<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        name: String,
        symbol: String,
        start_time: u64,
        coin_a_start_weight: String,
        coin_b_start_weight: String,
        end_time: u64,
        coin_a_end_weight: String,
        coin_b_end_weight: String,
        swap_fee_rate: String,
        coin_a_amount: u64,
        coin_b_amount: u64,
    ) acquires CoinCapabilities, Config, EventStore, ModuleStore, Pool {
        let (_, timestamp) = get_block_info();
        assert!(start_time > timestamp, error::invalid_argument(ELBP_START_TIME));
        assert!(end_time > start_time, error::invalid_argument(EWEIGHTS_TIMESTAMP));
        let weights = Weights {
            weights_before: Weight {
                coin_a_weight: decimal128::from_string(&coin_a_start_weight),
                coin_b_weight: decimal128::from_string(&coin_b_start_weight),
                timestamp: start_time, 
            },
            weights_after: Weight {
                coin_a_weight: decimal128::from_string(&coin_a_end_weight),
                coin_b_weight: decimal128::from_string(&coin_b_end_weight),
                timestamp: end_time,
            }
        };

        let coin_a = coin::withdraw<CoinA>(account, coin_a_amount);
        let coin_b = coin::withdraw<CoinB>(account, coin_b_amount);

        let liquidity_token = create_pair<CoinA, CoinB, LiquidityToken>(account, name, symbol, swap_fee_rate, coin_a, coin_b, weights);
            
        // register coin store for liquidity token deposit
        if (!coin::is_account_registered<LiquidityToken>(signer::address_of(account))) {
            coin::register<LiquidityToken>(account);
        };

        coin::deposit(signer::address_of(account), liquidity_token);
    }

    /// update swap fee rate
    public entry fun update_swap_fee_rate<CoinA, CoinB, LiquidityToken>(
        chain: &signer,
        swap_fee_rate: String,
    ) acquires Config, ModuleStore {
        check_chain_permission(chain);
        check_listed<CoinA, CoinB, LiquidityToken>();

        let owner_addr = coin_address<LiquidityToken>();
        let swap_fee_rate = decimal128::from_string(&swap_fee_rate);
        let config = borrow_global_mut<Config<CoinA, CoinB, LiquidityToken>>(owner_addr);
        assert!(
            decimal128::val(&swap_fee_rate) < decimal128::val(&decimal128::one()),
            error::invalid_argument(EOUT_OF_SWAP_FEE_RATE_RANGE)
        );

        config.swap_fee_rate = swap_fee_rate;

        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        let liquidity_token_type = type_info::type_name<LiquidityToken>();

        // update PairResponse
        let module_store = borrow_global_mut<ModuleStore>(@initia_std);
        let pair_response = table::borrow_mut(
            &mut module_store.pairs,
            PairKey{ coin_a_type, coin_b_type, liquidity_token_type },
        );

        pair_response.swap_fee_rate = swap_fee_rate;

        // emit event
        event::emit_event<SwapFeeUpdateEvent>(
            &mut module_store.swap_fee_update_event,
            SwapFeeUpdateEvent {
                coin_a_type,
                coin_b_type,
                liquidity_token_type,
                swap_fee_rate,
            },
        );
    }

    /// Make a event store for the account
    public entry fun register(account: &signer) {
        let account_addr = signer::address_of(account);
        assert!(
            !is_account_registered(account_addr),
            error::already_exists(EEVENT_STORE_ALREADY_PUBLISHED),
        );

        let event_store = EventStore {
            provide_events: event::new_event_handle<ProvideEvent>(account),
            withdraw_events: event::new_event_handle<WithdrawEvent>(account),
            swap_events: event::new_event_handle<SwapEvent>(account),
            single_asset_provide_events: event::new_event_handle<SingleAssetProvideEvent>(account),
        };
        move_to(account, event_store);
    }

    /// script of `provide_liquidity_from_coin_store`
    public entry fun provide_liquidity_script<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        coin_a_amount_in: u64,
        coin_b_amount_in: u64,
        min_liquidity: Option<u64>
    ) acquires CoinCapabilities, Config, EventStore, Pool {
        provide_liquidity_from_coin_store<CoinA, CoinB, LiquidityToken>(
            account,
            coin_a_amount_in,
            coin_b_amount_in,
            min_liquidity,
        );
    }

    /// Provide liquidity with 0x1::coin::CoinStore coins
    public fun provide_liquidity_from_coin_store<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        coin_a_amount_in: u64,
        coin_b_amount_in: u64,
        min_liquidity: Option<u64>
    ): (u64, u64, u64) acquires CoinCapabilities, Config, EventStore, Pool {
        check_listed<CoinA, CoinB, LiquidityToken>();

        let owner_addr = coin_address<LiquidityToken>();
        let pool = borrow_global_mut<Pool<CoinA, CoinB, LiquidityToken>>(owner_addr);
        let coin_a_amount = coin::value(&pool.coin_a);
        let coin_b_amount = coin::value(&pool.coin_b);
        let total_share = coin::supply<LiquidityToken>();

        // calculate the best coin amount
        let (coin_a, coin_b) = if (total_share == 0) {
            (
                coin::withdraw<CoinA>(account, coin_a_amount_in),
                coin::withdraw<CoinB>(account, coin_b_amount_in),
            )
        } else {
            let coin_a_share_ratio = decimal128::from_ratio_u64(coin_a_amount_in, coin_a_amount);
            let coin_b_share_ratio = decimal128::from_ratio_u64(coin_b_amount_in, coin_b_amount);
            if (decimal128::val(&coin_a_share_ratio) > decimal128::val(&coin_b_share_ratio)) {
                coin_a_amount_in = decimal128::mul_u64(&coin_b_share_ratio, coin_a_amount);
            } else {
                coin_b_amount_in = decimal128::mul_u64(&coin_a_share_ratio, coin_b_amount);
            };

            (
                coin::withdraw<CoinA>(account, coin_a_amount_in),
                coin::withdraw<CoinB>(account, coin_b_amount_in),
            )
        };

        let liquidity_token = provide_liquidity<CoinA, CoinB, LiquidityToken>(
            account,
            coin_a,
            coin_b,
            min_liquidity,
        );

        // register coin store for liquidity token deposit
        if (!coin::is_account_registered<LiquidityToken>(signer::address_of(account))) {
            coin::register<LiquidityToken>(account);
        };

        let liquidity_token_amount = coin::value(&liquidity_token);
        coin::deposit(signer::address_of(account), liquidity_token);

        (coin_a_amount_in, coin_b_amount_in, liquidity_token_amount)
    }

    /// Withdraw liquidity with liquidity token in the token store
    public entry fun withdraw_liquidity_script<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        liquidity: u64,
        min_coin_a_amount: Option<u64>,
        min_coin_b_amount: Option<u64>,
    ) acquires CoinCapabilities, Config, EventStore, Pool {
        assert!(liquidity != 0, error::invalid_argument(EZERO_LIQUIDITY));

        let addr = signer::address_of(account);
        let liquidity_token = coin::withdraw<LiquidityToken>(account, liquidity);
        let (coin_a, coin_b) = withdraw_liquidity(
            account,
            liquidity_token,
            min_coin_a_amount,
            min_coin_b_amount,
        );

        // register coin store for coin a and b deposit
        if (!coin::is_account_registered<CoinA>(signer::address_of(account))) {
            coin::register<CoinA>(account);
        };
    
        if (!coin::is_account_registered<CoinB>(signer::address_of(account))) {
            coin::register<CoinB>(account);
        };

        coin::deposit<CoinA>(addr, coin_a);
        coin::deposit<CoinB>(addr, coin_b);
    }

    /// Swap with the coin in the coin store
    public entry fun swap_script<OfferCoin, ReturnCoin, LiquidityToken>(
        account: &signer,
        offer_coin_amount: u64,
        min_return: Option<u64>,
    ) acquires Config, EventStore, Pool {
        let offer_coin = coin::withdraw<OfferCoin>(account, offer_coin_amount);
        let return_coin = swap<OfferCoin, ReturnCoin, LiquidityToken>(account, offer_coin);

        assert!(
            option::is_none(&min_return) || *option::borrow(&min_return) <= coin::value(&return_coin),
            error::invalid_state(EMIN_RETURN),
        );

        if (!coin::is_account_registered<ReturnCoin>(signer::address_of(account))) {
            coin::register<ReturnCoin>(account);
        };

        coin::deposit(signer::address_of(account), return_coin);
    }

    /// Single asset provide liquidity with token in the token store
    public entry fun single_asset_provide_liquidity_script<CoinA, CoinB, LiquidityToken, ProvideCoin>(
        account: &signer,
        amount_in: u64,
        min_liquidity: Option<u64>
    ) acquires Config, CoinCapabilities, EventStore, Pool {
        let addr = signer::address_of(account);
        let provide_coin = coin::withdraw<ProvideCoin>(account, amount_in);
        let liquidity_token = single_asset_provide_liquidity<CoinA, CoinB, LiquidityToken, ProvideCoin>(
            account,
            provide_coin,
            min_liquidity,
        );

        // register coin store for liquidity token deposit
        if (!coin::is_account_registered<LiquidityToken>(signer::address_of(account))) {
            coin::register<LiquidityToken>(account);
        };

        coin::deposit(addr, liquidity_token);
    }

    public fun create_pair<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        name: String,
        symbol: String,
        swap_fee_rate: String,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        weights: Weights,
    ): Coin<LiquidityToken> acquires CoinCapabilities, Config, EventStore, ModuleStore, Pool {
        assert!(
            !is_listed<CoinA, CoinB, LiquidityToken>(),
            error::invalid_state(EPAIR_ALREADY_LISTED),
        );

        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<LiquidityToken>(
            account,
            name,
            symbol,
            6,
        );

        let swap_fee_rate = decimal128::from_string(&swap_fee_rate);

        assert!(
            decimal128::val(&swap_fee_rate) < decimal128::val(&decimal128::one()),
            error::invalid_argument(EOUT_OF_SWAP_FEE_RATE_RANGE)
        );

        move_to(
            account,
            Config<CoinA, CoinB, LiquidityToken> {
                // temp weights for initial provide
                weights: Weights {
                    weights_before: Weight {
                        coin_a_weight: decimal128::one(),
                        coin_b_weight: decimal128::one(),
                        timestamp: 0,
                    },
                    weights_after: Weight {
                        coin_a_weight: decimal128::one(),
                        coin_b_weight: decimal128::one(),
                        timestamp: 0,
                    }
                },
                swap_fee_rate,
            }
        );

        move_to(
            account,
            CoinCapabilities { mint_cap, freeze_cap, burn_cap },
        );

        move_to(
            account,
            Pool<CoinA, CoinB, LiquidityToken> {
                coin_a: coin::zero(),
                coin_b: coin::zero(),
            }
        );

        let liquidity_token = provide_liquidity<CoinA, CoinB, LiquidityToken>(
            account,
            coin_a,
            coin_b,
            option::none(),
        );

        // update weights
        let config = borrow_global_mut<Config<CoinA, CoinB, LiquidityToken>>(signer::address_of(account));
        config.weights = weights;

        // update module store
        let module_store = borrow_global_mut<ModuleStore>(@initia_std);
        module_store.pair_count = module_store.pair_count + 1;

        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        let liquidity_token_type = type_info::type_name<LiquidityToken>();
        let pair_key = PairKey { coin_a_type, coin_b_type, liquidity_token_type };

        // add pair to table for queries
        table::add(
            &mut module_store.pairs,
            pair_key,
            PairResponse {
                coin_a_type,
                coin_b_type,
                liquidity_token_type,
                weights,
                swap_fee_rate,
            },
        );

        // emit create pair event
        event::emit_event<CreatePairEvent>(
            &mut module_store.create_pair_event,
            CreatePairEvent {
                coin_a_type,
                coin_b_type,
                liquidity_token_type,
                weights,
                swap_fee_rate,
            },
        );
        
        liquidity_token
    }

    /// Provide liquidity directly
    /// CONTRACT: not allow until LBP is ended
    public fun provide_liquidity<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        min_liquidity_amount: Option<u64>,
    ): Coin<LiquidityToken> acquires CoinCapabilities, Config, EventStore, Pool {
        check_listed<CoinA, CoinB, LiquidityToken>();
 
        let owner_addr = coin_address<LiquidityToken>();
        let config = borrow_global_mut<Config<CoinA, CoinB, LiquidityToken>>(owner_addr);
        let pool = borrow_global_mut<Pool<CoinA, CoinB, LiquidityToken>>(owner_addr);
        check_lbp_ended(&config.weights);

        // check account registeration
        // if not registered, register the account
        let account_addr = signer::address_of(account);
        if (!is_account_registered(account_addr)) {
            register(account);
        };

        let event_store = borrow_global_mut<EventStore>(signer::address_of(account));

        let coin_a_amount_in = coin::value(&coin_a);
        let coin_a_amount = coin::value(&pool.coin_a);
        let coin_b_amount_in = coin::value(&coin_b);
        let coin_b_amount = coin::value(&pool.coin_b);

        let total_share = coin::supply<LiquidityToken>();
        let liquidity = if (total_share == 0) {
            if (coin_a_amount_in > coin_b_amount_in) {
                coin_a_amount_in
            } else {
                coin_b_amount_in
            }
        } else {
            let coin_a_share_ratio = decimal128::from_ratio_u64(coin_a_amount_in, coin_a_amount);
            let coin_b_share_ratio = decimal128::from_ratio_u64(coin_b_amount_in, coin_b_amount);
            if (decimal128::val(&coin_a_share_ratio) > decimal128::val(&coin_b_share_ratio)) {
                (decimal128::mul(&coin_b_share_ratio, total_share) as u64)
            } else {
                (decimal128::mul(&coin_a_share_ratio, total_share) as u64)
            }
        };

        assert!(
            option::is_none(&min_liquidity_amount) || *option::borrow(&min_liquidity_amount) <= liquidity,
            error::invalid_state(EMIN_LIQUIDITY),
        );

        coin::merge(&mut pool.coin_a, coin_a);
        coin::merge(&mut pool.coin_b, coin_b);

        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        let liquidity_token_type = type_info::type_name<LiquidityToken>();

        event::emit_event<ProvideEvent>(
            &mut event_store.provide_events,
            ProvideEvent {
                coin_a_type,
                coin_b_type,
                liquidity_token_type,
                coin_a_amount: coin_a_amount_in,
                coin_b_amount: coin_b_amount_in,
                liquidity,
            },
        );

        let liquidity_token_capabilities = borrow_global<CoinCapabilities<LiquidityToken>>(owner_addr);
        coin::mint(liquidity, &liquidity_token_capabilities.mint_cap)
    }

    /// Withdraw liquidity directly
    /// CONTRACT: not allow until LBP is ended
    public fun withdraw_liquidity<CoinA, CoinB, LiquidityToken>(
        account: &signer,
        lp_token: Coin<LiquidityToken>,
        min_coin_a_amount: Option<u64>,
        min_coin_b_amount: Option<u64>,
    ): (Coin<CoinA>, Coin<CoinB>) acquires CoinCapabilities, Config, EventStore, Pool {
        check_listed<CoinA, CoinB, LiquidityToken>();
        let owner_addr = coin_address<LiquidityToken>();

        // check account registeration
        // if not registered, register the account
        let account_addr = signer::address_of(account);
        if (!is_account_registered(account_addr)) {
            register(account);
        };


        let pool = borrow_global_mut<Pool<CoinA, CoinB, LiquidityToken>>(owner_addr);
        let config = borrow_global_mut<Config<CoinA, CoinB, LiquidityToken>>(owner_addr);
        let event_store = borrow_global_mut<EventStore>(signer::address_of(account));
        let total_share = coin::supply<LiquidityToken>();
        let coin_a_amount = coin::value(&pool.coin_a);
        let given_token_amount = coin::value(&lp_token);
        let coin_b_amount = coin::value(&pool.coin_b);
        let given_share_ratio = decimal128::from_ratio((given_token_amount as u128), total_share);
        let coin_a_amount_out = decimal128::mul_u64(&given_share_ratio, coin_a_amount);
        let coin_b_amount_out = decimal128::mul_u64(&given_share_ratio, coin_b_amount);
        check_lbp_ended(&config.weights);

        assert!(
            option::is_none(&min_coin_a_amount) || *option::borrow(&min_coin_a_amount) <= coin_a_amount_out,
            error::invalid_state(EMIN_WITHDRAW),
        );
        assert!(
            option::is_none(&min_coin_b_amount) || *option::borrow(&min_coin_b_amount) <= coin_b_amount_out,
            error::invalid_state(EMIN_WITHDRAW),
        );

        // burn liquidity token
        let liquidity_token_capabilities = borrow_global<CoinCapabilities<LiquidityToken>>(owner_addr);
        coin::burn(lp_token, &liquidity_token_capabilities.burn_cap);

        // emit events
        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        let liquidity_token_type = type_info::type_name<LiquidityToken>();
        event::emit_event<WithdrawEvent>(
            &mut event_store.withdraw_events,
            WithdrawEvent {
                coin_a_type,
                coin_b_type,
                liquidity_token_type,
                coin_a_amount: coin_a_amount_out,
                coin_b_amount: coin_b_amount_out,
                liquidity: given_token_amount,
            },
        );

        // withdraw and return the coins
        (
            coin::extract(&mut pool.coin_a, coin_a_amount_out),
            coin::extract(&mut pool.coin_b, coin_b_amount_out),
        )
    }

    /// Swap directly
    public fun swap<OfferCoin, ReturnCoin, LiquidityToken>(
        account: &signer,
        offer_coin: Coin<OfferCoin>,
    ): Coin<ReturnCoin> acquires Config, EventStore, Pool {
        let offer_coin_type = type_info::type_name<OfferCoin>();
        let return_coin_type = type_info::type_name<ReturnCoin>();
        let liquidity_token_type = type_info::type_name<LiquidityToken>();
        let offer_amount = coin::value(&offer_coin);        

        // check account registeration
        // if not registered, register the account
        let account_addr = signer::address_of(account);
        if (!is_account_registered(account_addr)) {
            register(account);
        };

        let (offer_pool, return_pool, offer_weight, return_weight, swap_fee_rate) = pool_info<OfferCoin, ReturnCoin, LiquidityToken>(true);
        let (return_amount, fee_amount) = swap_simulation(
            offer_pool,
            return_pool,
            offer_weight,
            return_weight,
            coin::value(&offer_coin),
            swap_fee_rate,
        );

        // apply swap result to pool
        let return_coin = apply_swap<OfferCoin, ReturnCoin, LiquidityToken>(offer_coin, return_amount);

        // emit events
        let event_store = borrow_global_mut<EventStore>(signer::address_of(account));
        event::emit_event<SwapEvent>(
            &mut event_store.swap_events,
            SwapEvent {
                offer_coin_type,
                return_coin_type,
                liquidity_token_type,
                fee_amount,
                offer_amount,
                return_amount,
            },
        );

        return_coin
    }

    /// apply swap return to pool
    fun apply_swap<OfferCoin, ReturnCoin, LiquidityToken>(offer_coin: Coin<OfferCoin>, return_amount: u64): Coin<ReturnCoin> acquires Pool {
        let owner_addr = coin_address<LiquidityToken>();
        if (is_listed<OfferCoin, ReturnCoin, LiquidityToken>()){
            let pool = borrow_global_mut<Pool<OfferCoin, ReturnCoin, LiquidityToken>>(owner_addr);
            
            coin::merge<OfferCoin>(&mut pool.coin_a, offer_coin);
            coin::extract<ReturnCoin>(&mut pool.coin_b, return_amount)
        } else {
            let pool = borrow_global_mut<Pool<ReturnCoin, OfferCoin, LiquidityToken>>(owner_addr);
            
            coin::merge<OfferCoin>(&mut pool.coin_b, offer_coin);
            coin::extract<ReturnCoin>(&mut pool.coin_a, return_amount)
        }
    }

    /// Signle asset provide liquidity directly
    /// CONTRACT: cannot provide more than the pool amount to prevent huge price impact
    /// CONTRACT: not allow until LBP is ended
    public fun single_asset_provide_liquidity<CoinA, CoinB, LiquidityToken, ProvideCoin>(
        account: &signer,
        provide_coin: Coin<ProvideCoin>,
        min_liquidity_amount: Option<u64>,
    ): Coin<LiquidityToken> acquires Config, CoinCapabilities, EventStore, Pool {
        check_listed<CoinA, CoinB, LiquidityToken>();
        let owner_addr = coin_address<LiquidityToken>();

        let config = borrow_global<Config<CoinA, CoinB, LiquidityToken>>(owner_addr);
        check_lbp_ended(&config.weights);

        // check account registeration
        // if not registered, register the account
        let account_addr = signer::address_of(account);
        if (!is_account_registered(account_addr)) {
            register(account);
        };

        // load coin types
        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        let provide_coin_type = type_info::type_name<ProvideCoin>();
        let liquidity_token_type = type_info::type_name<LiquidityToken>();

        // provide coin type must be one of coin a or coin b coin type
        let is_coin_b = coin_b_type == provide_coin_type;
        let is_coin_a = coin_a_type == provide_coin_type;
        assert!(is_coin_b || is_coin_a, error::invalid_argument(ECOIN_TYPE));

        let total_share = coin::supply<LiquidityToken>();
        assert!(total_share != 0, error::invalid_state(EZERO_LIQUIDITY));

        // load values for fee and increased liquidity amount calculation
        let amount_in = coin::value(&provide_coin);
        let (coin_a_weight, coin_b_weight) = get_weight(&config.weights);
        let (normalized_weight, pool_amount_in) = if (is_coin_a) {
            let pool = borrow_global_mut<Pool<ProvideCoin, CoinB, LiquidityToken>>(owner_addr);
            let normalized_weight = decimal128::from_ratio(
                decimal128::val(&coin_a_weight),
                decimal128::val(&coin_a_weight) + decimal128::val(&coin_b_weight)
            );

            let pool_amount_in = coin::value(&pool.coin_a);
            coin::merge(&mut pool.coin_a, provide_coin);

            (normalized_weight, pool_amount_in)
        } else {
            let pool = borrow_global_mut<Pool<CoinA, ProvideCoin, LiquidityToken>>(owner_addr);
            let normalized_weight = decimal128::from_ratio(
                decimal128::val(&coin_b_weight),
                decimal128::val(&coin_a_weight) + decimal128::val(&coin_b_weight)
            );

            let pool_amount_in = coin::value(&pool.coin_b);
            coin::merge(&mut pool.coin_b, provide_coin);

            (normalized_weight, pool_amount_in)
        };

        // CONTRACT: cannot provide more than the pool amount to prevent huge price impact
        assert!(pool_amount_in > amount_in, error::invalid_argument(EPRICE_IMPACT));

        // compute fee amount with the assumption that we will swap (1 - normalized_weight) of amount_in
        let adjusted_swap_amount = decimal128::mul_u64(
            &decimal128::sub(&decimal128::one(), &normalized_weight),
            amount_in
        );
        let fee_amount = decimal128::mul_u64(&config.swap_fee_rate, adjusted_swap_amount);

        // actual amount in after deducting fee amount
        let adjusted_amount_in = amount_in - fee_amount;

        // calculate new total share and new liquidity
        let base = decimal128::from_ratio_u64(adjusted_amount_in + pool_amount_in, pool_amount_in);
        let pool_ratio = pow(&base, &normalized_weight);
        let new_total_share = decimal128::mul(&pool_ratio, total_share);
        let liquidity = (new_total_share - total_share as u64);

        // check min liquidity assertion
        assert!(
            option::is_none(&min_liquidity_amount) ||
                *option::borrow(&min_liquidity_amount) <= liquidity,
            error::invalid_state(EMIN_LIQUIDITY),
        );

        // emit events
        let event_store = borrow_global_mut<EventStore>(signer::address_of(account));
        event::emit_event<SingleAssetProvideEvent>(
            &mut event_store.single_asset_provide_events,
            SingleAssetProvideEvent {
                coin_a_type,
                coin_b_type,
                provide_coin_type,
                liquidity_token_type,
                provide_amount: amount_in,
                fee_amount,
                liquidity,
            },
        );

        // mint liquidity tokens to provider
        let liquidity_token_capabilities = borrow_global<CoinCapabilities<LiquidityToken>>(owner_addr);
        coin::mint(liquidity, &liquidity_token_capabilities.mint_cap)
    }

    /// Calculate out amount
    /// https://balancer.fi/whitepaper.pdf (15)
    /// return (return_amount, fee_amount)
    public fun swap_simulation(
        pool_amount_in: u64,
        pool_amount_out: u64,
        weight_in: Decimal128,
        weight_out: Decimal128,
        amount_in: u64,
        swap_fee_rate: Decimal128,
    ): (u64, u64) {
        let one = decimal128::one();
        let exp = decimal128::from_ratio(decimal128::val(&weight_in), decimal128::val(&weight_out));
        let fee_amount = decimal128::mul_u64(&swap_fee_rate, amount_in);
        let adjusted_amount_in = amount_in - fee_amount;
        let base = decimal128::from_ratio_u64(pool_amount_in, pool_amount_in + adjusted_amount_in);
        let sub_amount = pow(&base, &exp);
        (decimal128::mul_u64(&decimal128::sub(&one, &sub_amount), pool_amount_out), fee_amount)
    }

    /// a^x = 1 + sigma[(k^n)/n!]
    /// k = x * ln(a)
    fun pow(base: &Decimal128, exp: &Decimal128): Decimal128 {
        assert!(
            decimal128::val(base) != 0 && decimal128::val(base) < 2000000000000000000,
            error::invalid_argument(EOUT_OF_BASE_RANGE),
        );

        let res = decimal128::one();
        let (ln_a, neg) = ln(base);
        let k = mul_decimal128s(&ln_a, exp);
        let comp = k;
        let index = 1;
        let subs: vector<Decimal128> = vector[];
        while (decimal128::val(&comp) > PRECISION) {
            if (index & 1 == 1 && neg) {
                vector::push_back(&mut subs, comp)
            } else {
                res = decimal128::add(&res, &comp)
            };

            comp = decimal128::div(&mul_decimal128s(&comp, &k), index + 1);
            index = index + 1;
        };

        let index = 0;
        while (index < vector::length(&subs)) {
            let comp = vector::borrow(&subs, index);
            res = decimal128::sub(&res, comp);
            index = index + 1;
        };

        res
    }

    /// ln(1 + a) = sigma[(-1) ^ (n + 1) * (a ^ n / n)]
    /// https://en.wikipedia.org/wiki/Taylor_series#Natural_logarithm
    fun ln(num: &Decimal128): (Decimal128, bool) {
        let one = decimal128::val(&decimal128::one());
        let num_val = decimal128::val(num);
        let (a, a_neg) = if (num_val >= one) {
            (decimal128::sub(num, &decimal128::one()), false)
        } else {
            (decimal128::sub(&decimal128::one(), num), true)
        };

        let res = decimal128::zero();
        let comp = a;
        let index = 1;

        while (decimal128::val(&comp) > PRECISION) {
            if (index & 1 == 0 && !a_neg) {
                res = decimal128::sub(&res, &comp);
            } else {
                res = decimal128::add(&res, &comp);
            };

            // comp(old) = a ^ n / n
            // comp(new) = comp(old) * a * n / (n + 1) = a ^ (n + 1) / (n + 1)
            comp = decimal128::div(
                &decimal128::new(decimal128::val(&mul_decimal128s(&comp, &a)) * index), // comp * a * index
                index + 1,
            );

            index = index + 1;
        };

        (res, a_neg)
    }

    fun mul_decimal128s(decimal128_0: &Decimal128, decimal128_1: &Decimal128): Decimal128 {
        let one = (decimal128::val(&decimal128::one()) as u256);
        let val_mul = (decimal128::val(decimal128_0) as u256) * (decimal128::val(decimal128_1) as u256);
        decimal128::new((val_mul / one as u128))
    }

    // return (coin_a_weight, coin_b_weight)
    fun get_weight(weights: &Weights): (Decimal128, Decimal128) {
        let (_, timestamp) = get_block_info();
        if (timestamp <= weights.weights_before.timestamp) {
            (weights.weights_before.coin_a_weight, weights.weights_before.coin_b_weight)
        } else if (timestamp < weights.weights_after.timestamp) {
            let interval = (weights.weights_after.timestamp - weights.weights_before.timestamp as u128);
            let time_diff_after = (weights.weights_after.timestamp - timestamp as u128);
            let time_diff_before = (timestamp - weights.weights_before.timestamp as u128);

            // when timestamp_before < timestamp < timestamp_after
            // weight = a * timestamp + b
            // m = (a * timestamp_before + b) * (timestamp_after - timestamp) 
            //   = a * t_b * t_a - a * t_b * t + b * t_a - b * t
            // n = (a * timestamp_after + b) * (timestamp - timestamp_before)
            //   = a * t_a * t - a * t_a * t_b + b * t - b * t_b
            // l = m + n = a * t * (t_a - t_b) + b * (t_a - t_b)
            // weight = l / (t_a - t_b)
            let coin_a_m = decimal128::new(decimal128::val(&weights.weights_after.coin_a_weight) * time_diff_before);
            let coin_a_n = decimal128::new(decimal128::val(&weights.weights_before.coin_a_weight) * time_diff_after);
            let coin_a_l = decimal128::add(&coin_a_m, &coin_a_n);

            let coin_b_m = decimal128::new(decimal128::val(&weights.weights_after.coin_b_weight) * time_diff_before);
            let coin_b_n = decimal128::new(decimal128::val(&weights.weights_before.coin_b_weight) * time_diff_after);
            let coin_b_l = decimal128::add(&coin_b_m, &coin_b_n);
            (decimal128::div(&coin_a_l, interval), decimal128::div(&coin_b_l, interval))
        } else {
            (weights.weights_after.coin_a_weight, weights.weights_after.coin_b_weight)
        }
    }

    fun coin_address<CoinType>(): address {
        let type_info = type_info::type_of<CoinType>();
        type_info::account_address(&type_info)
    }

    fun check_lbp_ended(weights: &Weights) {
        let (_, timestamp) = get_block_info();

        assert!(timestamp >= weights.weights_after.timestamp, error::invalid_state(ELBP_NOT_ENDED))
    }

    #[test_only]
    public fun init_module_for_test(
        chain: &signer
    ) {
        init_module(chain);
    }

    #[test_only]
    use initia_std::block::set_block_info;

    #[test_only]
    struct CoinCaps<phantom CoinType> has key {
        burn_cap: coin::BurnCapability<CoinType>,
        freeze_cap: coin::FreezeCapability<CoinType>,
        mint_cap: coin::MintCapability<CoinType>,
    }

    #[test_only]
    struct USDC {}

    #[test_only]
    struct UsdcLiquidityToken {}

    #[test_only]
    fun initialized_coin<CoinType>(
        account: &signer
    ): (coin::BurnCapability<CoinType>, coin::FreezeCapability<CoinType>, coin::MintCapability<CoinType>) {
        coin::initialize<CoinType>(
            account,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            6,
        )
    }

    #[test(chain = @0x1)]
    fun end_to_end(
        chain: signer,
    ) acquires Config, CoinCapabilities, EventStore, ModuleStore, Pool {
        init_module(&chain);
        coin::init_module_for_test(&chain);

        let chain_addr = signer::address_of(&chain);

        let (initia_burn_cap, initia_freeze_cap, initia_mint_cap) = initialized_coin<initia_std::native_uinit::Coin>(&chain);
        let (usdc_burn_cap, usdc_freeze_cap, usdc_mint_cap) = initialized_coin<USDC>(&chain);

        coin::register<initia_std::native_uinit::Coin>(&chain);
        coin::register<USDC>(&chain);
        register(&chain);

        coin::deposit<initia_std::native_uinit::Coin>(chain_addr, coin::mint(100000000, &initia_mint_cap));
        coin::deposit<USDC>(chain_addr, coin::mint(100000000, &usdc_mint_cap));

        // spot price is 1
        create_pair_script<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>(
            &chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            string::utf8(b"0.8"),
            string::utf8(b"0.2"),
            string::utf8(b"0.003"),
            80000000,
            20000000,
        );

        assert!(coin::balance<initia_std::native_uinit::Coin>(chain_addr) == 20000000, 0);
        assert!(coin::balance<USDC>(chain_addr) == 80000000, 1);
        assert!(coin::balance<UsdcLiquidityToken>(chain_addr) == 80000000, 2);

        // swap init to usdc
        swap_script<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>(&chain, 1000, option::none());
        assert!(coin::balance<initia_std::native_uinit::Coin>(chain_addr) == 20000000 - 1000, 3);
        assert!(coin::balance<USDC>(chain_addr) == 80000000 + 996, 4); // return 999 commission 3

        // swap usdc to init
        swap_script<USDC, initia_std::native_uinit::Coin, UsdcLiquidityToken>(&chain, 1000, option::none());
        assert!(coin::balance<initia_std::native_uinit::Coin>(chain_addr) == 20000000 - 1000 + 997, 5); // return 1000 commission 3
        assert!(coin::balance<USDC>(chain_addr) == 80000000 + 996 - 1000, 6);

        // withdraw liquidity
        withdraw_liquidity_script<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>(&chain, 40000000, option::none(), option::none());
        assert!(coin::balance<initia_std::native_uinit::Coin>(chain_addr) == 20000000 - 1000 + 997 + 40000001, 7);
        assert!(coin::balance<USDC>(chain_addr) == 80000000 + 996 - 1000 + 10000002, 8);

        // single asset provide liquidity (coin b)
        // pool balance - init: 40000002, usdc: 10000002
        single_asset_provide_liquidity_script<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken, USDC>(&chain, 100000, option::none());
        assert!(coin::balance<UsdcLiquidityToken>(chain_addr) == 40000000 + 79491, 9);

        // single asset provide liquidity (coin a)
        // pool balance - init: 40000002, usdc: 10100002
        single_asset_provide_liquidity_script<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken, initia_std::native_uinit::Coin>(&chain, 100000, option::none());
        assert!(coin::balance<UsdcLiquidityToken>(chain_addr) == 40000000 + 79491 + 80090, 10);

        move_to(&chain, CoinCaps<initia_std::native_uinit::Coin> {
            burn_cap: initia_burn_cap,
            freeze_cap: initia_freeze_cap,
            mint_cap: initia_mint_cap,
        });

        move_to(&chain, CoinCaps<USDC> {
            burn_cap: usdc_burn_cap,
            freeze_cap: usdc_freeze_cap,
            mint_cap: usdc_mint_cap,
        });
    }

    #[test(chain = @0x1)]
    fun lbp_end_to_end(
        chain: signer,
    ) acquires Config, CoinCapabilities, EventStore, ModuleStore, Pool {
        init_module(&chain);
        coin::init_module_for_test(&chain);

        let chain_addr = signer::address_of(&chain);

        let (initia_burn_cap, initia_freeze_cap, initia_mint_cap) = initialized_coin<initia_std::native_uinit::Coin>(&chain);
        let (usdc_burn_cap, usdc_freeze_cap, usdc_mint_cap) = initialized_coin<USDC>(&chain);

        coin::register<initia_std::native_uinit::Coin>(&chain);
        coin::register<USDC>(&chain);
        register(&chain);

        coin::deposit<initia_std::native_uinit::Coin>(chain_addr, coin::mint(100000000, &initia_mint_cap));
        coin::deposit<USDC>(chain_addr, coin::mint(100000000, &usdc_mint_cap));

        set_block_info(10, 1000);

        create_lbp_pair_script<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>(
            &chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            2000,
            string::utf8(b"0.99"),
            string::utf8(b"0.01"),
            3000,
            string::utf8(b"0.61"),
            string::utf8(b"0.39"),
            string::utf8(b"0.003"),
            80000000,
            20000000,
        );

        assert!(
            get_spot_price<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>() ==
            decimal128::from_string(&string::utf8(b"24.75")),
            0,
        );

        // 0.8 : 0.2
        set_block_info(11, 2500);
        assert!(
            get_spot_price<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>() ==
            decimal128::from_string(&string::utf8(b"1")),
            1,
        );

        // 0.61 : 0.39
        set_block_info(12, 3500);
        assert!(
            get_spot_price<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>() ==
            decimal128::from_string(&string::utf8(b"0.391025641025641025")),
            2,
        );

        assert!(coin::balance<initia_std::native_uinit::Coin>(chain_addr) == 20000000, 0);
        assert!(coin::balance<USDC>(chain_addr) == 80000000, 1);
        assert!(coin::balance<UsdcLiquidityToken>(chain_addr) == 80000000, 3);

        // swap test during LBP (0.8: 0.2)
        set_block_info(11, 2500);

        // swap init to usdc
        swap_script<initia_std::native_uinit::Coin, USDC, UsdcLiquidityToken>(&chain, 1000, option::none());
        assert!(coin::balance<initia_std::native_uinit::Coin>(chain_addr) == 20000000 - 1000, 4);
        assert!(coin::balance<USDC>(chain_addr) == 80000000 + 996, 5); // return 999 commission 3

        // swap usdc to init
        swap_script<USDC, initia_std::native_uinit::Coin, UsdcLiquidityToken>(&chain, 1000, option::none());
        assert!(coin::balance<initia_std::native_uinit::Coin>(chain_addr) == 20000000 - 1000 + 997, 6); // return 1000 commission 3
        assert!(coin::balance<USDC>(chain_addr) == 80000000 + 996 - 1000, 7);


        move_to(&chain, CoinCaps<initia_std::native_uinit::Coin> {
            burn_cap: initia_burn_cap,
            freeze_cap: initia_freeze_cap,
            mint_cap: initia_mint_cap,
        });

        move_to(&chain, CoinCaps<USDC> {
            burn_cap: usdc_burn_cap,
            freeze_cap: usdc_freeze_cap,
            mint_cap: usdc_mint_cap,
        });
    }

    #[test]
    fun get_weight_test() {
        let weights = Weights {
            weights_before: Weight {
                coin_a_weight: decimal128::from_ratio(2, 10),
                coin_b_weight: decimal128::from_ratio(8, 10),
                timestamp: 1000,
            },
            weights_after: Weight {
                coin_a_weight: decimal128::from_ratio(8, 10),
                coin_b_weight: decimal128::from_ratio(2, 10),
                timestamp: 2000,
            },
        };

        set_block_info(10, 1000);
        let (coin_a_weight, coin_b_weight) = get_weight(&weights);
        assert!(
            coin_a_weight == decimal128::from_ratio(2, 10)
                && coin_b_weight == decimal128::from_ratio(8, 10),
            0,
        );

        set_block_info(15, 1500);
        let (coin_a_weight, coin_b_weight) = get_weight(&weights);
        assert!(
            coin_a_weight == decimal128::from_ratio(5, 10)
                && coin_b_weight == decimal128::from_ratio(5, 10),
            1,
        );

        set_block_info(20, 2000);
        let (coin_a_weight, coin_b_weight) = get_weight(&weights);
        assert!(
            coin_a_weight == decimal128::from_ratio(8, 10)
                && coin_b_weight == decimal128::from_ratio(2, 10),
            2,
        );

        set_block_info(30, 3000);
        let (coin_a_weight, coin_b_weight) = get_weight(&weights);
        assert!(
            coin_a_weight == decimal128::from_ratio(8, 10)
                && coin_b_weight == decimal128::from_ratio(2, 10),
            3,
        );
    }
    
    #[test_only]
    struct CoinA {}
    #[test_only]
    struct CoinB {}
    #[test_only]
    struct CoinC {}

    #[test_only]
    struct LpA {}
    #[test_only]
    struct LpB {}
    #[test_only]
    struct LpC {}
    #[test_only]
    struct LpD {}

    #[test(chain = @0x1)]
    fun get_pair_test(chain: signer) acquires Config, CoinCapabilities, EventStore, ModuleStore, Pool {
        init_module(&chain);
        coin::init_module_for_test(&chain);

        let chain_addr = signer::address_of(&chain);

        let (coin_a_burn_cap, coin_a_freeze_cap, coin_a_mint_cap) = initialized_coin<CoinA>(&chain);
        let (coin_b_burn_cap, coin_b_freeze_cap, coin_b_mint_cap) = initialized_coin<CoinB>(&chain);
        let (coin_c_burn_cap, coin_c_freeze_cap, coin_c_mint_cap) = initialized_coin<CoinC>(&chain);

        let coin_a_type = type_info::type_name<CoinA>();
        let coin_b_type = type_info::type_name<CoinB>();
        let coin_c_type = type_info::type_name<CoinC>();

        let lp_a_type = type_info::type_name<LpA>();
        let lp_b_type = type_info::type_name<LpB>();
        let lp_c_type = type_info::type_name<LpC>();
        let lp_d_type = type_info::type_name<LpD>();

        coin::register<CoinA>(&chain);
        coin::register<CoinB>(&chain);
        coin::register<CoinC>(&chain);
        register(&chain);

        coin::deposit<CoinA>(chain_addr, coin::mint(100000000, &coin_a_mint_cap));
        coin::deposit<CoinB>(chain_addr, coin::mint(100000000, &coin_b_mint_cap));
        coin::deposit<CoinC>(chain_addr, coin::mint(100000000, &coin_c_mint_cap));

        create_pair_script<CoinA, CoinB, LpA>(
            &chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            string::utf8(b"0.5"),
            string::utf8(b"0.5"),
            string::utf8(b"0.003"),
            1,
            1,
        );

        create_pair_script<CoinA, CoinB, LpB>(
            &chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            string::utf8(b"0.5"),
            string::utf8(b"0.5"),
            string::utf8(b"0.003"),
            1,
            1,
        );

        create_pair_script<CoinA, CoinC, LpC>(
            &chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            string::utf8(b"0.5"),
            string::utf8(b"0.5"),
            string::utf8(b"0.003"),
            1,
            1,
        );

        create_pair_script<CoinA, CoinC, LpD>(
            &chain,
            std::string::utf8(b"name"),
            std::string::utf8(b"SYMBOL"),
            string::utf8(b"0.5"),
            string::utf8(b"0.5"),
            string::utf8(b"0.003"),
            1,
            1,
        );

        let (_, timestamp) = get_block_info();
        let weight = decimal128::from_ratio(5, 10);
        let swap_fee_rate = decimal128::from_ratio(3, 1000);
        let weights = Weights {
            weights_before: Weight {
                coin_a_weight: weight,
                coin_b_weight: weight,
                timestamp
            },
            weights_after: Weight {
                coin_a_weight: weight,
                coin_b_weight: weight,
                timestamp
            }
        };

        let res = get_all_pairs(option::none(), option::none(), option::none(), 10);
        assert!(
            res == vector[
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_a_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_b_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_c_type,
                    liquidity_token_type: lp_c_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_c_type,
                    liquidity_token_type: lp_d_type,
                    weights,
                    swap_fee_rate,
                },
            ],
            0,
        );

        let res = get_all_pairs(
            option::some(coin_a_type),
            option::some(coin_b_type),
            option::some(lp_a_type),
            10,
        );
        assert!(
            res == vector[
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_b_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_c_type,
                    liquidity_token_type: lp_c_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_c_type,
                    liquidity_token_type: lp_d_type,
                    weights,
                    swap_fee_rate,
                },
            ],
            1,
        );

        let res = get_all_pairs(
            option::some(coin_a_type),
            option::some(coin_a_type),
            option::some(lp_a_type),
            10,
        );
        assert!(
            res == vector[
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_a_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_b_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_c_type,
                    liquidity_token_type: lp_c_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_c_type,
                    liquidity_token_type: lp_d_type,
                    weights,
                    swap_fee_rate,
                },
            ],
            2,
        );

        let res = get_pairs(
            coin_a_type,
            coin_b_type,
            option::none(),
            10,
        );
        assert!(
            res == vector[
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_a_type,
                    weights,
                    swap_fee_rate,
                },
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_b_type,
                    weights,
                    swap_fee_rate,
                },
            ],
            3,
        );

        let res = get_pairs(
            coin_a_type,
            coin_b_type,
            option::some(lp_a_type),
            10,
        );
        assert!(
            res == vector[
                PairResponse { 
                    coin_a_type: coin_a_type,
                    coin_b_type: coin_b_type,
                    liquidity_token_type: lp_b_type,
                    weights,
                    swap_fee_rate,
                },
            ],
            3,
        );

        move_to(&chain, CoinCaps<CoinA> {
            burn_cap: coin_a_burn_cap,
            freeze_cap: coin_a_freeze_cap,
            mint_cap: coin_a_mint_cap,
        });

        move_to(&chain, CoinCaps<CoinB> {
            burn_cap: coin_b_burn_cap,
            freeze_cap: coin_b_freeze_cap,
            mint_cap: coin_b_mint_cap,
        });

        move_to(&chain, CoinCaps<CoinC> {
            burn_cap: coin_c_burn_cap,
            freeze_cap: coin_c_freeze_cap,
            mint_cap: coin_c_mint_cap,
        });
    }
}
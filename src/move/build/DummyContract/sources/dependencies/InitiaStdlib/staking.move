/// This module provides the native staking
module initia_std::staking {
    use std::error;
    use std::event::{Self, EventHandle};
    use std::option::{Self, Option};
    use std::string::{Self, String};
    use std::signer;
    use std::vector;
    use std::type_info;

    use initia_std::account::create_signer_for_friend;
    use initia_std::block;
    use initia_std::coin::{Self, Coin};
    use initia_std::decimal128::{Self, Decimal128};
    use initia_std::table::{Self, Table};
    use initia_std::native_uinit::Coin as RewardCoin;
    use initia_std::dex;

    /// Only chain can execute.
    const EUNAUTHORIZED: u64 = 1;

    /// Chain already has `GlobalStateStore` registered
    const EGLOBAL_STORE_ALREADY_PUBLISHED: u64 = 2;

    /// Length of validators and amounts mismatch.
    const ELENGTH_MISMATCH: u64 = 3;

    /// Account already has `DelegationStore` registered
    const EDELEGATION_STORE_ALREADY_PUBLISHED: u64 = 4;

    /// Account hasn't registered `DelegationStore`
    const EDELEGATION_STORE_NOT_PUBLISHED: u64 = 5;

    /// Validator of delegation which is used as operand doesn't match the other operand one
    const EVALIDATOR_MISMATCH: u64 = 6;

    /// Insufficient amount of share or amount
    const EINSUFFICIENT_AMOUNT: u64 = 7;

    /// `release_time` of the `source_unbonding` must be sooner than or equal to the one of `dst_unbonding`
    const ERELEASE_TIME: u64 = 8;

    /// Can not claim before `release_time`
    const ENOT_RELEASED: u64 = 9;

    /// Can not find delegation
    const EDELEGATION_NOT_FOUND: u64 = 10;

    /// Can not find unbonding
    const EUNBONDING_NOT_FOUND: u64 = 11;

    /// Not an empty delegation or unbonding
    const ENOT_EMPTY: u64 = 12;

    /// Chain already has `RelayerStore` registered
    const ERELAYER_STORE_ALREADY_PUBLISHED: u64 = 13;

    /// `GlobalState` for a validator was not published
    const EGLOBAL_STATE_NOT_PUBLISHED: u64 = 14;

    /// Both `start_after_validator` and `start_after_release_time` either given or not given.
    const EINVALID_START_AFTER: u64 = 15;

    /// Constants
    const MAX_LIMIT: u8 = 30;

    /// Define a delegation entry which can be transferred.
    struct Delegation<phantom BondCoin> has store {
        validator: String,
        share: u64,
        reward_index: Decimal128,
    }

    /// Define a unbonding entry which can be transferred.
    struct Unbonding<phantom BondCoin> has store {
        validator: String,
        unbonding_share: u64,
        release_time: u64,
    }

    /// A holder of a delegation and associated event handles.
    /// These are kept in a single resource to ensure locality of data.
    struct DelegationStore<phantom BondCoin> has key {
        // key: validator
        delegations: Table<String, Delegation<BondCoin>>,
        // key: validator + release_times
        unbondings: Table<UnbondingKey, Unbonding<BondCoin>>,
        delegation_events: EventHandle<DelegationEvent>,
        unbonding_events: EventHandle<UnbondingEvent>,
        reward_events: EventHandle<RewardEvent>,
    }

    /// Key for `Unbonding`
    struct UnbondingKey has copy, drop {
        validator: String,
        release_time: u64,
    }

    /// Event emitted when some amount of reward is claimed by entry function.
    struct RewardEvent has drop, store {
        amount: u64,
    }

    /// Event emitted when some share of a coin is delegated from an account.
    struct DelegationEvent has drop, store {
        action: String,
        coin_type: String,
        validator: String,
        share: u64,
    }

    /// Event emitted when some share of a coin is undelegated from an account.
    struct UnbondingEvent has drop, store {
        action: String,
        coin_type: String,
        validator: String,
        share: u64,
        release_time: u64,
    }

    /// Global state
    struct GlobalStateStore<phantom BondCoin> has key {
        global_states: Table<String, GlobalState<BondCoin>>,
    }

    struct GlobalState<phantom BondCoin> has store {
        validator: String,
        reward_index: Decimal128,
        total_share: u128,
        reward: Coin<RewardCoin>,
        unbonding_coin: Coin<BondCoin>,
        unbonding_share: u128,
    }

    //
    // Query entry functions
    //

    struct DelegationResponse has drop {
        validator: String,
        share: u64,
        unclaimed_reward: u64,
    }

    struct UnbondingResponse has drop {
        validator: String,
        unbonding_amount: u64,
        release_time: u64,
    }

    /// util function to convert Delegation => DelegationResponse for third party queriers
    public fun get_delegation_response_from_delegation<BondCoin>(delegation: &Delegation<BondCoin>): DelegationResponse acquires GlobalStateStore {
        let global_store = borrow_global<GlobalStateStore<BondCoin>>(@initia_std);
        let state = table::borrow(&global_store.global_states, delegation.validator);

        let reward = calculate_reward(delegation, state);

        DelegationResponse {
            validator: delegation.validator,
            share: delegation.share,
            unclaimed_reward: reward,
        }
    }

    /// util function to convert Unbonding => UnbondingResponse for third party queriers
    public fun get_unbonding_response_from_unbonding<BondCoin>(unbonding: &Unbonding<BondCoin>): UnbondingResponse acquires GlobalStateStore{
        let unbonding_amount = get_unbonding_amount_from_unbonding<BondCoin>(unbonding);

        UnbondingResponse {
            validator: unbonding.validator,
            unbonding_amount,
            release_time: unbonding.release_time,
        }
    }

    #[view]
    /// Get delegation info of specifed addr and validator
    public fun get_delegation<BondCoin>(
        addr: address,
        validator: String,
    ): DelegationResponse acquires DelegationStore, GlobalStateStore {
        assert!(
            is_account_registered<BondCoin>(addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let delegation_store = borrow_global<DelegationStore<BondCoin>>(addr);

        assert!(table::contains(&delegation_store.delegations, validator), error::not_found(EDELEGATION_NOT_FOUND));

        let delegation = table::borrow(&delegation_store.delegations, validator);

        let global_store = borrow_global<GlobalStateStore<BondCoin>>(@initia_std);
        let state = table::borrow(&global_store.global_states, validator);

        let reward = calculate_reward(delegation, state);

        DelegationResponse {
            validator,
            share: delegation.share,
            unclaimed_reward: reward,
        }
    }

    #[view]
    /// Get all delegation info of an addr
    public fun get_delegations<BondCoin>(
        addr: address,
        start_after: Option<String>,
        limit: u8,
    ): vector<DelegationResponse> acquires DelegationStore, GlobalStateStore {
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        assert!(
            is_account_registered<BondCoin>(addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let delegation_store = borrow_global<DelegationStore<BondCoin>>(addr);

        let global_store = borrow_global<GlobalStateStore<BondCoin>>(@initia_std);

        let delegations_iter = table::iter(
            &delegation_store.delegations,
            option::none(),
            start_after,
            2,
        );

        let prepare = table::prepare<String, Delegation<BondCoin>>(&mut delegations_iter);
        let res: vector<DelegationResponse> = vector[];
        while (vector::length(&res) < (limit as u64) && prepare) {
            let (validator, delegation) = table::next<String, Delegation<BondCoin>>(&mut delegations_iter);
            let state = table::borrow(&global_store.global_states, validator);
            let reward = calculate_reward(delegation, state);
            vector::push_back(
                &mut res,
                DelegationResponse {
                    validator,
                    share: delegation.share,
                    unclaimed_reward: reward,
                },
            );
            prepare = table::prepare<String, Delegation<BondCoin>>(&mut delegations_iter);
        };

        res
    }

    #[view]
    /// Get unbonding info of (addr, validator, release time)
    public fun get_unbonding<BondCoin>(
        addr: address,
        validator: String,
        release_time: u64,
    ): UnbondingResponse acquires DelegationStore, GlobalStateStore {
        assert!(
            is_account_registered<BondCoin>(addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let delegation_store = borrow_global<DelegationStore<BondCoin>>(addr);

        let key = UnbondingKey { validator, release_time };
        assert!(table::contains(&delegation_store.unbondings, key), error::not_found(EUNBONDING_NOT_FOUND));

        let unbonding = table::borrow(&delegation_store.unbondings, key);
        let unbonding_amount = get_unbonding_amount_from_unbonding<BondCoin>(unbonding);

        UnbondingResponse {
            validator: unbonding.validator,
            unbonding_amount,
            release_time,
        }
    }

    #[view]
    /// Get all unbondings of (addr, validator)
    public fun get_unbondings<BondCoin>(
        addr: address,
        start_after_validator: Option<String>,
        start_after_release_time: Option<u64>,
        limit: u8,
    ): vector<UnbondingResponse> acquires DelegationStore, GlobalStateStore {
        if (limit > MAX_LIMIT) {
            limit = MAX_LIMIT;
        };

        assert!(
            is_account_registered<BondCoin>(addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        assert!(
            option::is_some(&start_after_validator) == option::is_some(&start_after_release_time),
            error::invalid_argument(EINVALID_START_AFTER)
        );

        let delegation_store = borrow_global<DelegationStore<BondCoin>>(addr);

        let start_after = if (option::is_some(&start_after_validator)) {
            option::some(UnbondingKey {
                validator: *option::borrow(&start_after_validator),
                release_time: *option::borrow(&start_after_release_time),
            })
        } else {
            option::none()
        };

        let unbondings_iter = table::iter(
            &delegation_store.unbondings,
            option::none(),
            start_after,
            2,
        );

        let res: vector<UnbondingResponse> = vector[];

        while (vector::length(&res) < (limit as u64) && table::prepare<UnbondingKey, Unbonding<BondCoin>>(
            &mut unbondings_iter
        )) {
            let (_, unbonding) = table::next<UnbondingKey, Unbonding<BondCoin>>(&mut unbondings_iter);
            let unbonding_amount = get_unbonding_amount_from_unbonding<BondCoin>(unbonding);
            vector::push_back(
                &mut res,
                UnbondingResponse {
                    validator: unbonding.validator,
                    unbonding_amount,
                    release_time: unbonding.release_time,
                },
            );
        };

        res
    }

    /// query helpers

    /// get `validator` from `DelegationResponse`
    public fun get_validator_from_delegation_response(delegation_res: &DelegationResponse): String {
        delegation_res.validator
    }

    /// get `share` from `DelegationResponse`
    public fun get_share_from_delegation_response(delegation_res: &DelegationResponse): u64 {
        delegation_res.share
    }

    /// get `unclaimed_reward` from `DelegationResponse`
    public fun get_unclaimed_reward_from_delegation_response(delegation_res: &DelegationResponse): u64 {
        delegation_res.unclaimed_reward
    }

    /// get `release_time` from `UnbondingResponse`
    public fun get_release_time_from_unbonding_response(unbonding_res: &UnbondingResponse): u64 {
        unbonding_res.release_time
    }

    /// get `unbonding_amount` from `UnbondingResponse`
    public fun get_unbonding_amount_from_unbonding_response(unbonding_res: &UnbondingResponse): u64 {
        unbonding_res.unbonding_amount
    }

    //
    // Execute entry functions
    // 

    // Chain functions

    /// Check signer is chain
    fun check_chain_permission(chain: &signer) {
        assert!(signer::address_of(chain) == @initia_std, error::permission_denied(EUNAUTHORIZED));
    }

    /// Initialize, Make global store
    entry fun initialize_for_chain<BondCoin>(chain: &signer) {
        check_chain_permission(chain);
        dex::check_liquidity_token<BondCoin>();

        assert!(
            !exists<GlobalStateStore<BondCoin>>(@initia_std),
            error::already_exists(EGLOBAL_STORE_ALREADY_PUBLISHED)
        );
        move_to(chain, GlobalStateStore<BondCoin> { global_states: table::new() });

        // register CoinStore for relayer;
        if (!coin::is_account_registered<BondCoin>(@relayer)) {
            let staking_module = create_signer_for_friend(@relayer);
            coin::register<BondCoin>(&staking_module);
        }
    }

    /// Slash unbonding coin 
    entry fun slash_unbonding_for_chain<BondCoin>(
        chain: &signer,
        validator: String,
        fraction: String
    ) acquires GlobalStateStore {
        check_chain_permission(chain);

        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);

        assert!(table::contains(&global_store.global_states, validator), error::not_found(EGLOBAL_STATE_NOT_PUBLISHED));
        let state = table::borrow_mut(&mut global_store.global_states, validator);
        let fraction = decimal128::from_string(&fraction);

        let unbonding_amount = coin::value(&state.unbonding_coin);
        let slash_amount = decimal128::mul_u64(&fraction, unbonding_amount);
        if (slash_amount > 0) {
            let slash_coin = coin::extract(&mut state.unbonding_coin, slash_amount);
            dex::burn_lp(slash_coin);
        }
    }

    /// Deposit unbonding coin to global store
    entry fun deposit_unbonding_coin_for_chain<BondCoin>(
        chain: &signer,
        validators: vector<String>,
        amounts: vector<u64>
    ) acquires GlobalStateStore {
        check_chain_permission(chain);

        assert!(vector::length(&validators) == vector::length(&amounts), error::invalid_argument(ELENGTH_MISMATCH));
        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);
        let staking_module = create_signer_for_friend(@relayer);

        let index = 0;
        while (index < vector::length(&validators)) {
            let validator = *vector::borrow(&validators, index);
            let amount = *vector::borrow(&amounts, index);

            assert!(
                table::contains(&global_store.global_states, validator),
                error::not_found(EGLOBAL_STATE_NOT_PUBLISHED)
            );
            let state = table::borrow_mut(&mut global_store.global_states, validator);

            // calculate share
            let total_unbonding_amount = coin::value(&state.unbonding_coin);
            let share_amount_ratio = if (total_unbonding_amount == 0) {
                decimal128::one()
            } else {
                decimal128::from_ratio(state.unbonding_share, (total_unbonding_amount as u128))
            };

            let share_diff = decimal128::mul_u64(&share_amount_ratio, amount);
            state.unbonding_share = state.unbonding_share + (share_diff as u128);

            let unbonding_coin = coin::withdraw<BondCoin>(&staking_module, amount);
            coin::merge<BondCoin>(&mut state.unbonding_coin, unbonding_coin);

            index = index + 1;
        }
    }

    /// Deposit staking reward, and update `reward_index`
    entry fun deposit_reward_for_chain<BondCoin>(
        chain: &signer,
        validators: vector<String>,
        amounts: vector<u64>
    ) acquires GlobalStateStore {
        check_chain_permission(chain);

        assert!(vector::length(&validators) == vector::length(&amounts), error::invalid_argument(ELENGTH_MISMATCH));
        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);
        let staking_module = create_signer_for_friend(@relayer);

        let index = 0;
        while (index < vector::length(&validators)) {
            let validator = *vector::borrow(&validators, index);
            let amount = *vector::borrow(&amounts, index);
            let reward = coin::withdraw<RewardCoin>(&staking_module, amount);

            assert!(
                table::contains(&global_store.global_states, validator),
                error::not_found(EGLOBAL_STATE_NOT_PUBLISHED)
            );
            let state = table::borrow_mut(&mut global_store.global_states, validator);

            state.reward_index = decimal128::add(
                &state.reward_index,
                &decimal128::from_ratio((amount as u128), state.total_share),
            );

            coin::merge(&mut state.reward, reward);

            index = index + 1;
        }
    }

    /// Register an account delegation store
    public entry fun register<BondCoin>(account: &signer) {
        let account_addr = signer::address_of(account);
        assert!(
            !is_account_registered<BondCoin>(account_addr),
            error::already_exists(EDELEGATION_STORE_ALREADY_PUBLISHED),
        );

        let delegation_store = DelegationStore<BondCoin> {
            delegations: table::new<String, Delegation<BondCoin>>(),
            unbondings: table::new<UnbondingKey, Unbonding<BondCoin>>(),
            delegation_events: event::new_event_handle<DelegationEvent>(account),
            unbonding_events: event::new_event_handle<UnbondingEvent>(account),
            reward_events: event::new_event_handle<RewardEvent>(account),
        };

        move_to(account, delegation_store);
    }

    /// Delegate coin to a validator and deposit reward to signer.
    public entry fun delegate_script<BondCoin>(
        account: &signer,
        validator: String,
        amount: u64,
    ) acquires DelegationStore, GlobalStateStore {
        let account_addr = signer::address_of(account);
        if (!is_account_registered<BondCoin>(account_addr)) {
            register<BondCoin>(account);
        };

        let coin = coin::withdraw<BondCoin>(account, amount);
        let delegation = delegate(validator, coin);

        let reward = deposit_delegation<BondCoin>(account_addr, delegation);

        let delegation_store = borrow_global_mut<DelegationStore<BondCoin>>(account_addr);

        event::emit_event<RewardEvent>(
            &mut delegation_store.reward_events,
            RewardEvent {
                amount: coin::value(&reward),
            }
        );

        coin::deposit(account_addr, reward);
    }

    /// Undelegate coin from a validator and deposit reward to signer.
    /// unbonding amount can be slightly different with input amount due to round error.
    public entry fun undelegate_script<BondCoin>(
        account: &signer,
        validator: String,
        amount: u64,
    ) acquires DelegationStore, GlobalStateStore {
        let account_addr = signer::address_of(account);

        assert!(
            is_account_registered<BondCoin>(account_addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let share = amount_to_share<BondCoin>(*string::bytes(&validator), amount);
        let delegation = withdraw_delegation<BondCoin>(account, validator, share);
        let (reward, unbonding) = undelegate(delegation);

        let delegation_store = borrow_global_mut<DelegationStore<BondCoin>>(account_addr);

        event::emit_event<RewardEvent>(
            &mut delegation_store.reward_events,
            RewardEvent {
                amount: coin::value(&reward),
            }
        );

        coin::deposit(account_addr, reward);
        deposit_unbonding<BondCoin>(account_addr, unbonding);
    }

    /// Claim `unbonding_coin` from expired unbonding.
    public entry fun claim_unbonding_script<BondCoin>(
        account: &signer,
        validator: String,
        release_time: u64
    ) acquires DelegationStore, GlobalStateStore {
        let account_addr = signer::address_of(account);

        assert!(
            is_account_registered<BondCoin>(account_addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        // withdraw unbonding all
        let unbonding_info = get_unbonding<BondCoin>(account_addr, validator, release_time);
        let unbonding = withdraw_unbonding<BondCoin>(account, validator, release_time, unbonding_info.unbonding_amount);
        let unbonding_coin = claim_unbonding<BondCoin>(unbonding);
        coin::deposit(account_addr, unbonding_coin)
    }

    public entry fun claim_reward_script<BondCoin>(
        account: &signer,
        validator: String
    ) acquires DelegationStore, GlobalStateStore {
        let account_addr = signer::address_of(account);

        assert!(
            is_account_registered<BondCoin>(account_addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let delegation_store = borrow_global_mut<DelegationStore<BondCoin>>(account_addr);

        assert!(table::contains(&delegation_store.delegations, validator), error::not_found(EDELEGATION_NOT_FOUND));

        let delegation = table::borrow_mut(&mut delegation_store.delegations, validator);
        let reward = claim_reward(delegation);

        event::emit_event<RewardEvent>(
            &mut delegation_store.reward_events,
            RewardEvent {
                amount: coin::value(&reward),
            }
        );

        coin::deposit(account_addr, reward);
    }

    ///
    /// Helpers and public functions 
    /// 

    /// For delegation object

    /// return empty delegation resource
    public fun empty_delegation<BondCoin>(validator: String): Delegation<BondCoin> {
        Delegation {
            share: 0,
            validator,
            reward_index: decimal128::zero(),
        }
    }

    /// Get `share` from `Delegation`
    public fun get_share_from_delegation<BondCoin>(delegation: &Delegation<BondCoin>): u64 {
        delegation.share
    }

    /// Get `validator` from `Delegation`
    public fun get_validator_from_delegation<BondCoin>(delegation: &Delegation<BondCoin>): String {
        delegation.validator
    }

    /// Destory empty delegation
    public fun destroy_empty_delegation<BondCoin>(delegation: Delegation<BondCoin>) {
        assert!(delegation.share == 0, error::invalid_argument(ENOT_EMPTY));
        let Delegation { share: _, validator: _, reward_index: _ } = delegation;
    }

    /// Deposit the delegation into recipient's account.
    public fun deposit_delegation<BondCoin>(
        account_addr: address,
        delegation: Delegation<BondCoin>,
    ): Coin<RewardCoin> acquires DelegationStore, GlobalStateStore {
        assert!(
            is_account_registered<BondCoin>(account_addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let delegation_store = borrow_global_mut<DelegationStore<BondCoin>>(account_addr);
        if (!table::contains(&delegation_store.delegations, delegation.validator)) {
            table::add(
                &mut delegation_store.delegations, delegation.validator,
                empty_delegation(delegation.validator),
            );
        };


        event::emit_event<DelegationEvent>(
            &mut delegation_store.delegation_events,
            DelegationEvent {
                action: string::utf8(b"deposit"),
                coin_type: type_info::type_name<BondCoin>(),
                share: delegation.share,
                validator: delegation.validator,
            }
        );

        let dst_delegation = table::borrow_mut(&mut delegation_store.delegations, delegation.validator);
        merge_delegation(dst_delegation, delegation)
    }

    /// Withdraw specified `share` from delegation.
    public fun withdraw_delegation<BondCoin>(
        account: &signer,
        validator: String,
        share: u64,
    ): Delegation<BondCoin> acquires DelegationStore {
        let account_addr = signer::address_of(account);

        assert!(
            is_account_registered<BondCoin>(account_addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let delegation_store = borrow_global_mut<DelegationStore<BondCoin>>(account_addr);
        let delegation = table::borrow_mut(&mut delegation_store.delegations, validator);

        event::emit_event<DelegationEvent>(
            &mut delegation_store.delegation_events,
            DelegationEvent {
                action: string::utf8(b"withdraw"),
                coin_type: type_info::type_name<BondCoin>(),
                share,
                validator,
            }
        );

        // If withdraw all, remove delegation
        if (delegation.share == share) {
            table::remove(&mut delegation_store.delegations, validator)
            // Else extract
        } else {
            extract_delegation<BondCoin>(delegation, share)
        }
    }

    /// Extracts specified share of delegatiion from the passed-in `delegation`.
    public fun extract_delegation<BondCoin>(delegation: &mut Delegation<BondCoin>, share: u64): Delegation<BondCoin> {
        assert!(delegation.share >= share, error::invalid_argument(EINSUFFICIENT_AMOUNT));

        // Total share is invariant and reward_indexes are same btw given and new one so no need to update `reward_index`.
        delegation.share = delegation.share - share;
        Delegation {
            share,
            validator: delegation.validator,
            reward_index: delegation.reward_index
        }
    }

    /// "Merges" the two given delegations.  The delegation passed in as `dst_delegation` will have a value equal
    /// to the sum of the two shares (`dst_delegation` and `source_delegation`).
    public fun merge_delegation<BondCoin>(
        dst_delegation: &mut Delegation<BondCoin>,
        source_delegation: Delegation<BondCoin>
    ): Coin<RewardCoin> acquires GlobalStateStore {
        assert!(
            dst_delegation.validator == source_delegation.validator,
            error::invalid_argument(EVALIDATOR_MISMATCH),
        );

        spec {
            assume dst_delegation.share + source_delegation.share <= MAX_U64;
        };

        let reward = claim_reward(dst_delegation);

        dst_delegation.share = dst_delegation.share + source_delegation.share;
        let source_reward = destroy_delegation_extract_reward(source_delegation);
        coin::merge(&mut reward, source_reward);

        reward
    }

    /// For unbonding object
    /// 

    fun unbonding_share_from_amount<BondCoin>(validator: String, unbonding_amount: u64): u64 acquires GlobalStateStore {
        let global_store = borrow_global<GlobalStateStore<BondCoin>>(@initia_std);

        assert!(table::contains(&global_store.global_states, validator), error::not_found(EGLOBAL_STATE_NOT_PUBLISHED));
        let state = table::borrow(&global_store.global_states, validator);

        let total_unbonding_amount = coin::value(&state.unbonding_coin);
        let share_amount_ratio = if (total_unbonding_amount == 0) {
            decimal128::one()
        } else {
            decimal128::from_ratio(state.unbonding_share, (total_unbonding_amount as u128))
        };

        decimal128::mul_u64(&share_amount_ratio, unbonding_amount)
    }

    fun unbonding_amount_from_share<BondCoin>(validator: String, unbonding_share: u64): u64 acquires GlobalStateStore {
        let global_store = borrow_global<GlobalStateStore<BondCoin>>(@initia_std);

        assert!(table::contains(&global_store.global_states, validator), error::not_found(EGLOBAL_STATE_NOT_PUBLISHED));
        let state = table::borrow(&global_store.global_states, validator);

        let total_unbonding_amount = coin::value(&state.unbonding_coin);
        let amount_share_ratio = if (state.unbonding_share == 0) {
            decimal128::one()
        } else {
            decimal128::from_ratio((total_unbonding_amount as u128), state.unbonding_share)
        };

        decimal128::mul_u64(&amount_share_ratio, unbonding_share)
    }


    /// return empty unbonding resource
    public fun empty_unbonding<BondCoin>(validator: String, release_time: u64): Unbonding<BondCoin> {
        Unbonding {
            validator,
            unbonding_share: 0,
            release_time,
        }
    }

    /// Get `validator` from `Unbonding`
    public fun get_validator_from_unbonding<BondCoin>(unbonding: &Unbonding<BondCoin>): String {
        unbonding.validator
    }

    /// Get `release_time` from `Unbonding`
    public fun get_release_time_from_unbonding<BondCoin>(unbonding: &Unbonding<BondCoin>): u64 {
        unbonding.release_time
    }

    /// Get `unbonding_share` from `Unbonding`
    public fun get_unbonding_share_from_unbonding<BondCoin>(unbonding: &Unbonding<BondCoin>): u64 {
        unbonding.unbonding_share
    }

    /// Get `unbonding_amount` from `Unbonding`
    public fun get_unbonding_amount_from_unbonding<BondCoin>(
        unbonding: &Unbonding<BondCoin>
    ): u64 acquires GlobalStateStore {
        unbonding_amount_from_share<BondCoin>(unbonding.validator, unbonding.unbonding_share)
    }

    /// Destory empty unbonding
    public fun destroy_empty_unbonding<BondCoin>(unbonding: Unbonding<BondCoin>) {
        assert!(unbonding.unbonding_share == 0, error::invalid_argument(ENOT_EMPTY));
        let Unbonding { validator: _, unbonding_share: _, release_time: _ } = unbonding;
    }

    /// Deposit the unbonding into recipient's account.
    public fun deposit_unbonding<BondCoin>(
        account_addr: address,
        unbonding: Unbonding<BondCoin>
    ) acquires DelegationStore {
        assert!(
            is_account_registered<BondCoin>(account_addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let key = UnbondingKey {
            validator: unbonding.validator,
            release_time: unbonding.release_time,
        };

        let delegation_store = borrow_global_mut<DelegationStore<BondCoin>>(account_addr);
        if (!table::contains(&delegation_store.unbondings, key)) {
            table::add(
                &mut delegation_store.unbondings, key,
                empty_unbonding(unbonding.validator, unbonding.release_time),
            );
        };

        event::emit_event<UnbondingEvent>(
            &mut delegation_store.unbonding_events,
            UnbondingEvent {
                action: string::utf8(b"deposit"),
                coin_type: type_info::type_name<BondCoin>(),
                validator: unbonding.validator,
                share: unbonding.unbonding_share,
                release_time: unbonding.release_time,
            }
        );

        let dst_unbonding = table::borrow_mut(&mut delegation_store.unbondings, key);
        merge_unbonding(dst_unbonding, unbonding);
    }

    /// Withdraw specifed `amount` of unbonding_amount from the unbonding.
    public fun withdraw_unbonding<BondCoin>(
        account: &signer,
        validator: String,
        release_time: u64,
        amount: u64,
    ): Unbonding<BondCoin> acquires DelegationStore, GlobalStateStore {
        let account_addr = signer::address_of(account);

        assert!(
            is_account_registered<BondCoin>(account_addr),
            error::not_found(EDELEGATION_STORE_NOT_PUBLISHED),
        );

        let delegation_store = borrow_global_mut<DelegationStore<BondCoin>>(account_addr);

        let key = UnbondingKey { validator, release_time };
        assert!(table::contains(&delegation_store.unbondings, key), error::not_found(EUNBONDING_NOT_FOUND));
        let unbonding = table::borrow_mut(&mut delegation_store.unbondings, key);

        event::emit_event<UnbondingEvent>(
            &mut delegation_store.unbonding_events,
            UnbondingEvent {
                action: string::utf8(b"withdraw"),
                coin_type: type_info::type_name<BondCoin>(),
                validator,
                share: unbonding.unbonding_share,
                release_time: unbonding.release_time,
            }
        );

        // If withdraw all, remove unbonding
        let share = unbonding_share_from_amount<BondCoin>(validator, amount);
        if (unbonding.unbonding_share == share) {
            table::remove(&mut delegation_store.unbondings, key)
            // Else extract
        } else {
            extract_unbonding(unbonding, share)
        }
    }

    /// Extracts specified amount of unbonding from the passed-in `unbonding`.
    public fun extract_unbonding<BondCoin>(unbonding: &mut Unbonding<BondCoin>, share: u64): Unbonding<BondCoin> {
        assert!(
            unbonding.unbonding_share >= share,
            error::invalid_argument(EINSUFFICIENT_AMOUNT),
        );

        unbonding.unbonding_share = unbonding.unbonding_share - share;
        Unbonding { validator: unbonding.validator, unbonding_share: share, release_time: unbonding.release_time }
    }

    /// Merge the two given unbondings. The unbonding_coin of the `source_unbonding` 
    /// will be merged into the unbonding_coin of the `dst_unbonding`.
    /// `release_time` of the `source_unbonding` must be sooner than or equal to the one of `dst_unbonding`
    public fun merge_unbonding<BondCoin>(
        dst_unbonding: &mut Unbonding<BondCoin>,
        source_unbonding: Unbonding<BondCoin>
    ) {
        assert!(dst_unbonding.validator == source_unbonding.validator, error::invalid_argument(EVALIDATOR_MISMATCH));
        assert!(dst_unbonding.release_time >= source_unbonding.release_time, error::invalid_argument(ERELEASE_TIME));

        spec {
            assume dst_unbonding.unbonding_share + source_unbonding.unbonding_share <= MAX_U64;
        };

        dst_unbonding.unbonding_share = dst_unbonding.unbonding_share + source_unbonding.unbonding_share;
        let Unbonding { validator: _, unbonding_share: _, release_time: _ } = source_unbonding;
    }

    /// Claim `unbonding_coin` from expired unbonding.
    public fun claim_unbonding<BondCoin>(unbonding: Unbonding<BondCoin>): Coin<BondCoin> acquires GlobalStateStore {
        let (_, timestamp) = block::get_block_info();
        assert!(unbonding.release_time <= timestamp, error::invalid_state(ENOT_RELEASED));

        let unbonding_amount = get_unbonding_amount_from_unbonding(&unbonding);
        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);

        // extract coin
        assert!(
            table::contains(&global_store.global_states, unbonding.validator),
            error::not_found(EGLOBAL_STATE_NOT_PUBLISHED)
        );
        let state = table::borrow_mut(&mut global_store.global_states, unbonding.validator);
        let unbonding_coin = coin::extract(&mut state.unbonding_coin, unbonding_amount);

        // decrease share
        state.unbonding_share = state.unbonding_share - (unbonding.unbonding_share as u128);

        // destroy empty
        let Unbonding { validator: _, unbonding_share: _, release_time: _ } = unbonding;

        unbonding_coin
    }

    /// Others

    /// Check the DelegationStore is already exist
    public fun is_account_registered<BondCoin>(account_addr: address): bool {
        exists<DelegationStore<BondCoin>>(account_addr)
    }

    /// Claim staking reward from the specified validator.
    public fun claim_reward<BondCoin>(
        delegation: &mut Delegation<BondCoin>
    ): Coin<RewardCoin> acquires GlobalStateStore {
        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);

        assert!(
            table::contains(&global_store.global_states, delegation.validator),
            error::not_found(EGLOBAL_STATE_NOT_PUBLISHED)
        );
        let state = table::borrow_mut(&mut global_store.global_states, delegation.validator);

        let reward_amount = calculate_reward(delegation, state);
        let reward = coin::extract(&mut state.reward, reward_amount);
        delegation.reward_index = state.reward_index;

        reward
    }

    /// Destory delegation and extract reward from delegation
    fun destroy_delegation_extract_reward<BondCoin>(
        delegation: Delegation<BondCoin>
    ): Coin<RewardCoin> acquires GlobalStateStore {
        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);

        assert!(
            table::contains(&global_store.global_states, delegation.validator),
            error::not_found(EGLOBAL_STATE_NOT_PUBLISHED)
        );
        let state = table::borrow_mut(&mut global_store.global_states, delegation.validator);

        let reward_amount = calculate_reward(&delegation, state);
        let reward = coin::extract(&mut state.reward, reward_amount);
        let Delegation { share: _, validator: _, reward_index: _ } = delegation;

        reward
    }

    /// calculate unclaimed reward
    fun calculate_reward<BondCoin>(delegation: &Delegation<BondCoin>, state: &GlobalState<BondCoin>): u64 {
        let index_diff = decimal128::sub(&state.reward_index, &delegation.reward_index);
        decimal128::mul_u64(&index_diff, delegation.share)
    }

    /// Delegate a coin to a validator of the given Delegation object.
    public fun delegate<BondCoin>(
        validator: String,
        amount: Coin<BondCoin>,
    ): Delegation<BondCoin> acquires GlobalStateStore {
        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);
        if (!table::contains(&mut global_store.global_states, validator)) {
            table::add(
                &mut global_store.global_states,
                validator,
                GlobalState<BondCoin> {
                    validator,
                    reward_index: decimal128::zero(),
                    total_share: 0,
                    reward: coin::zero(),
                    unbonding_coin: coin::zero(),
                    unbonding_share: 0,
                },
            )
        };

        let share_diff = delegate_internal<BondCoin>(*string::bytes(&validator), coin::value(&amount));
        let state = table::borrow_mut(&mut global_store.global_states, validator);
        state.total_share = state.total_share + (share_diff as u128);

        let delegation = Delegation {
            share: share_diff,
            validator,
            reward_index: state.reward_index,
        };

        coin::deposit<BondCoin>(@relayer, amount);

        delegation
    }

    /// Undelegate a coin from a validator of the given Delegation object.
    public fun undelegate<BondCoin>(
        delegation: Delegation<BondCoin>,
    ): (Coin<RewardCoin>, Unbonding<BondCoin>) acquires GlobalStateStore {
        let share = delegation.share;
        let validator = delegation.validator;

        let (unbonding_amount, release_time) = undelegate_internal<BondCoin>(*string::bytes(&validator), share);
        let reward = destroy_delegation_extract_reward(delegation);

        let global_store = borrow_global_mut<GlobalStateStore<BondCoin>>(@initia_std);

        assert!(table::contains(&global_store.global_states, validator), error::not_found(EGLOBAL_STATE_NOT_PUBLISHED));
        let state = table::borrow_mut(&mut global_store.global_states, validator);

        assert!(state.total_share >= (share as u128), error::invalid_state(EINSUFFICIENT_AMOUNT));
        state.total_share = state.total_share - (share as u128);

        let unbonding_share = unbonding_share_from_amount<BondCoin>(validator, unbonding_amount);
        let unbonding = Unbonding { validator, unbonding_share, release_time };

        (reward, unbonding)
    }

    //! Native functions
    native fun delegate_internal<BondCoin>(validator: vector<u8>, amount: u64): u64 /* share amount */;

    native fun undelegate_internal<BondCoin>(
        validator: vector<u8>,
        share: u64
    ): (u64 /* unbonding amount */, u64 /* unbond timestamp */);

    native public fun share_to_amount<BondCoin>(validator: vector<u8>, share: u64): u64 /* delegation amount */;

    native public fun amount_to_share<BondCoin>(validator: vector<u8>, amount: u64): u64 /* share amount */;

    #[test_only]
    struct CoinLP {}

    #[test_only]
    struct CoinA {}
    
    #[test_only]
    struct CoinB {}

    #[test_only]
    native public fun set_staking_share_ratio<BondCoin>(validator: vector<u8>, share: u64, amount: u64);

    #[test_only]
    public fun deposit_reward_for_test<BondCoin>(
        chain: &signer,
        validators: vector<String>,
        amounts: vector<u64>
    ) acquires GlobalStateStore {
        deposit_reward_for_chain<BondCoin>(chain, validators, amounts);
    }

    #[test_only]
    use std::block::set_block_info;

    #[test_only]
    use std::coin::{BurnCapability, FreezeCapability, MintCapability};

    #[test_only]
    struct TestCapabilityStore<phantom CoinType> has key {
        burn_cap: BurnCapability<CoinType>,
        freeze_cap: FreezeCapability<CoinType>,
        mint_cap: MintCapability<CoinType>,
    }

    #[test_only]
    fun test_setup(chain: &signer) {
        let _ = test_setup_with_pool_balances(chain, 100000000000000, 100000000000000);
    }

    #[test_only]
    public fun test_setup_with_pool_balances(chain: &signer, coin_a_amount: u64, coin_b_amount: u64): u64 {
        let chain_addr = signer::address_of(chain);

        dex::init_module_for_test(chain);
        coin::init_module_for_test(chain);

        // initialize reward coin
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<RewardCoin>(
            chain,
            string::utf8(b"INIT Coin"),
            string::utf8(b"uinit"),
            6,
        );

        move_to(chain, TestCapabilityStore<RewardCoin> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        // initialize dex coinA
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinA>(
            chain,
            string::utf8(b"CoinA"),
            string::utf8(b"CoinA"),
            6,
        );

        coin::register<CoinA>(chain);
        coin::deposit<CoinA>(chain_addr, coin::mint(coin_a_amount, &mint_cap));
        move_to(chain, TestCapabilityStore<CoinA> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        // initialize dex coinB
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<CoinB>(
            chain,
            string::utf8(b"CoinB"),
            string::utf8(b"CoinB"),
            6,
        );

        coin::register<CoinB>(chain);
        coin::deposit<CoinB>(chain_addr, coin::mint(coin_b_amount, &mint_cap));
        move_to(chain, TestCapabilityStore<CoinB> {
            burn_cap,
            freeze_cap,
            mint_cap,
        });

        // initialize staking coin
        dex::create_pair_script<CoinA, CoinB, CoinLP>(
            chain, 
            string::utf8(b"LP Coin"),
            string::utf8(b"LP"),
            string::utf8(b"0.8"),
            string::utf8(b"0.2"),
            string::utf8(b"0.003"),
            coin_a_amount,
            coin_b_amount,
        );

        // register RewardCoin coin store for relayer
        // CoinLP coin store will be created at staking::initialize
        let relayer = create_signer_for_friend(@relayer);
        coin::register<RewardCoin>(&relayer);

        initialize_for_chain<CoinLP>(chain);

        // return minted lp coin balance
        coin::balance<CoinLP>(chain_addr)
    }

    #[test_only]
    public fun fund_stake_coin(chain: &signer, receiver: address, amount: u64) {
        coin::deposit<CoinLP>(receiver, coin::withdraw<CoinLP>(chain, amount));
    }

    #[test_only]
    public fun fund_reward_coin(c_addr: address, m_addr: address, amt: u64) acquires TestCapabilityStore {
        let caps = borrow_global<TestCapabilityStore<RewardCoin>>(c_addr);
        let reward = coin::mint<RewardCoin>(amt, &caps.mint_cap);
        coin::deposit<RewardCoin>(m_addr, reward);
    }

    #[test(chain = @0x1, user1 = @0x1234, user2 = @0x4321)]
    fun end_to_end(
        chain: &signer,
        user1: &signer,
        user2: &signer,
    ) acquires DelegationStore, GlobalStateStore, TestCapabilityStore {
        test_setup(chain);

        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);
        let validator = string::utf8(b"validator");

        coin::register<CoinLP>(user1);
        coin::register<RewardCoin>(user1);
        coin::register<CoinLP>(user2);
        coin::register<RewardCoin>(user2);

        fund_stake_coin(chain, user1_addr, 1000000000);
        set_block_info(100, 10000);

        register<CoinLP>(user1);
        register<CoinLP>(user2);

        set_staking_share_ratio<CoinLP>(*string::bytes(&validator), 1, 1);

        delegate_script<CoinLP>(user1, validator, 10000000);

        assert!(coin::balance<CoinLP>(user1_addr) == 990000000, 0);

        let delegation = get_delegation<CoinLP>(user1_addr, validator);
        assert!(delegation.validator == validator, 1);
        assert!(delegation.share == 10000000, 2);
        assert!(delegation.unclaimed_reward == 0, 3);

        let capabilities = borrow_global<TestCapabilityStore<RewardCoin>>(signer::address_of(chain));
        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(1000000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[1000000]);

        let delegation = get_delegation<CoinLP>(user1_addr, validator);
        assert!(delegation.unclaimed_reward == 1000000, 4);

        let withdrawn_delegation = withdraw_delegation<CoinLP>(user1, validator, 5000000);
        let reward = deposit_delegation<CoinLP>(user2_addr, withdrawn_delegation);
        assert!(coin::value(&reward) == 500000, 5);
        coin::deposit(user1_addr, reward);

        let delegation = get_delegation<CoinLP>(user1_addr, validator);
        assert!(delegation.unclaimed_reward == 500000, 6);

        claim_reward_script<CoinLP>(user1, validator);
        assert!(coin::balance<RewardCoin>(user1_addr) == 1000000, 8);
        let delegation = get_delegation<CoinLP>(user1_addr, validator);
        assert!(delegation.unclaimed_reward == 0, 8);

        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(1000000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[1000000]);
        let delegation = get_delegation<CoinLP>(user1_addr, validator);
        assert!(delegation.unclaimed_reward == 500000, 9);

        undelegate_script<CoinLP>(user1, validator, 5000000);
        assert!(coin::balance<RewardCoin>(user1_addr) == 1500000, 10);

        // undelegate trigger `deposit_unbonding_coin_for_chain`
        deposit_unbonding_coin_for_chain<CoinLP>(chain, vector[validator], vector[5000000]);

        let unbondings = get_unbondings<CoinLP>(user1_addr, option::none(), option::none(), 1);
        let unbonding = vector::borrow(&unbondings, 0);

        let withdrawn_unbonding = withdraw_unbonding<CoinLP>(
            user1,
            validator,
            unbonding.release_time,
            2500000,
        );

        deposit_unbonding<CoinLP>(user2_addr, withdrawn_unbonding);

        let unbonding = get_unbonding<CoinLP>(user1_addr, validator, unbonding.release_time);
        assert!(unbonding.unbonding_amount == 2500000, 11);
        let unbonding = get_unbonding<CoinLP>(user2_addr, validator, unbonding.release_time);
        assert!(unbonding.unbonding_amount == 2500000, 12);

        set_block_info(100, 8640000);

        claim_unbonding_script<CoinLP>(user1, validator, unbonding.release_time);
        assert!(coin::balance<CoinLP>(user1_addr) == 992500000, 13);
    }

    #[test(chain = @0x1, user = @0x1234)]
    public fun test_delegate(
        chain: &signer,
        user: &signer,
    ) acquires DelegationStore, GlobalStateStore, TestCapabilityStore {
        test_setup(chain);

        let user_addr = signer::address_of(user);
        let validator = string::utf8(b"validator");

        coin::register<CoinLP>(user);
        coin::register<RewardCoin>(user);

        fund_stake_coin(chain, user_addr, 1000000);
        set_block_info(100, 10000);

        register<CoinLP>(user);

        set_staking_share_ratio<CoinLP>(*string::bytes(&validator), 1, 1);

        // Delegate with entry function
        delegate_script<CoinLP>(user, validator, 100000);

        let delegation = get_delegation<CoinLP>(user_addr, validator);
        assert!(delegation.share == 100000, 0);
        assert!(delegation.validator == validator, 1);
        assert!(coin::balance<CoinLP>(user_addr) == 900000, 2);

        // withdraw delegation
        let delegation0 = withdraw_delegation<CoinLP>(user, validator, 50000);
        let delegation = get_delegation<CoinLP>(user_addr, validator);
        assert!(delegation.share == 50000, 3);

        // withdraw all of rest delegation
        let delegation1 = withdraw_delegation(user, validator, 50000);
        let delegations = get_delegations<CoinLP>(user_addr, option::none(), 1);
        assert!(vector::length(&delegations) == 0, 4);

        let capabilities = borrow_global<TestCapabilityStore<RewardCoin>>(signer::address_of(chain));
        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(100000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[100000]);

        // deposit delegation
        let reward = deposit_delegation<CoinLP>(user_addr, delegation0);
        assert!(coin::value(&reward) == 50000, 5);

        let delegation = get_delegation<CoinLP>(user_addr, validator);
        assert!(delegation.share == 50000, 6);
        assert!(delegation.validator == validator, 7);

        coin::deposit(user_addr, reward);

        // extract delegation
        let delegation2 = extract_delegation(&mut delegation1, 10000);
        assert!(delegation1.share == 40000, 8);
        assert!(delegation2.share == 10000, 9);

        // merge delegation
        let reward = merge_delegation(&mut delegation1, delegation2);
        assert!(coin::value(&reward) == 50000, 13);
        assert!(delegation1.share == 50000, 14);
        coin::deposit(user_addr, reward);

        // delegate
        let coin = coin::withdraw<CoinLP>(user, 100000);
        let delegation3 = delegate(validator, coin);
        assert!(delegation3.share == 100000, 12);
        let reward = merge_delegation(&mut delegation1, delegation3);
        coin::destroy_zero(reward);

        let reward = deposit_delegation(user_addr, delegation1);
        assert!(coin::value(&reward) == 0, 15);
        coin::destroy_zero(reward);

        // 1000000 (mint) - 100000 (delegate_script) - 100000 (delegate)
        // 100000 (rewards)
        assert!(coin::balance<CoinLP>(user_addr) == 800000, 16);
        assert!(coin::balance<RewardCoin>(user_addr) == 100000, 17);

        let delegation = get_delegation<CoinLP>(user_addr, validator);
        assert!(delegation.share == 200000, 6);
    }

    #[test(chain = @0x1, user = @0x1234)]
    public fun test_undelegate(
        chain: &signer,
        user: &signer,
    ) acquires DelegationStore, GlobalStateStore, TestCapabilityStore {
        test_setup(chain);

        let user_addr = signer::address_of(user);
        let validator = string::utf8(b"validator");
        
        coin::register<CoinLP>(user);
        coin::register<RewardCoin>(user);

        fund_stake_coin(chain, user_addr, 1000000);
        set_block_info(100, 10000);

        register<CoinLP>(user);

        set_staking_share_ratio<CoinLP>(*string::bytes(&validator), 1, 1);

        delegate_script<CoinLP>(user, validator, 100000);

        let capabilities = borrow_global<TestCapabilityStore<RewardCoin>>(signer::address_of(chain));
        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(100000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[100000]);

        // undelegate with script
        undelegate_script<CoinLP>(user, validator, 10000);

        // undelegate trigger `deposit_unbonding_coin_for_chain`
        deposit_unbonding_coin_for_chain<CoinLP>(chain, vector[validator], vector[10000]);

        let delegation = get_delegation<CoinLP>(user_addr, validator);
        assert!(delegation.share == 90000, 0);

        let unbondings = get_unbondings<CoinLP>(user_addr, option::none(), option::none(), 1);
        let unbonding = vector::borrow(&unbondings, 0);
        let release_time = unbonding.release_time;
        assert!(unbonding.unbonding_amount == 10000, 1);
        assert!(coin::balance<CoinLP>(user_addr) == 900000, 2);
        assert!(coin::balance<RewardCoin>(user_addr) == 10000, 3);

        // distribute reward
        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(90000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[90000]);

        // undelegate
        let delegation = withdraw_delegation<CoinLP>(user, validator, 10000);
        let (reward, unbonding0) = undelegate<CoinLP>(delegation);
        assert!(coin::value(&reward) == 20000, 4);
        assert!(unbonding0.unbonding_share == 10000, 5);

        // undelegate trigger `deposit_unbonding_coin_for_chain`
        deposit_unbonding_coin_for_chain<CoinLP>(chain, vector[validator], vector[10000]);

        coin::deposit(user_addr, reward);
        assert!(coin::balance<RewardCoin>(user_addr) == 30000, 3);

        // extract unbonding
        let unbonding1 = extract_unbonding<CoinLP>(&mut unbonding0, 5000);
        assert!(unbonding0.unbonding_share == 5000, 7);
        assert!(unbonding1.unbonding_share == 5000, 8);

        // merge unbonding
        merge_unbonding<CoinLP>(&mut unbonding0, unbonding1);
        assert!(unbonding0.unbonding_share == 10000, 9);

        // deposit unbonding
        deposit_unbonding<CoinLP>(user_addr, unbonding0);
        let unbonding = get_unbonding<CoinLP>(user_addr, validator, release_time);
        assert!(unbonding.unbonding_amount == 20000, 10);

        // withdraw unbonding
        let unbonding = withdraw_unbonding<CoinLP>(user, validator, release_time, 10000);
        assert!(unbonding.unbonding_share == 10000, 11);

        // claim unbonding
        set_block_info(200, release_time);
        let coin = claim_unbonding<CoinLP>(unbonding);
        assert!(coin::value(&coin) == 10000, 12);
        coin::deposit(user_addr, coin);

        // claim unbonding with script
        claim_unbonding_script<CoinLP>(user, validator, release_time);
        assert!(coin::balance<CoinLP>(user_addr) == 920000, 13);
    }

    #[test(chain = @0x1, user1 = @0x1234, user2 = @0x4321)]
    fun test_claim_reward(
        chain: &signer,
        user1: &signer,
        user2: &signer,
    ) acquires DelegationStore, GlobalStateStore, TestCapabilityStore {
        test_setup(chain);

        let user1_addr = signer::address_of(user1);
        let user2_addr = signer::address_of(user2);

        let validator = string::utf8(b"validator");

        coin::register<CoinLP>(user1);
        coin::register<RewardCoin>(user1);
        coin::register<CoinLP>(user2);
        coin::register<RewardCoin>(user2);

        fund_stake_coin(chain, user1_addr, 1000000);
        fund_stake_coin(chain, user2_addr, 1000000);

        set_block_info(100, 10000);

        register<CoinLP>(user1);
        register<CoinLP>(user2);

        set_staking_share_ratio<CoinLP>(*string::bytes(&validator), 1, 1);

        delegate_script<CoinLP>(user1, string::utf8(b"validator"), 1000000);

        let capabilities = borrow_global<TestCapabilityStore<RewardCoin>>(signer::address_of(chain));
        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(100000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[100000]);

        // claim reward by script
        claim_reward_script<CoinLP>(user1, validator);
        assert!(coin::balance<RewardCoin>(user1_addr) == 100000, 0);

        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(100000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[100000]);

        // claim reward
        let delegation = withdraw_delegation<CoinLP>(user1, validator, 1000000);
        let reward = claim_reward<CoinLP>(&mut delegation);
        assert!(coin::value(&reward) == 100000, 1);
        coin::deposit(user1_addr, reward);

        let reward = deposit_delegation<CoinLP>(user1_addr, delegation);
        assert!(coin::value(&reward) == 0, 2);
        coin::destroy_zero(reward);

        assert!(coin::balance<RewardCoin>(user1_addr) == 200000, 3);

        delegate_script<CoinLP>(user2, string::utf8(b"validator"), 1000000);

        coin::deposit<RewardCoin>(@relayer, coin::mint<RewardCoin>(100000, &capabilities.mint_cap));
        deposit_reward_for_chain<CoinLP>(chain, vector[validator], vector[100000]);
        claim_reward_script<CoinLP>(user1, validator);
        assert!(coin::balance<RewardCoin>(user1_addr) == 250000, 4);
    }

    #[test(chain = @0x1)]
    #[expected_failure(abort_code = 0x1000C, location = Self)]
    public fun test_destroy_not_empty_delegation(
        chain: &signer,
    ) {
        test_setup(chain);

        let delegation = Delegation<CoinLP> {
            share: 100,
            validator: string::utf8(b"validator"),
            reward_index: decimal128::zero(),
        };

        destroy_empty_delegation(delegation);
    }

    #[test(chain = @0x1)]
    #[expected_failure(abort_code = 0x1000C, location = Self)]
    public fun test_destroy_not_empty_unbonding(
        chain: &signer,
    ) {
        test_setup(chain);

        let unbonding = Unbonding<CoinLP> {
            validator: string::utf8(b"validator"),
            unbonding_share: 100,
            release_time: 1234,
        };

        destroy_empty_unbonding(unbonding);
    }

    #[test(chain = @0x1)]
    #[expected_failure(abort_code = 0x10006, location = Self)]
    public fun test_merge_delegation_validator_mistmatch(
        chain: &signer,
    ) acquires GlobalStateStore {
        test_setup(chain);

        let delegation1 = Delegation<CoinLP> {
            share: 100,
            validator: string::utf8(b"validator1"),
            reward_index: decimal128::zero(),
        };

        let delegation2 = Delegation<CoinLP> {
            share: 100,
            validator: string::utf8(b"validator2"),
            reward_index: decimal128::zero(),
        };

        let reward = merge_delegation(&mut delegation1, delegation2);
        let Delegation { share: _, validator: _, reward_index: _ } = delegation1;
        coin::destroy_zero(reward);
    }


    #[test(chain = @0x1)]
    #[expected_failure(abort_code = 0x10008, location = Self)]
    public fun test_merge_unbonding_release_time(
        chain: &signer,
    ) {
        test_setup(chain);

        let validator = string::utf8(b"validator");
        let unbonding1 = Unbonding<CoinLP> {
            validator,
            unbonding_share: 100,
            release_time: 1000,
        };

        let unbonding2 = Unbonding<CoinLP> {
            validator,
            unbonding_share: 100,
            release_time: 1234,
        };

        merge_unbonding(&mut unbonding1, unbonding2);
        let Unbonding { validator: _, unbonding_share, release_time: _ } = unbonding1;

        assert!(unbonding_share == 200, 1);
    }

    #[test(chain = @0x1, user = @0x1234)]
    #[expected_failure(abort_code = 0x30009, location = Self)]
    public fun test_claim_not_released_unbonding(
        chain: &signer,
        user: &signer,
    ) acquires GlobalStateStore, DelegationStore {
        test_setup(chain);

        let user_addr = signer::address_of(user);
        let validator = string::utf8(b"validator");

        coin::register<CoinLP>(user);
        coin::register<RewardCoin>(user);

        fund_stake_coin(chain, user_addr, 100);

        register<CoinLP>(user);

        set_staking_share_ratio<CoinLP>(*string::bytes(&validator), 1, 1);

        // dummy delegation to create global states
        delegate_script<CoinLP>(user, validator, 100);

        fund_stake_coin(chain, @relayer, 100);
        deposit_unbonding_coin_for_chain<CoinLP>(chain, vector[validator], vector[100]);

        set_block_info(100, 100);

        let unbonding = Unbonding<CoinLP> {
            validator,
            unbonding_share: 100,
            release_time: 1000,
        };

        let coin = claim_unbonding(unbonding);
        assert!(coin::value(&coin) == 100, 1);


        coin::deposit(@relayer, coin);
    }

    #[test(chain = @0x1, user = @0x1234)]
    public fun test_query_entry_functions(
        chain: &signer,
        user: &signer,
    ) acquires DelegationStore, GlobalStateStore {
        test_setup(chain);

        let user_addr = signer::address_of(user);
        let validator1 = string::utf8(b"validator1");
        let validator2 = string::utf8(b"validator2");

        coin::register<CoinLP>(user);
        coin::register<RewardCoin>(user);

        fund_stake_coin(chain, user_addr, 1000000);

        set_block_info(100, 10000);

        register<CoinLP>(user);

        set_staking_share_ratio<CoinLP>(*string::bytes(&validator1), 1, 1);
        set_staking_share_ratio<CoinLP>(*string::bytes(&validator2), 1, 1);

        delegate_script<CoinLP>(user, validator1, 100000);
        delegate_script<CoinLP>(user, validator2, 100000);

        undelegate_script<CoinLP>(user, validator1, 10000);
        undelegate_script<CoinLP>(user, validator2, 10000);

        // undelegate trigger `deposit_unbonding_coin_for_chain`
        deposit_unbonding_coin_for_chain<CoinLP>(chain, vector[validator1, validator2], vector[10000, 10000]);

        // update block info
        set_block_info(200, 20000);

        undelegate_script<CoinLP>(user, validator1, 10000);

        // undelegate trigger `deposit_unbonding_coin_for_chain`
        deposit_unbonding_coin_for_chain<CoinLP>(chain, vector[validator1], vector[10000]);

        let delegation = get_delegation<CoinLP>(user_addr, validator1);
        assert!(
            delegation == DelegationResponse {
                validator: validator1,
                share: 80000,
                unclaimed_reward: 0,
            },
            0,
        );

        let delegations = get_delegations<CoinLP>(user_addr, option::none(), 10);
        assert!(
            delegations == vector[
                DelegationResponse {
                    validator: validator2,
                    share: 90000,
                    unclaimed_reward: 0,
                },
                DelegationResponse {
                    validator: validator1,
                    share: 80000,
                    unclaimed_reward: 0,
                },
            ],
            1,
        );

        let delegations = get_delegations<CoinLP>(user_addr, option::some(validator2), 10);
        assert!(
            delegations == vector[
                DelegationResponse {
                    validator: validator1,
                    share: 80000,
                    unclaimed_reward: 0,
                },
            ],
            2,
        );

        let unbonding = get_unbonding<CoinLP>(user_addr, validator1, 10000 + 7 * 24 * 60 * 60);
        assert!(
            unbonding == UnbondingResponse {
                validator: validator1,
                unbonding_amount: 10000,
                release_time: 10000 + 7 * 24 * 60 * 60,
            },
            3,
        );

        let unbondings = get_unbondings<CoinLP>(user_addr, option::none(), option::none(), 10);
        assert!(
            unbondings == vector[
                UnbondingResponse {
                    validator: validator2,
                    unbonding_amount: 10000,
                    release_time: 10000 + 7 * 24 * 60 * 60,
                },
                UnbondingResponse {
                    validator: validator1,
                    unbonding_amount: 10000,
                    release_time: 20000 + 7 * 24 * 60 * 60,
                },
                UnbondingResponse {
                    validator: validator1,
                    unbonding_amount: 10000,
                    release_time: 10000 + 7 * 24 * 60 * 60,
                },
            ],
            4,
        );

        let unbondings = get_unbondings<CoinLP>(
            user_addr,
            option::some(validator1),
            option::some(20000 + 7 * 24 * 60 * 60),
            10
        );
        assert!(
            unbondings == vector[
                UnbondingResponse {
                    validator: validator1,
                    unbonding_amount: 10000,
                    release_time: 10000 + 7 * 24 * 60 * 60,
                },
            ],
            5,
        );
    }

    #[test]
    public fun test_share_to_amount() {
        let validator = vector::singleton(1u8);
        set_staking_share_ratio<CoinLP>(validator, 100u64, 50u64);

        let amount = share_to_amount<CoinLP>(vector::singleton(1u8), 2);
        assert!(amount == 1u64, 0);
    }

    #[test]
    public fun test_amount_to_share() {
        let validator = vector::singleton(1u8);
        set_staking_share_ratio<CoinLP>(validator, 100u64, 50u64);

        let share = amount_to_share<CoinLP>(validator, 1);
        assert!(share == 2u64, 0);
    }

    #[test(chain = @0x1, user = @0x1234)]
    public fun test_slash_unbonding(
        chain: &signer,
        user: &signer,
    ) acquires DelegationStore, GlobalStateStore {
        test_setup(chain);

        let user_addr = signer::address_of(user);
        let validator = string::utf8(b"validator");

        coin::register<CoinLP>(user);
        coin::register<RewardCoin>(user);

        fund_stake_coin(chain, user_addr, 1000000);

        set_block_info(100, 10000);
        set_staking_share_ratio<CoinLP>(*string::bytes(&validator), 1, 1);

        register<CoinLP>(user);
        delegate_script<CoinLP>(user, validator, 100000);
        undelegate_script<CoinLP>(user, validator, 10000);

        // undelegate trigger `deposit_unbonding_coin_for_chain`
        deposit_unbonding_coin_for_chain<CoinLP>(chain, vector[validator], vector[10000]);
        slash_unbonding_for_chain<CoinLP>(chain, validator, string::utf8(b"0.1")); // 10%

        let unbonding_response = get_unbonding<CoinLP>(user_addr, validator, 10000 + 7 * 24 * 60 * 60);
        assert!(unbonding_response.unbonding_amount == 9000, 1);
    }
}

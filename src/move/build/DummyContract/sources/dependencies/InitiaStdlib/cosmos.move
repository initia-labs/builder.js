/// This module provides interfaces to allow CosmosMessage 
/// execution after the move execution finished.
module initia_std::cosmos {
    use std::signer;
    use std::string::{Self, String};

    public entry fun delegate(
        delegator: &signer, 
        validator: String, 
        denom: String, 
        amount: u64,
    ) {
        delegate_internal(
            signer::address_of(delegator),
            *string::bytes(&validator),
            *string::bytes(&denom),
            amount,
        )
    }

    /// ICS20 ibc transfer
    /// https://github.com/cosmos/ibc/tree/main/spec/app/ics-020-fungible-token-transfer
    public entry fun transfer(
        sender: &signer,
        receiver: String,
        token_denom: String,
        token_amount: u64,
        source_port: String,
        source_channel: String,
        revision_number: u64,
        revision_height: u64,
        timeout_timestamp: u64,
        memo: String,
    ) {
        transfer_internal(
            signer::address_of(sender),
            *string::bytes(&receiver),
            *string::bytes(&token_denom),
            token_amount,
            *string::bytes(&source_port),
            *string::bytes(&source_channel),
            revision_number,
            revision_height,
            timeout_timestamp,
            *string::bytes(&memo),
        )
    }

    /// ICS29 ibc relayer fee
    /// https://github.com/cosmos/ibc/tree/main/spec/app/ics-029-fee-payment
    public entry fun pay_fee(
        sender: &signer,
        source_port: String,
        source_channel: String,
        recv_fee_denom: String,
        recv_fee_amount: u64,
        ack_fee_denom: String,
        ack_fee_amount: u64,
        timeout_fee_denom: String,
        timeout_fee_amount: u64,
    ) {
        pay_fee_internal(
            signer::address_of(sender),
            *string::bytes(&source_port),
            *string::bytes(&source_channel),
            *string::bytes(&recv_fee_denom),
            recv_fee_amount,
            *string::bytes(&ack_fee_denom),
            ack_fee_amount,
            *string::bytes(&timeout_fee_denom),
            timeout_fee_amount,
        )
    }


    native fun delegate_internal(
        delegator: address, 
        validator: vector<u8>, 
        denom: vector<u8>, 
        amount: u64,
    );

    native fun transfer_internal(
        sender: address,
        receiver: vector<u8>,
        token_denom: vector<u8>,
        token_amount: u64,
        source_port: vector<u8>,
        source_channel: vector<u8>,
        revision_number: u64,
        revision_height: u64,
        timeout_timestamp: u64,
        memo: vector<u8>,
    );

    native fun pay_fee_internal(
        sender: address,
        source_port: vector<u8>,
        source_channel: vector<u8>,
        recv_fee_denom: vector<u8>,
        recv_fee_amount: u64,
        ack_fee_denom: vector<u8>,
        ack_fee_amount: u64,
        timeout_fee_denom: vector<u8>,
        timeout_fee_amount: u64,
    );
}
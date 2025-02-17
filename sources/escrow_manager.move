module campaign_manager::escrow {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use campaign_manager::campaign_state;
    use campaign_manager::reward_manager;

    /// Error codes
    const EINSUFFICIENT_BALANCE: u64 = 1;
    const ECAMPAIGN_NOT_FOUND: u64 = 2;
    const ENOT_CAMPAIGN_OWNER: u64 = 3;
    const ECAMPAIGN_ACTIVE: u64 = 4;
    const ECAMPAIGN_EXPIRED: u64 = 5;
    const ECONTRIBUTION_NOT_VERIFIED: u64 = 6;
    const EREWARD_ALREADY_CLAIMED: u64 = 7;
    const EESCROW_NOT_FOUND: u64 = 8;
    const EINVALID_AMOUNT: u64 = 9;
    const ELOW_QUALITY_SCORE: u64 = 10;

    struct CampaignEscrow<phantom CoinType> has store {
        campaign_id: String,
        owner: address,
        total_locked: u64,         // Total amount locked in escrow
        total_released: u64,       // Total amount released to contributors
        unit_reward: u64,          // Reward per verified contribution
        platform_fee: u64,         // Platform fee percentage (basis points: 100 = 1%)
        is_active: bool,
    }

    struct EscrowStore<phantom CoinType> has key {
        escrows: vector<CampaignEscrow<CoinType>>,
        platform_wallet: address,   // Address to receive platform fees
        escrow_events: event::EventHandle<EscrowEvent<CoinType>>,
        reward_events: event::EventHandle<RewardEvent<CoinType>>,
    }

    struct EscrowEvent<phantom CoinType> has drop, store {
        campaign_id: String,
        owner: address,
        amount: u64,
        event_type: String,        // "locked", "released", "refunded"
        timestamp: u64,
    }

    struct RewardEvent<phantom CoinType> has drop, store {
        campaign_id: String,
        contributor: address,
        contribution_id: String,
        amount: u64,
        timestamp: u64,
    }

    struct EscrowSigner has key {
        signer_cap: account::SignerCapability,
    }

    fun init_module(account: &signer) {
        let (escrow_signer, signer_cap) = account::create_resource_account(account, b"escrow");
        move_to(&escrow_signer, EscrowSigner { signer_cap });

        let escrow_store = EscrowStore<aptos_framework::aptos_coin::AptosCoin> {
            escrows: vector::empty(),
            platform_wallet: @campaign_manager, // Default to module publisher
            escrow_events: account::new_event_handle<EscrowEvent<aptos_framework::aptos_coin::AptosCoin>>(account),
            reward_events: account::new_event_handle<RewardEvent<aptos_framework::aptos_coin::AptosCoin>>(account),
        };
        move_to(account, escrow_store);
    }

    fun get_escrow_signer(): signer acquires EscrowSigner {
        let signer_cap = &borrow_global<EscrowSigner>(@campaign_manager).signer_cap;
        account::create_signer_with_capability(signer_cap)
    }

    public entry fun create_campaign_escrow<CoinType: key>(
        account: &signer,
        campaign_id: String,
        total_amount: u64,
        unit_reward: u64,
        platform_fee: u64,
    ) acquires EscrowStore {
        let sender = signer::address_of(account);
        
        // Verify campaign exists and is active
        assert!(
            campaign_state::verify_campaign_active(campaign_id),
            error::not_found(ECAMPAIGN_NOT_FOUND)
        );

        let escrow = CampaignEscrow<CoinType> {
            campaign_id,
            owner: sender,
            total_locked: total_amount,
            total_released: 0,
            unit_reward,
            platform_fee,
            is_active: true,
        };

        let escrow_store = borrow_global_mut<EscrowStore<CoinType>>(@campaign_manager);
        vector::push_back(&mut escrow_store.escrows, escrow);

        // Transfer funds from sender to escrow account
        coin::transfer<CoinType>(account, @campaign_manager, total_amount);

        event::emit_event(
            &mut escrow_store.escrow_events,
            EscrowEvent<CoinType> {
                campaign_id,
                owner: sender,
                amount: total_amount,
                event_type: string::utf8(b"locked"),
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    public entry fun release_reward<CoinType: key>(
        account: &signer,
        campaign_id: String,
        contribution_id: String,
    ) acquires EscrowStore, EscrowSigner {
        let sender = signer::address_of(account);
        
        // Verify reward is claimable
        assert!(
            reward_manager::is_reward_claimed<CoinType>(sender, campaign_id, contribution_id),
            error::invalid_state(EREWARD_ALREADY_CLAIMED)
        );

        let escrow_store = borrow_global_mut<EscrowStore<CoinType>>(@campaign_manager);
        let len = vector::length(&escrow_store.escrows);
        let i = 0;
        while (i < len) {
            let escrow = vector::borrow_mut(&mut escrow_store.escrows, i);
            if (escrow.campaign_id == campaign_id) {
                assert!(escrow.is_active, error::invalid_state(ECAMPAIGN_EXPIRED));
                
                // Calculate reward and platform fee
                let reward_amount = escrow.unit_reward;
                let platform_fee_amount = (reward_amount * escrow.platform_fee) / 10000;
                let contributor_amount = reward_amount - platform_fee_amount;

                // Update escrow state
                escrow.total_released = escrow.total_released + reward_amount;

                // Get escrow signer for withdrawals
                let escrow_signer = get_escrow_signer();

                // Transfer reward to contributor
                let reward_coin = coin::withdraw<CoinType>(&escrow_signer, contributor_amount);
                coin::deposit(sender, reward_coin);

                // Transfer platform fee
                let fee_coin = coin::withdraw<CoinType>(&escrow_signer, platform_fee_amount);
                coin::deposit(escrow_store.platform_wallet, fee_coin);

                event::emit_event(
                    &mut escrow_store.reward_events,
                    RewardEvent<CoinType> {
                        campaign_id,
                        contributor: sender,
                        contribution_id,
                        amount: contributor_amount,
                        timestamp: timestamp::now_seconds(),
                    },
                );

                // Add balance check
                assert!(escrow.total_locked - escrow.total_released >= reward_amount, 
                       error::invalid_state(EINSUFFICIENT_BALANCE));
                return
            };
            i = i + 1;
        };
        abort error::not_found(EESCROW_NOT_FOUND)
    }

    public entry fun refund_remaining<CoinType: key>(
        account: &signer,
        campaign_id: String,
    ) acquires EscrowStore, EscrowSigner {
        let sender = signer::address_of(account);
        let escrow_store = borrow_global_mut<EscrowStore<CoinType>>(@campaign_manager);
        
        let len = vector::length(&escrow_store.escrows);
        let i = 0;
        while (i < len) {
            let escrow = vector::borrow_mut(&mut escrow_store.escrows, i);
            if (escrow.campaign_id == campaign_id) {
                assert!(escrow.owner == sender, error::permission_denied(ENOT_CAMPAIGN_OWNER));
                assert!(!campaign_state::verify_campaign_active(campaign_id), 
                       error::invalid_state(ECAMPAIGN_ACTIVE));

                let remaining_amount = escrow.total_locked - escrow.total_released;
                if (remaining_amount > 0) {
                    escrow.is_active = false;
                    
                    // Get escrow signer for withdrawal
                    let escrow_signer = get_escrow_signer();

                    // Transfer remaining funds back to campaign owner
                    let refund_coin = coin::withdraw<CoinType>(&escrow_signer, remaining_amount);
                    coin::deposit(sender, refund_coin);

                    event::emit_event(
                        &mut escrow_store.escrow_events,
                        EscrowEvent<CoinType> {
                            campaign_id,
                            owner: sender,
                            amount: remaining_amount,
                            event_type: string::utf8(b"refunded"),
                            timestamp: timestamp::now_seconds(),
                        },
                    );
                };
                return
            };
            i = i + 1;
        };
        abort error::not_found(EESCROW_NOT_FOUND)
    }

    #[view]
    public fun get_escrow_info<CoinType>(
        campaign_id: String
    ): (address, u64, u64, u64, u64, bool) acquires EscrowStore {
        let escrow_store = borrow_global<EscrowStore<CoinType>>(@campaign_manager);
        let len = vector::length(&escrow_store.escrows);
        let i = 0;
        while (i < len) {
            let escrow = vector::borrow(&escrow_store.escrows, i);
            if (escrow.campaign_id == campaign_id) {
                return (
                    escrow.owner,
                    escrow.total_locked,
                    escrow.total_released,
                    escrow.unit_reward,
                    escrow.platform_fee,
                    escrow.is_active
                )
            };
            i = i + 1;
        };
        abort error::not_found(EESCROW_NOT_FOUND)
    }

    #[view]
    public fun get_available_balance<CoinType>(campaign_id: String): u64 acquires EscrowStore {
        let escrow_store = borrow_global<EscrowStore<CoinType>>(@campaign_manager);
        let len = vector::length(&escrow_store.escrows);
        let i = 0;
        while (i < len) {
            let escrow = vector::borrow(&escrow_store.escrows, i);
            if (escrow.campaign_id == campaign_id) {
                return escrow.total_locked - escrow.total_released
            };
            i = i + 1;
        };
        abort error::not_found(EESCROW_NOT_FOUND)
    }
} 

#[test_only]
module campaign_manager::escrow_tests {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin::{Self};
    use aptos_framework::timestamp;
    use campaign_manager::campaign;
    use campaign_manager::campaign_state;
    use campaign_manager::contribution;
    use campaign_manager::escrow;
    use campaign_manager::verifier;
    use campaign_manager::reward_manager;

    struct TestCoin has key { }

    fun setup_test_environment(
        admin: &signer,
        contributor: &signer,
        platform_wallet: &signer
    ) {
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(contributor));
        account::create_account_for_test(signer::address_of(platform_wallet));

        campaign::initialize(admin);
        campaign_state::initialize(admin);
        contribution::initialize(contributor);
        verifier::initialize(admin);
        reward_manager::initialize(admin);
        escrow::init_module<TestCoin>(admin);
    }

    fun setup_test_campaign(admin: &signer): string::String {
        let campaign_id = string::utf8(b"test_campaign");
        
        campaign::create_campaign<TestCoin>(
            admin,
            campaign_id,
            string::utf8(b"Test Campaign"),
            string::utf8(b"Description"),
            string::utf8(b"Requirements"),
            string::utf8(b"Criteria"),
            100, // unit_price
            1000, // total_budget
            5, // min_data_count
            10, // max_data_count
            timestamp::now_seconds() + 86400, // expiration (1 day)
            string::utf8(b"ipfs://test"),
            10, // platform_fee
        );

        campaign_id
    }

    #[test(admin = @campaign_manager, contributor = @0x456, platform = @0x789)]
    public fun test_create_escrow(
        admin: &signer,
        contributor: &signer,
        platform: &signer
    ) {
        setup_test_environment(admin, contributor, platform);
        let campaign_id = setup_test_campaign(admin);

        // Create escrow
        escrow::create_campaign_escrow<TestCoin>(
            admin,
            campaign_id,
            1000, // total_amount
            100,  // unit_reward
            10,   // platform_fee
        );

        // Verify escrow info
        let (owner, total_locked, total_released, unit_reward, platform_fee, is_active) = 
            escrow::get_escrow_info<TestCoin>(campaign_id);

        assert!(owner == signer::address_of(admin), 0);
        assert!(total_locked == 1000, 1);
        assert!(total_released == 0, 2);
        assert!(unit_reward == 100, 3);
        assert!(platform_fee == 10, 4);
        assert!(is_active == true, 5);

        // Verify available balance
        let available_balance = escrow::get_available_balance<TestCoin>(campaign_id);
        assert!(available_balance == 1000, 6);
    }

    #[test(admin = @campaign_manager, contributor = @0x456, platform = @0x789)]
    public fun test_release_reward(
        admin: &signer,
        contributor: &signer,
        platform: &signer
    ) {
        setup_test_environment(admin, contributor, platform);
        let campaign_id = setup_test_campaign(admin);

        // Create escrow
        escrow::create_campaign_escrow<TestCoin>(
            admin,
            campaign_id,
            1000, // total_amount
            100,  // unit_reward
            10,   // platform_fee (10 = 0.1%)
        );

        // Submit contribution
        let contribution_id = string::utf8(b"test_contribution_1");
        let data_url = string::utf8(b"ipfs://testdata");
        let data_hash = vector::empty<u8>();
        vector::push_back(&mut data_hash, 1);
        let signature = vector::empty<u8>();
        vector::push_back(&mut signature, 1);
        
        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id,
            contribution_id,
            data_url,
            data_hash,
            signature,
            80, // quality_score
        );

        // Release reward
        escrow::release_reward<TestCoin>(
            contributor,
            campaign_id,
            contribution_id,
        );

        // Verify escrow state after reward release
        let (_, total_locked, total_released, _, _, _) = 
            escrow::get_escrow_info<TestCoin>(campaign_id);

        assert!(total_released == 100, 0); // Full reward amount
        assert!(total_locked == 1000, 1);  // Original locked amount unchanged

        // Verify available balance
        let available_balance = escrow::get_available_balance<TestCoin>(campaign_id);
        assert!(available_balance == 900, 2); // 1000 - 100
    }

    #[test(admin = @campaign_manager, contributor = @0x456, platform = @0x789)]
    public fun test_refund_remaining(
        admin: &signer,
        contributor: &signer,
        platform: &signer
    ) {
        setup_test_environment(admin, contributor, platform);
        let campaign_id = setup_test_campaign(admin);

        // Create escrow
        escrow::create_campaign_escrow<TestCoin>(
            admin,
            campaign_id,
            1000, // total_amount
            100,  // unit_reward
            10,   // platform_fee
        );

        // Cancel campaign
        campaign::cancel_campaign<TestCoin>(admin, campaign_id);

        // Refund remaining amount
        escrow::refund_remaining<TestCoin>(
            admin,
            campaign_id,
        );

        // Verify escrow state after refund
        let (_, _, _, _, _, is_active) = escrow::get_escrow_info<TestCoin>(campaign_id);
        assert!(!is_active, 0);

        // Verify available balance is 0
        let available_balance = escrow::get_available_balance<TestCoin>(campaign_id);
        assert!(available_balance == 0, 1);
    }

    #[test(admin = @campaign_manager, contributor = @0x456, platform = @0x789)]
    #[expected_failure(abort_code = 4)]
    public fun test_refund_active_campaign(
        admin: &signer,
        contributor: &signer,
        platform: &signer
    ) {
        setup_test_environment(admin, contributor, platform);
        let campaign_id = setup_test_campaign(admin);

        // Create escrow
        escrow::create_campaign_escrow<TestCoin>(
            admin,
            campaign_id,
            1000,
            100,
            10,
        );

        // Attempt to refund while campaign is still active (should fail)
        escrow::refund_remaining<TestCoin>(
            admin,
            campaign_id,
        );
    }

    #[test(admin = @campaign_manager, contributor = @0x456, platform = @0x789)]
    #[expected_failure(abort_code = 3)]
    public fun test_unauthorized_refund(
        admin: &signer,
        contributor: &signer,
        platform: &signer
    ) {
        setup_test_environment(admin, contributor, platform);
        let campaign_id = setup_test_campaign(admin);

        // Create escrow
        escrow::create_campaign_escrow<TestCoin>(
            admin,
            campaign_id,
            1000,
            100,
            10,
        );

        // Cancel campaign
        campaign::cancel_campaign<TestCoin>(admin, campaign_id);

        // Attempt unauthorized refund (should fail)
        escrow::refund_remaining<TestCoin>(
            contributor, // Not the campaign owner
            campaign_id,
        );
    }

    #[test(admin = @campaign_manager, contributor = @0x456, platform = @0x789)]
    #[expected_failure(abort_code = 1)]
    public fun test_insufficient_balance(
        admin: &signer,
        contributor: &signer,
        platform: &signer
    ) {
        setup_test_environment(admin, contributor, platform);
        let campaign_id = setup_test_campaign(admin);

        // Create escrow with minimal balance
        escrow::create_campaign_escrow<TestCoin>(
            admin,
            campaign_id,
            100, // total_amount = exactly one reward
            100, // unit_reward
            10,  // platform_fee
        );

        // Submit and claim multiple contributions to exceed balance
        let contribution_id1 = string::utf8(b"contribution1");
        let contribution_id2 = string::utf8(b"contribution2");
        let data_url = string::utf8(b"ipfs://testdata");
        let data_hash = vector::empty<u8>();
        vector::push_back(&mut data_hash, 1);
        let signature = vector::empty<u8>();
        vector::push_back(&mut signature, 1);
        
        // Submit first contribution
        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id,
            contribution_id1,
            data_url,
            data_hash,
            signature,
            80,
        );

        // Release first reward
        escrow::release_reward<TestCoin>(
            contributor,
            campaign_id,
            contribution_id1,
        );

        // Attempt to submit and claim second contribution (should fail due to insufficient balance)
        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id,
            contribution_id2,
            data_url,
            data_hash,
            signature,
            80,
        );

        escrow::release_reward<TestCoin>(
            contributor,
            campaign_id,
            contribution_id2,
        );
    }
} 
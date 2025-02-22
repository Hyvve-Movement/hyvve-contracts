module campaign_manager::contribution {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use campaign_manager::campaign_state;
    use campaign_manager::verifier;
    use campaign_manager::escrow;
    use campaign_manager::reputation;

    /// Error codes
    const EINVALID_CONTRIBUTION: u64 = 1;
    const ECAMPAIGN_INACTIVE: u64 = 2;
    const EINVALID_SIGNATURE: u64 = 3;
    const EDUPLICATE_CONTRIBUTION: u64 = 4;
    const ECONTRIBUTION_NOT_FOUND: u64 = 5;
    const ECONTRIBUTION_ALREADY_VERIFIED: u64 = 6;
    const EVERIFIER_LOW_REPUTATION: u64 = 7;
    const ENOT_CONTRIBUTOR: u64 = 8;
    const ENOT_VERIFIER: u64 = 9;

    /// Verification threshold for high-quality contributions
    const VERIFICATION_THRESHOLD: u64 = 80;

    struct Contribution has store, copy {
        contribution_id: String,
        campaign_id: String,
        contributor: address,
        data_url: String,         // IPFS/Arweave URI for the actual data
        data_hash: vector<u8>,    // Hash of the data for verification
        timestamp: u64,
        verification_scores: verifier::VerificationScores,
        is_verified: bool,
        reward_released: bool
    }

    struct ContributionStore has key {
        contributions: vector<Contribution>,
        contribution_events: event::EventHandle<ContributionEvent>,
        verification_events: event::EventHandle<VerificationEvent>,
    }

    struct ContributionEvent has drop, store {
        contribution_id: String,
        campaign_id: String,
        contributor: address,
        data_url: String,
        data_hash: vector<u8>,
        verifier_reputation: u64,
        timestamp: u64,
    }

    struct VerificationEvent has drop, store {
        contribution_id: String,
        campaign_id: String,
        verification_score: u64,
        timestamp: u64,
    }

    fun init_module(account: &signer) {
        let contribution_store = ContributionStore {
            contributions: vector::empty(),
            contribution_events: account::new_event_handle<ContributionEvent>(account),
            verification_events: account::new_event_handle<VerificationEvent>(account),
        };
        move_to(account, contribution_store);
    }

    public entry fun submit_contribution<CoinType: key>(
        account: &signer,
        campaign_id: String,
        contribution_id: String,
        data_url: String,
        data_hash: vector<u8>,
        signature: vector<u8>,
        quality_score: u64,
    ) acquires ContributionStore {
        let sender = signer::address_of(account);
        
        // Initialize reputation store for new contributors
        reputation::ensure_reputation_store_exists(account);

        // Verify campaign is active
        assert!(
            campaign_state::verify_campaign_active(campaign_id),
            error::invalid_state(ECAMPAIGN_INACTIVE)
        );

        // Verify contribution hasn't been submitted before
        assert!(
            !contribution_exists(contribution_id),
            error::already_exists(EDUPLICATE_CONTRIBUTION)
        );

        // Delegate signature verification to the verifier module.
        let result = verifier::verify_contribution(
            campaign_id,
            data_hash,
            data_url,
            signature,
            quality_score
        );
        
        // Ensure the signature is valid.
        assert!(
            verifier::is_valid(&result),
            error::invalid_argument(EINVALID_SIGNATURE)
        );
        
        let scores = verifier::get_result_scores(&result);
        let (verifier_reputation, _) = verifier::get_scores(scores);
        
        let contribution = Contribution {
            contribution_id,
            campaign_id,
            contributor: sender,
            data_url,
            data_hash,
            timestamp: timestamp::now_seconds(),
            verification_scores: *scores,
            is_verified: true,
            reward_released: false,
        };

        let contribution_store = borrow_global_mut<ContributionStore>(@campaign_manager);
        vector::push_back(&mut contribution_store.contributions, contribution);

        // Increment contribution count in campaign
        let _ = campaign_state::increment_contributions(campaign_id);

        event::emit_event(
            &mut contribution_store.contribution_events,
            ContributionEvent {
                contribution_id,
                campaign_id,
                contributor: sender,
                data_url,
                data_hash,
                verifier_reputation,
                timestamp: timestamp::now_seconds(),
            },
        );

        // Release reward if scores are sufficient
        if (verifier::is_sufficient_for_reward(scores)) {
            // Release reward through escrow
            escrow::release_reward<CoinType>(
                account,
                campaign_id,
                contribution_id,
            );

            // Mark contribution as rewarded
            let len = vector::length(&contribution_store.contributions);
            let i = len - 1; // We just added it, so it's the last one
            let contribution = vector::borrow_mut(&mut contribution_store.contributions, i);
            contribution.reward_released = true;

            // Award reputation points to contributor
            reputation::add_reputation_points(
                sender,
                10, // Base points for successful contribution
                b"Successful contribution with reward"
            );

            // Get campaign owner and award them points too
            let owner = campaign_state::get_campaign_owner(campaign_id);
            if (reputation::has_reputation_store(owner)) {
                reputation::add_reputation_points(
                    owner,
                    5, // Points for successful reward payout
                    b"Successful reward payout"
                );
                // Record successful payment for campaign owner
                reputation::record_successful_payment(owner);
            };
        };

        // Record the base contribution regardless of reward
        reputation::record_successful_contribution(sender);
    }

    public entry fun verify_contribution<CoinType: key>(
        account: &signer,
        contribution_id: String,
        quality_score: u64,
        verifier_signature: vector<u8>,
    ) acquires ContributionStore {
        let sender = signer::address_of(account);
        
        // Initialize reputation store for new verifiers
        reputation::ensure_reputation_store_exists(account);
        
        // Verify that the sender is an authorized verifier
        assert!(
            campaign_manager::verifier::is_active_verifier(sender),
            error::permission_denied(ENOT_VERIFIER)
        );
        
        let contribution_store = borrow_global_mut<ContributionStore>(@campaign_manager);
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow_mut(&mut contribution_store.contributions, i);
            if (contribution.contribution_id == contribution_id) {
                assert!(!contribution.is_verified, error::invalid_state(ECONTRIBUTION_ALREADY_VERIFIED));
                
                // Verify the verification signature using verifier's address
                assert!(
                    verify_verification_signature(contribution_id, quality_score, sender, verifier_signature),
                    error::invalid_argument(EINVALID_SIGNATURE)
                );

                contribution.is_verified = true;

                // Use new score checking
                let (verifier_reputation, _) = verifier::get_scores(&contribution.verification_scores);
                let scores = verifier::create_verification_scores(verifier_reputation, quality_score);
                if (verifier::is_sufficient_for_reward(&scores)) {
                    // Release reward through escrow
                    escrow::release_reward<CoinType>(
                        account,
                        contribution.campaign_id,
                        contribution_id,
                    );
                    contribution.reward_released = true;
                };

                event::emit_event(
                    &mut contribution_store.verification_events,
                    VerificationEvent {
                        contribution_id,
                        campaign_id: contribution.campaign_id,
                        verification_score: quality_score,
                        timestamp: timestamp::now_seconds(),
                    },
                );

                // If verification is successful (score above threshold), award reputation
                if (quality_score >= VERIFICATION_THRESHOLD) {
                    reputation::add_reputation_points(
                        sender,
                        20, // Extra points for high-quality contribution
                        b"High-quality verified contribution"
                    );
                };

                return
            };
            i = i + 1;
        };
        abort error::not_found(ECONTRIBUTION_NOT_FOUND)
    }

    public fun get_contribution_details(
        contribution_id: String
    ): Contribution acquires ContributionStore {
        let contribution_store = borrow_global<ContributionStore>(@campaign_manager);
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow(&contribution_store.contributions, i);
            if (contribution.contribution_id == contribution_id) {
                return *contribution
            };
            i = i + 1;
        };
        abort error::not_found(ECONTRIBUTION_NOT_FOUND)
    }

    // Helper function to check if a contribution already exists
    fun contribution_exists(
        contribution_id: String
    ): bool acquires ContributionStore {
        let contribution_store = borrow_global<ContributionStore>(@campaign_manager);
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow(&contribution_store.contributions, i);
            if (contribution.contribution_id == contribution_id) {
                return true
            };
            i = i + 1;
        };
        false
    }

    // (The helper function verify_contribution_signature is now removed)
    fun verify_verification_signature(
        contribution_id: String,
        quality_score: u64,
        verifier: address,
        signature: vector<u8>
    ): bool {
        let message = vector::empty<u8>();
        let contribution_id_bytes = *string::bytes(&contribution_id);
        vector::append(&mut message, contribution_id_bytes);
        
        // Convert score to bytes and append
        let score_bytes = vector::empty<u8>();
        vector::push_back(&mut score_bytes, (quality_score as u8));
        vector::append(&mut message, score_bytes);
        
        // Verify using verifier's address
        campaign_manager::verifier::verify_signature(verifier, message, signature)
    }

    #[view]
    public fun get_contribution_store(): vector<Contribution> acquires ContributionStore {
        let contribution_store = borrow_global<ContributionStore>(@campaign_manager);
        contribution_store.contributions
    }

    #[view]
    public fun get_address_contribution_count(
        contributor_address: address,
        campaign_id: String
    ): u64 acquires ContributionStore {
        let contribution_store = borrow_global<ContributionStore>(@campaign_manager);
        let count = 0u64;
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow(&contribution_store.contributions, i);
            if (contribution.contributor == contributor_address && 
                contribution.campaign_id == campaign_id &&
                contribution.reward_released) {
                count = count + 1;
            };
            i = i + 1;
        };
        count
    }

    #[view]
    public fun get_address_total_contributions(
        contributor_address: address
    ): (u64, u64) acquires ContributionStore {
        let contribution_store = borrow_global<ContributionStore>(@campaign_manager);
        let total_count = 0u64;
        let verified_count = 0u64;
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow(&contribution_store.contributions, i);
            if (contribution.contributor == contributor_address) {
                total_count = total_count + 1;
                if (contribution.is_verified && contribution.reward_released) {
                    verified_count = verified_count + 1;
                };
            };
            i = i + 1;
        };
        (total_count, verified_count)
    }
}

#[test_only]
module campaign_manager::contribution_tests {
    use std::string;
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use campaign_manager::campaign;
    use campaign_manager::campaign_state;
    use campaign_manager::verifier;
    use campaign_manager::escrow;

    struct TestCoin has key { }

    fun setup_test_environment(
        admin: &signer,
        contributor: &signer,
        verifier_account: &signer
    ) {
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(contributor));
        account::create_account_for_test(signer::address_of(verifier_account));

        campaign::initialize(admin);
        campaign_state::initialize(admin);
        verifier::initialize(admin);
        escrow::init_module(admin);
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

        // Create escrow for the campaign
        escrow::create_campaign_escrow<TestCoin>(
            admin,
            campaign_id,
            1000, // total_amount
            100,  // unit_reward
            10,   // platform_fee
        );

        campaign_id
    }

    #[test(admin = @campaign_manager, contributor = @0x456, verifier = @0x789)]
    public fun test_submit_contribution(
        admin: &signer,
        contributor: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, contributor, verifier);
        let campaign_id = setup_test_campaign(admin);

        // Create test data
        let contribution_id = string::utf8(b"test_contribution_1");
        let data_url = string::utf8(b"ipfs://testdata");
        let data_hash = vector::empty<u8>();
        vector::push_back(&mut data_hash, 1);
        let signature = vector::empty<u8>();
        vector::push_back(&mut signature, 1);
        let quality_score = 80;

        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id,
            contribution_id,
            data_url,
            data_hash,
            signature,
            quality_score,
        );

        let submitted_contribution = contribution::get_contribution_details(
            contribution_id
        );

        assert!(submitted_contribution.contribution_id == contribution_id, 0);
        assert!(submitted_contribution.campaign_id == campaign_id, 1);
        assert!(submitted_contribution.contributor == signer::address_of(contributor), 2);
        assert!(submitted_contribution.data_url == data_url, 3);
        assert!(submitted_contribution.data_hash == data_hash, 4);
        assert!(submitted_contribution.is_verified == true, 5);
        assert!(submitted_contribution.reward_released == true, 6); // Reward should be released immediately
    }

    #[test(admin = @campaign_manager, contributor = @0x456, verifier = @0x789)]
    public fun test_verify_contribution(
        admin: &signer,
        contributor: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, contributor, verifier);
        let campaign_id = setup_test_campaign(admin);

        // Register verifier
        verifier::register_verifier(verifier, string::utf8(b"Test Verifier"), 90);

        // Submit initial contribution
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
            80,
        );

        // Create verification signature
        let verifier_signature = vector::empty<u8>();
        vector::push_back(&mut verifier_signature, 1);

        // Verify contribution
        contribution::verify_contribution<TestCoin>(
            verifier,
            contribution_id,
            90, // quality_score
            verifier_signature,
        );

        // Check contribution status
        let verified_contribution = contribution::get_contribution_details(
            contribution_id
        );

        assert!(verified_contribution.is_verified == true, 0);
        assert!(verified_contribution.reward_released == true, 1); // Reward should be released after verification
    }

    #[test(admin = @campaign_manager, contributor = @0x456, verifier = @0x789)]
    #[expected_failure(abort_code = 4)]
    public fun test_duplicate_contribution(
        admin: &signer,
        contributor: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, contributor, verifier);
        let campaign_id = setup_test_campaign(admin);

        // Create test data
        let contribution_id = string::utf8(b"test_contribution_1");
        let data_url = string::utf8(b"ipfs://testdata");
        let data_hash = vector::empty<u8>();
        vector::push_back(&mut data_hash, 1);
        let signature = vector::empty<u8>();
        vector::push_back(&mut signature, 1);
        
        // Submit first contribution
        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id,
            contribution_id,
            data_url,
            data_hash,
            signature,
            80,
        );

        // Attempt to submit duplicate contribution (should fail)
        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id,
            contribution_id,
            data_url,
            data_hash,
            signature,
            80,
        );
    }

    #[test(admin = @campaign_manager, contributor = @0x456, verifier = @0x789)]
    #[expected_failure(abort_code = 2)]
    public fun test_submit_to_inactive_campaign(
        admin: &signer,
        contributor: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, contributor, verifier);
        let campaign_id = setup_test_campaign(admin);

        // Cancel campaign
        campaign::cancel_campaign<TestCoin>(admin, campaign_id);

        // Attempt to submit contribution to cancelled campaign (should fail)
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
            80,
        );
    }

    #[test(admin = @campaign_manager, contributor = @0x456, verifier = @0x789)]
    public fun test_get_address_contribution_count(admin: &signer, contributor: &signer) {
        setup_test_environment(admin, contributor, verifier);
        let campaign_id = setup_test_campaign(admin);

        let contributor_addr = signer::address_of(contributor);

        // Initially should be 0
        let count = contribution::get_address_contribution_count(contributor_addr, campaign_id);
        assert!(count == 0, 0);

        // Add some contributions
        let contribution1 = Contribution {
            contribution_id: string::utf8(b"contribution1"),
            campaign_id,
            contributor: contributor_addr,
            data_url: string::utf8(b"ipfs://data1"),
            data_hash: vector::empty(),
            timestamp: timestamp::now_seconds(),
            verification_scores: verifier::create_verification_scores(90, 85),
            is_verified: true,
            reward_released: true
        };

        let contribution2 = Contribution {
            contribution_id: string::utf8(b"contribution2"),
            campaign_id,
            contributor: contributor_addr,
            data_url: string::utf8(b"ipfs://data2"),
            data_hash: vector::empty(),
            timestamp: timestamp::now_seconds(),
            verification_scores: verifier::create_verification_scores(90, 85),
            is_verified: true,
            reward_released: true
        };

        let contribution_store = borrow_global_mut<ContributionStore>(@campaign_manager);
        vector::push_back(&mut contribution_store.contributions, contribution1);
        vector::push_back(&mut contribution_store.contributions, contribution2);

        // Should now be 2
        let count = contribution::get_address_contribution_count(contributor_addr, campaign_id);
        assert!(count == 2, 1);
    }

    #[test(admin = @campaign_manager, contributor = @0x456)]
    public fun test_get_address_total_contributions(admin: &signer, contributor: &signer) {
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(contributor));
        
        contribution::init_module(admin);
        
        let contributor_addr = signer::address_of(contributor);

        // Initially should be 0
        let (total, verified) = contribution::get_address_total_contributions(contributor_addr);
        assert!(total == 0 && verified == 0, 0);

        // Add some contributions
        let contribution1 = Contribution {
            contribution_id: string::utf8(b"contribution1"),
            campaign_id: string::utf8(b"campaign1"),
            contributor: contributor_addr,
            data_url: string::utf8(b"ipfs://data1"),
            data_hash: vector::empty(),
            timestamp: timestamp::now_seconds(),
            verification_scores: verifier::create_verification_scores(90, 85),
            is_verified: true,
            reward_released: true
        };

        let contribution2 = Contribution {
            contribution_id: string::utf8(b"contribution2"),
            campaign_id: string::utf8(b"campaign1"),
            contributor: contributor_addr,
            data_url: string::utf8(b"ipfs://data2"),
            data_hash: vector::empty(),
            timestamp: timestamp::now_seconds(),
            verification_scores: verifier::create_verification_scores(90, 85),
            is_verified: false,
            reward_released: false
        };

        let contribution_store = borrow_global_mut<ContributionStore>(@campaign_manager);
        vector::push_back(&mut contribution_store.contributions, contribution1);
        vector::push_back(&mut contribution_store.contributions, contribution2);

        // Should now have 2 total, 1 verified
        let (total, verified) = contribution::get_address_total_contributions(contributor_addr);
        assert!(total == 2 && verified == 1, 1);
    }
} 
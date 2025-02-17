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
    use campaign_manager::reward_manager;

    /// Error codes
    const EINVALID_CONTRIBUTION: u64 = 1;
    const ECAMPAIGN_INACTIVE: u64 = 2;
    const EINVALID_SIGNATURE: u64 = 3;
    const EDUPLICATE_CONTRIBUTION: u64 = 4;
    const ECONTRIBUTION_NOT_FOUND: u64 = 5;
    const ECONTRIBUTION_ALREADY_VERIFIED: u64 = 6;
    const EVERIFIER_LOW_REPUTATION: u64 = 7;
    const ENOT_CONTRIBUTOR: u64 = 8;

    struct Contribution has store, copy {
        contribution_id: String,
        campaign_id: String,
        contributor: address,
        data_url: String,         // IPFS/Arweave URI for the actual data
        data_hash: vector<u8>,    // Hash of the data for verification
        timestamp: u64,
        verification_scores: verifier::VerificationScores,
        is_verified: bool,
        reward_claimed: bool
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

    public fun initialize(account: &signer) {
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
        
        // Verify campaign is active
        assert!(
            campaign_state::verify_campaign_active(campaign_id),
            error::invalid_state(ECAMPAIGN_INACTIVE)
        );

        // Verify contribution hasn't been submitted before
        assert!(
            !contribution_exists(sender, contribution_id),
            error::already_exists(EDUPLICATE_CONTRIBUTION)
        );

        let result = verifier::verify_contribution(
            campaign_id,
            data_hash,
            data_url,
            signature,
            quality_score
        );
        
        assert!(verifier::is_valid(&result), error::invalid_argument(EINVALID_SIGNATURE));
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
            reward_claimed: false,
        };

        let contribution_store = borrow_global_mut<ContributionStore>(sender);
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

        // Only release reward if scores are sufficient
        if (verifier::is_sufficient_for_reward(scores)) {
            reward_manager::process_reward<CoinType>(
                account,
                campaign_id,
                contribution_id,
                scores,
                0, // Amount will be determined by escrow
            );
        };
    }

    public entry fun verify_contribution<CoinType: key>(
        account: &signer,
        contribution_id: String,
        quality_score: u64,
        verifier_signature: vector<u8>,
    ) acquires ContributionStore {
        let sender = signer::address_of(account);
        
        // Verify that the sender is an authorized verifier
        assert!(
            campaign_manager::verifier::is_active_verifier(sender),
            error::permission_denied(ENOT_CONTRIBUTOR)
        );
        
        let contribution_store = borrow_global_mut<ContributionStore>(sender);
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow_mut(&mut contribution_store.contributions, i);
            if (contribution.contribution_id == contribution_id) {
                assert!(!contribution.is_verified, error::invalid_state(ECONTRIBUTION_ALREADY_VERIFIED));
                
                // Verify the verification signature
                assert!(
                    verify_verification_signature(contribution_id, quality_score, verifier_signature),
                    error::invalid_argument(EINVALID_SIGNATURE)
                );

                contribution.is_verified = true;

                // Use new score checking
                let (verifier_reputation, _) = verifier::get_scores(&contribution.verification_scores);
                let scores = verifier::create_verification_scores(verifier_reputation, quality_score);
                if (verifier::is_sufficient_for_reward(&scores)) {
                    reward_manager::process_reward<CoinType>(
                        account,
                        contribution.campaign_id,
                        contribution_id,
                        &scores,
                        0, // Amount will be determined by escrow
                    );
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
                return
            };
            i = i + 1;
        };
        abort error::not_found(ECONTRIBUTION_NOT_FOUND)
    }

    public fun get_contribution_details(
        contributor_address: address,
        contribution_id: String
    ): Contribution acquires ContributionStore {
        let contribution_store = borrow_global<ContributionStore>(contributor_address);
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
        contributor: address,
        contribution_id: String
    ): bool acquires ContributionStore {
        if (!exists<ContributionStore>(contributor)) {
            return false
        };
        
        let contribution_store = borrow_global<ContributionStore>(contributor);
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

    // Update the verify_contribution_signature function to use the verifier module
    fun verify_contribution_signature(
        campaign_id: String,
        data_hash: vector<u8>,
        signature: vector<u8>
    ): bool {
        let message = vector::empty<u8>();
        let campaign_id_bytes = *string::bytes(&campaign_id);
        vector::append(&mut message, campaign_id_bytes);
        vector::append(&mut message, data_hash);
        
        campaign_manager::verifier::verify_signature(@campaign_manager, message, signature)
    }

    // Update the verify_verification_signature function to use the verifier module
    fun verify_verification_signature(
        contribution_id: String,
        quality_score: u64,
        signature: vector<u8>
    ): bool {
        let message = vector::empty<u8>();
        let contribution_id_bytes = *string::bytes(&contribution_id);
        vector::append(&mut message, contribution_id_bytes);
        
        // Convert score to bytes and append
        let score_bytes = vector::empty<u8>();
        vector::push_back(&mut score_bytes, (quality_score as u8));
        vector::append(&mut message, score_bytes);
        
        campaign_manager::verifier::verify_signature(@campaign_manager, message, signature)
    }

    public fun mark_reward_claimed(
        contributor_address: address,
        contribution_id: String
    ): bool acquires ContributionStore {
        let contribution_store = borrow_global_mut<ContributionStore>(contributor_address);
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow_mut(&mut contribution_store.contributions, i);
            if (contribution.contribution_id == contribution_id) {
                if (!contribution.reward_claimed && contribution.is_verified) {
                    contribution.reward_claimed = true;
                    return true
                };
                return false
            };
            i = i + 1;
        };
        false
    }

    public fun claim_reward<CoinType: key>(
        account: &signer,
        campaign_id: String,
        contribution_id: String,
    ) acquires ContributionStore {
        let sender = signer::address_of(account);
        
        let contribution_store = borrow_global_mut<ContributionStore>(sender);
        let len = vector::length(&contribution_store.contributions);
        let i = 0;
        while (i < len) {
            let contribution = vector::borrow_mut(&mut contribution_store.contributions, i);
            if (contribution.contribution_id == contribution_id) {
                assert!(contribution.is_verified, error::invalid_state(EINVALID_CONTRIBUTION));
                assert!(!contribution.reward_claimed, error::invalid_state(ECONTRIBUTION_ALREADY_VERIFIED));
                
                let (verifier_reputation, _) = verifier::get_scores(&contribution.verification_scores);
                assert!(verifier_reputation >= 70, error::invalid_argument(EVERIFIER_LOW_REPUTATION));

                contribution.reward_claimed = true;
                
                // Release reward through escrow
                campaign_manager::escrow::release_reward<CoinType>(
                    account,
                    campaign_id,
                    contribution_id,
                );
                return
            };
            i = i + 1;
        };
        abort error::not_found(ECONTRIBUTION_NOT_FOUND)
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
    use campaign_manager::contribution;
    use campaign_manager::campaign_state;
    use campaign_manager::verifier;

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
        contribution::initialize(contributor);
        campaign_state::initialize(admin);
        verifier::initialize(admin);
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
            signer::address_of(contributor),
            contribution_id
        );

        assert!(submitted_contribution.contribution_id == contribution_id, 0);
        assert!(submitted_contribution.campaign_id == campaign_id, 1);
        assert!(submitted_contribution.contributor == signer::address_of(contributor), 2);
        assert!(submitted_contribution.data_url == data_url, 3);
        assert!(submitted_contribution.data_hash == data_hash, 4);
        assert!(submitted_contribution.is_verified == true, 5);
        assert!(submitted_contribution.reward_claimed == false, 6);
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
            signer::address_of(contributor),
            contribution_id
        );

        assert!(verified_contribution.is_verified == true, 0);
    }

    #[test(admin = @campaign_manager, contributor = @0x456)]
    public fun test_claim_reward(
        admin: &signer,
        contributor: &signer
    ) {
        setup_test_environment(admin, contributor, admin);
        let campaign_id = setup_test_campaign(admin);

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
            80,
        );

        // Claim reward
        contribution::claim_reward<TestCoin>(
            contributor,
            campaign_id,
            contribution_id,
        );

        // Verify reward is claimed
        let contribution_after_claim = contribution::get_contribution_details(
            signer::address_of(contributor),
            contribution_id
        );

        assert!(contribution_after_claim.reward_claimed == true, 0);
    }

    #[test(admin = @campaign_manager, contributor = @0x456)]
    #[expected_failure(abort_code = 4)]
    public fun test_duplicate_contribution(
        admin: &signer,
        contributor: &signer
    ) {
        setup_test_environment(admin, contributor, admin);
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

    #[test(admin = @campaign_manager, contributor = @0x456)]
    #[expected_failure(abort_code = 2)]
    public fun test_submit_to_inactive_campaign(
        admin: &signer,
        contributor: &signer
    ) {
        setup_test_environment(admin, contributor, admin);
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
} 
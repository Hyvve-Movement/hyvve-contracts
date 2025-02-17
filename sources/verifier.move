module campaign_manager::verifier {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::ed25519;
    use aptos_framework::bcs;
    use aptos_std::hash;

    /// Error codes
    const ENOT_AUTHORIZED: u64 = 1;
    const EVERIFIER_NOT_FOUND: u64 = 2;
    const EVERIFIER_ALREADY_EXISTS: u64 = 3;
    const EINVALID_SIGNATURE: u64 = 4;
    const EINVALID_PUBLIC_KEY: u64 = 5;
    const EVERIFIER_INACTIVE: u64 = 6;
    const ENOT_ADMIN: u64 = 7;
    const EKEY_ALREADY_EXISTS: u64 = 8;
    const EKEY_NOT_FOUND: u64 = 9;
    const EVERIFIER_LOW_REPUTATION: u64 = 10;
    const ELOW_QUALITY_SCORE: u64 = 11;
    const EINVALID_SCORE: u64 = 12;

    const MINIMUM_VERIFIER_REPUTATION: u64 = 70;
    const MINIMUM_QUALITY_SCORE: u64 = 70;
    const MAXIMUM_SCORE: u64 = 100;
    const MINIMUM_SCORE: u64 = 0;

    struct VerifierInfo has store {
        address: address,
        public_key: vector<u8>,    // ED25519 public key
        reputation_score: u64,      // 0-100 score based on verification accuracy
        total_verifications: u64,
        is_active: bool,
        last_active: u64,          // Timestamp of last verification
    }

    struct VerifierRegistry has key {
        verifiers: vector<VerifierInfo>,
        admin: address,            // Address that can add/remove verifiers
        verifier_events: event::EventHandle<VerifierEvent>,
    }

    struct VerifierEvent has drop, store {
        verifier_address: address,
        action: String,            // "added", "removed", "updated"
        timestamp: u64,
    }

    struct VerifierKey has store {
        public_key: vector<u8>,
        reputation_score: u64,     // 0-100 score
        total_verifications: u64,
        last_active: u64,
    }

    struct VerifierStore has key {
        admin: address,
        verifier_keys: vector<VerifierKey>,
    }

    struct VerificationResult has drop {
        is_valid: bool,
        scores: VerificationScores,
    }

    struct VerificationScores has copy, drop, store {
        verifier_reputation: u64,
        quality_score: u64,
    }

    fun init_module(account: &signer) {
        let sender = signer::address_of(account);
        let verifier_registry = VerifierRegistry {
            verifiers: vector::empty(),
            admin: sender,
            verifier_events: account::new_event_handle<VerifierEvent>(account),
        };
        move_to(account, verifier_registry);

        // Initialize verifier store in the same init_module
        move_to(account, VerifierStore {
            admin: sender,
            verifier_keys: vector::empty(),
        });
    }

    public entry fun add_verifier(
        admin: &signer,
        verifier_address: address,
        public_key: vector<u8>,
    ) acquires VerifierRegistry {
        let sender = signer::address_of(admin);
        
        // First check if verifier exists without holding mutable borrow
        {
            let registry = borrow_global<VerifierRegistry>(@campaign_manager);
            assert!(registry.admin == sender, error::permission_denied(ENOT_AUTHORIZED));
            let len = vector::length(&registry.verifiers);
            let i = 0;
            let exists = false;
            while (i < len) {
                let verifier = vector::borrow(&registry.verifiers, i);
                if (verifier.address == verifier_address) {
                    exists = true;
                    break
                };
                i = i + 1;
            };
            assert!(!exists, error::already_exists(EVERIFIER_ALREADY_EXISTS));
        };
        
        // Verify public key format (should be 32 bytes for ED25519)
        assert!(vector::length(&public_key) == 32, error::invalid_argument(EINVALID_PUBLIC_KEY));
        
        let verifier = VerifierInfo {
            address: verifier_address,
            public_key,
            reputation_score: 100, 
            total_verifications: 0,
            is_active: true,
            last_active: timestamp::now_seconds(),
        };

        let registry = borrow_global_mut<VerifierRegistry>(@campaign_manager);
        vector::push_back(&mut registry.verifiers, verifier);

        event::emit_event(
            &mut registry.verifier_events,
            VerifierEvent {
                verifier_address,
                action: string::utf8(b"added"),
                timestamp: timestamp::now_seconds(),
            },
        );
    }

    public entry fun remove_verifier(
        admin: &signer,
        verifier_address: address,
    ) acquires VerifierRegistry {
        let sender = signer::address_of(admin);
        let registry = borrow_global_mut<VerifierRegistry>(@campaign_manager);
        
        assert!(registry.admin == sender, error::permission_denied(ENOT_AUTHORIZED));

        let len = vector::length(&registry.verifiers);
        let i = 0;
        while (i < len) {
            let verifier = vector::borrow_mut(&mut registry.verifiers, i);
            if (verifier.address == verifier_address) {
                verifier.is_active = false;
                
                event::emit_event(
                    &mut registry.verifier_events,
                    VerifierEvent {
                        verifier_address,
                        action: string::utf8(b"removed"),
                        timestamp: timestamp::now_seconds(),
                    },
                );
                return
            };
            i = i + 1;
        };
        abort error::not_found(EVERIFIER_NOT_FOUND)
    }

    public fun verify_signature(
        verifier_address: address,
        message: vector<u8>,
        signature: vector<u8>,
    ): bool acquires VerifierRegistry {
        let registry = borrow_global_mut<VerifierRegistry>(@campaign_manager);
        
        let len = vector::length(&registry.verifiers);
        let i = 0;
        while (i < len) {
            let verifier = vector::borrow_mut(&mut registry.verifiers, i);
            if (verifier.address == verifier_address) {
                assert!(verifier.is_active, error::invalid_state(EVERIFIER_INACTIVE));
                
                // Verify ED25519 signature
                let sig = ed25519::new_signature_from_bytes(signature);
                let pk = ed25519::new_unvalidated_public_key_from_bytes(verifier.public_key);
                let msg_hash = hash::sha2_256(message);
                let is_valid = ed25519::signature_verify_strict(&sig, &pk, msg_hash);

                if (is_valid) {
                    verifier.total_verifications = verifier.total_verifications + 1;
                    verifier.last_active = timestamp::now_seconds();
                };

                return is_valid
            };
            i = i + 1;
        };
        abort error::not_found(EVERIFIER_NOT_FOUND)
    }

    public entry fun update_reputation(
        admin: &signer,
        public_key: vector<u8>,
        new_score: u64,
    ) acquires VerifierStore {
        let store = borrow_global_mut<VerifierStore>(@campaign_manager);
        assert!(signer::address_of(admin) == store.admin, ENOT_ADMIN);
        assert!(new_score <= 100, EINVALID_SCORE);
        
        let i = 0;
        let len = vector::length(&store.verifier_keys);
        while (i < len) {
            let key = vector::borrow_mut(&mut store.verifier_keys, i);
            if (key.public_key == public_key) {
                key.reputation_score = new_score;
                return
            };
            i = i + 1;
        };
        abort EKEY_NOT_FOUND
    }

    public fun is_active_verifier(verifier_address: address): bool acquires VerifierRegistry {
        if (!exists<VerifierRegistry>(@campaign_manager)) {
            return false
        };
        
        let registry = borrow_global<VerifierRegistry>(@campaign_manager);
        let len = vector::length(&registry.verifiers);
        let i = 0;
        while (i < len) {
            let verifier = vector::borrow(&registry.verifiers, i);
            if (verifier.address == verifier_address) {
                return verifier.is_active
            };
            i = i + 1;
        };
        false
    }

    fun verifier_exists(verifier_address: address): bool acquires VerifierRegistry {
        let registry = borrow_global<VerifierRegistry>(@campaign_manager);
        let len = vector::length(&registry.verifiers);
        let i = 0;
        while (i < len) {
            let verifier = vector::borrow(&registry.verifiers, i);
            if (verifier.address == verifier_address) {
                return true
            };
            i = i + 1;
        };
        false
    }

    #[view]
    public fun get_verifier_info(public_key: vector<u8>): (u64, u64, u64) acquires VerifierStore {
        let store = borrow_global<VerifierStore>(@campaign_manager);
        let i = 0;
        let len = vector::length(&store.verifier_keys);
        while (i < len) {
            let key = vector::borrow(&store.verifier_keys, i);
            if (key.public_key == public_key) {
                return (
                    key.reputation_score,
                    key.total_verifications,
                    key.last_active
                )
            };
            i = i + 1;
        };
        abort EKEY_NOT_FOUND
    }

    public fun initialize_verifier_store(account: &signer) {
        move_to(account, VerifierStore {
            admin: signer::address_of(account),
            verifier_keys: vector::empty(),
        });
    }

    public entry fun add_verifier_key(
        admin: &signer,
        public_key: vector<u8>,
    ) acquires VerifierStore {
        let store = borrow_global_mut<VerifierStore>(@campaign_manager);
        assert!(signer::address_of(admin) == store.admin, ENOT_ADMIN);
        
        // Check if key already exists
        let i = 0;
        let len = vector::length(&store.verifier_keys);
        while (i < len) {
            let key = vector::borrow(&store.verifier_keys, i);
            assert!(key.public_key != public_key, EKEY_ALREADY_EXISTS);
            i = i + 1;
        };
        
        let verifier_key = VerifierKey {
            public_key,
            reputation_score: 100,  
            total_verifications: 0,
            last_active: timestamp::now_seconds(),
        };
        
        vector::push_back(&mut store.verifier_keys, verifier_key);
    }

    public fun verify_contribution(
        campaign_id: String,
        data_hash: vector<u8>,
        data_url: String,
        signature: vector<u8>,
        quality_score: u64,
    ): VerificationResult acquires VerifierStore {
        let message = vector::empty<u8>();
        vector::append(&mut message, *string::bytes(&campaign_id));
        vector::append(&mut message, data_hash);
        vector::append(&mut message, *string::bytes(&data_url));
        vector::append(&mut message, bcs::to_bytes(&quality_score));
        
        let message_hash = hash::sha2_256(message);
        let signature = ed25519::new_signature_from_bytes(signature);
        
        let store = borrow_global_mut<VerifierStore>(@campaign_manager);
        let i = 0;
        let len = vector::length(&store.verifier_keys);
        
        while (i < len) {
            let key = vector::borrow_mut(&mut store.verifier_keys, i);
            let pk = ed25519::new_unvalidated_public_key_from_bytes(key.public_key);
            if (ed25519::signature_verify_strict(&signature, &pk, message_hash)) {
                key.total_verifications = key.total_verifications + 1;
                key.last_active = timestamp::now_seconds();
                
                return VerificationResult {
                    is_valid: true,
                    scores: create_verification_scores(key.reputation_score, quality_score),
                }
            };
            i = i + 1;
        };
        
        VerificationResult {
            is_valid: false,
            scores: create_verification_scores(0, 0),
        }
    }

    public fun create_verification_scores(verifier_reputation: u64, quality_score: u64): VerificationScores {
        assert!(is_valid_score(verifier_reputation), error::invalid_argument(EINVALID_SCORE));
        assert!(is_valid_score(quality_score), error::invalid_argument(EINVALID_SCORE));
        
        VerificationScores {
            verifier_reputation,
            quality_score,
        }
    }

    public fun is_valid_score(score: u64): bool {
        score >= MINIMUM_SCORE && score <= MAXIMUM_SCORE
    }

    public fun is_sufficient_for_reward(scores: &VerificationScores): bool {
        scores.verifier_reputation >= MINIMUM_VERIFIER_REPUTATION && 
        scores.quality_score >= MINIMUM_QUALITY_SCORE
    }

    public fun get_scores(scores: &VerificationScores): (u64, u64) {
        (scores.verifier_reputation, scores.quality_score)
    }

    public fun is_valid(result: &VerificationResult): bool {
        result.is_valid
    }

    public fun get_result_scores(result: &VerificationResult): &VerificationScores {
        &result.scores
    }
}

#[test_only]
module campaign_manager::verifier_tests {
    use std::string;
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::ed25519;
    use campaign_manager::verifier;

    fun setup_test_environment(
        admin: &signer,
        verifier_account: &signer
    ) {
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(verifier_account));

        verifier::initialize(admin);
        verifier::initialize_verifier_store(admin);
    }

    fun generate_test_keypair(): (vector<u8>, vector<u8>) {
        // Generate a test ED25519 keypair for testing
        let public_key = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        let private_key = x"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        (public_key, private_key)
    }

    #[test(admin = @campaign_manager, verifier = @0x456)]
    public fun test_add_verifier(
        admin: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, verifier);
        let (public_key, _) = generate_test_keypair();
        let verifier_addr = signer::address_of(verifier);

        verifier::add_verifier(admin, verifier_addr, public_key);

        assert!(verifier::is_active_verifier(verifier_addr), 0);
    }

    #[test(admin = @campaign_manager, verifier = @0x456)]
    public fun test_add_verifier_key(
        admin: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, verifier);
        let (public_key, _) = generate_test_keypair();

        verifier::add_verifier_key(admin, public_key);

        let (reputation_score, total_verifications, _) = verifier::get_verifier_info(public_key);
        assert!(reputation_score == 100, 0); // Initial reputation score
        assert!(total_verifications == 0, 1); // No verifications yet
    }

    #[test(admin = @campaign_manager, verifier = @0x456)]
    public fun test_remove_verifier(
        admin: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, verifier);
        let (public_key, _) = generate_test_keypair();
        let verifier_addr = signer::address_of(verifier);

        verifier::add_verifier(admin, verifier_addr, public_key);
        assert!(verifier::is_active_verifier(verifier_addr), 0);

        verifier::remove_verifier(admin, verifier_addr);
        assert!(!verifier::is_active_verifier(verifier_addr), 1);
    }

    #[test(admin = @campaign_manager, verifier = @0x456)]
    public fun test_verify_contribution(
        admin: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, verifier);
        let (public_key, _) = generate_test_keypair();

        // Add verifier key
        verifier::add_verifier_key(admin, public_key);

        // Create test contribution data
        let campaign_id = string::utf8(b"test_campaign");
        let data_hash = x"1234567890";
        let data_url = string::utf8(b"ipfs://testdata");
        let quality_score: u64 = 80;

        // Create a test signature (in real world this would be properly signed)
        let signature = vector::empty<u8>();
        let i = 0;
        while (i < 64) {
            vector::push_back(&mut signature, 1);
            i = i + 1;
        };

        // Verify contribution
        let result = verifier::verify_contribution(
            campaign_id,
            data_hash,
            data_url,
            signature,
            quality_score,
        );

        // Note: The verification will fail because we're using dummy signatures
        assert!(!verifier::is_valid(&result), 0);
    }

    #[test(admin = @campaign_manager)]
    public fun test_verification_scores() {
        let admin = &account::create_signer_for_test(@campaign_manager);
        setup_test_environment(admin, admin);

        // Test valid scores
        let scores = verifier::create_verification_scores(80, 85);
        let (verifier_reputation, quality_score) = verifier::get_scores(&scores);
        assert!(verifier_reputation == 80, 0);
        assert!(quality_score == 85, 1);
        assert!(verifier::is_sufficient_for_reward(&scores), 2);

        // Test score validation
        let scores_low = verifier::create_verification_scores(70, 70);
        assert!(verifier::is_sufficient_for_reward(&scores_low), 3);

        let scores_insufficient = verifier::create_verification_scores(69, 80);
        assert!(!verifier::is_sufficient_for_reward(&scores_insufficient), 4);
    }

    #[test(admin = @campaign_manager)]
    #[expected_failure(abort_code = 12)]
    public fun test_invalid_score() {
        let admin = &account::create_signer_for_test(@campaign_manager);
        setup_test_environment(admin, admin);

        // Attempt to create scores with invalid value (>100)
        verifier::create_verification_scores(101, 80);
    }

    #[test(admin = @campaign_manager, verifier = @0x456)]
    #[expected_failure(abort_code = 3)]
    public fun test_duplicate_verifier(
        admin: &signer,
        verifier: &signer
    ) {
        setup_test_environment(admin, verifier);
        let (public_key, _) = generate_test_keypair();
        let verifier_addr = signer::address_of(verifier);

        // Add verifier first time
        verifier::add_verifier(admin, verifier_addr, public_key);

        // Attempt to add same verifier again (should fail)
        verifier::add_verifier(admin, verifier_addr, public_key);
    }

    #[test(admin = @campaign_manager, verifier = @0x456, unauthorized = @0x789)]
    #[expected_failure(abort_code = 1)]
    public fun test_unauthorized_verifier_removal(
        admin: &signer,
        verifier: &signer,
        unauthorized: &signer
    ) {
        setup_test_environment(admin, verifier);
        let (public_key, _) = generate_test_keypair();
        let verifier_addr = signer::address_of(verifier);

        // Add verifier
        verifier::add_verifier(admin, verifier_addr, public_key);

        // Create unauthorized account
        account::create_account_for_test(signer::address_of(unauthorized));

        // Attempt unauthorized removal (should fail)
        verifier::remove_verifier(unauthorized, verifier_addr);
    }

    #[test(admin = @campaign_manager)]
    public fun test_update_reputation() {
        let admin = &account::create_signer_for_test(@campaign_manager);
        setup_test_environment(admin, admin);
        let (public_key, _) = generate_test_keypair();

        // Add verifier key
        verifier::add_verifier_key(admin, public_key);

        // Update reputation
        verifier::update_reputation(admin, public_key, 90);

        // Verify updated reputation
        let (reputation_score, _, _) = verifier::get_verifier_info(public_key);
        assert!(reputation_score == 90, 0);
    }
} 
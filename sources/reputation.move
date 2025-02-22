module campaign_manager::reputation {
    use std::error;
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;

    // Error codes
    const ENO_REPUTATION_STORE: u64 = 1;
    const EINVALID_REPUTATION_CHANGE: u64 = 2;
    const EINVALID_BADGE_ID: u64 = 3;

    // Constants for reputation thresholds
    const BRONZE_THRESHOLD: u64 = 100;
    const SILVER_THRESHOLD: u64 = 500;
    const GOLD_THRESHOLD: u64 = 1000;
    const PLATINUM_THRESHOLD: u64 = 5000;

    // Contribution thresholds
    const CONTRIBUTION_MILESTONE_1: u64 = 10;  // 10 contributions
    const CONTRIBUTION_MILESTONE_2: u64 = 50;  // 50 contributions
    const CONTRIBUTION_MILESTONE_3: u64 = 100; // 100 contributions

    // Payment thresholds
    const PAYMENT_MILESTONE_1: u64 = 5;   // 5 successful payments
    const PAYMENT_MILESTONE_2: u64 = 25;  // 25 successful payments
    const PAYMENT_MILESTONE_3: u64 = 50;  // 50 successful payments

    // Badge types
    // Contributor badges
    const BADGE_CONTRIBUTOR: u8 = 1;
    const BADGE_TOP_CONTRIBUTOR: u8 = 2;
    const BADGE_EXPERT_CONTRIBUTOR: u8 = 3;

    // Campaign creator badges
    const BADGE_CAMPAIGN_CREATOR: u8 = 10;
    const BADGE_RELIABLE_PAYER: u8 = 11;
    const BADGE_TRUSTED_CREATOR: u8 = 12;
    const BADGE_EXPERT_CREATOR: u8 = 13;

    // Verifier badges
    const BADGE_VERIFIER: u8 = 20;
    const BADGE_TRUSTED_VERIFIER: u8 = 21;
    const BADGE_EXPERT_VERIFIER: u8 = 22;

    // Achievement badges
    const BADGE_FIRST_CONTRIBUTION: u8 = 30;
    const BADGE_FIRST_CAMPAIGN: u8 = 31;
    const BADGE_FIRST_VERIFICATION: u8 = 32;

    struct Badge has store, drop, copy {
        badge_type: u8,
        timestamp: u64,
        description: vector<u8>
    }

    struct ReputationStore has key {
        reputation_score: u64,
        badges: vector<Badge>,
        contribution_count: u64,
        successful_payments: u64,
        reputation_events: event::EventHandle<ReputationChangeEvent>
    }

    struct ReputationChangeEvent has drop, store {
        user: address,
        points_change: u64,
        is_increase: bool,
        reason: vector<u8>,
        timestamp: u64
    }

    public fun ensure_reputation_store_exists(account: &signer) {
        let addr = signer::address_of(account);
        if (!exists<ReputationStore>(addr)) {
            initialize(account);
        };
    }

    #[view]
    public fun has_reputation_store(addr: address): bool {
        exists<ReputationStore>(addr)
    }

    fun initialize(account: &signer) {
        let store = ReputationStore {
            reputation_score: 0,
            badges: vector::empty<Badge>(),
            contribution_count: 0,
            successful_payments: 0,
            reputation_events: account::new_event_handle<ReputationChangeEvent>(account)
        };
        move_to(account, store);
    }

    public fun add_reputation_points(
        account_addr: address,
        points: u64,
        reason: vector<u8>
    ) acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global_mut<ReputationStore>(account_addr);
        
        store.reputation_score = store.reputation_score + points;
        
        // Emit reputation change event
        event::emit_event(&mut store.reputation_events, ReputationChangeEvent {
            user: account_addr,
            points_change: points,
            is_increase: true,
            reason,
            timestamp: timestamp::now_seconds()
        });

        // Check and award badges based on new score
        check_and_award_badges(store);
    }

    public fun record_successful_contribution(account_addr: address) acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global_mut<ReputationStore>(account_addr);
        
        store.contribution_count = store.contribution_count + 1;
        add_reputation_points(account_addr, 10, b"Successful contribution");
    }

    public fun record_successful_payment(account_addr: address) acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global_mut<ReputationStore>(account_addr);
        
        store.successful_payments = store.successful_payments + 1;
        add_reputation_points(account_addr, 15, b"Successful payment");
    }

    fun check_and_award_badges(store: &mut ReputationStore) {
        let score = store.reputation_score;
        let contributions = store.contribution_count;
        let payments = store.successful_payments;
        
        // Reputation-based badges
        if (score >= PLATINUM_THRESHOLD) {
            award_badge(store, BADGE_EXPERT_CONTRIBUTOR, b"Expert Contributor - Achieved highest reputation tier");
            award_badge(store, BADGE_EXPERT_CREATOR, b"Expert Creator - Achieved highest reputation tier");
        } else if (score >= GOLD_THRESHOLD) {
            award_badge(store, BADGE_TOP_CONTRIBUTOR, b"Top Contributor - Achieved gold reputation tier");
            award_badge(store, BADGE_TRUSTED_CREATOR, b"Trusted Creator - Achieved gold reputation tier");
        } else if (score >= SILVER_THRESHOLD) {
            award_badge(store, BADGE_RELIABLE_PAYER, b"Reliable Participant - Achieved silver reputation tier");
        } else if (score >= BRONZE_THRESHOLD) {
            award_badge(store, BADGE_CONTRIBUTOR, b"Active Contributor - Achieved bronze reputation tier");
            award_badge(store, BADGE_CAMPAIGN_CREATOR, b"Campaign Creator - Achieved bronze reputation tier");
        };

        // Contribution milestone badges
        if (contributions >= CONTRIBUTION_MILESTONE_3) {
            award_badge(store, BADGE_EXPERT_CONTRIBUTOR, b"Expert Contributor - Made 100+ contributions");
        } else if (contributions >= CONTRIBUTION_MILESTONE_2) {
            award_badge(store, BADGE_TOP_CONTRIBUTOR, b"Top Contributor - Made 50+ contributions");
        } else if (contributions >= CONTRIBUTION_MILESTONE_1) {
            award_badge(store, BADGE_CONTRIBUTOR, b"Active Contributor - Made 10+ contributions");
        } else if (contributions == 1) {
            award_badge(store, BADGE_FIRST_CONTRIBUTION, b"First Contribution - Made first contribution");
        };

        // Payment milestone badges
        if (payments >= PAYMENT_MILESTONE_3) {
            award_badge(store, BADGE_EXPERT_CREATOR, b"Expert Creator - Made 50+ successful payments");
        } else if (payments >= PAYMENT_MILESTONE_2) {
            award_badge(store, BADGE_TRUSTED_CREATOR, b"Trusted Creator - Made 25+ successful payments");
        } else if (payments >= PAYMENT_MILESTONE_1) {
            award_badge(store, BADGE_RELIABLE_PAYER, b"Reliable Payer - Made 5+ successful payments");
        } else if (payments == 1) {
            award_badge(store, BADGE_FIRST_CAMPAIGN, b"First Campaign - Made first successful payment");
        };
    }

    fun award_badge(store: &mut ReputationStore, badge_type: u8, description: vector<u8>) {
        // Check if badge already exists
        let i = 0;
        let len = vector::length(&store.badges);
        while (i < len) {
            let badge = vector::borrow(&store.badges, i);
            if (badge.badge_type == badge_type) {
                return
            };
            i = i + 1;
        };

        // Award new badge
        let new_badge = Badge {
            badge_type,
            timestamp: timestamp::now_seconds(),
            description
        };
        vector::push_back(&mut store.badges, new_badge);
    }

    #[view]
    public fun get_reputation_score(account_addr: address): u64 acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global<ReputationStore>(account_addr);
        store.reputation_score
    }

    #[view]
    public fun get_badge_count(account_addr: address): u64 acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global<ReputationStore>(account_addr);
        vector::length(&store.badges)
    }

    #[view]
    public fun get_badges(account_addr: address): vector<Badge> acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global<ReputationStore>(account_addr);
        *&store.badges
    }

    #[view]
    public fun get_contribution_count(account_addr: address): u64 acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global<ReputationStore>(account_addr);
        store.contribution_count
    }

    #[view]
    public fun get_successful_payments(account_addr: address): u64 acquires ReputationStore {
        assert!(exists<ReputationStore>(account_addr), error::not_found(ENO_REPUTATION_STORE));
        let store = borrow_global<ReputationStore>(account_addr);
        store.successful_payments
    }
} 
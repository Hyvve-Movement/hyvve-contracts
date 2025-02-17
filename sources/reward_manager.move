module campaign_manager::reward_manager {
    use std::error;
    use std::signer;
    use std::string::String;
    use std::vector;
    use campaign_manager::verifier;

    const EINVALID_REWARD: u64 = 1;
    const EREWARD_ALREADY_CLAIMED: u64 = 2;
    const EINSUFFICIENT_SCORE: u64 = 3;

    struct RewardClaim has store {
        campaign_id: String,
        contribution_id: String,
        amount: u64,
        is_claimed: bool,
    }

    struct RewardStore<phantom CoinType> has key {
        claims: vector<RewardClaim>,
    }

    fun init_module(account: &signer) {
        move_to(account, RewardStore<aptos_framework::aptos_coin::AptosCoin> {
            claims: vector::empty(),
        });
    }

    public fun process_reward<CoinType: key>(
        account: &signer,
        campaign_id: String,
        contribution_id: String,
        scores: &verifier::VerificationScores,
        amount: u64,
    ): bool acquires RewardStore {
        let sender = signer::address_of(account);
        
        // Verify scores are sufficient
        assert!(
            verifier::is_sufficient_for_reward(scores),
            error::invalid_argument(EINSUFFICIENT_SCORE)
        );

        let store = borrow_global_mut<RewardStore<CoinType>>(sender);
        let claim = RewardClaim {
            campaign_id,
            contribution_id,
            amount,
            is_claimed: false,
        };
        vector::push_back(&mut store.claims, claim);
        true
    }

    public fun claim_reward<CoinType: key>(
        account: &signer,
        campaign_id: String,
        contribution_id: String,
    ): bool acquires RewardStore {
        let sender = signer::address_of(account);
        let store = borrow_global_mut<RewardStore<CoinType>>(sender);
        
        let len = vector::length(&store.claims);
        let i = 0;
        while (i < len) {
            let claim = vector::borrow_mut(&mut store.claims, i);
            if (claim.campaign_id == campaign_id && 
                claim.contribution_id == contribution_id) {
                assert!(!claim.is_claimed, error::invalid_state(EREWARD_ALREADY_CLAIMED));
                claim.is_claimed = true;
                return true
            };
            i = i + 1;
        };
        false
    }

    public fun is_reward_claimed<CoinType: key>(
        account_addr: address,
        campaign_id: String,
        contribution_id: String,
    ): bool acquires RewardStore {
        if (!exists<RewardStore<CoinType>>(account_addr)) {
            return false
        };
        let store = borrow_global<RewardStore<CoinType>>(account_addr);
        let len = vector::length(&store.claims);
        let i = 0;
        while (i < len) {
            let claim = vector::borrow(&store.claims, i);
            if (claim.campaign_id == campaign_id && 
                claim.contribution_id == contribution_id) {
                return claim.is_claimed
            };
            i = i + 1;
        };
        false
    }
} 
module campaign_manager::campaign {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin::{Self, Coin};
    use campaign_manager::campaign_state;
    use campaign_manager::escrow;

    /// Error codes
    const EINVALID_REWARD_POOL: u64 = 1;
    const EINVALID_UNIT_PRICE: u64 = 2;
    const EINVALID_EXPIRATION: u64 = 3;
    const ECAMPAIGN_NOT_FOUND: u64 = 4;
    const ECAMPAIGN_EXPIRED: u64 = 5;
    const ENOT_CAMPAIGN_OWNER: u64 = 6;
    const EESCROW_NOT_SETUP: u64 = 7;
    const EINVALID_BUDGET: u64 = 8;
    const EINVALID_DURATION: u64 = 9;
    const ECAMPAIGN_ALREADY_EXISTS: u64 = 10;
    const ENOT_OWNER: u64 = 11;
    const ECAMPAIGN_ACTIVE: u64 = 12;

    struct Campaign has store, copy {
        campaign_id: String,
        owner: address,
        title: String,
        description: String,
        data_requirements: String,
        quality_criteria: String,
        unit_price: u64,          // Reward per valid contribution
        total_budget: u64,        // Total campaign budget
        min_data_count: u64,      // Minimum number of data points required
        max_data_count: u64,      // Maximum number of data points allowed
        expiration: u64,
        is_active: bool,
        total_contributions: u64,
        metadata_uri: String,     // IPFS/Arweave URI for additional metadata
        escrow_setup: bool,       // Track if escrow is set up
    }

    struct CampaignStore has key {
        campaigns: vector<Campaign>,
        campaign_creation_events: event::EventHandle<CampaignCreationEvent>,
        campaign_update_events: event::EventHandle<CampaignUpdateEvent>,
        campaign_events: event::EventHandle<CampaignEvent>,
    }

    struct CampaignCreationEvent has drop, store {
        campaign_id: String,
        owner: address,
        title: String,
        total_budget: u64,
        unit_price: u64,
        expiration: u64,
    }

    struct CampaignUpdateEvent has drop, store {
        campaign_id: String,
        new_data_requirements: String,
        new_quality_criteria: String,
        new_expiration: u64,
    }

    struct CampaignEvent has drop, store {
        campaign_id: String,
        owner: address,
        total_budget: u64,
        event_type: String,  // "created", "cancelled"
        timestamp: u64,
    }

    public fun initialize(account: &signer) {
        let campaign_store = CampaignStore {
            campaigns: vector::empty(),
            campaign_creation_events: account::new_event_handle<CampaignCreationEvent>(account),
            campaign_update_events: account::new_event_handle<CampaignUpdateEvent>(account),
            campaign_events: account::new_event_handle<CampaignEvent>(account),
        };
        move_to(account, campaign_store);
    }

    public entry fun create_campaign<CoinType: key>(
        account: &signer,
        campaign_id: String,
        title: String,
        description: String,
        data_requirements: String,
        quality_criteria: String,
        unit_price: u64,
        total_budget: u64,
        min_data_count: u64,
        max_data_count: u64,
        expiration: u64,
        metadata_uri: String,
        platform_fee: u64,
    ) acquires CampaignStore {
        let sender = signer::address_of(account);
        
        // Validate inputs
        assert!(unit_price > 0, error::invalid_argument(EINVALID_UNIT_PRICE));
        assert!(total_budget >= unit_price, error::invalid_argument(EINVALID_REWARD_POOL));
        assert!(min_data_count > 0 && min_data_count <= max_data_count, error::invalid_argument(EINVALID_REWARD_POOL));
        assert!(
            expiration > timestamp::now_seconds(),
            error::invalid_argument(EINVALID_EXPIRATION)
        );
        
        // Verify campaign doesn't exist
        assert!(!campaign_exists(campaign_id), error::already_exists(ECAMPAIGN_ALREADY_EXISTS));

        let campaign = Campaign {
            campaign_id,
            owner: sender,
            title,
            description,
            data_requirements,
            quality_criteria,
            unit_price,
            total_budget,
            min_data_count,
            max_data_count,
            expiration,
            is_active: true,
            total_contributions: 0,
            metadata_uri,
            escrow_setup: false,
        };

        let campaign_store = borrow_global_mut<CampaignStore>(@campaign_manager);
        vector::push_back(&mut campaign_store.campaigns, campaign);

        // Set up escrow for the campaign
        campaign_manager::escrow::create_campaign_escrow<CoinType>(
            account,
            campaign_id,
            total_budget,
            unit_price,
            platform_fee,
        );

        // Mark escrow as set up
        let len = vector::length(&mut campaign_store.campaigns);
        let campaign = vector::borrow_mut(&mut campaign_store.campaigns, len - 1);
        campaign.escrow_setup = true;

        event::emit_event(
            &mut campaign_store.campaign_creation_events,
            CampaignCreationEvent {
                campaign_id,
                owner: sender,
                title,
                total_budget,
                unit_price,
                expiration,
            },
        );
    }

    public entry fun update_campaign(
        account: &signer,
        campaign_id: String,
        new_data_requirements: String,
        new_quality_criteria: String,
        new_expiration: u64,
    ) acquires CampaignStore {
        let sender = signer::address_of(account);
        let campaign_store = borrow_global_mut<CampaignStore>(@campaign_manager);
        
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow_mut(&mut campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                assert!(campaign.owner == sender, error::permission_denied(ENOT_CAMPAIGN_OWNER));
                assert!(campaign.is_active, error::invalid_state(ECAMPAIGN_EXPIRED));
                assert!(campaign.escrow_setup, error::invalid_state(EESCROW_NOT_SETUP));
                
                campaign.data_requirements = new_data_requirements;
                campaign.quality_criteria = new_quality_criteria;
                campaign.expiration = new_expiration;

                event::emit_event(
                    &mut campaign_store.campaign_update_events,
                    CampaignUpdateEvent {
                        campaign_id,
                        new_data_requirements,
                        new_quality_criteria,
                        new_expiration,
                    },
                );
                return
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    public entry fun cancel_campaign<CoinType: key>(
        account: &signer,
        campaign_id: String
    ) acquires CampaignStore {
        let sender = signer::address_of(account);
        let campaign_store = borrow_global_mut<CampaignStore>(@campaign_manager);
        
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow_mut(&mut campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                assert!(campaign.owner == sender, error::permission_denied(ENOT_OWNER));
                assert!(campaign.is_active, error::invalid_state(ECAMPAIGN_EXPIRED));
                
                campaign.is_active = false;
                campaign_state::deactivate_campaign(campaign_id);
                
                // Refund remaining escrow balance
                campaign_manager::escrow::refund_remaining<CoinType>(account, campaign_id);

                event::emit_event(
                    &mut campaign_store.campaign_events,
                    CampaignEvent {
                        campaign_id,
                        owner: sender,
                        total_budget: campaign.total_budget,
                        event_type: string::utf8(b"cancelled"),
                        timestamp: timestamp::now_seconds(),
                    },
                );
                return
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    #[view]
    public fun get_campaign_details(
        campaign_store_address: address,
        campaign_id: String
    ): (String, String, String, String, u64, u64, u64, u64, u64, bool, String) acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                return (
                    campaign.title,
                    campaign.description,
                    campaign.data_requirements,
                    campaign.quality_criteria,
                    campaign.unit_price,
                    campaign.total_budget,
                    campaign.min_data_count,
                    campaign.max_data_count,
                    campaign.expiration,
                    campaign.is_active,
                    campaign.metadata_uri
                )
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    #[view]
    public fun get_campaign_status(
        campaign_store_address: address,
        campaign_id: String
    ): (bool, u64, u64) acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                return (
                    campaign.is_active,
                    campaign.total_contributions,
                    campaign.max_data_count - campaign.total_contributions
                )
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    public fun verify_campaign_active(
        campaign_store_address: address,
        campaign_id: String
    ): bool acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                return campaign.is_active && timestamp::now_seconds() <= campaign.expiration
            };
            i = i + 1;
        };
        false
    }

    public fun get_unit_price(
        campaign_store_address: address,
        campaign_id: String
    ): u64 acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                return campaign.unit_price
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    public fun increment_contributions(
        campaign_store_address: address,
        campaign_id: String
    ): bool acquires CampaignStore {
        let campaign_store = borrow_global_mut<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow_mut(&mut campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                if (campaign.total_contributions < campaign.max_data_count) {
                    campaign.total_contributions = campaign.total_contributions + 1;
                    return true
                };
                return false
            };
            i = i + 1;
        };
        false
    }

    fun campaign_exists(campaign_id: String): bool acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(@campaign_manager);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                return true
            };
            i = i + 1;
        };
        false
    }

    #[view]
    public fun get_active_campaigns(
        campaign_store_address: address
    ): vector<Campaign> acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let active_campaigns = vector::empty<Campaign>();
        let current_time = timestamp::now_seconds();
        
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.is_active && current_time <= campaign.expiration) {
                vector::push_back(&mut active_campaigns, *campaign);
            };
            i = i + 1;
        };
        active_campaigns
    }

    #[view]
    public fun get_owner_active_campaigns(
        campaign_store_address: address,
        owner_address: address
    ): vector<Campaign> acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let owner_campaigns = vector::empty<Campaign>();
        let current_time = timestamp::now_seconds();
        
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.owner == owner_address && 
                campaign.is_active && 
                current_time <= campaign.expiration) {
                vector::push_back(&mut owner_campaigns, *campaign);
            };
            i = i + 1;
        };
        owner_campaigns
    }

    #[view]
    public fun get_campaign_count(
        campaign_store_address: address
    ): (u64, u64) acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let total_count = vector::length(&campaign_store.campaigns);
        let current_time = timestamp::now_seconds();
        
        let active_count = 0;
        let i = 0;
        while (i < total_count) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.is_active && current_time <= campaign.expiration) {
                active_count = active_count + 1;
            };
            i = i + 1;
        };
        (total_count, active_count)
    }
}
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

    fun init_module(account: &signer) {
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

        campaign_state::add_campaign(
            campaign_id,
            timestamp::now_seconds(),
            expiration,
        );

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

#[test_only]
module campaign_manager::campaign_tests {
    use std::string;
    use std::signer;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::timestamp;
    use campaign_manager::campaign;

    struct TestCoin has key { }

    #[test(campaign_admin = @campaign_manager, contributor = @0x456)]
    public fun test_create_campaign(campaign_admin: &signer, contributor: &signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(campaign_admin);
        account::create_account_for_test(signer::address_of(campaign_admin));
        account::create_account_for_test(signer::address_of(contributor));
        
        // Initialize campaign store
        campaign::init_module(campaign_admin);

        // Create test campaign
        let campaign_id = string::utf8(b"test_campaign_1");
        let title = string::utf8(b"Test Campaign");
        let description = string::utf8(b"Test Description");
        let data_requirements = string::utf8(b"Test Requirements");
        let quality_criteria = string::utf8(b"Test Criteria");
        let unit_price = 100;
        let total_budget = 1000;
        let min_data_count = 5;
        let max_data_count = 10;
        let expiration = timestamp::now_seconds() + 86400; // 1 day from now
        let metadata_uri = string::utf8(b"ipfs://test");
        let platform_fee = 10;

        // Create campaign
        campaign::create_campaign<TestCoin>(
            campaign_admin,
            campaign_id,
            title,
            description,
            data_requirements,
            quality_criteria,
            unit_price,
            total_budget,
            min_data_count,
            max_data_count,
            expiration,
            metadata_uri,
            platform_fee,
        );

        let (
            returned_title,
            returned_description,
            returned_requirements,
            returned_criteria,
            returned_unit_price,
            returned_budget,
            returned_min_count,
            returned_max_count,
            returned_expiration,
            is_active,
            returned_metadata
        ) = campaign::get_campaign_details(@campaign_manager, campaign_id);

        assert!(returned_title == title, 0);
        assert!(returned_description == description, 1);
        assert!(returned_requirements == data_requirements, 2);
        assert!(returned_criteria == quality_criteria, 3);
        assert!(returned_unit_price == unit_price, 4);
        assert!(returned_budget == total_budget, 5);
        assert!(returned_min_count == min_data_count, 6);
        assert!(returned_max_count == max_data_count, 7);
        assert!(returned_expiration == expiration, 8);
        assert!(is_active == true, 9);
        assert!(returned_metadata == metadata_uri, 10);
    }

    #[test(campaign_admin = @campaign_manager)]
    #[expected_failure(abort_code = 2)]
    public fun test_create_campaign_invalid_price(campaign_admin: &signer) {
        // Setup
        timestamp::set_time_has_started_for_testing(campaign_admin);
        account::create_account_for_test(signer::address_of(campaign_admin));
        campaign::init_module(campaign_admin);

        // Attempt to create campaign with invalid price (0)
        campaign::create_campaign<TestCoin>(
            campaign_admin,
            string::utf8(b"test_campaign"),
            string::utf8(b"title"),
            string::utf8(b"description"),
            string::utf8(b"requirements"),
            string::utf8(b"criteria"),
            0, // Invalid price
            1000,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"metadata"),
            10,
        );
    }

    #[test(campaign_admin = @campaign_manager)]
    public fun test_update_campaign(campaign_admin: &signer) {
        // Setup
        timestamp::set_time_has_started_for_testing(campaign_admin);
        account::create_account_for_test(signer::address_of(campaign_admin));
        campaign::init_module(campaign_admin);

        // Create initial campaign
        let campaign_id = string::utf8(b"test_campaign");
        campaign::create_campaign<TestCoin>(
            campaign_admin,
            campaign_id,
            string::utf8(b"title"),
            string::utf8(b"description"),
            string::utf8(b"requirements"),
            string::utf8(b"criteria"),
            100,
            1000,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"metadata"),
            10,
        );

        // Update campaign
        let new_requirements = string::utf8(b"new requirements");
        let new_criteria = string::utf8(b"new criteria");
        let new_expiration = timestamp::now_seconds() + 172800; // 2 days

        campaign::update_campaign(
            campaign_admin,
            campaign_id,
            new_requirements,
            new_criteria,
            new_expiration,
        );

        let (
            _title,
            _description,
            returned_requirements,
            returned_criteria,
            _unit_price,
            _budget,
            _min_count,
            _max_count,
            returned_expiration,
            _is_active,
            _metadata
        ) = campaign::get_campaign_details(@campaign_manager, campaign_id);

        assert!(returned_requirements == new_requirements, 0);
        assert!(returned_criteria == new_criteria, 1);
        assert!(returned_expiration == new_expiration, 2);
    }

    #[test(campaign_admin = @campaign_manager)]
    public fun test_cancel_campaign(campaign_admin: &signer) {
        timestamp::set_time_has_started_for_testing(campaign_admin);
        account::create_account_for_test(signer::address_of(campaign_admin));
        campaign::init_module(campaign_admin);

        let campaign_id = string::utf8(b"test_campaign");
        campaign::create_campaign<TestCoin>(
            campaign_admin,
            campaign_id,
            string::utf8(b"title"),
            string::utf8(b"description"),
            string::utf8(b"requirements"),
            string::utf8(b"criteria"),
            100,
            1000,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"metadata"),
            10,
        );

        campaign::cancel_campaign<TestCoin>(campaign_admin, campaign_id);

        let (is_active, _, _) = campaign::get_campaign_status(@campaign_manager, campaign_id);
        assert!(!is_active, 0);
    }

    #[test(campaign_admin = @campaign_manager)]
    public fun test_get_campaign_count(campaign_admin: &signer) {
        timestamp::set_time_has_started_for_testing(campaign_admin);
        account::create_account_for_test(signer::address_of(campaign_admin));
        campaign::init_module(campaign_admin);

        let campaign_id1 = string::utf8(b"campaign1");
        let campaign_id2 = string::utf8(b"campaign2");
        
        campaign::create_campaign<TestCoin>(
            campaign_admin,
            campaign_id1,
            string::utf8(b"title1"),
            string::utf8(b"description1"),
            string::utf8(b"requirements1"),
            string::utf8(b"criteria1"),
            100,
            1000,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"metadata1"),
            10,
        );

        campaign::create_campaign<TestCoin>(
            campaign_admin,
            campaign_id2,
            string::utf8(b"title2"),
            string::utf8(b"description2"),
            string::utf8(b"requirements2"),
            string::utf8(b"criteria2"),
            200,
            2000,
            10,
            20,
            timestamp::now_seconds() + 86400,
            string::utf8(b"metadata2"),
            10,
        );

        let (total_count, active_count) = campaign::get_campaign_count(@campaign_manager);
        assert!(total_count == 2, 0);
        assert!(active_count == 2, 1);

        campaign::cancel_campaign<TestCoin>(campaign_admin, campaign_id1);

        let (total_count, active_count) = campaign::get_campaign_count(@campaign_manager);
        assert!(total_count == 2, 2);
        assert!(active_count == 1, 3);
    }
}
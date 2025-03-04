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
    use campaign_manager::contribution;
    use campaign_manager::reputation;

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
    const EUSERNAME_ALREADY_TAKEN: u64 = 13;
    const EUSERNAME_TOO_LONG: u64 = 14;
    const EUSERNAME_ALREADY_SET: u64 = 15;
    const EUSERNAME_EDIT_LIMIT_REACHED: u64 = 16;
    const ENO_USERNAME: u64 = 17;

    // Username constraints
    const MAX_USERNAME_LENGTH: u64 = 32;
    const MAX_USERNAME_EDITS: u64 = 2;

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
        encryption_pub_key: vector<u8>, // Public encryption key for AES-256-CBC
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

    struct UsernameStore has key {
        usernames: vector<UsernameEntry>
    }

    struct UsernameEntry has store, drop {
        address: address,
        username: vector<u8>,
        edit_count: u64
    }

    fun init_module(account: &signer) {
        let campaign_store = CampaignStore {
            campaigns: vector::empty(),
            campaign_creation_events: account::new_event_handle<CampaignCreationEvent>(account),
            campaign_update_events: account::new_event_handle<CampaignUpdateEvent>(account),
            campaign_events: account::new_event_handle<CampaignEvent>(account),
        };
        move_to(account, campaign_store);

        // Initialize username store
        move_to(account, UsernameStore {
            usernames: vector::empty<UsernameEntry>()
        });
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
        encryption_pub_key: vector<u8>
    ) acquires CampaignStore {
        let sender = signer::address_of(account);
        
        // Initialize reputation store for new campaign creators
        reputation::ensure_reputation_store_exists(account);
        
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
            encryption_pub_key,
        };

        let campaign_store = borrow_global_mut<CampaignStore>(@campaign_manager);
        vector::push_back(&mut campaign_store.campaigns, campaign);

        campaign_state::add_campaign(
            campaign_id,
            timestamp::now_seconds(),
            expiration,
            sender,
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
    ): (String, String, String, String, u64, u64, u64, u64, u64, bool, String, vector<u8>) acquires CampaignStore {
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
                    campaign.metadata_uri,
                    campaign.encryption_pub_key 
                )
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    #[view]
    public fun get_encryption_public_key(
        campaign_store_address: address,
        campaign_id: String
    ): vector<u8> acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                return campaign.encryption_pub_key
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

    #[view]
    public fun is_campaign_owner(
        campaign_store_address: address,
        campaign_id: String,
        owner_address: address
    ): bool acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                return campaign.owner == owner_address
            };
            i = i + 1;
        };
        false
    }

    #[view]
    public fun get_campaign_remaining_budget<CoinType: key>(
        campaign_store_address: address,
        campaign_id: String
    ): u64 acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                assert!(campaign.escrow_setup, error::invalid_state(EESCROW_NOT_SETUP));
                return campaign_manager::escrow::get_available_balance<CoinType>(campaign_id)
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    #[view]
    public fun get_address_total_spent<CoinType: key>(
        campaign_store_address: address,
        owner_address: address
    ): u64 acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let total_spent = 0u64;
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.owner == owner_address && campaign.escrow_setup) {
                total_spent = total_spent + campaign.total_budget;
            };
            i = i + 1;
        };
        total_spent
    }

    #[view]
    public fun get_address_total_earned<CoinType: key>(
        campaign_store_address: address,
        contributor_address: address
    ): u64 acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let total_earned = 0u64;
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.escrow_setup) {
                // Get contribution count and rewards for this campaign
                let contribution_count = campaign_manager::contribution::get_address_contribution_count(
                    contributor_address,
                    campaign.campaign_id
                );
                if (contribution_count > 0) {
                    total_earned = total_earned + (contribution_count * campaign.unit_price);
                };
            };
            i = i + 1;
        };
        total_earned
    }

    #[view]
    public fun get_address_campaign_count(
        campaign_store_address: address,
        owner_address: address
    ): (u64, u64) acquires CampaignStore {
        let campaign_store = borrow_global<CampaignStore>(campaign_store_address);
        let total_count = 0u64;
        let active_count = 0u64;
        let current_time = timestamp::now_seconds();
        
        let len = vector::length(&campaign_store.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&campaign_store.campaigns, i);
            if (campaign.owner == owner_address) {
                total_count = total_count + 1;
                if (campaign.is_active && current_time <= campaign.expiration) {
                    active_count = active_count + 1;
                };
            };
            i = i + 1;
        };
        (total_count, active_count)
    }

    public entry fun set_username(account: &signer, username: vector<u8>) acquires UsernameStore {
        let sender = signer::address_of(account);
        let username_store = borrow_global_mut<UsernameStore>(@campaign_manager);
        
        // Check username length
        assert!(vector::length(&username) <= MAX_USERNAME_LENGTH, error::invalid_argument(EUSERNAME_TOO_LONG));
        
        // Check if username is already taken
        let len = vector::length(&username_store.usernames);
        let i = 0;
        while (i < len) {
            let entry = vector::borrow(&username_store.usernames, i);
            if (entry.username == username) {
                abort error::already_exists(EUSERNAME_ALREADY_TAKEN)
            };
            if (entry.address == sender) {
                abort error::already_exists(EUSERNAME_ALREADY_SET)
            };
            i = i + 1;
        };
        
        // Add new username
        let entry = UsernameEntry {
            address: sender,
            username,
            edit_count: 0
        };
        vector::push_back(&mut username_store.usernames, entry);
    }

    public entry fun edit_username(account: &signer, new_username: vector<u8>) acquires UsernameStore {
        let sender = signer::address_of(account);
        let username_store = borrow_global_mut<UsernameStore>(@campaign_manager);
        
        // Check username length
        assert!(vector::length(&new_username) <= MAX_USERNAME_LENGTH, error::invalid_argument(EUSERNAME_TOO_LONG));
        
        // Check if new username is already taken by someone else
        let len = vector::length(&username_store.usernames);
        let i = 0;
        while (i < len) {
            let entry = vector::borrow(&username_store.usernames, i);
            if (entry.username == new_username && entry.address != sender) {
                abort error::already_exists(EUSERNAME_ALREADY_TAKEN)
            };
            i = i + 1;
        };
        
        // Find and update existing username
        i = 0;
        while (i < len) {
            let entry = vector::borrow_mut(&mut username_store.usernames, i);
            if (entry.address == sender) {
                // Check edit limit
                assert!(entry.edit_count < MAX_USERNAME_EDITS, error::invalid_state(EUSERNAME_EDIT_LIMIT_REACHED));
                entry.username = new_username;
                entry.edit_count = entry.edit_count + 1;
                return
            };
            i = i + 1;
        };
        // If we get here, user hasn't set a username yet
        abort error::not_found(ENO_USERNAME)
    }

    #[view]
    public fun get_username(addr: address): vector<u8> acquires UsernameStore {
        let username_store = borrow_global<UsernameStore>(@campaign_manager);
        let len = vector::length(&username_store.usernames);
        let i = 0;
        while (i < len) {
            let entry = vector::borrow(&username_store.usernames, i);
            if (entry.address == addr) {
                return *&entry.username
            };
            i = i + 1;
        };
        vector::empty<u8>() // Return empty vector if no username is found
    }

    #[view]
    public fun get_username_edit_count(addr: address): u64 acquires UsernameStore {
        let username_store = borrow_global<UsernameStore>(@campaign_manager);
        let len = vector::length(&username_store.usernames);
        let i = 0;
        while (i < len) {
            let entry = vector::borrow(&username_store.usernames, i);
            if (entry.address == addr) {
                return entry.edit_count
            };
            i = i + 1;
        };
        0
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
    use campaign_manager::contribution;

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

    #[test(admin = @campaign_manager, other_user = @0x456)]
    public fun test_is_campaign_owner(admin: &signer, other_user: &signer) {
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(other_user));
        campaign::init_module(admin);

        let campaign_id = string::utf8(b"test_campaign");
        
        // Create a campaign as admin
        campaign::create_campaign<TestCoin>(
            admin,
            campaign_id,
            string::utf8(b"Test Campaign"),
            string::utf8(b"Description"),
            string::utf8(b"Requirements"),
            string::utf8(b"Criteria"),
            100,
            1000,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"ipfs://test"),
            10,
        );

        // Check that admin is the owner
        assert!(campaign::is_campaign_owner(@campaign_manager, campaign_id, signer::address_of(admin)), 0);
        
        // Check that other_user is not the owner
        assert!(!campaign::is_campaign_owner(@campaign_manager, campaign_id, signer::address_of(other_user)), 1);
        
        // Check non-existent campaign returns false
        assert!(!campaign::is_campaign_owner(
            @campaign_manager,
            string::utf8(b"non_existent_campaign"),
            signer::address_of(admin)
        ), 2);
    }

    #[test(campaign_admin = @campaign_manager)]
    public fun test_get_campaign_remaining_budget(campaign_admin: &signer) {
        timestamp::set_time_has_started_for_testing(campaign_admin);
        account::create_account_for_test(signer::address_of(campaign_admin));
        campaign::init_module(campaign_admin);

        let campaign_id = string::utf8(b"test_campaign");
        let total_budget = 1000;
        
        campaign::create_campaign<TestCoin>(
            campaign_admin,
            campaign_id,
            string::utf8(b"Test Campaign"),
            string::utf8(b"Description"),
            string::utf8(b"Requirements"),
            string::utf8(b"Criteria"),
            100, // unit_price
            total_budget,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"ipfs://test"),
            10,
            vector::empty(), // empty encryption key for test
        );

        let remaining_budget = campaign::get_campaign_remaining_budget<TestCoin>(
            @campaign_manager,
            campaign_id
        );
        
        // Initially, remaining budget should equal total budget
        assert!(remaining_budget == total_budget, 0);
    }

    #[test(admin = @campaign_manager, contributor = @0x456)]
    public fun test_address_totals(admin: &signer, contributor: &signer) {
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(contributor));
        campaign::init_module(admin);
        contribution::init_module(admin);

        // Create two campaigns
        let campaign_id1 = string::utf8(b"test_campaign_1");
        let campaign_id2 = string::utf8(b"test_campaign_2");
        let unit_price1 = 100;
        let unit_price2 = 200;
        let total_budget1 = 1000;
        let total_budget2 = 2000;

        // Create campaigns
        campaign::create_campaign<TestCoin>(
            admin,
            campaign_id1,
            string::utf8(b"Test Campaign 1"),
            string::utf8(b"Description"),
            string::utf8(b"Requirements"),
            string::utf8(b"Criteria"),
            unit_price1,
            total_budget1,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"ipfs://test1"),
            10,
            vector::empty(),
        );

        campaign::create_campaign<TestCoin>(
            admin,
            campaign_id2,
            string::utf8(b"Test Campaign 2"),
            string::utf8(b"Description"),
            string::utf8(b"Requirements"),
            string::utf8(b"Criteria"),
            unit_price2,
            total_budget2,
            5,
            10,
            timestamp::now_seconds() + 86400,
            string::utf8(b"ipfs://test2"),
            10,
            vector::empty(),
        );

        // Check total spent by admin
        let total_spent = campaign::get_address_total_spent<TestCoin>(
            @campaign_manager,
            signer::address_of(admin)
        );
        assert!(total_spent == total_budget1 + total_budget2, 0);

        // Submit contributions from contributor
        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id1,
            string::utf8(b"contribution1"),
            string::utf8(b"ipfs://data1"),
            vector::empty(),
            vector::empty(),
            80,
        );

        contribution::submit_contribution<TestCoin>(
            contributor,
            campaign_id2,
            string::utf8(b"contribution2"),
            string::utf8(b"ipfs://data2"),
            vector::empty(),
            vector::empty(),
            80,
        );

        // Check total earned by contributor
        let total_earned = campaign::get_address_total_earned<TestCoin>(
            @campaign_manager,
            signer::address_of(contributor)
        );
        assert!(total_earned == unit_price1 + unit_price2, 1);
    }

    #[test(admin = @campaign_manager)]
    public fun test_get_address_campaign_count(admin: &signer) {
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        campaign::init_module(admin);

        let admin_addr = signer::address_of(admin);
        
        // Initially should be 0
        let (total, active) = campaign::get_address_campaign_count(@campaign_manager, admin_addr);
        assert!(total == 0 && active == 0, 0);

        // Create two campaigns
        campaign::create_campaign<TestCoin>(
            admin,
            string::utf8(b"campaign1"),
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
            vector::empty(),
        );

        campaign::create_campaign<TestCoin>(
            admin,
            string::utf8(b"campaign2"),
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
            vector::empty(),
        );

        // Should now have 2 total, 2 active
        let (total, active) = campaign::get_address_campaign_count(@campaign_manager, admin_addr);
        assert!(total == 2 && active == 2, 1);

        // Cancel one campaign
        campaign::cancel_campaign<TestCoin>(admin, string::utf8(b"campaign1"));

        // Should now have 2 total, 1 active
        let (total, active) = campaign::get_address_campaign_count(@campaign_manager, admin_addr);
        assert!(total == 2 && active == 1, 2);
    }
}
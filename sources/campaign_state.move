module campaign_manager::campaign_state {
    use std::error;
    use std::string::String;
    use std::vector;
    use aptos_framework::timestamp;

    const ECAMPAIGN_NOT_FOUND: u64 = 1;
    const ECAMPAIGN_INACTIVE: u64 = 2;

    struct CampaignState has key {
        campaigns: vector<Campaign>,
    }

    struct Campaign has store {
        campaign_id: String,
        start_time: u64,
        end_time: u64,
        is_active: bool,
        total_contributions: u64,
    }

    fun init_module(account: &signer) {
        move_to(account, CampaignState {
            campaigns: vector::empty(),
        });
    }

    public fun verify_campaign_active(campaign_id: String): bool acquires CampaignState {
        let state = borrow_global<CampaignState>(@campaign_manager);
        let len = vector::length(&state.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow(&state.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                let current_time = timestamp::now_seconds();
                return campaign.is_active && 
                       current_time >= campaign.start_time && 
                       current_time <= campaign.end_time
            };
            i = i + 1;
        };
        false
    }

    public fun add_campaign(
        campaign_id: String,
        start_time: u64,
        end_time: u64,
    ) acquires CampaignState {
        let state = borrow_global_mut<CampaignState>(@campaign_manager);
        let campaign = Campaign {
            campaign_id,
            start_time,
            end_time,
            is_active: true,
            total_contributions: 0,
        };
        vector::push_back(&mut state.campaigns, campaign);
    }

    public fun increment_contributions(campaign_id: String): u64 acquires CampaignState {
        let state = borrow_global_mut<CampaignState>(@campaign_manager);
        let len = vector::length(&state.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow_mut(&mut state.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                campaign.total_contributions = campaign.total_contributions + 1;
                return campaign.total_contributions
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }

    public fun deactivate_campaign(campaign_id: String) acquires CampaignState {
        let state = borrow_global_mut<CampaignState>(@campaign_manager);
        let len = vector::length(&state.campaigns);
        let i = 0;
        while (i < len) {
            let campaign = vector::borrow_mut(&mut state.campaigns, i);
            if (campaign.campaign_id == campaign_id) {
                campaign.is_active = false;
                return
            };
            i = i + 1;
        };
        abort error::not_found(ECAMPAIGN_NOT_FOUND)
    }
} 
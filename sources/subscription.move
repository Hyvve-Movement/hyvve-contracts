module campaign_manager::subscription {
    use std::error;
    use std::signer;
    use std::vector;
    use std::string::{Self, String};
    use aptos_framework::account;
    use aptos_framework::event;
    use aptos_framework::timestamp;
    use aptos_framework::coin;

    /// Error codes
    const EINVALID_SUBSCRIPTION_PRICE: u64 = 1;
    const EINVALID_SUBSCRIPTION_DURATION: u64 = 2;
    const ESUBSCRIPTION_NOT_FOUND: u64 = 3;
    const ESUBSCRIPTION_ALREADY_EXISTS: u64 = 4;
    const ESUBSCRIPTION_EXPIRED: u64 = 5;
    const ENOT_SUBSCRIBER: u64 = 6;
    const ESUBSCRIPTION_ACTIVE: u64 = 7;
    const EINSUFFICIENT_BALANCE: u64 = 8;
    const ENOT_OWNER: u64 = 9;
    const ENO_PAYMENT_CAPABILITY: u64 = 10;

    /// Constants
    const SECONDS_PER_MONTH: u64 = 2592000; // 30 days in seconds
    const DEFAULT_SUBSCRIPTION_PRICE: u64 = 200_000_000; // 2 APT

    struct DelegatedPaymentCapability<phantom CoinType> has key {
        balance: coin::Coin<CoinType>
    }

    struct Subscription has store, copy {
        subscriber: address,
        start_time: u64,
        end_time: u64,
        subscription_type: String,
        price: u64,
        is_active: bool,
        auto_renew: bool,
        has_payment_capability: bool
    }

    struct SubscriptionStore has key {
        subscriptions: vector<Subscription>,
        subscription_events: event::EventHandle<SubscriptionEvent>,
    }

    struct SubscriptionEvent has drop, store {
        subscriber: address,
        subscription_type: String,
        event_type: String,  // "created", "renewed", "cancelled"
        timestamp: u64,
    }

    fun init_module(account: &signer) {
        let subscription_store = SubscriptionStore {
            subscriptions: vector::empty(),
            subscription_events: account::new_event_handle<SubscriptionEvent>(account),
        };
        move_to(account, subscription_store);
    }

    public entry fun setup_payment_delegation<CoinType>(
        account: &signer,
        amount: u64
    ) acquires DelegatedPaymentCapability {
        let sender = signer::address_of(account);
        let payment = coin::withdraw<CoinType>(account, amount);
        
        if (exists<DelegatedPaymentCapability<CoinType>>(sender)) {
            let cap = borrow_global_mut<DelegatedPaymentCapability<CoinType>>(sender);
            coin::merge(&mut cap.balance, payment);
        } else {
            move_to(account, DelegatedPaymentCapability<CoinType> {
                balance: payment
            });
        }
    }

    public entry fun create_subscription<CoinType>(
        account: &signer,
        subscription_type: String,
        auto_renew: bool,
    ) acquires SubscriptionStore {
        let sender = signer::address_of(account);
        
        // Use default price
        let price = DEFAULT_SUBSCRIPTION_PRICE;
        
        // Check if subscription already exists
        assert!(!subscription_exists(sender), error::already_exists(ESUBSCRIPTION_ALREADY_EXISTS));

        let current_time = timestamp::now_seconds();
        let subscription = Subscription {
            subscriber: sender,
            start_time: current_time,
            end_time: current_time + SECONDS_PER_MONTH,
            subscription_type,
            price,
            is_active: true,
            auto_renew,
            has_payment_capability: exists<DelegatedPaymentCapability<CoinType>>(sender)
        };

        // Process payment
        let payment = coin::withdraw<CoinType>(account, price);
        coin::deposit(@campaign_manager, payment);

        let subscription_store = borrow_global_mut<SubscriptionStore>(@campaign_manager);
        vector::push_back(&mut subscription_store.subscriptions, subscription);

        event::emit_event(
            &mut subscription_store.subscription_events,
            SubscriptionEvent {
                subscriber: sender,
                subscription_type,
                event_type: string::utf8(b"created"),
                timestamp: current_time,
            },
        );
    }

    public entry fun create_subscription_with_delegation<CoinType>(
        account: &signer,
        subscription_type: String,
        auto_renew: bool,
        delegation_amount: u64,
    ) acquires SubscriptionStore, DelegatedPaymentCapability {
        // First setup the payment delegation
        setup_payment_delegation<CoinType>(account, delegation_amount);
        
        // Then create the subscription with default price
        create_subscription<CoinType>(account, subscription_type, auto_renew);
    }

    public entry fun renew_subscription<CoinType>(
        account: &signer
    ) acquires SubscriptionStore {
        let sender = signer::address_of(account);
        let subscription_store = borrow_global_mut<SubscriptionStore>(@campaign_manager);
        
        let len = vector::length(&subscription_store.subscriptions);
        let i = 0;
        while (i < len) {
            let subscription = vector::borrow_mut(&mut subscription_store.subscriptions, i);
            if (subscription.subscriber == sender) {
                assert!(subscription.is_active, error::invalid_state(ESUBSCRIPTION_EXPIRED));
                
                // Process renewal payment
                let payment = coin::withdraw<CoinType>(account, subscription.price);
                coin::deposit(@campaign_manager, payment);

                // Update subscription period
                subscription.start_time = timestamp::now_seconds();
                subscription.end_time = subscription.start_time + SECONDS_PER_MONTH;

                event::emit_event(
                    &mut subscription_store.subscription_events,
                    SubscriptionEvent {
                        subscriber: sender,
                        subscription_type: subscription.subscription_type,
                        event_type: string::utf8(b"renewed"),
                        timestamp: timestamp::now_seconds(),
                    },
                );
                return
            };
            i = i + 1;
        };
        abort error::not_found(ESUBSCRIPTION_NOT_FOUND)
    }

    public entry fun cancel_subscription(
        account: &signer
    ) acquires SubscriptionStore {
        let sender = signer::address_of(account);
        let subscription_store = borrow_global_mut<SubscriptionStore>(@campaign_manager);
        
        let len = vector::length(&subscription_store.subscriptions);
        let i = 0;
        while (i < len) {
            let subscription = vector::borrow_mut(&mut subscription_store.subscriptions, i);
            if (subscription.subscriber == sender) {
                assert!(subscription.is_active, error::invalid_state(ESUBSCRIPTION_EXPIRED));
                
                subscription.is_active = false;
                subscription.auto_renew = false;

                event::emit_event(
                    &mut subscription_store.subscription_events,
                    SubscriptionEvent {
                        subscriber: sender,
                        subscription_type: subscription.subscription_type,
                        event_type: string::utf8(b"cancelled"),
                        timestamp: timestamp::now_seconds(),
                    },
                );
                return
            };
            i = i + 1;
        };
        abort error::not_found(ESUBSCRIPTION_NOT_FOUND)
    }

    #[view]
    public fun get_subscription_status(
        subscriber: address
    ): (bool, u64, String, bool) acquires SubscriptionStore {
        let subscription_store = borrow_global<SubscriptionStore>(@campaign_manager);
        let len = vector::length(&subscription_store.subscriptions);
        let i = 0;
        while (i < len) {
            let subscription = vector::borrow(&subscription_store.subscriptions, i);
            if (subscription.subscriber == subscriber) {
                return (
                    subscription.is_active,
                    subscription.end_time,
                    subscription.subscription_type,
                    subscription.auto_renew
                )
            };
            i = i + 1;
        };
        abort error::not_found(ESUBSCRIPTION_NOT_FOUND)
    }

    #[view]
    public fun is_subscription_active(subscriber: address): bool acquires SubscriptionStore {
        let subscription_store = borrow_global<SubscriptionStore>(@campaign_manager);
        let len = vector::length(&subscription_store.subscriptions);
        let i = 0;
        while (i < len) {
            let subscription = vector::borrow(&subscription_store.subscriptions, i);
            if (subscription.subscriber == subscriber) {
                return subscription.is_active && 
                       timestamp::now_seconds() <= subscription.end_time
            };
            i = i + 1;
        };
        false
    }

    fun subscription_exists(subscriber: address): bool acquires SubscriptionStore {
        let subscription_store = borrow_global<SubscriptionStore>(@campaign_manager);
        let len = vector::length(&subscription_store.subscriptions);
        let i = 0;
        while (i < len) {
            let subscription = vector::borrow(&subscription_store.subscriptions, i);
            if (subscription.subscriber == subscriber) {
                return true
            };
            i = i + 1;
        };
        false
    }

    public entry fun process_due_renewals<CoinType>(
        admin: &signer
    ) acquires SubscriptionStore, DelegatedPaymentCapability {
        // Verify admin is the campaign manager
        assert!(signer::address_of(admin) == @campaign_manager, error::permission_denied(ENOT_OWNER));
        
        let subscription_store = borrow_global_mut<SubscriptionStore>(@campaign_manager);
        let current_time = timestamp::now_seconds();
        let i = 0;
        let len = vector::length(&subscription_store.subscriptions);
        
        while (i < len) {
            let subscription = vector::borrow_mut(&mut subscription_store.subscriptions, i);
            
            // Check if subscription is due for renewal
            if (subscription.is_active && 
                subscription.auto_renew && 
                current_time > subscription.end_time) {
                
                let subscriber = subscription.subscriber;
                
                // Check if subscriber has payment capability
                if (exists<DelegatedPaymentCapability<CoinType>>(subscriber)) {
                    let payment_cap = borrow_global_mut<DelegatedPaymentCapability<CoinType>>(subscriber);
                    
                    if (coin::value(&payment_cap.balance) >= subscription.price) {
                        // Process the renewal payment from delegated store
                        let payment = coin::extract(&mut payment_cap.balance, subscription.price);
                        coin::deposit(@campaign_manager, payment);

                        // Update subscription period
                        subscription.start_time = current_time;
                        subscription.end_time = current_time + SECONDS_PER_MONTH;

                        event::emit_event(
                            &mut subscription_store.subscription_events,
                            SubscriptionEvent {
                                subscriber,
                                subscription_type: subscription.subscription_type,
                                event_type: string::utf8(b"auto_renewed"),
                                timestamp: current_time,
                            },
                        );
                    } else {
                        // If insufficient funds, deactivate subscription
                        subscription.is_active = false;
                        subscription.auto_renew = false;

                        event::emit_event(
                            &mut subscription_store.subscription_events,
                            SubscriptionEvent {
                                subscriber,
                                subscription_type: subscription.subscription_type,
                                event_type: string::utf8(b"renewal_failed"),
                                timestamp: current_time,
                            },
                        );
                    }
                } else {
                    // No payment capability, deactivate subscription
                    subscription.is_active = false;
                    subscription.auto_renew = false;

                    event::emit_event(
                        &mut subscription_store.subscription_events,
                        SubscriptionEvent {
                            subscriber,
                            subscription_type: subscription.subscription_type,
                            event_type: string::utf8(b"renewal_failed_no_capability"),
                            timestamp: current_time,
                        },
                    );
                }
            };
            i = i + 1;
        };
    }

    #[view]
    public fun get_due_renewals_count(): u64 acquires SubscriptionStore {
        let subscription_store = borrow_global<SubscriptionStore>(@campaign_manager);
        let current_time = timestamp::now_seconds();
        let due_count = 0;
        let i = 0;
        let len = vector::length(&subscription_store.subscriptions);
        
        while (i < len) {
            let subscription = vector::borrow(&subscription_store.subscriptions, i);
            if (subscription.is_active && 
                subscription.auto_renew && 
                current_time > subscription.end_time) {
                due_count = due_count + 1;
            };
            i = i + 1;
        };
        
        due_count
    }

    #[test(admin = @campaign_manager, subscriber = @0x456)]
    public fun test_process_due_renewals(admin: &signer, subscriber: &signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(subscriber));
        init_module(admin);

        // Create subscription
        create_subscription<TestCoin>(
            subscriber,
            string::utf8(b"premium"),
            true, // auto_renew
        );

        // Fast forward time past subscription end
        timestamp::fast_forward_seconds(SECONDS_PER_MONTH + 1);

        // Process renewals
        process_due_renewals<TestCoin>(admin);

        // Verify subscription was renewed
        let (is_active, end_time, _, _) = get_subscription_status(signer::address_of(subscriber));
        assert!(is_active == true, 0);
        assert!(end_time > timestamp::now_seconds(), 1);
    }

    #[test_only]
    struct TestCoin has key { }

    #[test(admin = @campaign_manager, subscriber = @0x456)]
    public fun test_create_subscription(admin: &signer, subscriber: &signer) {
        // Setup test environment
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(subscriber));
        
        // Initialize subscription store
        init_module(admin);

        // Create test subscription
        let subscription_type = string::utf8(b"premium");
        
        create_subscription<TestCoin>(
            subscriber,
            subscription_type,
            true, // auto_renew
        );

        let (is_active, _, returned_type, _) = get_subscription_status(signer::address_of(subscriber));
        assert!(is_active == true, 0);
        assert!(returned_type == subscription_type, 1);
    }

    #[test(admin = @campaign_manager, subscriber = @0x456)]
    public fun test_cancel_subscription(admin: &signer, subscriber: &signer) {
        // Setup
        timestamp::set_time_has_started_for_testing(admin);
        account::create_account_for_test(signer::address_of(admin));
        account::create_account_for_test(signer::address_of(subscriber));
        init_module(admin);

        // Create and then cancel subscription
        create_subscription<TestCoin>(
            subscriber,
            string::utf8(b"premium"),
            true,
        );

        cancel_subscription(subscriber);

        let (is_active, _, _, _) = get_subscription_status(signer::address_of(subscriber));
        assert!(!is_active, 0);
    }
} 
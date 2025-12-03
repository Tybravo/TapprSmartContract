#[test_only]
module TapprWallet::TapprWalletTests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock;
    use TapprWallet::TapprWallet::{
        Self,
        Wallet,
        AdminCap,
        FeeVault,
        VerilensAttestationRegistry,
        E_INVALID_AMOUNT,
        E_WALLET_FROZEN,
        E_ATTESTATION_ALREADY_USED
    };

    // Test addresses
    const ADMIN: address = @0xAD;
    const USER1: address = @0xA1;
    const USER2: address = @0xA2;

    // Helper function to create a test coin
    fun create_coin(amount: u64, scenario: &mut Scenario): Coin<SUI> {
        coin::mint_for_testing<SUI>(amount, ts::ctx(scenario))
    }

    // Helper to create test attestation data
    fun create_test_attestation_data(nonce: u64): (
        vector<u8>,  // transaction_hash
        vector<u8>,  // attestation_signature
        vector<u8>,  // tee_pubkey
        u64,         // timestamp
        u64,         // nonce
        vector<u8>   // metadata
    ) {
        let tx_hash = b"test_transaction_hash";
        let sig = b"test_signature";
        let pubkey = b"test_pubkey";
        let timestamp = 1000000;
        let metadata = b"test_metadata";
        
        (tx_hash, sig, pubkey, timestamp, nonce, metadata)
    }

    // Initialize test scenario
    fun setup_test(scenario: &mut Scenario) {
        ts::next_tx(scenario, ADMIN);
        {
            TapprWallet::test_init(ts::ctx(scenario));
        };
    }

    // ==================== MODULE INITIALIZATION TESTS ====================

    #[test]
    fun test_init_creates_admin_cap() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_for_sender<AdminCap>(&scenario), 0);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_init_creates_fee_vault() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let fee_vault = ts::take_shared<FeeVault>(&scenario);
            assert!(TapprWallet::fee_vault_balance(&fee_vault) == 0, 0);
            assert!(TapprWallet::total_fees_collected(&fee_vault) == 0, 0);
            ts::return_shared(fee_vault);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_init_creates_attestation_registry() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            assert!(ts::has_most_recent_shared<VerilensAttestationRegistry>(), 0);
        };
        
        ts::end(scenario);
    }

    // ==================== WALLET CREATION TESTS ====================

    #[test]
    fun test_create_wallet_basic() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, USER1);
        {
            let wallet = ts::take_from_sender<Wallet>(&scenario);
            assert!(TapprWallet::owner_of(&wallet) == USER1, 0);
            assert!(TapprWallet::balance_of(&wallet) == 0, 1);
            assert!(!TapprWallet::is_frozen(&wallet), 2);
            assert!(TapprWallet::daily_limit(&wallet) == 10000000000, 3);
            assert!(TapprWallet::transaction_limit(&wallet) == 5000000000, 4);
            assert!(TapprWallet::daily_spent(&wallet) == 0, 5);
            assert!(TapprWallet::total_received(&wallet) == 0, 6);
            assert!(TapprWallet::total_sent(&wallet) == 0, 7);
            assert!(TapprWallet::transaction_count(&wallet) == 0, 8);
            assert!(!TapprWallet::is_kyc_verified(&wallet), 9);
            ts::return_to_sender(&scenario, wallet);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_create_multiple_wallets_same_user() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        // Create first wallet
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        // Create second wallet
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, USER1);
        {
            let ids = ts::ids_for_sender<Wallet>(&scenario);
            assert!(ids.length() == 2, 0);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_create_wallets_different_users() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        // User1 creates wallet
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        // User2 creates wallet
        ts::next_tx(&mut scenario, USER2);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        // Verify User1's wallet
        ts::next_tx(&mut scenario, USER1);
        {
            let wallet = ts::take_from_sender<Wallet>(&scenario);
            assert!(TapprWallet::owner_of(&wallet) == USER1, 0);
            ts::return_to_sender(&scenario, wallet);
        };
        
        // Verify User2's wallet
        ts::next_tx(&mut scenario, USER2);
        {
            let wallet = ts::take_from_sender<Wallet>(&scenario);
            assert!(TapprWallet::owner_of(&wallet) == USER2, 0);
            ts::return_to_sender(&scenario, wallet);
        };
        
        ts::end(scenario);
    }

    // ==================== VIEW FUNCTION TESTS ====================

    #[test]
    fun test_view_functions_initial_state() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, USER1);
        {
            let wallet = ts::take_from_sender<Wallet>(&scenario);
            
            // Test all view functions
            assert!(TapprWallet::balance_of(&wallet) == 0, 0);
            assert!(TapprWallet::owner_of(&wallet) == USER1, 1);
            assert!(!TapprWallet::is_frozen(&wallet), 2);
            assert!(TapprWallet::daily_limit(&wallet) == 10000000000, 3);
            assert!(TapprWallet::transaction_limit(&wallet) == 5000000000, 4);
            assert!(TapprWallet::daily_spent(&wallet) == 0, 5);
            assert!(TapprWallet::total_received(&wallet) == 0, 6);
            assert!(TapprWallet::total_sent(&wallet) == 0, 7);
            assert!(TapprWallet::transaction_count(&wallet) == 0, 8);
            assert!(!TapprWallet::is_kyc_verified(&wallet), 9);
            
            ts::return_to_sender(&scenario, wallet);
        };
        
        ts::end(scenario);
    }

    // ==================== DEPOSIT TESTS ====================

    #[test]
    fun test_deposit_valid_amount() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(1000000000, &mut scenario); // 1 SUI
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            assert!(TapprWallet::balance_of(&wallet) == 1000000000, 0);
            assert!(TapprWallet::total_received(&wallet) == 1000000000, 1);
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_deposit_minimum_amount() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(1, &mut scenario); // 1 MIST
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            assert!(TapprWallet::balance_of(&wallet) == 1, 0);
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_deposit_maximum_amount() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let max_amount = 18446744073709551615u64; // Max u64
            let deposit_coin = create_coin(max_amount, &mut scenario);
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            assert!(TapprWallet::balance_of(&wallet) == max_amount, 0);
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_deposit_multiple_times() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        // First deposit
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(1000000000, &mut scenario);
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        // Second deposit
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(500000000, &mut scenario);
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            assert!(TapprWallet::balance_of(&wallet) == 1500000000, 0);
            assert!(TapprWallet::total_received(&wallet) == 1500000000, 1);
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_INVALID_AMOUNT)]
    fun test_deposit_zero_amount() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(0, &mut scenario);
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_WALLET_FROZEN)]
    fun test_deposit_to_frozen_wallet() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        // User creates wallet
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        // Admin freezes wallet
        ts::next_tx(&mut scenario, ADMIN);
        {
            let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
            let mut wallet = ts::take_from_address<Wallet>(&scenario, USER1);
            
            TapprWallet::freeze_wallet(&admin_cap, &mut wallet, ts::ctx(&mut scenario));
            
            ts::return_to_address(USER1, wallet);
            ts::return_to_sender(&scenario, admin_cap);
        };
        
        // Try to deposit (should fail)
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(1000000000, &mut scenario);
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = E_ATTESTATION_ALREADY_USED)]
    fun test_deposit_replay_attack() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        // First deposit
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(1000000000, &mut scenario);
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        // Try to reuse same attestation (should fail)
        ts::next_tx(&mut scenario, USER1);
        {
            let mut wallet = ts::take_from_sender<Wallet>(&scenario);
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            let clock = clock::create_for_testing(ts::ctx(&mut scenario));
            
            let nonce = 1u64; // Reuse same nonce
            let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
            let deposit_coin = create_coin(1000000000, &mut scenario);
            
            TapprWallet::deposit_with_attestation(
                &mut wallet,
                &mut registry,
                deposit_coin,
                tx_hash,
                sig,
                pubkey,
                timestamp,
                nonce,
                metadata,
                &clock,
                ts::ctx(&mut scenario)
            );
            
            clock.destroy_for_testing();
            ts::return_to_sender(&scenario, wallet);
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_deposit_accumulates_total_received() {
        let mut scenario = ts::begin(USER1);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, USER1);
        {
            TapprWallet::create_wallet(ts::ctx(&mut scenario));
        };
        
        let deposits = vector[100000000, 200000000, 300000000, 400000000];
        let mut expected_total = 0u64;
        
        let mut i = 0;
        while (i < deposits.length()) {
            ts::next_tx(&mut scenario, USER1);
            {
                let mut wallet = ts::take_from_sender<Wallet>(&scenario);
                let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
                let clock = clock::create_for_testing(ts::ctx(&mut scenario));
                
                let amount = *deposits.borrow(i);
                expected_total = expected_total + amount;
                
                let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
                let (tx_hash, sig, pubkey, timestamp, _, metadata) = create_test_attestation_data(nonce);
                let deposit_coin = create_coin(amount, &mut scenario);
                
                TapprWallet::deposit_with_attestation(
                    &mut wallet,
                    &mut registry,
                    deposit_coin,
                    tx_hash,
                    sig,
                    pubkey,
                    timestamp,
                    nonce,
                    metadata,
                    &clock,
                    ts::ctx(&mut scenario)
                );
                
                assert!(TapprWallet::total_received(&wallet) == expected_total, 0);
                
                clock.destroy_for_testing();
                ts::return_to_sender(&scenario, wallet);
                ts::return_shared(registry);
            };
            i = i + 1;
        };
        
        ts::end(scenario);
    }

    // ==================== NONCE GENERATION TESTS ====================

    #[test]
    fun test_generate_fresh_nonce_increments() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            
            let nonce1 = TapprWallet::generate_fresh_nonce(&mut registry);
            let nonce2 = TapprWallet::generate_fresh_nonce(&mut registry);
            let nonce3 = TapprWallet::generate_fresh_nonce(&mut registry);
            
            assert!(nonce1 == 1, 0);
            assert!(nonce2 == 2, 1);
            assert!(nonce3 == 3, 2);
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    #[test]
    fun test_generate_many_nonces() {
        let mut scenario = ts::begin(ADMIN);
        setup_test(&mut scenario);
        
        ts::next_tx(&mut scenario, ADMIN);
        {
            let mut registry = ts::take_shared<VerilensAttestationRegistry>(&scenario);
            
            let mut i = 0;
            while (i < 100) {
                let nonce = TapprWallet::generate_fresh_nonce(&mut registry);
                assert!(nonce == i + 1, 0);
                i = i + 1;
            };
            
            ts::return_shared(registry);
        };
        
        ts::end(scenario);
    }

    // ==================== WITHDRAW TESTS ====================
    // (Tests up to this point as requested)
}

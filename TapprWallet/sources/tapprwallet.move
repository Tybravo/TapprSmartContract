#[allow(unused_field, unused_use, duplicate_alias, lint(coin_field), unused_const)]
module TapprWallet::TapprWallet {
    
    use std::string::{String, utf8};
    use std::vector;
    use sui::event;
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use sui::vec_map::{Self, VecMap};

    // Error codes
    const E_INSUFFICIENT_BALANCE: u64 = 0;
    const E_INVALID_AMOUNT: u64 = 1;
    const E_WALLET_FROZEN: u64 = 2;
    const E_DAILY_LIMIT_EXCEEDED: u64 = 3;
    const E_UNAUTHORIZED: u64 = 4;
    const E_TRANSACTION_LIMIT_EXCEEDED: u64 = 5;
    const E_MINIMUM_AMOUNT_NOT_MET: u64 = 6;
    const E_ATTESTATION_ALREADY_USED: u64 = 7;

    // Constants
    const DEFAULT_DAILY_LIMIT: u64 = 10000000000; // 10 SUI in MIST
    const DEFAULT_TRANSACTION_LIMIT: u64 = 5000000000; // 5 SUI in MIST
    const MINIMUM_TRANSACTION: u64 = 1000000; // 0.001 SUI in MIST
    const PLATFORM_FEE_BPS: u64 = 50; // 0.5% (50 basis points)
    const BPS_DENOMINATOR: u64 = 10000;

    // Wallet structure
    public struct Wallet has key, store {
        id: UID,
        owner: address,
        balance: Coin<SUI>,
        is_frozen: bool,
        daily_limit: u64,
        transaction_limit: u64,
        daily_spent: u64,
        last_reset_day: u64,
        total_received: u64,
        total_sent: u64,
        transaction_count: u64,
        kyc_verified: bool,
    }

    // Platform admin capability
    public struct AdminCap has key, store {
        id: UID,
    }

    // Fee collection wallet
    public struct FeeVault has key {
        id: UID,
        balance: Coin<SUI>,
        total_fees_collected: u64,
    }

    // Verilens attestation tracker - SIMPLIFIED
    // Only tracks used nonces to prevent replay attacks
    public struct VerilensAttestationRegistry has key {
        id: UID,
        used_nonces: VecMap<u64, bool>, // Prevent replay attacks using u64 (8-byte) nonces
        nonce_counter: u64, // Monotonic counter for generating fresh u64 nonces
    }

    // Verilens attestation - contains ALL verification proof from TEE
    public struct VerilensAttestation has copy, drop, store {
        transaction_hash: vector<u8>,      // Hash of transaction data
        attestation_signature: vector<u8>, // TEE signature (already verified by Verilens)
        tee_pubkey: vector<u8>,            // TEE public key (for reference/audit)
        timestamp: u64,                    // When TEE verified this
        nonce: u64,                        // Unique 8-byte identifier (u64)
        metadata: vector<u8>,              // Additional TEE metadata
    }

    // Lightweight on-chain proof - links to Web2 DB
    public struct VerifiedTransaction has key, store {
        id: UID,
        transaction_hash: vector<u8>,      // Links to Web2 DB
        attestation: VerilensAttestation,  // Complete TEE proof
        wallet_address: address,           // Source wallet
        amount: u64,                       // Transaction amount
        timestamp: u64,                    // Blockchain timestamp
    }

    // Events
    public struct WalletCreatedEvent has copy, drop {
        wallet_id: address,
        owner: address,
        timestamp: u64,
    }

    public struct DepositEvent has copy, drop {
        wallet_id: address,
        amount: u64,
        new_balance: u64,
        verilens_verified: bool,
        attestation_hash: vector<u8>,
        timestamp: u64,
    }

    public struct WithdrawalEvent has copy, drop {
        wallet_id: address,
        recipient: address,
        amount: u64,
        fee: u64,
        net_amount: u64,
        verilens_verified: bool,
        attestation_hash: vector<u8>,
        verified_tx_id: address,
        timestamp: u64,
    }

    public struct TransferEvent has copy, drop {
        source_wallet_id: address,
        dest_wallet_id: address,
        amount: u64,
        fee: u64,
        verilens_verified: bool,
        attestation_hash: vector<u8>,
        verified_tx_id: address,
        timestamp: u64,
    }

    public struct WalletFrozenEvent has copy, drop {
        wallet_id: address,
        frozen_by: address,
        timestamp: u64,
    }

    public struct WalletUnfrozenEvent has copy, drop {
        wallet_id: address,
        unfrozen_by: address,
        timestamp: u64,
    }

    public struct LimitUpdatedEvent has copy, drop {
        wallet_id: address,
        daily_limit: u64,
        transaction_limit: u64,
        timestamp: u64,
    }

    public struct KYCVerifiedEvent has copy, drop {
        wallet_id: address,
        verified_by: address,
        timestamp: u64,
    }

    public struct FeeCollectedEvent has copy, drop {
        amount: u64,
        total_fees: u64,
        timestamp: u64,
    }

    // This event signals Web2 backend to update database
    public struct TransactionVerifiedOnChainEvent has copy, drop {
        transaction_hash: vector<u8>,      // Links to Web2 DB
        attestation_hash: vector<u8>,      // Verilens TEE proof
        verified_tx_id: address,            // On-chain receipt ID
        wallet_address: address,            // User's wallet
        amount: u64,                        // Amount
        timestamp: u64,                     // Blockchain timestamp
    }

    // Initialize module
    fun init(ctx: &mut TxContext) {
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        
        let fee_vault = FeeVault {
            id: object::new(ctx),
            balance: coin::zero<SUI>(ctx),
            total_fees_collected: 0,
        };

        let attestation_registry = VerilensAttestationRegistry {
            id: object::new(ctx),
            used_nonces: vec_map::empty(),
            nonce_counter: 0,
        };

        transfer::transfer(admin_cap, tx_context::sender(ctx));
        transfer::share_object(fee_vault);
        transfer::share_object(attestation_registry);
    }

    // View functions
    public fun balance_of(wallet: &Wallet): u64 {
        coin::value(&wallet.balance)
    }

    public fun owner_of(wallet: &Wallet): address {
        wallet.owner
    }

    public fun is_frozen(wallet: &Wallet): bool {
        wallet.is_frozen
    }

    public fun daily_limit(wallet: &Wallet): u64 {
        wallet.daily_limit
    }

    public fun transaction_limit(wallet: &Wallet): u64 {
        wallet.transaction_limit
    }

    public fun daily_spent(wallet: &Wallet): u64 {
        wallet.daily_spent
    }

    public fun total_received(wallet: &Wallet): u64 {
        wallet.total_received
    }

    public fun total_sent(wallet: &Wallet): u64 {
        wallet.total_sent
    }

    public fun transaction_count(wallet: &Wallet): u64 {
        wallet.transaction_count
    }

    public fun is_kyc_verified(wallet: &Wallet): bool {
        wallet.kyc_verified
    }

    public fun fee_vault_balance(vault: &FeeVault): u64 {
        coin::value(&vault.balance)
    }

    public fun total_fees_collected(vault: &FeeVault): u64 {
        vault.total_fees_collected
    }

    // Calculate platform fee
    fun calculate_fee(amount: u64): u64 {
        (amount * PLATFORM_FEE_BPS) / BPS_DENOMINATOR
    }

    // Reset daily spending if new day
    fun reset_daily_limit_if_needed(wallet: &mut Wallet, clock: &Clock) {
        let current_day = clock::timestamp_ms(clock) / 86400000;
        if (current_day > wallet.last_reset_day) {
            wallet.daily_spent = 0;
            wallet.last_reset_day = current_day;
        };
    }

    // Generate a fresh 8-byte (u64) nonce from the registry counter
    // Use this in tests to get a new nonce each time without reusing values.
    public fun generate_fresh_nonce(registry: &mut VerilensAttestationRegistry): u64 {
        // increment counter
        registry.nonce_counter = registry.nonce_counter + 1;
        registry.nonce_counter
    }

    // Verify Verilens attestation - SIMPLIFIED
    // Verilens TEE already did all cryptographic verification
    // We just check for replay attacks
    fun verify_attestation(
        registry: &VerilensAttestationRegistry,
        attestation: &VerilensAttestation
    ): bool {
        // Only check: Has this nonce been used before?
        // This prevents someone from reusing a valid attestation
        if (vec_map::contains(&registry.used_nonces, &attestation.nonce)) {
            return false  // Replay attack detected!
        };

        // Trust Verilens TEE - it already verified:
        // ✓ Transaction authenticity
        // ✓ Cryptographic signatures
        // ✓ Business logic rules
        // ✓ User authorization
        // ✓ Fraud detection
        
        true
    }

    // Mark attestation nonce as used
    fun mark_attestation_used(
        registry: &mut VerilensAttestationRegistry,
        nonce: u64
    ) {
        vec_map::insert(&mut registry.used_nonces, nonce, true);
    }

    // Create lightweight verified transaction record
    fun create_verified_transaction(
        transaction_hash: vector<u8>,
        attestation: VerilensAttestation,
        wallet_address: address,
        amount: u64,
        timestamp: u64,
        ctx: &mut TxContext
    ): VerifiedTransaction {
        VerifiedTransaction {
            id: object::new(ctx),
            transaction_hash,
            attestation,
            wallet_address,
            amount,
            timestamp,
        }
    }

    // Create a new wallet
    public entry fun create_wallet(ctx: &mut TxContext) {
        let wallet = Wallet {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            balance: coin::zero<SUI>(ctx),
            is_frozen: false,
            daily_limit: DEFAULT_DAILY_LIMIT,
            transaction_limit: DEFAULT_TRANSACTION_LIMIT,
            daily_spent: 0,
            last_reset_day: 0,
            total_received: 0,
            total_sent: 0,
            transaction_count: 0,
            kyc_verified: false,
        };

        let wallet_id = object::uid_to_address(&wallet.id);
        
        event::emit(WalletCreatedEvent {
            wallet_id,
            owner: tx_context::sender(ctx),
            timestamp: tx_context::epoch(ctx),
        });

        transfer::public_transfer(wallet, tx_context::sender(ctx));
    }

    // Deposit with Verilens attestation
    public entry fun deposit_with_attestation(
        wallet: &mut Wallet,
        registry: &mut VerilensAttestationRegistry,
        coin: Coin<SUI>,
        transaction_hash: vector<u8>,
        attestation_signature: vector<u8>,
        tee_pubkey: vector<u8>,
        attestation_timestamp: u64,
        nonce: u64,
        metadata: vector<u8>,
        clock: &Clock,
        _ctx: &mut TxContext
    ) {
        let amount = coin::value(&coin);
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(!wallet.is_frozen, E_WALLET_FROZEN);

        let wallet_id = object::uid_to_address(&wallet.id);

        // Create attestation from Verilens TEE data
        let attestation = VerilensAttestation {
            transaction_hash,
            attestation_signature,
            tee_pubkey,
            timestamp: attestation_timestamp,
            nonce,
            metadata,
        };

        // Verify attestation (only checks replay)
        let is_verified = verify_attestation(registry, &attestation);
        assert!(is_verified, E_ATTESTATION_ALREADY_USED);

        // Mark nonce as used
        mark_attestation_used(registry, nonce);

        // Process deposit
        coin::join(&mut wallet.balance, coin);
        wallet.total_received = wallet.total_received + amount;

        event::emit(DepositEvent {
            wallet_id,
            amount,
            new_balance: coin::value(&wallet.balance),
            verilens_verified: true,
            attestation_hash: attestation.transaction_hash,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // Withdraw with Verilens attestation
    public entry fun withdraw_with_attestation(
        wallet: &mut Wallet,
        fee_vault: &mut FeeVault,
        registry: &mut VerilensAttestationRegistry,
        recipient: address,
        amount: u64,
        transaction_hash: vector<u8>,
        attestation_signature: vector<u8>,
        tee_pubkey: vector<u8>,
        attestation_timestamp: u64,
        nonce: u64,
        metadata: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount >= MINIMUM_TRANSACTION, E_MINIMUM_AMOUNT_NOT_MET);
        assert!(!wallet.is_frozen, E_WALLET_FROZEN);
        assert!(tx_context::sender(ctx) == wallet.owner, E_UNAUTHORIZED);

        reset_daily_limit_if_needed(wallet, clock);

        let fee = calculate_fee(amount);
        let total_required = amount + fee;

        assert!(coin::value(&wallet.balance) >= total_required, E_INSUFFICIENT_BALANCE);
        assert!(amount <= wallet.transaction_limit, E_TRANSACTION_LIMIT_EXCEEDED);
        assert!(wallet.daily_spent + amount <= wallet.daily_limit, E_DAILY_LIMIT_EXCEEDED);

        let wallet_id = object::uid_to_address(&wallet.id);

        // Create attestation from Verilens TEE
        let attestation = VerilensAttestation {
            transaction_hash,
            attestation_signature,
            tee_pubkey,
            timestamp: attestation_timestamp,
            nonce,
            metadata,
        };

        // Verify (only replay check - trust Verilens TEE for everything else)
        let is_verified = verify_attestation(registry, &attestation);
        assert!(is_verified, E_ATTESTATION_ALREADY_USED);

        // Mark nonce as used
        mark_attestation_used(registry, nonce);

        // Create on-chain proof
        let verified_tx = create_verified_transaction(
            transaction_hash,
            attestation,
            wallet_id,
            amount,
            clock::timestamp_ms(clock),
            ctx
        );

        let verified_tx_id = object::uid_to_address(&verified_tx.id);

        // Process withdrawal
        let withdrawal_coin = coin::split(&mut wallet.balance, amount, ctx);
        let fee_coin = coin::split(&mut wallet.balance, fee, ctx);
        coin::join(&mut fee_vault.balance, fee_coin);
        fee_vault.total_fees_collected = fee_vault.total_fees_collected + fee;

        transfer::public_transfer(withdrawal_coin, recipient);
        transfer::public_transfer(verified_tx, wallet.owner);

        // Update stats
        wallet.daily_spent = wallet.daily_spent + amount;
        wallet.total_sent = wallet.total_sent + amount;
        wallet.transaction_count = wallet.transaction_count + 1;

        event::emit(WithdrawalEvent {
            wallet_id,
            recipient,
            amount,
            fee,
            net_amount: amount,
            verilens_verified: true,
            attestation_hash: transaction_hash,
            verified_tx_id,
            timestamp: clock::timestamp_ms(clock),
        });

        // Backend listens for this to update Web2 DB
        event::emit(TransactionVerifiedOnChainEvent {
            transaction_hash,
            attestation_hash: attestation_signature,
            verified_tx_id,
            wallet_address: wallet_id,
            amount,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // Transfer between wallets with Verilens attestation
    public entry fun transfer_with_attestation(
        source_wallet: &mut Wallet,
        dest_wallet: &mut Wallet,
        fee_vault: &mut FeeVault,
        registry: &mut VerilensAttestationRegistry,
        amount: u64,
        transaction_hash: vector<u8>,
        attestation_signature: vector<u8>,
        tee_pubkey: vector<u8>,
        attestation_timestamp: u64,
        nonce: u64,
        metadata: vector<u8>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(amount >= MINIMUM_TRANSACTION, E_MINIMUM_AMOUNT_NOT_MET);
        assert!(!source_wallet.is_frozen, E_WALLET_FROZEN);
        assert!(!dest_wallet.is_frozen, E_WALLET_FROZEN);
        assert!(tx_context::sender(ctx) == source_wallet.owner, E_UNAUTHORIZED);

        reset_daily_limit_if_needed(source_wallet, clock);

        let fee = calculate_fee(amount) / 2;
        let total_required = amount + fee;

        assert!(coin::value(&source_wallet.balance) >= total_required, E_INSUFFICIENT_BALANCE);
        assert!(amount <= source_wallet.transaction_limit, E_TRANSACTION_LIMIT_EXCEEDED);
        assert!(source_wallet.daily_spent + amount <= source_wallet.daily_limit, E_DAILY_LIMIT_EXCEEDED);

        let source_id = object::uid_to_address(&source_wallet.id);
        let dest_id = object::uid_to_address(&dest_wallet.id);

        // Create attestation from Verilens TEE
        let attestation = VerilensAttestation {
            transaction_hash,
            attestation_signature,
            tee_pubkey,
            timestamp: attestation_timestamp,
            nonce,
            metadata,
        };

        // Verify (only replay check)
        let is_verified = verify_attestation(registry, &attestation);
        assert!(is_verified, E_ATTESTATION_ALREADY_USED);

        // Mark nonce as used
        mark_attestation_used(registry, nonce);

        // Create on-chain proof
        let verified_tx = create_verified_transaction(
            transaction_hash,
            attestation,
            source_id,
            amount,
            clock::timestamp_ms(clock),
            ctx
        );

        let verified_tx_id = object::uid_to_address(&verified_tx.id);

        // Process transfer
        let transferred_coin = coin::split(&mut source_wallet.balance, amount, ctx);
        coin::join(&mut dest_wallet.balance, transferred_coin);

        let fee_coin = coin::split(&mut source_wallet.balance, fee, ctx);
        coin::join(&mut fee_vault.balance, fee_coin);
        fee_vault.total_fees_collected = fee_vault.total_fees_collected + fee;

        transfer::public_transfer(verified_tx, source_wallet.owner);

        // Update stats
        source_wallet.daily_spent = source_wallet.daily_spent + amount;
        source_wallet.total_sent = source_wallet.total_sent + amount;
        source_wallet.transaction_count = source_wallet.transaction_count + 1;
        dest_wallet.total_received = dest_wallet.total_received + amount;

        event::emit(TransferEvent {
            source_wallet_id: source_id,
            dest_wallet_id: dest_id,
            amount,
            fee,
            verilens_verified: true,
            attestation_hash: transaction_hash,
            verified_tx_id,
            timestamp: clock::timestamp_ms(clock),
        });

        // Backend listens for this
        event::emit(TransactionVerifiedOnChainEvent {
            transaction_hash,
            attestation_hash: attestation_signature,
            verified_tx_id,
            wallet_address: source_id,
            amount,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    // Admin: Freeze wallet
    public entry fun freeze_wallet(
        _admin_cap: &AdminCap,
        wallet: &mut Wallet,
        ctx: &mut TxContext
    ) {
        wallet.is_frozen = true;

        event::emit(WalletFrozenEvent {
            wallet_id: object::uid_to_address(&wallet.id),
            frozen_by: tx_context::sender(ctx),
            timestamp: tx_context::epoch(ctx),
        });
    }

    // Admin: Unfreeze wallet
    public entry fun unfreeze_wallet(
        _admin_cap: &AdminCap,
        wallet: &mut Wallet,
        ctx: &mut TxContext
    ) {
        wallet.is_frozen = false;

        event::emit(WalletUnfrozenEvent {
            wallet_id: object::uid_to_address(&wallet.id),
            unfrozen_by: tx_context::sender(ctx),
            timestamp: tx_context::epoch(ctx),
        });
    }

    // Admin: Verify KYC
    public entry fun verify_kyc(
        _admin_cap: &AdminCap,
        wallet: &mut Wallet,
        ctx: &mut TxContext
    ) {
        wallet.kyc_verified = true;

        event::emit(KYCVerifiedEvent {
            wallet_id: object::uid_to_address(&wallet.id),
            verified_by: tx_context::sender(ctx),
            timestamp: tx_context::epoch(ctx),
        });
    }

    // User: Update spending limits
    public entry fun update_limits(
        wallet: &mut Wallet,
        new_daily_limit: u64,
        new_transaction_limit: u64,
        ctx: &mut TxContext
    ) {
        assert!(tx_context::sender(ctx) == wallet.owner, E_UNAUTHORIZED);
        assert!(wallet.kyc_verified, E_UNAUTHORIZED);

        wallet.daily_limit = new_daily_limit;
        wallet.transaction_limit = new_transaction_limit;

        event::emit(LimitUpdatedEvent {
            wallet_id: object::uid_to_address(&wallet.id),
            daily_limit: new_daily_limit,
            transaction_limit: new_transaction_limit,
            timestamp: tx_context::epoch(ctx),
        });
    }

    // Admin: Withdraw fees
    public entry fun withdraw_fees(
        _admin_cap: &AdminCap,
        fee_vault: &mut FeeVault,
        recipient: address,
        amount: u64,
        _ctx: &mut TxContext
    ) {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(coin::value(&fee_vault.balance) >= amount, E_INSUFFICIENT_BALANCE);

        let withdrawal = coin::split(&mut fee_vault.balance, amount, _ctx);
        transfer::public_transfer(withdrawal, recipient);
    }

    
    // This is a test-only initialization function

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(ctx);
    }

}


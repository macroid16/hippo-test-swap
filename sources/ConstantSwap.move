module HippoSwap::ConstantSwap {
    use Std::Signer;
    use Std::Option;
    use Std::ASCII;

    use AptosFramework::Coin;
    use AptosFramework::Timestamp;

    use HippoSwap::SafeMath;
    use HippoSwap::Math;

    const MODULE_ADMIN: address = @HippoSwapAdmin;
    const MINIMUM_LIQUIDITY: u128 = 1000;
    const LIQUIDITY_LOCK: address = @0x1;
    const BALANCE_MAX: u128 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // 2**112

    // List of errors
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_ALREADY_INITIALIZED: u64 = 1;
    const ERROR_NOT_CREATOR: u64 = 2;
    const ERROR_ALREADY_LOCKED: u64 = 3;
    const ERROR_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 4;
    const ERROR_OVERFLOW: u64 = 5;

    /// The LP Token type
    struct LPToken<phantom T0, phantom T1> has key {}

    /// TODO: This is just a temp solution as Coin does not have method to
    /// TODO: check if the account has already registered.
    struct AddressMeta<phantom T0, phantom T1> has key { }

    /// Stores the metadata required for the token pairs
    struct TokenPairMetadata<phantom T0, phantom T1> has key {
        /// Lock for mint and burn
        locked: bool,
        /// The admin of the token pair
        creator: address,
        /// The address to transfer mint fees to
        fee_to: address,
        /// Whether we are charging a fee for mint/burn
        fee_on: bool,
        /// It's reserve0 * reserve1, as of immediately after the most recent liquidity event
        k_last: u128,
        /// The LP token
        lp: Coin::Coin<LPToken<T0, T1>>,
        mint_cap: Coin::MintCapability<LPToken<T0, T1>>,
        burn_cap: Coin::BurnCapability<LPToken<T0, T1>>,
    }

    /// Stores the reservation info required for the token pairs
    struct TokenPairReserve<phantom T0, phantom T1> has key {
        // TODO: seems like reserve can be u64, kiv.
        reserve0: u64,
        reserve1: u64,
        block_timestamp_last: u64
    }

    public(script) fun create_token_pair<T0, T1>(sender: signer, fee_to: address, fee_on: bool) {
        let sender_addr = Signer::address_of(&sender);

        // TODO: consider removing this restriction in the future
        assert!(sender_addr == MODULE_ADMIN, ERROR_ONLY_ADMIN);

        assert!(!exists<TokenPairReserve<T0, T1>>(sender_addr), ERROR_ALREADY_INITIALIZED);

        // now we init the LP token
        // TODO: someone give it a better name and symbol
        let (mint_cap, burn_cap) = Coin::initialize<LPToken<T0, T1>>(
            &sender,
            ASCII::string(b"LP-TOKEN"),
            ASCII::string(b"LP"),
            18,
            true
        );

        move_to<TokenPairReserve<T0, T1>>(
            &sender,
            TokenPairReserve {
                reserve0: 0,
                reserve1: 0,
                block_timestamp_last: 0
            }
        );

        move_to<TokenPairMetadata<T0, T1>>(
            &sender,
            TokenPairMetadata {
                locked: false,
                creator: sender_addr,
                fee_to,
                fee_on,
                k_last: 0,
                lp: Coin::zero<LPToken<T0, T1>>(),
                mint_cap,
                burn_cap
            }
        );
    }

    /// The init process for a sender. One must call this function first
    /// before interacting with the mint/burn.
    /// TODO: remove this method if Coin::is_account_register or sth similar
    /// TODO: is provided
    public fun register<T0, T1>(sender: signer) {
        if (!is_registered<T0, T1>(Signer::address_of(&sender))) {
            let meta = AddressMeta<T0, T1> {};
            Coin::register<LPToken<T0, T1>>(&sender);
            move_to(&sender, meta);
        };
    }

    /// TODO: remove this method if Coin::is_account_register or sth similar
    /// TODO: is provided
    public fun is_registered<T0, T1>(addr: address): bool {
        exists<AddressMeta<T0, T1>>(addr)
    }

    public fun get_reserves<T0, T1>(): (u64, u64, u64) acquires TokenPairReserve {
        let reserve = borrow_global<TokenPairReserve<T0, T1>>(MODULE_ADMIN);
        (
            reserve.reserve0,
            reserve.reserve1,
            reserve.block_timestamp_last
        )
    }

    /// Mint LP Token.
    /// This low-level function should be called from a contract which performs important safety checks
    public fun mint<T0, T1>(sender: signer, creator: address): u128 acquires TokenPairReserve, TokenPairMetadata {
        let metadata = borrow_global_mut<TokenPairMetadata<T0, T1>>(creator);
        // should have no need to check the creator again
        assert!(!metadata.locked, ERROR_ALREADY_LOCKED);

        let reserves = borrow_global_mut<TokenPairReserve<T0, T1>>(MODULE_ADMIN);
        let balance0 = Coin::balance<T0>(@HippoSwap);
        let balance1 = Coin::balance<T1>(@HippoSwap);
        let amount0 = SafeMath::sub((balance0 as u128), (reserves.reserve0 as u128));
        let amount1 = SafeMath::sub((balance1 as u128), (reserves.reserve1 as u128));

        mint_fee(reserves.reserve0, reserves.reserve1, metadata);

        let total_supply = (total_lp_supply<T0, T1>() as u128);
        let liquidity = if (total_supply == 0u128) {
            let l = SafeMath::sub(
                Math::sqrt(
                    SafeMath::mul(amount0, amount1)
                ),
                MINIMUM_LIQUIDITY
            );
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            deposit_lp<T0, T1>(LIQUIDITY_LOCK, (MINIMUM_LIQUIDITY as u64), &metadata.mint_cap);
            l
        } else {
            Math::min(
                SafeMath::div(
                    SafeMath::mul(amount0, total_supply),
                    (reserves.reserve0 as u128)
                ),
                SafeMath::div(
                    SafeMath::mul(amount1, total_supply),
                    (reserves.reserve1 as u128)
                )
            )
        };

        assert!(liquidity > 0u128, ERROR_INSUFFICIENT_LIQUIDITY_MINTED);
        deposit_lp<T0, T1>(Signer::address_of(&sender), (liquidity as u64), &metadata.mint_cap);

        update<T0, T1>(balance0, balance1, reserves);

        if (metadata.fee_on)
            metadata.k_last = SafeMath::mul((reserves.reserve0 as u128), (reserves.reserve1 as u128));

        liquidity
    }

    fun update<T0, T1>(balance0: u64, balance1: u64, reserve: &mut TokenPairReserve<T0, T1>) {
        assert!(
            (balance0 as u128) <= BALANCE_MAX && (balance1 as u128) <= BALANCE_MAX,
            ERROR_OVERFLOW
        );

        let block_timestamp = Timestamp::now_seconds() % 0xFFFFFFFF;
        // TODO: not sure what these does for now in Uniswap V2
//        let time_elapsed = block_timestamp - timestamp_last; // overflow is desired
//        if (time_elapsed > 0 && reserve0 != 0 && reserve1 != 0) {
//             price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
//             price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
//         }

        reserve.reserve0 = balance0;
        reserve.reserve1 = balance1;
        reserve.block_timestamp_last = block_timestamp;
    }

    fun deposit_lp<T0, T1>(
        to: address,
        amount: u64,
        mint_cap: &Coin::MintCapability<LPToken<T0, T1>>
    ) {
        let coins = Coin::mint<LPToken<T0, T1>>(amount, mint_cap);
        Coin::deposit(to, coins);
    }

    fun mint_fee<T0, T1>(reserve0: u64, reserve1: u64, metadata: &mut TokenPairMetadata<T0, T1>) {
        if (metadata.fee_on) {
            if (metadata.k_last != 0) {
                let root_k = Math::sqrt(
                    SafeMath::mul(
                        (reserve0 as u128),
                        (reserve1 as u128)
                    )
                );
                let root_k_last = Math::sqrt(metadata.k_last);
                if (root_k > root_k_last) {
                    let total_supply = (total_lp_supply<T0, T1>() as u128);

                    let numerator = SafeMath::mul(
                        total_supply,
                        SafeMath::sub(root_k, root_k_last)
                    );

                    let denominator = SafeMath::add(
                        root_k_last,
                        SafeMath::mul(root_k, 5u128)
                    );

                    let liquidity = (SafeMath::div(
                        numerator,
                        denominator
                    ) as u64);
                    deposit_lp<T0, T1>(metadata.fee_to, liquidity, &metadata.mint_cap);
                }
            }
        } else if (metadata.k_last != 0) metadata.k_last = 0;
    }

    fun total_lp_supply<T0, T1>(): u64 {
        Option::get_with_default(
            &Coin::supply<LPToken<T0, T1>>(),
            0u64
        )
    }

    // ================ Tests ================
//    #[test_only]
//    struct TokenX {}
//    #[test_only]
//    struct TokenY {}
//
//    #[test(admin = @HippoSwapAdmin)]
//    public(script) fun init_works(admin: signer) {
//        create_token_pair<TokenX, TokenY>(admin, Signer::address_of(&admin));
//    }
    
    // #[test(admin = @HippoSwap)]
    // public(script) fun mint_works(admin: signer) {
    //     let decimals: u64 = 18;
    //     let total_supply: u64 = 1000000 * 10 ^ decimals;

    //     Coin::initialize<Token1>(&admin, b"token1", total_supply, true);
    // }
}
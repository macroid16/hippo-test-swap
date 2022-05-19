/// Uniswap v2 like token swap program
module HippoSwap::CPSwap {
    use Std::Signer;
    use Std::Option;
    use Std::ASCII;

    use AptosFramework::Coin;
    use AptosFramework::Timestamp;

    use HippoSwap::SafeMath;
    use HippoSwap::Utils;
    use HippoSwap::Math;

    const MODULE_ADMIN: address = @HippoSwap;
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
    const ERROR_INSUFFICIENT_AMOUNT: u64 = 6;
    const ERROR_INSUFFICIENT_LIQUIDITY: u64 = 7;
    const ERROR_INVALID_AMOUNT: u64 = 8;
    const ERROR_TOKENS_NOT_SORTED: u64 = 9;
    const ERROR_INSUFFICIENT_LIQUIDITY_BURNED: u64 = 10;
    const ERROR_INSUFFICIENT_TOKEN0_AMOUNT: u64 = 11;
    const ERROR_INSUFFICIENT_TOKEN1_AMOUNT: u64 = 12;

    /// The LP Token type
    struct LPToken<phantom T0, phantom T1> has key {}

    struct GenericTokenBalance<phantom T> has key {
        coin: Coin::Coin<T>
    }

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
    struct TokenPairReserve<phantom T0: key, phantom T1: key> has key {
        // TODO: seems like reserve can be u64, kiv.
        reserve0: u64,
        reserve1: u64,
        block_timestamp_last: u64
    }

    public fun register_token<T: key>(sender: &signer) {
        let sender_addr = Signer::address_of(sender);
        assert!(sender_addr == MODULE_ADMIN, ERROR_NOT_CREATOR);

        assert!(
            !exists<GenericTokenBalance<T>>(sender_addr),
            ERROR_ALREADY_INITIALIZED
        );

        move_to<GenericTokenBalance<T>>(
            sender,
            GenericTokenBalance { coin: Coin::zero<T>() }
        );
    }

    /// Create the specified token pair
    public fun create_token_pair<T0: key, T1: key>(
        sender: &signer,
        fee_to: address,
        fee_on: bool,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>
    ) {
        assert!(Utils::is_tokens_sorted<T0, T1>(), ERROR_TOKENS_NOT_SORTED);

        let sender_addr = Signer::address_of(sender);
        assert!(sender_addr == MODULE_ADMIN, ERROR_NOT_CREATOR);
        assert!(!exists<TokenPairReserve<T0, T1>>(sender_addr), ERROR_ALREADY_INITIALIZED);

        // now we init the LP token
        let (mint_cap, burn_cap) = Coin::initialize<LPToken<T0, T1>>(
            sender,
            ASCII::string(lp_name),
            ASCII::string(lp_symbol),
            8,
            true
        );

        move_to<TokenPairReserve<T0, T1>>(
            sender,
            TokenPairReserve {
                reserve0: 0,
                reserve1: 0,
                block_timestamp_last: 0
            }
        );

        move_to<TokenPairMetadata<T0, T1>>(
            sender,
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
    public fun register_account<T0, T1>(sender: &signer) {
        assert!(Utils::is_tokens_sorted<T0, T1>(), ERROR_TOKENS_NOT_SORTED);
        Coin::register<LPToken<T0, T1>>(sender);
    }

    public fun get_reserves<T0: key, T1: key>(): (u64, u64, u64) acquires TokenPairReserve {
        assert!(Utils::is_tokens_sorted<T0, T1>(), ERROR_TOKENS_NOT_SORTED);
        let reserve = borrow_global<TokenPairReserve<T0, T1>>(MODULE_ADMIN);
        (
            reserve.reserve0,
            reserve.reserve1,
            reserve.block_timestamp_last
        )
    }

    /// Add more liquidity to token types. This method explicitly assumes the
    /// min of both tokens are 0.
    public fun add_liquidity<T0: key, T1: key>(
        sender: &signer,
        amount0: u64,
        amount1: u64
    ): (u64, u64, u64) acquires TokenPairReserve, TokenPairMetadata, GenericTokenBalance {
        assert!(Utils::is_tokens_sorted<T0, T1>(), ERROR_TOKENS_NOT_SORTED);

        let (reserve0, reserve1, _) = get_reserves<T0, T1>();
        let (a0, a1) = if (reserve0 == 0 && reserve1 == 0) {
            (amount0, amount1)
        } else {
            let amount1_optimal = quote(amount0, reserve0, reserve1);
            if (amount1_optimal <= amount1) {
                (amount0, amount1_optimal)
            } else {
                let amount0_optimal = quote(amount1, reserve1, reserve0);
                assert!(amount0_optimal <= amount0, ERROR_INVALID_AMOUNT);
                (amount0_optimal, amount1)
            }
        };

        deposit_token<T0>(Coin::withdraw<T0>(sender, a0));
        deposit_token<T1>(Coin::withdraw<T1>(sender, a1));
        (a0, a1, mint<T0, T1>(sender))
    }

    /// Remove liquidity to token types.
    public fun remove_liquidity<T0: key, T1: key>(
        sender: &signer,
        liquidity: u64,
        amount0_min: u64,
        amount1_min: u64
    ): (u64, u64) acquires TokenPairMetadata, TokenPairReserve, GenericTokenBalance {
        assert!(Utils::is_tokens_sorted<T0, T1>(), ERROR_TOKENS_NOT_SORTED);

        let to_burn = Coin::withdraw<LPToken<T0, T1>>(sender, liquidity);
        let (amount0, amount1) = burn(to_burn, Signer::address_of(sender));
        assert!(amount0 >= amount0_min, ERROR_INSUFFICIENT_TOKEN0_AMOUNT);
        assert!(amount1 >= amount1_min, ERROR_INSUFFICIENT_TOKEN1_AMOUNT);
        (amount0, amount1)
    }

    // ======================= Internal Functions ==============================
    /// Mint LP Token.
    /// This low-level function should be called from a contract which performs important safety checks
    fun mint<T0: key, T1: key>(sender: &signer): u64 acquires TokenPairReserve, TokenPairMetadata {
        let metadata = borrow_global_mut<TokenPairMetadata<T0, T1>>(MODULE_ADMIN);

        // Lock it, reentrancy protection
        assert!(!metadata.locked, ERROR_ALREADY_LOCKED);
        metadata.locked = true;

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
        deposit_lp<T0, T1>(
            Signer::address_of(sender),
            (liquidity as u64), &metadata.mint_cap
        );

        update<T0, T1>(balance0, balance1, reserves);

        if (metadata.fee_on)
            metadata.k_last = SafeMath::mul((reserves.reserve0 as u128), (reserves.reserve1 as u128));

        // Unlock it
        metadata.locked = false;

        (liquidity as u64)
    }

    fun burn<T0: key, T1: key>(to_burn: Coin::Coin<LPToken<T0, T1>>, to: address): (u64, u64)
    acquires TokenPairMetadata, TokenPairReserve, GenericTokenBalance
    {
        let metadata = borrow_global_mut<TokenPairMetadata<T0, T1>>(MODULE_ADMIN);

        // Lock it, reentrancy protection
        assert!(!metadata.locked, ERROR_ALREADY_LOCKED);
        metadata.locked = true;

        let reserves = borrow_global_mut<TokenPairReserve<T0, T1>>(MODULE_ADMIN);
        let balance0 = Coin::balance<T0>(@HippoSwap);
        let balance1 = Coin::balance<T1>(@HippoSwap);
        let liquidity = Coin::balance<LPToken<T0, T1>>(@HippoSwap) + Coin::value(&to_burn);

        mint_fee(reserves.reserve0, reserves.reserve1, metadata);

        let total_lp_supply = total_lp_supply<T0, T1>();
        let amount0 = (SafeMath::div(
            SafeMath::mul(
                (balance0 as u128),
                (liquidity as u128)
            ),
        (total_lp_supply as u128)
        ) as u64);
        let amount1 = (SafeMath::div(
            SafeMath::mul(
                (balance1 as u128),
                (liquidity as u128)
            ),
        (total_lp_supply as u128)
        ) as u64);
        assert!(amount0 > 0 && amount1 > 0, ERROR_INSUFFICIENT_LIQUIDITY_BURNED);

        Coin::burn(to_burn, &metadata.burn_cap);
        transfer_token<T0>(amount0, to);
        transfer_token<T1>(amount1, to);

        update(
            Coin::balance<T0>(@HippoSwap),
            Coin::balance<T1>(@HippoSwap),
            reserves
        );

        if (metadata.fee_on)
            metadata.k_last = SafeMath::mul((reserves.reserve0 as u128), (reserves.reserve1 as u128));

        (amount0, amount1)
    }

    fun update<T0: key, T1: key>(balance0: u64, balance1: u64, reserve: &mut TokenPairReserve<T0, T1>) {
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

    /// Deposit `amount` to this contract
    fun deposit_token<T: key>(amount: Coin::Coin<T>) acquires GenericTokenBalance {
        let balance = borrow_global_mut<GenericTokenBalance<T>>(MODULE_ADMIN);
        Coin::merge(&mut balance.coin, amount);
    }

    /// Transfer `amount` from this contract to `recipient`
    fun transfer_token<T: key>(amount: u64, recipient: address) acquires GenericTokenBalance {
        let balance = borrow_global_mut<GenericTokenBalance<T>>(MODULE_ADMIN);
        assert!(Coin::value<T>(&balance.coin) > amount, ERROR_INSUFFICIENT_AMOUNT);
        Coin::deposit(recipient, Coin::extract(&mut balance.coin, amount));
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

    fun quote(amount0: u64, reserve0: u64, reserve1: u64): u64 {
        assert!(amount0 > 0, ERROR_INSUFFICIENT_AMOUNT);
        assert!(reserve0 > 0 && reserve1 > 0, ERROR_INSUFFICIENT_LIQUIDITY);
        (SafeMath::div(
            SafeMath::mul(
                (amount0 as u128),
                (reserve1 as u128)
            ),
            (reserve0 as u128)
        ) as u64)
    }

    // ================ Tests ================
    #[test_only]
    struct Token0 has key {}

    #[test_only]
    struct Token1 has key {}

    #[test_only]
    struct CapContainer<phantom T: key> has key {
        mc: Coin::MintCapability<T>,
        bc: Coin::BurnCapability<T>
    }

    #[test_only]
    fun issue_token<T: key>(admin: &signer, to: &signer, name: vector<u8>, total_supply: u64) {
        let (mc, bc) = Coin::initialize<T>(
            admin,
            ASCII::string(name),
            ASCII::string(name),
            8u64,
            true
        );

        Coin::register<T>(admin);
        Coin::register<T>(to);

        let a = Coin::mint(total_supply, &mc);
        Coin::deposit(Signer::address_of(to), a);
        move_to<CapContainer<T>>(admin, CapContainer{ mc, bc });
    }

    #[test(admin = @HippoSwap)]
    public fun init_works(admin: signer) {
        let fee_to = Signer::address_of(&admin);
        create_token_pair<Token0, Token1>(
            &admin,
            fee_to,
            true,
            b"name",
            b"symbol"
        );
    }
    
     #[test(admin = @HippoSwap, lp_provider = @0x02, lock = @0x01, core = @0xa550c18)]
     public fun mint_works(admin: signer, lp_provider: signer, lock: signer, core: signer)
        acquires TokenPairReserve, TokenPairMetadata, GenericTokenBalance
     {
         let decimals: u64 = 8;
         let total_supply: u64 = 1000000 * 10 ^ decimals;

         issue_token<Token0>(&admin, &lp_provider, b"t0", total_supply);
         issue_token<Token1>(&admin, &lp_provider, b"t1", total_supply);

         let fee_to = Signer::address_of(&admin);
         create_token_pair<Token0, Token1>(
             &admin,
             fee_to,
             true,
             b"name",
             b"symbol"
         );

         Timestamp::set_time_has_started_for_testing(&core);
         register_account<Token0, Token1>(&lp_provider);
         register_account<Token0, Token1>(&lock);

         add_liquidity<Token0, Token1>(
             &lp_provider,
             10000u64,
             10000u64
         );

         assert!(
             Coin::balance<Token0>(Signer::address_of(&admin)) > 0,
             0
         );
         assert!(
             Coin::balance<Token1>(Signer::address_of(&admin)) > 0,
             0
         );

         // check balance of lp provider
         assert!(
             Coin::balance<LPToken<Token0, Token1>>(Signer::address_of(&lp_provider)) > 0,
             0
         );
         assert!(
             Coin::balance<Token0>(Signer::address_of(&lp_provider)) < total_supply,
             0
         );
         assert!(
             Coin::balance<Token1>(Signer::address_of(&lp_provider)) < total_supply,
             0
         );
     }
}
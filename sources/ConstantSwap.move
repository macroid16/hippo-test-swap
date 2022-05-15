module HippoSwap::ConstantSwap {
    use AptosFramework::Coin;
    use AptosFramework::Signer;
    use Std::Option;

    use HippoSwap::SafeMath;
    use HippoSwap::Math;

    const MODULE_ADMIN: address = @HippoSwapAdmin;
    const MINIMUM_LIQUIDITY: u128 = 1000;
    const LIQUIDITY_LOCK: address = @0x1;

    // List of errors
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_ALREADY_INITIALIZED: u64 = 1;
    const ERROR_NOT_CREATOR: u64 = 2;
    const ERROR_ALREADY_LOCKED: u64 = 3;
    const ERROR_INSUFFICIENT_LIQUIDITY_MINTED: u64 = 4;

    struct LPToken<phantom T0, phantom T1> has key {}

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
    }

    /// Stores the reservation info required for the token pairs
    struct TokenPairReserve<phantom T0, phantom T1> has key {
        reserve0: Coin::Coin<T0>,
        reserve1: Coin::Coin<T1>,
        block_timestamp_last: u64
    }

    public fun create_token_pair<T0, T1>(sender: signer, fee_to: address, fee_on: bool) {
        let sender_addr = Signer::address_of(&sender);

        // TODO: consider removing this restriction in the future
        assert!(sender_addr == MODULE_ADMIN, ERROR_ONLY_ADMIN);

        assert!(!exists<TokenPairReserve<T0, T1>>(sender_addr), ERROR_ALREADY_INITIALIZED);

        move_to<TokenPairReserve<T0, T1>>(
            &sender,
            TokenPairReserve {
                reserve0: Coin::zero<T0>(),
                reserve1: Coin::zero<T1>(),
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
                lp: Coin::zero<LPToken<T0, T1>>()
            }
        );
    }

    public fun get_reserves<T0, T1>(): (u64, u64, u64) acquires TokenPairReserve {
        let reserve = borrow_global<TokenPairReserve<T0, T1>>(MODULE_ADMIN);
        (
            Coin::value(&reserve.reserve0),
            Coin::value(&reserve.reserve1),
            reserve.block_timestamp_last
        )
    }

    public(script) fun mint<T0, T1>(sender: signer, creator: address): u128 acquires TokenPairReserve, TokenPairMetadata {
        let metadata = borrow_global_mut<TokenPairMetadata<T0, T1>>(creator);
        // should have no need to check the creator again
        assert!(!metadata.locked, ERROR_ALREADY_LOCKED);

        let (reserve0, reserve1, _) = get_reserves<T0, T1>();
        let balance0 = Coin::balance<T0>(@HippoSwap);
        let balance1 = Coin::balance<T1>(@HippoSwap);
        let amount0 = SafeMath::sub((balance0 as u128), (reserve0 as u128));
        let amount1 = SafeMath::sub((balance1 as u128), (reserve1 as u128));

        let fee_liquidity = mint_fee(
            reserve0,
            reserve1,
            metadata
        );
        if (fee_liquidity > 0u64) Coin::mint<LPToken<T0, T1>>(&sender, metadata.fee_to, fee_liquidity);

        let total_supply = (total_lp_supply<T0, T1>() as u128);
        let liquidity = if (total_supply == 0u128) {
            let l = SafeMath::sub(
                Math::sqrt(
                    SafeMath::mul(amount0, amount1)
                ),
                MINIMUM_LIQUIDITY
            );
            // permanently lock the first MINIMUM_LIQUIDITY tokens
            Coin::mint<LPToken<T0, T1>>(&sender, LIQUIDITY_LOCK, (MINIMUM_LIQUIDITY as u64));
            l
        } else {
            Math::min(
                SafeMath::div(
                    SafeMath::mul(amount0, total_supply),
                    (reserve0 as u128)
                ),
                SafeMath::div(
                    SafeMath::mul(amount1, total_supply),
                    (reserve1 as u128)
                )
            )
        };

        assert!(liquidity > 0u128, ERROR_INSUFFICIENT_LIQUIDITY_MINTED);
        Coin::mint<LPToken<T0, T1>>(&sender, Signer::address_of(&sender), (liquidity as u64));

        update(balance0, balance1, reserve0, reserve1);

        if (metadata.fee_on)
            metadata.k_last = SafeMath::mul((reserve0 as u128), (reserve1 as u128));

        liquidity
    }

    fun update(balance0: u64, balance1: u64, reserve0: u64, reserve1: u64) {
        // require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');

        // uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        // uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        // if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
        //     // * never overflows, and + overflow is desired
        //     price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
        //     price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        // }
        // reserve0 = uint112(balance0);
        // reserve1 = uint112(balance1);
        // blockTimestampLast = blockTimestamp;
    }

    fun mint_fee<T0, T1>(reserve0: u64, reserve1: u64, metadata: &mut TokenPairMetadata<T0, T1>): u64 {
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

                    return (SafeMath::div(
                        numerator,
                        denominator
                    ) as u64)
                }
            }
        } else if (metadata.k_last != 0) metadata.k_last = 0;
        0u64
    }

    fun total_lp_supply<T0, T1>(): u64 {
        Option::get_with_default(
            &Coin::supply<LPToken<T0, T1>>(),
            0u64
        )
    }

    // ================ Tests ================
    #[test_only]
    struct TokenX {}
    #[test_only]
    struct TokenY {}

    #[test(admin = @HippoSwapAdmin)]
    public(script) fun init_works(admin: signer) {
        create_token_pair<TokenX, TokenY>(admin, Signer::address_of(&admin));
    }
    
    // #[test(admin = @HippoSwap)]
    // public(script) fun mint_works(admin: signer) {
    //     let decimals: u64 = 18;
    //     let total_supply: u64 = 1000000 * 10 ^ decimals;

    //     Coin::initialize<Token1>(&admin, b"token1", total_supply, true);
    // }
}
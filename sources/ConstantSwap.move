module HippoSwap::ConstantSwap {
    use AptosFramework::Coin;
    use AptosFramework::Signer;

    use HippoSwap::SafeMath;

    const MODULE_ADMIN: address = @HippoSwapAdmin;

    // List of errors
    const ERROR_ONLY_ADMIN: u64 = 0;
    const ERROR_ALREADY_INITIALIZED: u64 = 1;

    /// Stores the metadata required for the token pairs
    struct TokenPairMetadata<phantom T0, phantom T1> has key {
        /// Lock for mint and burn
        locked: bool,
        /// The admin of the token pair
        creator: address,
        /// The address to transfer mint fees to
        fee_to: address
    }

    /// Stores the reservation info required for the token pairs
    struct TokenPairReserve<phantom T0, phantom T1> has key {
        reserve0: Coin::Coin<T0>,
        reserve1: Coin::Coin<T1>,
        block_timestamp_last: u64
    }

    public fun create_token_pair<T0, T1>(sender: signer, fee_to: address) {
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
                fee_to
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

    public fun mint<T0, T1>(): bool acquires TokenPairReserve {
    // public fun mint<T0, T1>(sender: signer): bool acquires TokenPairReserve {
        let (reserve0, reserve1, _) = get_reserves<T0, T1>();
        let balance0 = Coin::balance<T0>(@HippoSwap);
        let balance1 = Coin::balance<T1>(@HippoSwap);
        let amount0 = SafeMath::sub(balance0, reserve0);
        let amount1 = SafeMath::sub(balance1, reserve1);

        let fee_on = mint_fee(_reserve0, _reserve1);
        amount0 > amount1
    }

    fun mint_fee(reserve0: u64, reserve1: u64): bool acquires TokenPairMetadata {

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
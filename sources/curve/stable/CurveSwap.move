module HippoSwap::StableCurveSwap {
    use Std::ASCII;
    use Std::Option;
    use AptosFramework::Coin;

    use HippoSwap::HippoConfig;

    // Token

    struct LPToken<phantom X, phantom Y> has key, store, copy {}

    struct LPCapability<phantom X, phantom Y> has key, store {
        mint: Coin::MintCapability<LPToken<X, Y>>,
        burn: Coin::BurnCapability<LPToken<X, Y>>,
    }

    // Swap

    struct SwapPair<phantom X, phantom Y> has key, store {
        x_reserve: Coin::Coin<X>,
        y_reserve: Coin::Coin<Y>,
        last_k: u128
    }


    const DECIMALS: u64 = 18;

    const ERROR_SWAP_BURN_CALC_INVALID: u64 = 2004;
    const ERROR_SWAP_ADDLIQUIDITY_INVALID: u64 = 2007;
    const ERROR_SWAP_TOKEN_NOT_EXISTS: u64 = 2008;

    // Token utilities

    public fun initialize_coin<X, Y>(signer: &signer, name: ASCII::String, symbol: ASCII::String) {
        let (mint_capability, burn_capability) = Coin::initialize<LPToken<X, Y>>(
            signer, name, symbol, DECIMALS, true
        );
        move_to(signer, LPCapability{ mint: mint_capability, burn: burn_capability });
    }

    fun mint<X, Y>(amount: u64): Coin::Coin<LPToken<X, Y>> acquires LPCapability {
        let liquidity_cap = borrow_global<LPCapability<X, Y>>(HippoConfig::admin_address());
        let mint_token = Coin::mint<LPToken<X, Y>>(amount, &liquidity_cap.mint);
        mint_token
    }

    fun burn<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>,
    ) acquires LPCapability {
        let liquidity_cap = borrow_global<LPCapability<X, Y>>(HippoConfig::admin_address());
        Coin::burn<LPToken<X, Y>>(to_burn, &liquidity_cap.burn);
    }

    #[test(admin = @HippoSwap, core_resource_account = @CoreResources)]
    fun mint_mock_coin(admin: &signer) acquires LPCapability {
        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );
        let coin = mint<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(100);
        burn(coin)
    }

    // Swap utilities

    public fun get_reserves<X: copy + store, Y: copy + store>(): (u64, u64) acquires SwapPair {
        let pair = borrow_global<SwapPair<X, Y>>(HippoConfig::admin_address());
        let x_reserve = Coin::value(&pair.x_reserve);
        let y_reserve = Coin::value(&pair.y_reserve);
        (x_reserve, y_reserve)
    }

    fun make_swap_pair<X: copy + store, Y: copy + store>(): SwapPair<X, Y> {
        SwapPair<X, Y>{
            x_reserve: Coin::zero<X>(),
            y_reserve: Coin::zero<Y>(),
            last_k: 0,
        }
    }

    public fun initialize<X: copy + store, Y: copy + store>(signer: &signer, name: ASCII::String, symbol: ASCII::String) {
        let token_pair = make_swap_pair<X, Y>();
        move_to(signer, token_pair);
        initialize_coin<X, Y>(signer, name, symbol)
    }

    public fun add_liquidity<X: copy + store, Y: copy + store>(x: Coin::Coin<X>, y: Coin::Coin<Y>
    ): Coin::Coin<LPToken<X, Y>> acquires SwapPair, LPCapability {
        let (x_reserve, y_reserve) = get_reserves<X, Y>();
        let x_value = Coin::value<X>(&x);
        let y_value = Coin::value<Y>(&y);
        // TODO: Need to be corrected.
        let liquidity = x_value + y_value;
        assert!(liquidity > 0, ERROR_SWAP_ADDLIQUIDITY_INVALID);
        let token_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        Coin::merge(&mut token_pair.x_reserve, x);
        Coin::merge(&mut token_pair.y_reserve, y);
        let mint_token = mint<X, Y>(liquidity);
        update_oracle<X, Y>(x_reserve, y_reserve);
        mint_token
    }

    public fun remove_liquidity<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>,
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires SwapPair, LPCapability {
        let to_burn_value = Coin::value(&to_burn);
        let swap_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        let x_reserve = Coin::value(&swap_pair.x_reserve);
        let y_reserve = Coin::value(&swap_pair.y_reserve);
        let total_supply = Option::extract(&mut Coin::supply<LPToken<X, Y>>());
        // TODO: Implement the algorithm   !!! Unsafe current
        let x = to_burn_value * x_reserve / total_supply;
        let y = to_burn_value * y_reserve / total_supply;
        // assert!(x > 0 && y > 0, ERROR_SWAP_BURN_CALC_INVALID);
        burn<X, Y>(to_burn);
        let x_coin = Coin::extract(&mut swap_pair.x_reserve, x);
        let y_coin = Coin::extract(&mut swap_pair.y_reserve, y);
        update_oracle<X, Y>(x_reserve, y_reserve);
        (x_coin, y_coin)
    }

    fun update_oracle<X: copy + store, Y: copy + store>(x_reserve: u64, y_reserve: u64, ) acquires SwapPair {
        let token_pair = borrow_global_mut<SwapPair<X, Y>>(HippoConfig::admin_address());
        // TODO: Not implemented.
        token_pair.last_k = ((x_reserve * y_reserve) as u128);
    }

    #[test_only]
    fun init_mock_coin<Money: store>(creator: &signer): Coin::Coin<Money> {
        use HippoSwap::MockCoin;
        MockCoin::initialize<Money>(creator, 9);
        MockCoin::mint<Money>(20)
    }

    #[test(admin = @HippoSwap, core_resource_account = @CoreResources)]
    fun mint_lptoken_coin(admin: &signer, ) acquires SwapPair, LPCapability {
        use Std::Signer;
        //        use AptosFramework::Genesis;

        //        Genesis::setup(core_resource_account);

        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            admin,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );

        let x = init_mock_coin<HippoSwap::MockCoin::WETH>(admin);
        let y = init_mock_coin<HippoSwap::MockCoin::WDAI>(admin);
        let liquidity = add_liquidity(x, y);
        let (x, y) = remove_liquidity(liquidity);
        Coin::deposit(Signer::address_of(admin), x);
        Coin::deposit(Signer::address_of(admin), y);
    }

    #[test(source = @HippoSwap)]
    #[expected_failure(abort_code = 2007)]
    public fun fail_add_liquidity(source: &signer) acquires SwapPair, LPCapability {
        use Std::Signer;
        use HippoSwap::MockCoin;
        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(
            source,
            ASCII::string(b"Curve:WETH-WDAI"),
            ASCII::string(b"WEWD")
        );
        MockCoin::initialize<MockCoin::WETH>(source, 18);
        MockCoin::initialize<MockCoin::WDAI>(source, 18);
        let x = MockCoin::mint<MockCoin::WETH>(0);
        let y = MockCoin::mint<MockCoin::WDAI>(0);
        let liquidity = add_liquidity(x, y);
        Coin::deposit(Signer::address_of(source), liquidity)
    }
}

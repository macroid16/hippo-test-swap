module HippoSwap::Swap {
    use Std::ASCII;
    use Std::Option;
    use AptosFramework::Coin;
    use AptosFramework::TypeInfo;

    use HippoSwap::SwapConfig;

    struct Liquidity<phantom X, phantom Y> has key, store, copy {}

    struct LiquidityCapability<phantom X, phantom Y> has key, store {
        mint: Coin::MintCapability<Liquidity<X, Y>>,
        burn: Coin::BurnCapability<Liquidity<X, Y>>,
    }

    struct SwapPair<phantom X, phantom Y> has key, store {
        x_reserve: Coin::Coin<X>,
        y_reserve: Coin::Coin<Y>,
        last_k: u128,
    }

    const LIQUIDITY_SCALE: u8 = 9;

    const ERROR_SWAP_BURN_CALC_INVALID: u64 = 2004;
    const ERROR_SWAP_ADDLIQUIDITY_INVALID: u64 = 2007;

    public fun initialize<X: copy + store, Y: copy + store>(signer: &signer) {
        let token_pair = make_swap_pair<X, Y>();
        move_to(signer, token_pair);

        register_coin<X, Y>(signer);
    }

    fun register_coin<X: copy + store, Y: copy + store>(signer: &signer) {
        let info = TypeInfo::type_of<Liquidity<X, Y>>();
        // TODO: It's better to be shortened with the symbol.
        let name = ASCII::string(TypeInfo::struct_name(&info));
        let symbol = ASCII::string(TypeInfo::struct_name(&info));
        let (mint_capability, burn_capability) = Coin::initialize<Liquidity<X, Y>>(
            signer, name, symbol, 2, true
        );
        move_to(signer, LiquidityCapability{ mint: mint_capability, burn: burn_capability });
    }

    fun make_swap_pair<X: copy + store, Y: copy + store>(): SwapPair<X, Y> {
        SwapPair<X, Y>{
            x_reserve: Coin::zero<X>(),
            y_reserve: Coin::zero<Y>(),
            last_k: 0,
        }
    }

    /// Get reserves of a token pair.
    /// The order of type args should be sorted.
    public fun get_reserves<X: copy + store, Y: copy + store>(): (u64, u64) acquires SwapPair {
        let pair = borrow_global<SwapPair<X, Y>>(SwapConfig::admin_address());
        let x_reserve = Coin::value(&pair.x_reserve);
        let y_reserve = Coin::value(&pair.y_reserve);
        (x_reserve, y_reserve)
    }

    /// type args, X, Y should be sorted.
    public fun mint<X: copy + store, Y: copy + store>(x: Coin::Coin<X>, y: Coin::Coin<Y>
    ): Coin::Coin<Liquidity<X, Y>> acquires SwapPair, LiquidityCapability {
        let (x_reserve, y_reserve) = get_reserves<X, Y>();
        let x_value = Coin::value<X>(&x);
        let y_value = Coin::value<Y>(&y);
        // TODO: Need to be corrected.
        let liquidity = x_value + y_value;
        assert!(liquidity > 0, ERROR_SWAP_ADDLIQUIDITY_INVALID);
        let token_pair = borrow_global_mut<SwapPair<X, Y>>(SwapConfig::admin_address());
        Coin::merge(&mut token_pair.x_reserve, x);
        Coin::merge(&mut token_pair.y_reserve, y);
        let liquidity_cap = borrow_global<LiquidityCapability<X, Y>>(SwapConfig::admin_address());
        let mint_token = Coin::mint<Liquidity<X, Y>>(liquidity, &liquidity_cap.mint);
        update_oracle<X, Y>(x_reserve, y_reserve);
        mint_token
    }


    public fun burn<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<Liquidity<X, Y>>,
    ): (Coin::Coin<X>, Coin::Coin<Y>) acquires SwapPair, LiquidityCapability {
        let to_burn_value = Coin::value(&to_burn);
        let swap_pair = borrow_global_mut<SwapPair<X, Y>>(SwapConfig::admin_address());
        let x_reserve = Coin::value(&swap_pair.x_reserve);
        let y_reserve = Coin::value(&swap_pair.y_reserve);
        let total_supply = Option::extract(&mut Coin::supply<Liquidity<X, Y>>());
        // TODO: Implement the algorithm   !!! Unsafe current
        let x = to_burn_value * x_reserve / total_supply;
        let y = to_burn_value * y_reserve / total_supply;
        assert!(x > 0 && y > 0, ERROR_SWAP_BURN_CALC_INVALID);
        let liquidity_cap = borrow_global<LiquidityCapability<X, Y>>(SwapConfig::admin_address());
        Coin::burn<Liquidity<X, Y>>(to_burn, &liquidity_cap.burn);
        let x_coin = Coin::extract(&mut swap_pair.x_reserve, x);
        let y_coin = Coin::extract(&mut swap_pair.y_reserve, y);
        update_oracle<X, Y>(x_reserve, y_reserve);
        (x_coin, y_coin)
    }

    fun update_oracle<X: copy + store, Y: copy + store>(x_reserve: u64, y_reserve: u64, ) acquires SwapPair {
        let token_pair = borrow_global_mut<SwapPair<X, Y>>(SwapConfig::admin_address());
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
    fun mint_mock_coin(admin: &signer, core_resource_account: &signer) acquires SwapPair, LiquidityCapability {
        use Std::Signer;
        use AptosFramework::Genesis;

        Genesis::setup(core_resource_account);

        initialize<HippoSwap::MockCoin::WETH, HippoSwap::MockCoin::WDAI>(admin);

        let x = init_mock_coin<HippoSwap::MockCoin::WETH>(admin);
        let y = init_mock_coin<HippoSwap::MockCoin::WDAI>(admin);
        let liquidity = mint(x, y);
        let (x, y) = burn(liquidity);
        Coin::deposit(Signer::address_of(admin), x);
        Coin::deposit(Signer::address_of(admin), y);
    }
}

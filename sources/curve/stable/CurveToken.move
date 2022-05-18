module HippoSwap::StableCurveToken {
    use Std::ASCII;
    use AptosFramework::Coin;

    use HippoSwap::HippoConfig;

    friend HippoSwap::StableCurvePool;

    struct LPToken<phantom X, phantom Y> has key, store, copy {}

    struct LPCapability<phantom X, phantom Y> has key, store {
        mint: Coin::MintCapability<LPToken<X, Y>>,
        burn: Coin::BurnCapability<LPToken<X, Y>>,
    }

    const LIQUIDITY_SCALE: u64 = 18;

    const ERROR_SWAP_BURN_CALC_INVALID: u64 = 2004;
    const ERROR_SWAP_ADDLIQUIDITY_INVALID: u64 = 2007;

    public fun initialize<X, Y>(signer: &signer, name: ASCII::String, symbol: ASCII::String) {
        let (mint_capability, burn_capability) = Coin::initialize<LPToken<X, Y>>(
            signer, name, symbol, LIQUIDITY_SCALE, true
        );
        move_to(signer, LPCapability{ mint: mint_capability, burn: burn_capability });
    }

    public(friend) fun mint<X, Y>(amount: u64): Coin::Coin<LPToken<X, Y>> acquires LPCapability {
        let liquidity_cap = borrow_global<LPCapability<X, Y>>(HippoConfig::admin_address());
        let mint_token = Coin::mint<LPToken<X, Y>>(amount, &liquidity_cap.mint);
        mint_token
    }

    public(friend) fun burn<X: copy + store, Y: copy + store>(to_burn: Coin::Coin<LPToken<X, Y>>,
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
}

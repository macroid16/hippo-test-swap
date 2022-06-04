module HippoSwap::MockDeploy {
    use HippoSwap::MockCoin;
    use TokenRegistry::TokenRegistry;
    use AptosFramework::Coin;

    public fun init_coin_and_create_store<CoinType>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u64,
    ) {
        // create CoinInfo
        if (!Coin::is_coin_initialized<CoinType>()) {
            MockCoin::initialize<CoinType>(admin, decimals);
        };

        // add coin to registry
        if (!TokenRegistry::has_token<CoinType>(@HippoSwap)) {
            TokenRegistry::add_token<CoinType>(
                admin,
                name,
                symbol,
                name,
                (decimals as u8),
                b"",
                b"",
            );
        }
    }

    public fun init_registry(admin: &signer) {
        if (!TokenRegistry::is_registry_initialized(Std::Signer::address_of(admin))) {
            TokenRegistry::initialize(admin);
        }
    }

    #[test(admin = @HippoSwap, core = @CoreResources, vm = @0, trader = @0xFFFFFF01, )]
    fun test_init_coin(admin: &signer) {
        use HippoSwap::MockCoin;
        TokenRegistry::initialize(admin);
        init_coin_and_create_store<MockCoin::WBTC>(admin, b"Bitcoin", b"BTC", 8);
    }
}

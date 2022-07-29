module hippo_swap::mock_deploy {
    use hippo_swap::mock_coin;
    use coin_registry::coin_registry;
    use aptos_framework::coin;

    public fun init_coin_and_create_store<CoinType>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u64,
    ) {
        // create CoinInfo
        if (!coin::is_coin_initialized<CoinType>()) {
            mock_coin::initialize<CoinType>(admin, decimals);
        };

        // add coin to registry
        if (!coin_registry::has_token<CoinType>(@hippo_swap)) {
            coin_registry::add_token<CoinType>(
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
        if (!coin_registry::is_registry_initialized(std::signer::address_of(admin))) {
            coin_registry::initialize(admin);
        }
    }

    #[test(admin = @hippo_swap)]
    fun test_init_coin(admin: &signer) {
        use hippo_swap::mock_coin;
        coin_registry::initialize(admin);
        init_coin_and_create_store<mock_coin::WBTC>(admin, b"Bitcoin", b"BTC", 8);
    }
}

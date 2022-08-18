module hippo_swap::mock_deploy {
    use hippo_swap::mock_coin;
    use aptos_framework::coin;
    use coin_list::coin_list;
    use std::string;
    use std::vector;

    public fun init_coin_and_register<CoinType>(
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
        if (!coin_list::is_coin_registered<CoinType>()){
            coin_list::add_to_registry_by_signer<CoinType>(
                admin,
                string::utf8(name),
                string::utf8(symbol),
                string::utf8(vector::empty<u8>()),
                string::utf8(vector::empty<u8>()),
                string::utf8(vector::empty<u8>()),
                false
            );
        };
    }

    public fun init_registry(coin_list_admin: &signer) {
        if (!coin_list::is_registry_initialized()){
            coin_list::initialize(coin_list_admin)
        };
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list)]
    fun test_init_coin(admin: &signer, coin_list_admin: &signer) {
        use hippo_swap::mock_coin;
        use aptos_framework::account;
        use std::signer;
        account::create_account(signer::address_of(admin));

        coin_list::initialize(coin_list_admin);
        assert!(coin_list::is_registry_initialized(), 1);

        init_coin_and_register<mock_coin::WBTC>(admin, b"Bitcoin", b"BTC", 8);
        assert!(coin::is_coin_initialized<mock_coin::WBTC>(), 2);
        assert!(coin_list::is_coin_registered<mock_coin::WBTC>(), 3);
    }
}

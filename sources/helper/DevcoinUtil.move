module hippo_swap::devcoin_util {
    use aptos_framework::coin;
    use coin_list::coin_list;
    use coin_list::devnet_coins;
    use std::string;
    use std::vector;

    public fun init_coin<CoinType>(coin_list_admin: &signer,decimals: u8){
        if (!coin::is_coin_initialized<CoinType>()) {
            devnet_coins::initialize<CoinType>(coin_list_admin, decimals);
        };
    }

    public fun init_coin_and_register<CoinType>(
        admin: &signer,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
    ) {
        if (!coin::is_coin_initialized<CoinType>()) {
            devnet_coins::init_coin_and_register<CoinType>(
                admin,
                string::utf8(name),
                string::utf8(symbol),
                string::utf8(vector::empty<u8>()),
                string::utf8(vector::empty<u8>()),
                string::utf8(vector::empty<u8>()),
                decimals
            );
        };
    }

    public fun init_registry(coin_list_admin: &signer) {
        if (!coin_list::is_registry_initialized()){
            coin_list::initialize(coin_list_admin)
        };
    }

    #[test_only]
    public fun init_registry_and_devnet_coins(coin_list_admin: &signer){
        coin_list::initialize(coin_list_admin);
        devnet_coins::deploy(coin_list_admin);
    }
    #[test(admin = @hippo_swap, coin_list_admin = @coin_list)]
    fun test_init_coin(admin: &signer, coin_list_admin: &signer) {
        use aptos_framework::aptos_account;
        use std::signer;
        aptos_account::create_account(signer::address_of(admin));

        coin_list::initialize(coin_list_admin);
        assert!(coin_list::is_registry_initialized(), 1);

        init_coin_and_register<devnet_coins::DevnetBTC>(coin_list_admin, b"Bitcoin", b"BTC", 8);
        assert!(coin::is_coin_initialized<devnet_coins::DevnetBTC>(), 2);
        assert!(coin_list::is_coin_registered<devnet_coins::DevnetBTC>(), 3);
    }
}

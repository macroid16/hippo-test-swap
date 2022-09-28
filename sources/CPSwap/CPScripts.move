address hippo_swap {
module cp_scripts {
    use hippo_swap::cp_swap;
    use std::signer;
    use aptos_framework::coin;
    use coin_list::coin_list;
    use coin_list::devnet_coins;

    const E_SWAP_ONLY_ONE_IN_ALLOWED: u64 = 0;
    const E_SWAP_ONLY_ONE_OUT_ALLOWED: u64 = 1;
    const E_SWAP_NONZERO_INPUT_REQUIRED: u64 = 2;
    const E_OUTPUT_LESS_THAN_MIN: u64 = 3;
    const E_TOKEN_REGISTRY_NOT_INITIALIZED:u64 = 4;

    const E_TOKEN_X_NOT_REGISTERED:u64 = 5;
    const E_TOKEN_Y_NOT_REGISTERED:u64 = 6;
    const E_LP_TOKEN_ALREADY_REGISTERED:u64 = 7;
    const E_LP_TOKEN_ALREADY_IN_COIN_LIST:u64 = 8;

    public fun create_new_pool<X, Y>(
        admin: &signer,
        fee_to: address,
        fee_on: bool,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        _lp_logo_url: vector<u8>,
        _lp_project_url: vector<u8>,
    ) {
        use hippo_swap::math;

        let admin_addr = signer::address_of(admin);
        assert!(coin_list::is_registry_initialized(), E_TOKEN_REGISTRY_NOT_INITIALIZED);
        assert!(coin_list::is_coin_registered<X>(), E_TOKEN_X_NOT_REGISTERED);
        assert!(coin_list::is_coin_registered<Y>(), E_TOKEN_Y_NOT_REGISTERED);
        assert!(!coin_list::is_coin_registered<cp_swap::LPToken<X,Y>>(), E_LP_TOKEN_ALREADY_REGISTERED);
        assert!(!coin_list::is_coin_registered<cp_swap::LPToken<Y,X>>(), E_LP_TOKEN_ALREADY_REGISTERED);

        assert!(!coin_list::is_coin_in_list<cp_swap::LPToken<X,Y>>(admin_addr), E_LP_TOKEN_ALREADY_IN_COIN_LIST);
        assert!(!coin_list::is_coin_in_list<cp_swap::LPToken<Y,X>>(admin_addr), E_LP_TOKEN_ALREADY_IN_COIN_LIST);

        let decimals = math::max((coin::decimals<X>() as u128), (coin::decimals<Y>() as u128));
        let decimals = (decimals as u8);

        cp_swap::create_token_pair<X, Y>(admin, fee_to, fee_on, lp_name, lp_symbol, decimals);
    }
    #[cmd]
    public entry fun create_new_pool_script<X, Y>(
        sender: &signer,
        fee_to: address,
        fee_on: bool,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        lp_logo_url: vector<u8>,
        lp_project_url: vector<u8>,
    ) {
        create_new_pool<X,Y>(
            sender,
            fee_to,
            fee_on,
            lp_name,
            lp_symbol,
            lp_logo_url,
            lp_project_url,
        );
    }
    #[cmd]
    public entry fun add_liquidity_script<X, Y>(
        sender: &signer,
        amount_x: u64,
        amount_y: u64
    ) {
        cp_swap::add_liquidity<X,Y>(sender, amount_x, amount_y);
    }
    #[cmd]
    public entry fun remove_liquidity_script<X, Y>(
        sender: &signer,
        liquidity: u64,
        amount_x_min: u64,
        amount_y_min: u64
    ) {
        cp_swap::remove_liquidity<X,Y>(sender, liquidity, amount_x_min, amount_y_min);
    }
    #[cmd]
    public entry fun swap_script<X, Y>(
        sender: &signer,
        x_in: u64,
        y_in: u64,
        x_min_out: u64,
        y_min_out: u64,
    ) {
        assert!(!(x_in > 0 && y_in > 0), E_SWAP_ONLY_ONE_IN_ALLOWED);
        assert!(!(x_min_out > 0 && y_min_out > 0), E_SWAP_ONLY_ONE_OUT_ALLOWED);
        // X to Y
        if (x_in > 0) {
            let y_out = cp_swap::swap_x_to_exact_y<X, Y>(sender, x_in, signer::address_of(sender));
            assert!(y_out >= y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else if (y_in > 0) {
            let x_out = cp_swap::swap_y_to_exact_x<X, Y>(sender, y_in, signer::address_of(sender));
            assert!(x_out >= x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else {
            assert!(false, E_SWAP_NONZERO_INPUT_REQUIRED);
        }
    }

    #[test_only]
    use aptos_framework::timestamp;

    fun mock_create_pair_and_add_liquidity<X, Y>(
        admin: &signer,
        symbol: vector<u8>,
        left_amt:u64,
        right_amt:u64,
        lp_amt:u64
    ) {
        create_new_pool<X, Y>(
            admin,
            signer::address_of(admin),
            false,
            symbol,
            symbol,
            b"",
            b"",
        );

        let some_x = devnet_coins::mint<X>(left_amt);
        let some_y = devnet_coins::mint<Y>(right_amt);
        let (unused_x, unused_y, some_lp) = cp_swap::add_liquidity_direct(some_x, some_y);

        assert!(coin::value(&unused_x) == 0, 5);
        assert!(coin::value(&unused_y) == 0, 5);
        assert!(coin::value(&some_lp) == lp_amt, 5);

        devnet_coins::burn(unused_x);
        devnet_coins::burn(unused_y);
        coin::deposit(signer::address_of(admin), some_lp);

    }

    // coinlist registry must be initialized before this method
    #[cmd]
    public entry fun mock_deploy_script(admin: &signer) {
        let btc_amt = 1000000000;
        mock_create_pair_and_add_liquidity<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDC>(
            admin,
            b"BTC-USDC",
            btc_amt,
            btc_amt * 10000,
            btc_amt * 100 - 1000,
        );

        mock_create_pair_and_add_liquidity<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDT>(
            admin,
            b"BTC-USDT",
            btc_amt,
            btc_amt * 10000,
            btc_amt * 100 - 1000,
        );
    }

    #[test_only]
    use hippo_swap::devcoin_util;


    #[test_only]
    public fun mock_deploy(admin: &signer, coin_list_admin: &signer){
        devcoin_util::init_coin_and_register<devnet_coins::DevnetBTC>(coin_list_admin, b"Bitcoin", b"BTC", 8);
        devcoin_util::init_coin_and_register<devnet_coins::DevnetUSDC>(coin_list_admin,b"USDC", b"USDC", 8);
        devcoin_util::init_coin_and_register<devnet_coins::DevnetUSDT>(coin_list_admin, b"USDT", b"USDT", 8);

        mock_deploy_script(admin)
    }

    #[test(admin=@hippo_swap, coin_list_admin = @coin_list, user=@0x1234567, core=@aptos_framework)]
    fun test_initialization_cpswap(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {

        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(user));
        devcoin_util::init_registry(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);
        /*
           1. perform local depploy
           2. user trades
       */
        // 1
        mock_deploy(admin,coin_list_admin);
        // 2
        coin::register<devnet_coins::DevnetBTC>(user);
        coin::register<devnet_coins::DevnetUSDC>(user);
        let user_addr = signer::address_of(user);
        devnet_coins::mint_to_wallet<devnet_coins::DevnetBTC>(user, 100);
        assert!(coin::balance<devnet_coins::DevnetUSDC>(user_addr)==0, 5);
        cp_swap::swap_x_to_exact_y<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDC>(user, 100, user_addr);
        assert!(coin::balance<devnet_coins::DevnetUSDC>(user_addr) > 0, 5);

    }

    #[test(admin=@hippo_swap, coin_list_admin = @coin_list, user=@0x1234567, core=@aptos_framework)]
    fun test_add_remove_liquidity(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(user));
        devcoin_util::init_registry(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);
        /*
            1. create pools
            2. add liquidity to BTC-USDC
            3. remove liquidity from BTC-USDC
        */

        // 1
        mock_deploy(admin,coin_list_admin);

        // 2
        let btc_amt = 100;
        let price = 10000;
        devnet_coins::mint_to_wallet<devnet_coins::DevnetBTC>(user, btc_amt);
        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDC>(user, btc_amt * price);
        add_liquidity_script<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDC>(user, btc_amt, btc_amt * price);

        let user_addr = signer::address_of(user);
        assert!(coin::balance<devnet_coins::DevnetBTC>(user_addr) == 0, 0);
        assert!(coin::balance<devnet_coins::DevnetUSDC>(user_addr) == 0, 0);

        // 3
        remove_liquidity_script<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDC>(
            user,
            coin::balance<cp_swap::LPToken<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDC>>(user_addr),
            0,
            0,
        );
        assert!(coin::balance<devnet_coins::DevnetBTC>(user_addr) == btc_amt, 0);
        assert!(coin::balance<devnet_coins::DevnetUSDC>(user_addr) == btc_amt * price, 0);
    }

    #[test(admin=@hippo_swap, coin_list_admin = @coin_list, user=@0x1234567, core=@aptos_framework)]
    fun test_swap(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(user));
        devcoin_util::init_registry(coin_list_admin);
        /*
            1. create pools
            2. swap x to y
            3. swap y to x
        */
        timestamp::set_time_has_started_for_testing(core);
        // 1
        mock_deploy(admin,coin_list_admin);

        // 2
        let btc_amt = 100;
        let price = 10000;
        devnet_coins::mint_to_wallet<devnet_coins::DevnetBTC>(user, btc_amt);
        swap_script<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDC>(user, btc_amt, 0, 0, btc_amt * price * 99 / 100);

        // 3
        let usdc_balance = coin::balance<devnet_coins::DevnetUSDC>(signer::address_of(user));
        swap_script<devnet_coins::DevnetBTC, devnet_coins::DevnetUSDC>(user, 0, usdc_balance, btc_amt * 99 / 100, 0);
        assert!(coin::balance<devnet_coins::DevnetUSDC>(signer::address_of(user)) == 0, 0);
        assert!(coin::balance<devnet_coins::DevnetBTC>(signer::address_of(user)) >= btc_amt * 99 / 100, 0);

    }

     #[test_only]
     public fun swap<X, Y>(
        sender: &signer,
        x_in: u64,
        y_in: u64,
        x_min_out: u64,
        y_min_out: u64,
    ) {
        assert!(!(x_in > 0 && y_in > 0), E_SWAP_ONLY_ONE_IN_ALLOWED);
        assert!(!(x_min_out > 0 && y_min_out > 0), E_SWAP_ONLY_ONE_OUT_ALLOWED);
        // X to Y
        if (x_in > 0) {
            let y_out = cp_swap::swap_x_to_exact_y<X, Y>(sender, x_in, signer::address_of(sender));
            assert!(y_out >= y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else if (y_in > 0) {
            let x_out = cp_swap::swap_y_to_exact_x<X, Y>(sender, y_in, signer::address_of(sender));
            assert!(x_out >= x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else {
            assert!(false, E_SWAP_NONZERO_INPUT_REQUIRED);
        }
    }
}
}

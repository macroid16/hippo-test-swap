address hippo_swap {
module piece_swap_script {
    use std::signer;
    use hippo_swap::piece_swap;
    use aptos_framework::coin;
    use std::vector;
    use std::string;
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

    /*
    1. create_new_pool_script
    2. swap_script
    3. add_liquidity_script
    4. remove_liquidity_script
    */

    public fun create_new_pool<X, Y>(
        admin: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        lp_logo_url: vector<u8>,
        lp_project_url: vector<u8>,
        k: u128,
        w1_numerator: u128,
        w1_denominator: u128,
        w2_numerator: u128,
        w2_denominator: u128,
        swap_fee_per_million: u64,
        protocol_fee_share_per_thousand: u64,
    ) {
        use hippo_swap::math;

        let admin_addr = signer::address_of(admin);
        assert!(coin_list::is_registry_initialized(), E_TOKEN_REGISTRY_NOT_INITIALIZED);
        assert!(coin_list::is_coin_registered<X>(), E_TOKEN_X_NOT_REGISTERED);
        assert!(coin_list::is_coin_registered<Y>(), E_TOKEN_Y_NOT_REGISTERED);
        assert!(!coin_list::is_coin_registered<piece_swap::LPToken<X,Y>>(), E_LP_TOKEN_ALREADY_REGISTERED);
        assert!(!coin_list::is_coin_registered<piece_swap::LPToken<Y,X>>(), E_LP_TOKEN_ALREADY_REGISTERED);

        assert!(!coin_list::is_coin_in_list<piece_swap::LPToken<X,Y>>(admin_addr), E_LP_TOKEN_ALREADY_IN_COIN_LIST);
        assert!(!coin_list::is_coin_in_list<piece_swap::LPToken<Y,X>>(admin_addr), E_LP_TOKEN_ALREADY_IN_COIN_LIST);

        let decimals = math::max((coin::decimals<X>() as u128), (coin::decimals<Y>() as u128));
        let decimals = (decimals as u8);

        piece_swap::create_new_pool<X, Y>(
            admin,
            lp_name,
            lp_symbol,
            decimals,
            k,
            w1_numerator,
            w1_denominator,
            w2_numerator,
            w2_denominator,
            swap_fee_per_million,
            protocol_fee_share_per_thousand,
        );

        coin_list::add_to_registry_by_signer<piece_swap::LPToken<X,Y>>(
            admin,
            string::utf8(lp_name),
            string::utf8(lp_symbol),
            string::utf8(vector::empty<u8>()),
            string::utf8(lp_logo_url),
            string::utf8(lp_project_url),
            false,
        );
        if (!coin_list::is_coin_in_list<X>(admin_addr)){
            coin_list::add_to_list<X>(admin);
        };
        if (!coin_list::is_coin_in_list<Y>(admin_addr)){
            coin_list::add_to_list<Y>(admin);
        };
        coin_list::add_to_list<piece_swap::LPToken<X,Y>>(admin);

    }

    #[cmd]
    public entry fun create_new_pool_script<X, Y>(
        admin: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        k: u128,
        w1_numerator: u128,
        w1_denominator: u128,
        w2_numerator: u128,
        w2_denominator: u128,
        swap_fee_per_million: u64,
        protocol_fee_share_per_thousand: u64,
    ) {
        create_new_pool<X, Y>(
            admin,
            lp_name,
            lp_symbol,
            b"",
            b"",
            k,
            w1_numerator,
            w1_denominator,
            w2_numerator,
            w2_denominator,
            swap_fee_per_million,
            protocol_fee_share_per_thousand,
        )
    }

    #[cmd]
    public entry fun add_liquidity_script<X, Y>(
        sender: &signer,
        amount_x: u64,
        amount_y: u64
    ) {
        piece_swap::add_liquidity<X,Y>(sender, amount_x, amount_y);
    }
    #[cmd]
    public entry fun remove_liquidity_script<X, Y>(
        sender: &signer,
        liquidity: u64,
    ) {
        piece_swap::remove_liquidity<X,Y>(sender, liquidity);
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
            let y_out = piece_swap::swap_x_to_y<X, Y>(sender, x_in);
            assert!(y_out >= y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else if (y_in > 0) {
            let x_out = piece_swap::swap_y_to_x<X, Y>(sender, y_in);
            assert!(x_out >= x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else {
            assert!(false, E_SWAP_NONZERO_INPUT_REQUIRED);
        }
    }

    #[cmd]
    public entry fun mock_deploy_script(admin: &signer) {

        let billion = 1000000000;
        create_new_pool_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetUSDC>(
            admin,
            b"USDT-USDC PieceSwap LP Token",
            b"USDT-USDC-PS_LP",
            billion * billion,
            110,
            100,
            105,
            100,
            100,
            100,
        );

        create_new_pool_script<devnet_coins::DevnetDAI, devnet_coins::DevnetUSDC>(
            admin,
            b"DAI-USDC PieceSwap LP Token",
            b"DAI-USDC-PS_LP",
            billion * billion,
            110,
            100,
            105,
            100,
            100,
            100,
        );

        // 3
        let initial_amount = 1000000 * 100000000;
        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDT>(admin, initial_amount);
        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDC>(admin, initial_amount);
        add_liquidity_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetUSDC>(admin, initial_amount, initial_amount);

        devnet_coins::mint_to_wallet<devnet_coins::DevnetDAI>(admin, initial_amount);
        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDC>(admin, initial_amount);
        add_liquidity_script<devnet_coins::DevnetDAI, devnet_coins::DevnetUSDC>(admin, initial_amount, initial_amount);
    }
    #[test_only]
    use hippo_swap::devcoin_util::init_registry_and_devnet_coins;

    #[test(admin=@hippo_swap, coin_list_admin = @coin_list)]
    public entry fun test_mock_deploy(admin: &signer, coin_list_admin: &signer) {
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        init_registry_and_devnet_coins(coin_list_admin);
        mock_deploy_script(admin);
    }

    #[test(admin=@hippo_swap, coin_list_admin = @coin_list)]
    public entry fun test_remove_liquidity(admin: &signer, coin_list_admin: &signer) {
        use aptos_framework::coin;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        init_registry_and_devnet_coins(coin_list_admin);
        /*
            1. mock_deploy
            2. remove liquidity
        */

        // 1
        mock_deploy_script(admin);

        // 2
        remove_liquidity_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetUSDC>(admin, 100);
        remove_liquidity_script<devnet_coins::DevnetDAI, devnet_coins::DevnetUSDC>(admin, 100);

        let admin_addr = signer::address_of(admin);
        assert!(coin::balance<devnet_coins::DevnetUSDT>(admin_addr) == 100, 0);
        assert!(coin::balance<devnet_coins::DevnetDAI>(admin_addr) == 100, 0);
        assert!(coin::balance<devnet_coins::DevnetUSDC>(admin_addr) == 200, 0);
    }

    #[test(admin=@hippo_swap, coin_list_admin = @coin_list, user=@0x1234567)]
    public entry fun test_swap(admin: &signer, coin_list_admin: &signer, user: &signer) {
        use coin_list::devnet_coins;
        use aptos_framework::coin;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(user));
        init_registry_and_devnet_coins(coin_list_admin);
        /*
            1. create pools
            2. swap x to y
            3. swap y to x
        */

        // 1
        mock_deploy_script(admin);

        // 2
        let usdt_amt = 10000000;
        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDT>(user, usdt_amt);
        swap_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetUSDC>(user, usdt_amt, 0, 0, usdt_amt * 999 / 1000);

        // 3
        let usdc_balance = coin::balance<devnet_coins::DevnetUSDC>(signer::address_of(user));
        swap_script<devnet_coins::DevnetDAI, devnet_coins::DevnetUSDC>(user, 0, usdc_balance, usdc_balance * 999 / 1000, 0);
        assert!(coin::balance<devnet_coins::DevnetUSDC>(signer::address_of(user)) == 0, 0);
        assert!(coin::balance<devnet_coins::DevnetUSDT>(signer::address_of(user)) == 0, 0);
        assert!(coin::balance<devnet_coins::DevnetDAI>(signer::address_of(user)) >= usdc_balance * 999 / 1000, 0);

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
            let y_out = piece_swap::swap_x_to_y<X, Y>(sender, x_in);
            assert!(y_out >= y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else if (y_in > 0) {
            let x_out = piece_swap::swap_y_to_x<X, Y>(sender, y_in);
            assert!(x_out >= x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else {
            assert!(false, E_SWAP_NONZERO_INPUT_REQUIRED);
        }
    }

}
}
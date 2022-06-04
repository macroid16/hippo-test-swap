address HippoSwap {
module PieceSwapScript {
    use Std::Signer;
    use HippoSwap::PieceSwap;
    use TokenRegistry::TokenRegistry;
    use AptosFramework::Coin;

    const E_SWAP_ONLY_ONE_IN_ALLOWED: u64 = 0;
    const E_SWAP_ONLY_ONE_OUT_ALLOWED: u64 = 1;
    const E_SWAP_NONZERO_INPUT_REQUIRED: u64 = 2;
    const E_OUTPUT_LESS_THAN_MIN: u64 = 3;
    const E_TOKEN_REGISTRY_NOT_INITIALIZED:u64 = 4;
    const E_TOKEN_X_NOT_REGISTERED:u64 = 5;
    const E_TOKEN_Y_NOT_REGISTERED:u64 = 6;
    const E_LP_TOKEN_ALREADY_REGISTERED:u64 = 7;

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
        lp_description: vector<u8>,
        lp_logo_url: vector<u8>,
        lp_project_url: vector<u8>,
        k: u128,
        w1_numerator: u128,
        w1_denominator: u128,
        w2_numerator: u128,
        w2_denominator: u128,
    ) {
        use HippoSwap::Math;

        let admin_addr = Signer::address_of(admin);
        assert!(TokenRegistry::is_registry_initialized(admin_addr), E_TOKEN_REGISTRY_NOT_INITIALIZED);
        assert!(TokenRegistry::has_token<X>(admin_addr), E_TOKEN_X_NOT_REGISTERED);
        assert!(TokenRegistry::has_token<Y>(admin_addr), E_TOKEN_Y_NOT_REGISTERED);
        assert!(!TokenRegistry::has_token<PieceSwap::LPToken<X,Y>>(admin_addr), E_LP_TOKEN_ALREADY_REGISTERED);
        assert!(!TokenRegistry::has_token<PieceSwap::LPToken<Y,X>>(admin_addr), E_LP_TOKEN_ALREADY_REGISTERED);

        let decimals = Math::max((Coin::decimals<X>() as u128), (Coin::decimals<Y>() as u128));
        let decimals = (decimals as u64);

        PieceSwap::create_new_pool<X, Y>(
            admin,
            lp_name,
            lp_symbol,
            decimals,
            k,
            w1_numerator,
            w1_denominator,
            w2_numerator,
            w2_denominator,
        );

        // register LP token to registry
        TokenRegistry::add_token<PieceSwap::LPToken<X,Y>>(
            admin,
            lp_name,
            lp_symbol,
            lp_description,
            (decimals as u8),
            lp_logo_url,
            lp_project_url,
        );
    }

    public(script) fun create_new_pool_script<X, Y>(
        admin: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        k: u128,
        w1_numerator: u128,
        w1_denominator: u128,
        w2_numerator: u128,
        w2_denominator: u128,
    ) {
        create_new_pool<X, Y>(
            admin,
            lp_name,
            lp_symbol,
            b"",
            b"",
            b"",
            k,
            w1_numerator,
            w1_denominator,
            w2_numerator,
            w2_denominator,
        )
    }

    public(script) fun add_liquidity_script<X, Y>(
        sender: &signer,
        amount_x: u64,
        amount_y: u64
    ) {
        PieceSwap::add_liquidity<X,Y>(sender, amount_x, amount_y);
    }
    public(script) fun remove_liquidity_script<X, Y>(
        sender: &signer,
        liquidity: u64,
    ) {
        PieceSwap::remove_liquidity<X,Y>(sender, liquidity);
    }
    public(script) fun swap_script<X, Y>(
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
            let y_out = PieceSwap::swap_x_to_y<X, Y>(sender, x_in);
            assert!(y_out >= y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else if (y_in > 0) {
            let x_out = PieceSwap::swap_y_to_x<X, Y>(sender, y_in);
            assert!(x_out >= x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
        else {
            assert!(false, E_SWAP_NONZERO_INPUT_REQUIRED);
        }
    }

    public(script) fun mock_deploy_script(admin: &signer) {
        use HippoSwap::MockDeploy;
        use HippoSwap::MockCoin;
        use HippoSwap::MockCoin::{WUSDC, WUSDT, WDAI};
        /*
        1. initialize registry
        2. initialize coins (and add them to registry)
        3. create token pairs
        4. adds liquidity
        */
        let admin_addr = Signer::address_of(admin);

        // 1
        if (!TokenRegistry::is_registry_initialized(admin_addr)) {
            // Std::Debug::print(&299999919999);
            // It's weird that the coverage does not mark the if branch.
            // Find the reason later from the compiler part of the aptos-core repo.
            TokenRegistry::initialize(admin);
        };

        // 2
        MockDeploy::init_coin_and_create_store<WUSDC>(admin, b"USDC", b"USDC", 8);
        MockDeploy::init_coin_and_create_store<WUSDT>(admin, b"USDT", b"USDT", 8);
        MockDeploy::init_coin_and_create_store<WDAI>(admin, b"DAI", b"DAI", 8);

        // 3
        let billion = 1000000000;
        create_new_pool_script<WUSDT, WUSDC>(
            admin,
            b"USDT-USDC PieceSwap LP Token",
            b"USDT-USDC-PS_LP",
            billion * billion,
            110,
            100,
            105,
            100,
        );

        create_new_pool_script<WDAI, WUSDC>(
            admin,
            b"DAI-USDC PieceSwap LP Token",
            b"DAI-USDC-PS_LP",
            billion * billion,
            110,
            100,
            105,
            100,
        );

        // 4
        let initial_amount = 1000000 * 100000000;
        MockCoin::faucet_mint_to<WUSDT>(admin, initial_amount);
        MockCoin::faucet_mint_to<WUSDC>(admin, initial_amount);
        add_liquidity_script<WUSDT, WUSDC>(admin, initial_amount, initial_amount);

        MockCoin::faucet_mint_to<WDAI>(admin, initial_amount);
        MockCoin::faucet_mint_to<WUSDC>(admin, initial_amount);
        add_liquidity_script<WDAI, WUSDC>(admin, initial_amount, initial_amount);
    }

    #[test(admin=@HippoSwap)]
    public(script) fun test_mock_deploy(admin: &signer) {
        mock_deploy_script(admin);
    }

    #[test(admin=@HippoSwap)]
    public(script) fun test_remove_liquidity(admin: &signer) {
        use HippoSwap::MockCoin::{WUSDC, WUSDT, WDAI};
        use AptosFramework::Coin;
        /*
        1. mock_deploy
        2. remove liquidity
        */
        mock_deploy_script(admin);

        // 2
        remove_liquidity_script<WUSDT, WUSDC>(admin, 100);
        remove_liquidity_script<WDAI, WUSDC>(admin, 100);

        let admin_addr = Signer::address_of(admin);
        assert!(Coin::balance<WUSDT>(admin_addr) == 100, 0);
        assert!(Coin::balance<WDAI>(admin_addr) == 100, 0);
        assert!(Coin::balance<WUSDC>(admin_addr) == 200, 0);
    }

    #[test(admin=@HippoSwap, user=@0x1234567)]
    public(script) fun test_swap(admin: &signer, user: &signer) {
        use HippoSwap::MockCoin;
        use HippoSwap::MockCoin::{WUSDC, WUSDT, WDAI};
        use AptosFramework::Coin;
        /*
        1. create pools
        2. swap x to y
        3. swap y to x
        */
        // 1
        mock_deploy_script(admin);

        // 2
        let usdt_amt = 10000000;
        MockCoin::faucet_mint_to<WUSDT>(user, usdt_amt);
        swap_script<WUSDT, WUSDC>(user, usdt_amt, 0, 0, usdt_amt * 999 / 1000);

        // 3
        let usdc_balance = Coin::balance<MockCoin::WUSDC>(Signer::address_of(user));
        swap_script<WDAI, WUSDC>(user, 0, usdc_balance, usdc_balance * 999 / 1000, 0);
        assert!(Coin::balance<WUSDC>(Signer::address_of(user)) == 0, 0);
        assert!(Coin::balance<WUSDT>(Signer::address_of(user)) == 0, 0);
        assert!(Coin::balance<WDAI>(Signer::address_of(user)) >= usdc_balance * 999 / 1000, 0);

    }
}
}
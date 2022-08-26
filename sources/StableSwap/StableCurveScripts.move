module hippo_swap::stable_curve_scripts {
    use std::string;
    use aptos_framework::timestamp;
    use hippo_swap::stable_curve_swap;
    use std::signer;
    use coin_list::coin_list;
    use aptos_framework::coin;
    use hippo_swap::math;
    use std::vector;

    const MICRO_CONVERSION_FACTOR: u64 = 1000000;

    const E_SWAP_ONLY_ONE_IN_ALLOWED: u64 = 0;
    const E_SWAP_ONLY_ONE_OUT_ALLOWED: u64 = 1;
    const E_SWAP_NONZERO_INPUT_REQUIRED: u64 = 2;
    const E_OUTPUT_LESS_THAN_MIN: u64 = 3;
    const E_TOKEN_REGISTRY_NOT_INITIALIZED: u64 = 4;

    const E_TOKEN_X_NOT_REGISTERED: u64 = 5;
    const E_TOKEN_Y_NOT_REGISTERED: u64 = 6;
    const E_LP_TOKEN_ALREADY_REGISTERED:u64 = 7;
    const E_LP_TOKEN_ALREADY_IN_COIN_LIST:u64 = 8;

    public fun create_new_pool<X, Y>(
        admin: &signer,
        lp_name: vector<u8>,
        lp_symbol: vector<u8>,
        lp_logo_url: vector<u8>,
        lp_project_url: vector<u8>,
        fee: u64,
        admin_fee: u64
    ) {

        let admin_addr = signer::address_of(admin);
        assert!(coin_list::is_registry_initialized(), E_TOKEN_REGISTRY_NOT_INITIALIZED);
        assert!(coin_list::is_coin_registered<X>(), E_TOKEN_X_NOT_REGISTERED);
        assert!(coin_list::is_coin_registered<Y>(), E_TOKEN_Y_NOT_REGISTERED);
        assert!(!coin_list::is_coin_registered<stable_curve_swap::LPToken<X,Y>>(), E_LP_TOKEN_ALREADY_REGISTERED);
        assert!(!coin_list::is_coin_registered<stable_curve_swap::LPToken<Y,X>>(), E_LP_TOKEN_ALREADY_REGISTERED);

        assert!(!coin_list::is_coin_in_list<stable_curve_swap::LPToken<X,Y>>(admin_addr), E_LP_TOKEN_ALREADY_IN_COIN_LIST);
        assert!(!coin_list::is_coin_in_list<stable_curve_swap::LPToken<Y,X>>(admin_addr), E_LP_TOKEN_ALREADY_IN_COIN_LIST);

        let block_timestamp = timestamp::now_microseconds();
        let future_time = block_timestamp + 24 * 3600 * MICRO_CONVERSION_FACTOR;

        let decimals = math::max((coin::decimals<X>() as u128), (coin::decimals<Y>() as u128));
        let decimals = (decimals as u8);

        stable_curve_swap::initialize<X, Y>(
            admin,
            string::utf8(lp_name),
            string::utf8(lp_symbol),
            decimals,
            60,
            80,
            block_timestamp,
            future_time,
            fee,
            admin_fee
        );


        coin_list::add_to_registry_by_signer<stable_curve_swap::LPToken<X,Y>>(
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
        coin_list::add_to_list<stable_curve_swap::LPToken<X,Y>>(admin);
    }

    #[cmd]
    public entry fun add_liquidity<X, Y>(sender: &signer, amount_x: u64, amount_y: u64) {
        stable_curve_swap::add_liquidity<X, Y>(sender, amount_x, amount_y);
    }

    #[cmd]
    public entry fun remove_liquidity<X, Y>(sender: &signer, liquidity: u64, min_amount_x: u64, min_amount_y: u64, ) {
        stable_curve_swap::remove_liquidity<X, Y>(sender, liquidity, min_amount_x, min_amount_y);
    }


    public fun swap<X, Y>(
        sender: &signer,
        x_in: u64,
        y_in: u64,
        x_min_out: u64,
        y_min_out: u64,
    ) {
        let cond_a = (x_in > 0 && y_in > 0);
        let cond_b = (x_in == 0 && y_in == 0);
        let cond_c = (x_min_out > 0 && y_min_out > 0);
        assert!(!(cond_a || cond_b), E_SWAP_ONLY_ONE_IN_ALLOWED);
        assert!(!cond_c, E_SWAP_ONLY_ONE_OUT_ALLOWED);
        let addr = signer::address_of(sender);
        if (x_in > 0) {
            let (_, _, out_amount) = stable_curve_swap::swap_x_to_exact_y<X, Y>(sender, x_in, addr);
            assert!(out_amount > y_min_out, E_OUTPUT_LESS_THAN_MIN);
        }  else {
            let (_, out_amount, _) = stable_curve_swap::swap_y_to_exact_x<X, Y>(sender, y_in, addr);
            assert!(out_amount > x_min_out, E_OUTPUT_LESS_THAN_MIN);
        }
    }

    #[cmd]
    public entry fun swap_script<X, Y>(
        sender: &signer,
        x_in: u64,
        y_in: u64,
        x_min_out: u64,
        y_min_out: u64,
    ) {
        swap<X, Y>(sender, x_in, y_in, x_min_out, y_min_out)
    }

    fun mock_create_pair_and_add_liquidity<X, Y>(
        admin: &signer,
        symbol: vector<u8>,
        fee: u64,
        admin_fee: u64,
        left_amt: u64,
        right_amt: u64,
        lp_amt: u64,
    ) {
        // 1. create pair(pool)
        let admin_addr = signer::address_of(admin);
        let name = string::utf8(symbol);
        let (initial_A, future_A) = (60, 100);
        let initial_A_time = timestamp::now_microseconds();
        let future_A_time = initial_A_time + 24 * 3600 * MICRO_CONVERSION_FACTOR;
        // std::debug::print(&199928828);
        // It's weird that the coverage does not mark the if branch.
        // Find the reason later from the compiler part of the aptos-core repo.
        let decimals = math::max((coin::decimals<X>() as u128), (coin::decimals<Y>() as u128));
        let decimals = (decimals as u8);
        stable_curve_swap::initialize<X, Y>(
            admin, name, name, decimals, initial_A, future_A, initial_A_time, future_A_time, fee, admin_fee
        );
        coin_list::add_to_registry_by_signer<stable_curve_swap::LPToken<X,Y>>(
            admin,
            string::utf8(symbol),
            string::utf8(symbol),
            string::utf8(vector::empty<u8>()),
            string::utf8(vector::empty<u8>()),
            string::utf8(vector::empty<u8>()),
            false,
        );
        if (!coin_list::is_coin_in_list<X>(admin_addr)){
            coin_list::add_to_list<X>(admin);
        };
        if (!coin_list::is_coin_in_list<Y>(admin_addr)){
            coin_list::add_to_list<Y>(admin);
        };
        coin_list::add_to_list<stable_curve_swap::LPToken<X,Y>>(admin);

        // 2. add liquidity
        let some_x = devnet_coins::mint<X>(left_amt);
        let some_y = devnet_coins::mint<Y>(right_amt);

        let (unused_x, unused_y, some_lp) = stable_curve_swap::add_liquidity_direct(some_x, some_y);

        assert!(coin::value(&some_lp) == lp_amt, 5);
        devnet_coins::deposit(admin,unused_x);
        devnet_coins::deposit(admin,unused_y);
        devnet_coins::deposit(admin,some_lp);
    }

    #[cmd]
    public entry fun mock_deploy_script(admin: &signer) {
        let (fee, admin_fee) = (3000, 200000);
        let coin_amt = 1000000000;
        mock_create_pair_and_add_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(
            admin,
            b"USDC-USDT-CURVE-LP",
            fee, admin_fee,
            coin_amt * 100,
            coin_amt * 100,
            200000000000
        );
        mock_create_pair_and_add_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetSOL>(
            admin,
            b"USDC-DAI-CURVE-LP",
            fee, admin_fee,
            coin_amt * 100,
            coin_amt * 100,
            200000000000
        );
    }
    #[test_only]
    use std::vector;
    use coin_list::devnet_coins;
    #[test_only]
    use hippo_swap::devcoin_util::init_registry_and_devnet_coins;

    #[test_only]
    fun start_up(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        use aptos_framework::coin;
        use coin_list::devnet_coins;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(user));
        init_registry_and_devnet_coins(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);

        create_new_pool<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(
            admin,
            b"Curve:WUSDT-WDAI",
            b"WUWD",
            b"",
            b"",
            3000, // 0.3 %
            200000, // 20 % from lp_fee -> 0.06 %
        );
        let x = devnet_coins::mint<devnet_coins::DevnetUSDT>(100000000);
        let y = devnet_coins::mint<devnet_coins::DevnetSOL>(100000000);
        let trader_addr = signer::address_of(user);
        coin::register<devnet_coins::DevnetUSDT>(user);
        coin::register<devnet_coins::DevnetSOL>(user);
        coin::register<stable_curve_swap::LPToken<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>>(user);
        coin::deposit(trader_addr, x);
        coin::deposit(trader_addr, y);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, user = @0x1234567, core = @aptos_framework)]
    fun test_scripts(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        start_up(admin, coin_list_admin, user, core);

        add_liquidity<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 10000000, 20000000);
        swap_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 2000000, 0, 0, 100);
        swap_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 0, 2000000, 110, 0);
        remove_liquidity<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 400000, 100, 100);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, user = @0x1234567, core = @aptos_framework)]
    #[expected_failure(abort_code = 0)]
    fun test_failx(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        start_up(admin, coin_list_admin, user, core);

        add_liquidity<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 10000000, 20000000);
        swap_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 0, 0, 0, 100);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, user = @0x1234567, core = @aptos_framework)]
    #[expected_failure(abort_code = 1)]
    fun test_faily(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        start_up(admin, coin_list_admin, user, core);

        add_liquidity<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 10000000, 20000000);
        swap_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 120, 0, 10, 10);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, user = @0x1234567, core = @aptos_framework)]
    #[expected_failure(abort_code = 3)]
    fun test_fail_output_less_x(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        start_up(admin, coin_list_admin, user, core);

        add_liquidity<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 20000000, 20000000);
        swap_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 1, 0, 0, 100000000000);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, user = @0x1234567, core = @aptos_framework)]
    #[expected_failure(abort_code = 3)]
    fun test_fail_output_less_y(admin: &signer, coin_list_admin: &signer, user: &signer, core: &signer) {
        start_up(admin, coin_list_admin, user, core);

        add_liquidity<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 20000000, 20000000);
        swap_script<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(user, 0, 1, 10000000000, 0);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, core = @aptos_framework)]
    fun test_mock_deploy(admin: &signer, coin_list_admin: &signer, core: &signer) {
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        init_registry_and_devnet_coins(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);

        mock_deploy_script(admin);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, user = @0x1234567, core = @aptos_framework)]
    #[expected_failure(abort_code = 5)]
    fun fail_lp_amt(admin: &signer, coin_list_admin: &signer, core: &signer) {
        // mock depoly
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        init_registry_and_devnet_coins(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);

        mock_deploy_script(admin);

        let btc_amt = 1000000000;
        let (fee, admin_fee) = (3000, 200000);
        std::debug::print(&110000000);
        mock_create_pair_and_add_liquidity<devnet_coins::DevnetUSDT, devnet_coins::DevnetSOL>(
            admin,
            b"USDT-DAI-LP",
            fee, admin_fee,
            btc_amt,
            btc_amt * 10000,
            32001352823
        )
    }

    #[test_only]
    public fun assert_launch_lq(admin: &signer, coin_list_admin: &signer, core: &signer, amt_x: u64, amt_y: u64, lp_predict: u64) {
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        init_registry_and_devnet_coins(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);
        let (fee, admin_fee) = (3000, 200000);
        // the A value was initialed with 60.
        mock_create_pair_and_add_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(
            admin, b"USDC-USDT-LP", fee, admin_fee, amt_x, amt_y, lp_predict
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_validate_basic(admin: &signer, coin_list_admin: &signer, core: &signer) {
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        init_registry_and_devnet_coins(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);
        let usdc_amt = 500000000;
        let usdt_amt = 500000000;
        let (fee, admin_fee) = (3000, 200000);
        // Init with (5, 5) price unit of (x, y), which is the ideal balance and mint lp_token of 10 units.
        // Fee-free for the first investment.
        mock_create_pair_and_add_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(
            admin, b"USDC-USDT-LP", fee, admin_fee, usdc_amt, usdt_amt, 1000000000
        );
        let (_, _, _, _, _, lp_precision, multiplier_x, multiplier_y, _, _,
            _, _, _, _) = stable_curve_swap::get_pool_info<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>();

        assert!(lp_precision == 8, 2);  // 10 ** 8 , which is equal to the larger value between x and y.
        assert!(multiplier_x == 1, 2);                // the scaling factor of x and y is 1 because they share the same decimals.
        assert!(multiplier_y == 1, 2);
        stable_curve_swap::remove_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin, 100000000, 100000, 100000);
        let admin_addr = signer::address_of(admin);
        let balance_x = coin::balance<devnet_coins::DevnetUSDC>(admin_addr);
        let balance_y = coin::balance<devnet_coins::DevnetUSDT>(admin_addr);
        assert!(balance_x == 50000000, 3);
        assert!(balance_y == 50000000, 3);
    }

    // Let's make initial value of x and y 10 times of the former test. We'll get lp_token of the corresponding factor.
    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_validate_scale(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 5000000000, 5000000000, 10000000000)
    }


    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    #[expected_failure]             //  ARITHMETIC_ERROR:  let new_d = (ann * s + d_p * 2) __*__ d / ((ann - 1) * d + 3 * d_p)
    public fun test_data_set_max_level(admin: &signer, coin_list_admin: &signer, core: &signer) {
        init_registry_and_devnet_coins(coin_list_admin);
        timestamp::set_time_has_started_for_testing(core);
        let usdc_amt = 5 * 100000000 * 10000000000;
        // 10 ** 10 of 8 decimal coin will cause the digits overflow from the optimized get_D_origin method.
        // The capacity will be much lower if using the get_D_improved or get_D_newton_method which are mathematically equivalent.
        let usdt_amt = 5 * 100000000 * 10000000000;
        let (fee, admin_fee) = (3000, 200000);
        mock_create_pair_and_add_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(
            admin, b"USDC-USDT-LP", fee, admin_fee, usdc_amt, usdt_amt,
            10 * 100000000 * 10000000000
        );
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_init_imbalance(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 40 * 100000000, 60 * 100000000, 9996588165); // Slightly less than 100 * 100000000
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_init_tiny_q(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 40, 60, 99);
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_init_tiny_qr_1(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 30, 70, 99);
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_init_tiny_qr_2(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 10, 90, 98);
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_init_tiny_qr_3(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 1, 99, 86);
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_init_small_qr_1(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 100, 9900, 8690);
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_init_small_qr_2(admin: &signer, coin_list_admin: &signer, core: &signer) {
        assert_launch_lq(admin, coin_list_admin, core, 1, 9999, 3199);
    }

    #[test(admin = @hippo_swap,coin_list_admin = @coin_list, core = @aptos_framework)]
    public fun test_data_set_trade_proc(admin: &signer, coin_list_admin: &signer, core: &signer) {
        let admin_addr = signer::address_of(admin);
        assert_launch_lq(admin, coin_list_admin, core, 500000, 500000, 1000000);
        // let balance = coin::balance<LPToken<Mockcoin::WUSDC, Mockcoin::WUSDT>>(admin_addr);
        let balance = stable_curve_swap::balance<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin_addr);
        assert!(balance == 1000000, 1);
        // let (fee_x, fee_y) = StableCurveSwap::get_fee_reserves<Mockcoin::WUSDC, Mockcoin::WUSDT>();

        // The second investment;

        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDC>(admin, 500000);
        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDT>(admin, 1000000);
        stable_curve_swap::add_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin, 500000, 1000000);

        // check intermediate data add_liquidity_direct:
        // d1: 2499147, d0: 1000000
        // calc_reserve_and_fees:
        // ideal_reserve: 1249573,
        // old_reserve_x: 500000, new_reserve_x: 1000000, differenct_x: 249573, fee_x: 374, admin_fee_x: 74
        // old_reserve_y: 500000, new_reserve_y: 1500000 differenct_y: 250427, fee_y: 375, admin_fee_y: 75
        // d2: 2498397      // which was caculated from the amount of coin x after fee (including lp&admin) charged,
        // existed lp_token ( token_supply ): 1000000
        // mint_amount: 1498397
        // reserve_x:  999926 - 500000 = 499926 ( increased including the lp_fee(300), the increase of value of the stake holder), the amount of the part minted is 499626
        // reserve_y:  1499925 - 500000 = 999925 ( increased including the lp_fee(300), the increase of value of the stake holder), the amount of the part minted is 1499625
        // now the token_supply increased to 2498397

        let balance = stable_curve_swap::balance<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin_addr);
        // std::debug::print(&balance);
        // 1500000 incoming currencies totally brings 1498397 lp.
        assert!(balance == 2498397, 1);
        let (_, _, _, fee_amt_x, fee_amt_y, _, _, _, _, _, _, _, _, _) = stable_curve_swap::get_pool_info<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>();

        assert!(fee_amt_x == 74, 1);
        assert!(fee_amt_y == 75, 1);

        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDC>(admin, 200000);
        stable_curve_swap::swap_x_to_exact_y<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin, 200000, admin_addr);

        let balance = coin::balance<devnet_coins::DevnetUSDT>(admin_addr);

        assert!(balance == 200217, 1);
        let (_, _, _, fee_amt_x, fee_amt_y, _, _, _, _, _, _, _, _, _) = stable_curve_swap::get_pool_info<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>();

        assert!(fee_amt_x == 74, 1);
        assert!(fee_amt_y == 195, 1); // increased 120 = 200000 * 0.003 * 0.2


        stable_curve_swap::swap_y_to_exact_x<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin, 200000, admin_addr);

        let balance = coin::balance<devnet_coins::DevnetUSDC>(admin_addr);

        assert!(balance == 198587, 1);      // nearly 2 % loss
        let (_, _, _, fee_x, fee_y, _, _, _, _, _, _, _, _, _) = stable_curve_swap::get_pool_info<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>();
        assert!(fee_x == 193, 1);
        assert!(fee_y == 195, 1);


        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDC>(admin, 20000000);
        stable_curve_swap::swap_x_to_exact_y<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin, 20000000, admin_addr);

        let balance = coin::balance<devnet_coins::DevnetUSDT>(admin_addr);

        assert!(balance == 1495223, 1); // Seems that the pool was exhausted, and the lp earn a lot.
        let (_, _, _, fee_x, fee_y, _, _, _, _, _, _, _, _, _) = stable_curve_swap::get_pool_info<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>();
        assert!(fee_x == 193, 1);
        assert!(fee_y == 1094, 1);

        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDC>(admin, 50000000);
        devnet_coins::mint_to_wallet<devnet_coins::DevnetUSDT>(admin, 10000000);
        stable_curve_swap::add_liquidity<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin, 50000000, 10000000);

        let balance = stable_curve_swap::balance<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>(admin_addr);

        assert!(balance == 25338477, 1);
        let (_, _, _, fee_x, fee_y, _, _, _, _, _, _, _, _, _) = stable_curve_swap::get_pool_info<devnet_coins::DevnetUSDC, devnet_coins::DevnetUSDT>();
        assert!(fee_x == 42969, 1);
        assert!(fee_y == 4083, 1);
    }
}

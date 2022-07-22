address hippo_swap {
module router {
    use aptos_framework::coin;
    use std::signer;
    use hippo_swap::cp_swap;
    use hippo_swap::stable_curve_swap;
    use hippo_swap::piece_swap;

    const POOL_TYPE_CONSTANT_PRODUCT:u8 = 1;
    const POOL_TYPE_STABLE_CURVE:u8 = 2;
    const POOL_TYPE_PIECEWISE:u8 = 3;

    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_OUTPUT_LESS_THAN_MINIMUM: u64 = 2;

    #[noke]
    public fun get_intermediate_output<X, Y>(pool_type: u8, is_x_to_y: bool, x_in: coin::Coin<X>): coin::Coin<Y> {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            if (is_x_to_y) {
                let (x_out, y_out) = cp_swap::swap_x_to_exact_y_direct<X, Y>(x_in);
                coin::destroy_zero(x_out);
                y_out
            }
            else {
                let (y_out, x_out) = cp_swap::swap_y_to_exact_x_direct<Y, X>(x_in);
                coin::destroy_zero(x_out);
                y_out
            }
        }
        else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            if (is_x_to_y) {
                let (zero, zero2, y_out) = stable_curve_swap::swap_x_to_exact_y_direct<X, Y>(x_in);
                coin::destroy_zero(zero);
                coin::destroy_zero(zero2);
                y_out
            }
            else {
                let (zero, y_out, zero2) = stable_curve_swap::swap_y_to_exact_x_direct<Y, X>(x_in);
                coin::destroy_zero(zero);
                coin::destroy_zero(zero2);
                y_out
            }
        }
        else if (pool_type == POOL_TYPE_PIECEWISE) {
            if (is_x_to_y) {
                let y_out = piece_swap::swap_x_to_y_direct<X, Y>(x_in);
                y_out
            }
            else {
                let y_out = piece_swap::swap_y_to_x_direct<Y, X>(x_in);
                y_out
            }
        }
        else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    /*
    Execute 2 swap actions back-to-back.
    Swaps X to Y to Z
    so X,Y,Z are arranged in swap order, not pool order
    */
    public fun two_step_route<X, Y, Z>(
        sender: &signer,
        first_pool_type: u8,
        first_is_x_to_y: bool, // first trade uses normal order
        second_pool_type: u8,
        second_is_x_to_y: bool, // whether second trade uses normal order
        x_in: u64,
        z_min_out: u64,
    ): u64 {
        let coin_x = coin::withdraw<X>(sender, x_in);
        let coin_y = get_intermediate_output<X, Y>(first_pool_type, first_is_x_to_y, coin_x);

        let coin_z = get_intermediate_output<Y, Z>(second_pool_type, second_is_x_to_y, coin_y);

        let coin_z_amt = coin::value(&coin_z);

        assert!(coin_z_amt >= z_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        let sender_addr = signer::address_of(sender);
        if (!coin::is_account_registered<Z>(sender_addr)) {
            coin::register_internal<Z>(sender);
        };
        coin::deposit(sender_addr, coin_z);
        coin_z_amt
    }

    public entry fun two_step_route_script<X, Y, Z>(
        sender: &signer,
        first_pool_type: u8,
        first_is_x_to_y: bool, // first trade uses normal order
        second_pool_type: u8,
        second_is_x_to_y: bool, // whether second trade uses normal order
        x_in: u64,
        z_min_out: u64,
    ) {
        two_step_route<X, Y, Z>(
            sender,
            first_pool_type,
            first_is_x_to_y,
            second_pool_type,
            second_is_x_to_y,
            x_in,
            z_min_out,
        );
    }

    /*
    Execute 3 swap actions back-to-back.
    Swaps X to Y to Z to A
    so X,Y,Z are arranged in swap order, not pool order
    */
    public fun three_step_route<X, Y, Z, A>(
        sender: &signer,
        first_pool_type: u8,
        first_is_x_to_y: bool, // whether first trade uses normal order
        second_pool_type: u8,
        second_is_x_to_y: bool, // whehter second trade uses normal order
        third_pool_type: u8,
        third_is_x_to_y: bool, // whether third trade uses normal order
        x_in: u64,
        a_min_out: u64,
    ) {
        let coin_x = coin::withdraw<X>(sender, x_in);
        let coin_y = get_intermediate_output<X, Y>(first_pool_type, first_is_x_to_y, coin_x);
        let coin_z = get_intermediate_output<Y, Z>(second_pool_type, second_is_x_to_y, coin_y);
        let coin_a = get_intermediate_output<Z, A>(third_pool_type, third_is_x_to_y, coin_z);
        assert!(coin::value(&coin_a) >= a_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        let sender_addr = signer::address_of(sender);
        if (!coin::is_account_registered<A>(sender_addr)) {
            coin::register_internal<A>(sender);
        };
        coin::deposit(sender_addr, coin_a);
    }

    public entry fun three_step_route_script<X, Y, Z, A>(
        sender: &signer,
        first_pool_type: u8,
        first_is_x_to_y: bool, // whether first trade uses normal order
        second_pool_type: u8,
        second_is_x_to_y: bool, // whehter second trade uses normal order
        third_pool_type: u8,
        third_is_x_to_y: bool, // whether third trade uses normal order
        x_in: u64,
        a_min_out: u64,
    ) {
        three_step_route<X, Y, Z, A>(
            sender,
            first_pool_type,
            first_is_x_to_y,
            second_pool_type,
            second_is_x_to_y,
            third_pool_type,
            third_is_x_to_y,
            x_in,
            a_min_out,
        )
    }

    #[test_only]
    use aptos_framework::timestamp;
    #[test_only]
    use hippo_swap::piece_swap_script;
    #[test_only]
    use hippo_swap::cp_scripts;
    #[test_only]
    use hippo_swap::mock_coin;

    #[test(admin=@hippo_swap, user=@0x12345, core=@aptos_framework)]
    public entry fun test_two_step(admin: &signer, user: &signer, core: &signer) {
        timestamp::set_time_has_started_for_testing(core);
        // 1
        // creates BTC-USDC and BTC-USDT
        cp_scripts::mock_deploy_script(admin);
        // creates USDT-USDC and DAI-USDC
        piece_swap_script::mock_deploy_script(admin);

        // mint some BTC to user first
        let btc_amount = 100;
        mock_coin::faucet_mint_to<mock_coin::WBTC>(user, btc_amount);

        two_step_route_script<mock_coin::WBTC, mock_coin::WUSDC, mock_coin::WUSDT>(
            user,
            POOL_TYPE_CONSTANT_PRODUCT,
            true,
            POOL_TYPE_PIECEWISE,
            false,
            btc_amount,
            0
        );

        let user_addr = signer::address_of(user);

        assert!(coin::balance<mock_coin::WBTC>(user_addr) == 0, 0);
        assert!(!coin::is_account_registered<mock_coin::WUSDC>(user_addr), 0);
        assert!(coin::balance<mock_coin::WUSDT>(user_addr) >= btc_amount * 10000 * 99 / 100, 0);
        assert!(coin::balance<mock_coin::WUSDT>(user_addr) <= btc_amount * 10000, 0);
    }

    #[test(admin=@hippo_swap, user=@0x12345, core=@aptos_framework)]
    public entry fun test_three_step(admin: &signer, user: &signer, core: &signer) {
        timestamp::set_time_has_started_for_testing(core);
        // 1
        // creates BTC-USDC and BTC-USDT
        cp_scripts::mock_deploy_script(admin);
        // creates USDT-USDC and DAI-USDC
        piece_swap_script::mock_deploy_script(admin);

        // DAI -> USDC -> USDT -> BTC
        // mint some BTC to user first
        let dai_amount = 10000000;
        mock_coin::faucet_mint_to<mock_coin::WDAI>(user, dai_amount);

        three_step_route_script<mock_coin::WDAI, mock_coin::WUSDC, mock_coin::WUSDT, mock_coin::WBTC>(
            user,
            POOL_TYPE_PIECEWISE, // dai to usdc
            true,
            POOL_TYPE_PIECEWISE, // usdc to usdt
            false,
            POOL_TYPE_CONSTANT_PRODUCT, // usdt to btc
            false,
            dai_amount,
            0
        );

        let user_addr = signer::address_of(user);

        assert!(coin::balance<mock_coin::WDAI>(user_addr) == 0, 0);
        assert!(!coin::is_account_registered<mock_coin::WUSDC>(user_addr), 0);
        assert!(!coin::is_account_registered<mock_coin::WUSDT>(user_addr), 0);
        assert!(coin::balance<mock_coin::WBTC>(user_addr) >= dai_amount / 10000 * 99 / 100, 0);
        assert!(coin::balance<mock_coin::WBTC>(user_addr) <= dai_amount / 10000, 0);
    }

    // Extra utilities.

    public fun add_liquidity_route<X, Y>(signer: &signer, pool_type: u8, amount_x: u64, amount_y: u64):(u64, u64, u64) {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            cp_swap::add_liquidity<X, Y>(signer, amount_x, amount_y)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            stable_curve_swap::add_liquidity<X, Y>(signer, amount_x, amount_y)
        } else if ( pool_type == POOL_TYPE_PIECEWISE) {
            piece_swap::add_liquidity<X, Y>(signer, amount_x, amount_y)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }

    public fun remove_liquidity_route<X, Y>(signer: &signer, pool_type: u8, liquidity: u64, amount_x_min: u64, amount_y_min: u64):(u64, u64) {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            cp_swap::remove_liquidity<X, Y>(signer, liquidity, amount_x_min, amount_y_min)
        } else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            stable_curve_swap::remove_liquidity<X, Y>(signer, liquidity, amount_x_min, amount_y_min)
        } else if ( pool_type == POOL_TYPE_PIECEWISE) {
            piece_swap::remove_liquidity<X, Y>(signer, liquidity)
        } else {
            abort E_UNKNOWN_POOL_TYPE
        }
    }
}
}

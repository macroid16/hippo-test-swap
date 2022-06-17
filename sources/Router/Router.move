address HippoSwap {
module Router {
    use AptosFramework::Coin;
    use Std::Signer;
    use HippoSwap::CPSwap;
    use HippoSwap::StableCurveSwap;

    const POOL_TYPE_CONSTANT_PRODUCT:u8 = 1;
    const POOL_TYPE_STABLE_CURVE:u8 = 2;

    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_OUTPUT_LESS_THAN_MINIMUM: u64 = 2;

    public fun get_intermediate_output<X, Y>(pool_type: u8, is_x_to_y: bool, x_in: Coin::Coin<X>): Coin::Coin<Y> {
        if (pool_type == POOL_TYPE_CONSTANT_PRODUCT) {
            if (is_x_to_y) {
                let (x_out, y_out) = CPSwap::swap_x_to_exact_y_direct<X, Y>(x_in);
                Coin::destroy_zero(x_out);
                y_out
            }
            else {
                let (y_out, x_out) = CPSwap::swap_y_to_exact_x_direct<Y, X>(x_in);
                Coin::destroy_zero(x_out);
                y_out
            }
        }
        else if (pool_type == POOL_TYPE_STABLE_CURVE) {
            if (is_x_to_y) {
                let (zero, zero2, y_out) = StableCurveSwap::swap_x_to_exact_y_direct<X, Y>(x_in);
                Coin::destroy_zero(zero);
                Coin::destroy_zero(zero2);
                y_out
            }
            else {
                let (zero, y_out, zero2) = StableCurveSwap::swap_y_to_exact_x_direct<Y, X>(x_in);
                Coin::destroy_zero(zero);
                Coin::destroy_zero(zero2);
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
    ) {
        let coin_x = Coin::withdraw<X>(sender, x_in);
        let coin_y = get_intermediate_output<X, Y>(first_pool_type, first_is_x_to_y, coin_x);

        let coin_z = get_intermediate_output<Y, Z>(second_pool_type, second_is_x_to_y, coin_y);

        assert!(Coin::value(&coin_z) >= z_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        let sender_addr = Signer::address_of(sender);
        if (!Coin::is_account_registered<Z>(sender_addr)) {
            Coin::register_internal<Z>(sender);
        };
        Coin::deposit(sender_addr, coin_z);
    }

    public(script) fun two_step_route_script<X, Y, Z>(
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
        )
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
        let coin_x = Coin::withdraw<X>(sender, x_in);
        let coin_y = get_intermediate_output<X, Y>(first_pool_type, first_is_x_to_y, coin_x);
        let coin_z = get_intermediate_output<Y, Z>(second_pool_type, second_is_x_to_y, coin_y);
        let coin_a = get_intermediate_output<Z, A>(third_pool_type, third_is_x_to_y, coin_z);
        assert!(Coin::value(&coin_a) >= a_min_out, E_OUTPUT_LESS_THAN_MINIMUM);
        let sender_addr = Signer::address_of(sender);
        if (!Coin::is_account_registered<A>(sender_addr)) {
            Coin::register_internal<A>(sender);
        };
        Coin::deposit(sender_addr, coin_a);
    }

    public(script) fun three_step_route_script<X, Y, Z, A>(
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
    use AptosFramework::Timestamp;
    #[test_only]
    use HippoSwap::StableCurveScripts;
    #[test_only]
    use HippoSwap::CPScripts;
    #[test_only]
    use HippoSwap::MockCoin;

    #[test(admin=@HippoSwap, user=@0x12345, core=@0xa550c18)]
    public(script) fun test_two_step(admin: &signer, user: &signer, core: &signer) {
        Timestamp::set_time_has_started_for_testing(core);
        // 1
        // creates BTC-USDC and BTC-USDT
        CPScripts::mock_deploy_script(admin);
        // creates USDC-USDT and USDC-DAI
        StableCurveScripts::mock_deploy_script(admin);

        // mint some BTC to user first
        let btc_amount = 100;
        MockCoin::faucet_mint_to<MockCoin::WBTC>(user, btc_amount);

        two_step_route<MockCoin::WBTC, MockCoin::WUSDC, MockCoin::WUSDT>(
            user,
            POOL_TYPE_CONSTANT_PRODUCT,
            true,
            POOL_TYPE_STABLE_CURVE,
            true,
            btc_amount,
            0
        );


    }
}
}

#[test_only]
module hippo_swap::curve_test {
    use coin_list::devnet_coins::{DevnetUSDC as WUSDC, DevnetSOL as WDAI};
    use hippo_swap::TestShared;
    use hippo_swap::router;
    use hippo_swap::stable_curve_scripts;
    use hippo_swap::devcoin_util;

    // Keep the consts the same with TestShared.move.


    const ADMIN: address = @hippo_swap;
    const INVESTOR: address = @0x2FFF;
    const SWAPPER: address = @0x2FFE;

    const POOL_TYPE_CONSTANT_PRODUCT: u8 = 1;
    const POOL_TYPE_STABLE_CURVE: u8 = 2;
    const POOL_TYPE_PIECEWISE: u8 = 3;

    const E_NOT_IMPLEMENTED: u64 = 0;
    const E_UNKNOWN_POOL_TYPE: u64 = 1;
    const E_BALANCE_PREDICTION: u64 = 2;

    // 10 to the power of n.
    const P3: u64 = 1000;
    const THOUSAND: u64 = 1000;
    const P4: u64 = 10000;
    const P5: u64 = 100000;
    const P6: u64 = 1000000;
    const MILLION: u64 = 1000000;
    const P7: u64 = 10000000;
    const P8: u64 = 100000000;
    const P9: u64 = 1000000000;
    const BILLION: u64 = 1000000000;
    const P10: u64 = 10000000000;
    const P11: u64 = 100000000000;
    const P12: u64 = 1000000000000;
    const TRILLION: u64 = 1000000000000;
    const P13: u64 = 10000000000000;
    const P14: u64 = 100000000000000;
    const P15: u64 = 1000000000000000;
    const P16: u64 = 10000000000000000;
    const P17: u64 = 100000000000000000;
    const P18: u64 = 1000000000000000000;
    const P19: u64 = 10000000000000000000;

    const LABEL_SAVE_POINT: u128 = 333000000000000000000000000000000000000;
    const LABEL_RESERVE_XY: u128 = 333000000000000000000000000000000000001;
    const LABEL_FEE: u128 = 333000000000000000000000000000000000002;
    const LABEL_LPTOKEN_SUPPLY: u128 = 333000000000000000000000000000000000003;

    const INC: u8 = 0;
    const DEC: u8 = 1;

    const ADD_LIQUIDITY: u8 = 0;
    const SWAP: u8 = 1;
    const REMOVE_LIQUIDITY: u8 = 2;

    // Keep the consts the same with TestShared.move.

    struct PoolDelta has drop {
        sx: u8,
        sy: u8,
        slp: u8,
        sfx: u8,
        sfy: u8,
        sflp: u8,
        // sign_reserve_x, ... sign_fee_x, sign_fee_y, sign_fee_lp
        dx: u64,
        dy: u64,
        dlp: u64,
        dfx: u64,
        dfy: u64,
        dflp: u64,
        // delta_reserve_x, ... delta_fee_lp,
    }

    struct WalletDelta has drop {
        sx: u8,
        sy: u8,
        slp: u8,
        // signs
        dx: u64,
        dy: u64,
        dlp: u64              // delta values
    }

    struct TransactionParams has drop {
        amt_x: u64,
        // amount x in value
        amt_y: u64,
        // amount y in value
        amt_lp: u64,
        // amount lp in value
        p: PoolDelta,
        // expected pool delta values
        w: WalletDelta,
        // expected wallet delta values
    }

    #[test_only]
    fun new_transaction_param(
        amt_x: u64, amt_y: u64, amt_lp: u64,
        sx: u8, sy: u8, slp: u8, sfx: u8, sfy: u8, sflp: u8,
        dx: u64, dy: u64, dlp: u64, dfx: u64, dfy: u64, dflp: u64,
        wsx: u8, wsy: u8, wslp: u8,
        wdx: u64, wdy: u64, wdlp: u64
    ): TransactionParams {
        TransactionParams{
            amt_x, amt_y, amt_lp,
            p: PoolDelta{
                sx, sy, slp, sfx, sfy, sflp,
                dx, dy, dlp, dfx, dfy, dflp
            },
            w: WalletDelta{
                sx: wsx, sy: wsy, slp: wslp,
                dx: wdx, dy: wdy, dlp: wdlp
            },
        }
    }

    #[test_only]
    fun add_param(
        amt_x: u64, amt_y: u64, dx: u64, dy: u64, dlp: u64, dfx: u64, dfy: u64
    ): TransactionParams {
        TransactionParams{
            amt_x, amt_y, amt_lp: 0,
            p: PoolDelta{
                sx: INC, sy: INC, slp: INC, sfx: INC, sfy: INC, sflp: INC,
                dx, dy, dlp, dfx, dfy, dflp: 0
            },
            w: WalletDelta{
                sx: DEC, sy: DEC, slp: INC,
                dx: amt_x, dy: amt_y, dlp
            },
        }
    }

    #[test_only]
    fun swap_param(
        amt_x: u64, amt_y: u64, dx: u64, dy: u64, dfx: u64, dfy: u64, receive_amt: u64
    ): TransactionParams {
        let (sx, sy, wdx, wdy): (u8, u8, u64, u64);
        if (amt_x>0) {
            (sx, sy, wdx, wdy) = (INC, DEC, amt_x, receive_amt);
        } else {
            (sx, sy, wdx, wdy) = (DEC, INC, receive_amt, amt_y);
        };
        TransactionParams{
            amt_x, amt_y, amt_lp: 0,
            p: PoolDelta{
                sx, sy, slp: INC, sfx: INC, sfy: INC, sflp: INC,
                dx, dy, dlp: 0, dfx, dfy, dflp: 0
            },
            w: WalletDelta{
                sx: sy, sy: sx, slp: INC,
                dx: wdx, dy: wdy, dlp: 0
            },
        }
    }

    #[test_only]
    fun remove_param(
        amt_lp: u64, dx: u64, dy: u64
    ): TransactionParams {
        TransactionParams{
            amt_x: 0, amt_y: 0, amt_lp,
            p: PoolDelta{
                sx: DEC, sy: DEC, slp: DEC, sfx: DEC, sfy: DEC, sflp: DEC,
                dx, dy, dlp: amt_lp, dfx: 0, dfy: 0, dflp: 0
            },
            w: WalletDelta{
                sx: INC, sy: INC, slp: DEC,
                dx, dy, dlp: amt_lp
            },
        }
    }

    #[test_only]
    public fun test_pool_debug<X, Y>(
        admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer
    ) {
        let pool_type = POOL_TYPE_STABLE_CURVE;
        TestShared::prepare_for_test<X, Y>(admin, coin_list_admin, investor, swapper, core, pool_type, 8, 7, 0, 0, 0, 0, 0, 100, 100000);
        TestShared::fund_for_participants<X, Y>(investor, P8, P7);
        TestShared::sync_wallet_save_point<X, Y>(investor, pool_type);
        TestShared::fund_for_participants<X, Y>(swapper, P8, P7);
        TestShared::sync_wallet_save_point<X, Y>(swapper, pool_type);
        TestShared::assert_pool_delta<X, Y>(pool_type, false,
            INC, INC, INC, INC, INC, INC,
            0, 0, 0, 0, 0, 0
        );
        TestShared::debug_print_wallet_comparision<X, Y>(swapper, pool_type);
        router::add_liquidity_route<X, Y>(investor, pool_type, P8, P7);
        TestShared::debug_print_comparision<X, Y>(pool_type);
        TestShared::assert_pool_delta<X, Y>(pool_type, true,
            INC, INC, INC, INC, INC, INC,
            P8, P7, 2 * P8, 0, 0, 0
        );
        stable_curve_scripts::swap<X, Y>(swapper, P6, 0, 0, 20);
        TestShared::debug_print_comparision<X, Y>(pool_type);
        TestShared::debug_print_wallet_comparision<X, Y>(swapper, pool_type);
        stable_curve_scripts::swap<X, Y>(swapper, 0, P5, 0, 20);
        TestShared::debug_print_comparision<X, Y>(pool_type);
        stable_curve_scripts::swap<X, Y>(swapper, P7, 0, 0, 20);
        TestShared::debug_print_comparision<X, Y>(pool_type);
    }


    #[test_only]
    public fun test_pool<X, Y>(
        admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer, decimal_x: u8, decimal_y: u8
    ) {
        let pool_type = POOL_TYPE_STABLE_CURVE;
        TestShared::time_start(core);
        devcoin_util::init_registry_and_devnet_coins(admin);
        TestShared::init_mock_coin_pair<X, Y>(coin_list_admin, decimal_x, decimal_y);
        TestShared::create_pool<X, Y>(admin, pool_type, 0, 0, 0, 0, 0, 100, 100000);
        TestShared::fund_for_participants<X, Y>(investor, P8, P7);
        TestShared::fund_for_participants<X, Y>(swapper, P8, P7);
        TestShared::assert_pool_delta<X, Y>(pool_type, false,
            INC, INC, INC, INC, INC, INC,
            0, 0, 0, 0, 0, 0
        );

        router::add_liquidity_route<X, Y>(investor, pool_type, P8, P7);
        TestShared::assert_pool_delta<X, Y>(pool_type, true,
            INC, INC, INC, INC, INC, INC,
            P8, P7, 2 * P8, 0, 0, 0
        );
        stable_curve_scripts::swap<X, Y>(swapper, P6, 0, 0, 20);
        TestShared::debug_print_comparision<X, Y>(pool_type);
        stable_curve_scripts::swap<X, Y>(swapper, 0, P5, 0, 20);
        TestShared::debug_print_comparision<X, Y>(pool_type);
        stable_curve_scripts::swap<X, Y>(swapper, P7, 0, 0, 20);
        TestShared::debug_print_comparision<X, Y>(pool_type);
    }


    #[test_only]
    fun perform_transaction<X, Y>(trader: &signer, pool_type: u8, action: u8, print_debug: bool, param: TransactionParams) {
        if (action == ADD_LIQUIDITY) {
            router::add_liquidity_route<X, Y>(trader, pool_type, param.amt_x, param.amt_y);
        } else if (action == SWAP) {
            stable_curve_scripts::swap<X, Y>(trader, param.amt_x, param.amt_y, 0, 0);
        } else if (action == REMOVE_LIQUIDITY) {
            router::remove_liquidity_route<X, Y>(trader, pool_type, param.amt_lp, param.amt_x, param.amt_y);
        };
        if (print_debug) {
            TestShared::debug_print_comparision<X, Y>(pool_type);
            TestShared::debug_print_wallet_comparision<X, Y>(trader, pool_type);
        };
        TestShared::assert_pool_delta<X, Y>(pool_type, true,
            param.p.sx,
            param.p.sy,
            param.p.slp,
            param.p.sfx,
            param.p.sfy,
            param.p.sflp,
            param.p.dx,
            param.p.dy,
            param.p.dlp,
            param.p.dfx,
            param.p.dfy,
            param.p.dflp,
        );
        TestShared::assert_wallet_delta<X, Y>(trader, pool_type, true,
            param.w.sx, param.w.sy, param.w.slp,
            param.w.dx, param.w.dy, param.w.dlp
        );
    }

    #[test_only]
    public fun test_pool_case<X, Y>(
        admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer,
        print_debug: bool,
        skip_swap: bool,
        pool_type: u8,
        decimal_x: u8, // The decimal of coin x
        decimal_y: u8, // The decimal of coin y
        fee: u64,
        protocal_fee: u64,
        add_1: TransactionParams,
        add_2: TransactionParams,
        swap_1: TransactionParams,
        remove_1: TransactionParams
    ) {
        TestShared::prepare_for_test<X, Y>(admin, coin_list_admin, investor, swapper, core, pool_type, decimal_x, decimal_y,
            0, 0, 0, 0, 0, fee, protocal_fee
        );
        let liquidity_x = add_1.amt_x + add_2.amt_x;
        let liquidity_y = add_1.amt_y + add_2.amt_y;

        TestShared::fund_for_participants<X, Y>(investor, liquidity_x, liquidity_y);
        TestShared::sync_wallet_save_point<X, Y>(investor, pool_type);
        TestShared::fund_for_participants<X, Y>(swapper, swap_1.amt_x, swap_1.amt_y);
        TestShared::sync_wallet_save_point<X, Y>(swapper, pool_type);
        TestShared::assert_pool_delta<X, Y>(pool_type, false,
            INC, INC, INC, INC, INC, INC,
            0, 0, 0, 0, 0, 0
        );

        if (print_debug) {
            TestShared::debug_print_wallet_comparision<X, Y>(swapper, pool_type);
        };
        perform_transaction<X, Y>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_1);
        perform_transaction<X, Y>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_2);
        if (!skip_swap) {
            perform_transaction<X, Y>(swapper, pool_type, SWAP, print_debug, swap_1);
        };
        perform_transaction<X, Y>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_1);
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_add_remove(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 7, 100, 100000);
        let add_1 = new_transaction_param(
            P8, P7, 0,
            INC, INC, INC, INC, INC, INC,
            P8, P7, 2 * P8, 0, 0, 0,
            DEC, DEC, INC,
            P8, P7, 2 * P8
        );
        let add_2 = new_transaction_param(
            P8, P7, 0,
            INC, INC, INC, INC, INC, INC,
            P8, P7, 2 * P8, 0, 0, 0,
            DEC, DEC, INC,
            P8, P7, 2 * P8
        );
        let swap = new_transaction_param(
            P7, 0, 0,
            INC, INC, INC, INC, INC, INC,
            P8, P7, 2 * P8, 0, 0, 0,
            DEC, DEC, INC,
            P8, P7, 2 * P8
        );
        let remove_1 = TransactionParams{
            amt_x: 0, amt_y: 0, amt_lp: 2 * P8,
            p: PoolDelta{
                sx: DEC, sy: DEC, slp: DEC, sfx: INC, sfy: INC, sflp: INC,
                dx: P8, dy: P7, dlp: 2 * P8, dfx: 0, dfy: 0, dflp: 0
            },
            w: WalletDelta{
                sx: INC, sy: INC, slp: DEC,
                dx: P8, dy: P7, dlp: 2 * P8
            },
        };
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            false, true,
            POOL_TYPE_STABLE_CURVE,
            decimal_x, decimal_y, fee, protocal_fee,
            add_1,
            add_2,
            swap,
            remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_standard(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));

        // This test case demonstrates that the pool works fine when it has
        // reserve x of 2 units and y of 2 units
        // exchanging 1 unit of x, outcoming 0.989 unit of y affording 0.011 unit slipage.
        // the pool received fee for 1 / 10000 (1000), and the actual admin fee is 98 (offset 2 which should be ideally 100)

        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 7, 100, 100000);
        let add_1 = new_transaction_param(
            P8, P7, 0, INC, INC, INC, INC, INC, INC, P8, P7, 2 * P8, 0, 0, 0, DEC, DEC, INC, P8, P7, 2 * P8
        );
        let add_2 = new_transaction_param(
            P8, P7, 0, INC, INC, INC, INC, INC, INC, P8, P7, 2 * P8, 0, 0, 0, DEC, DEC, INC, P8, P7, 2 * P8
        );
        let swap = new_transaction_param(
            P8, 0, 0, INC, DEC, INC, INC, INC, INC, P8, 9892678, 0, 0, 98, 0, DEC, INC, INC, P8, 9892580, 0
        );
        let remove_1 = new_transaction_param(
            0, 0, 2 * P8, DEC, DEC, DEC, INC, INC, INC, 15 * P7, 5053661, 2 * P8, 0, 0, 0, INC, INC, DEC, 15 * P7, 5053661, 2 * P8
        );
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, POOL_TYPE_STABLE_CURVE, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }


    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_2(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // This test case demonstrates a small pool in different decimals of x & y which only has
        // reserve x of 2 units and y of 2 units works good when
        // exchanging 0.01 unit (1/200 of reserve) of x, outcoming 0.0099982 unit of y, The margin of error was 0.012 %.
        // And the fee was lost x in fraction of a tiny amount
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 7, 100, 100000);
        let add_1 = new_transaction_param(
            P8, P7, 0, INC, INC, INC, INC, INC, INC, P8, P7, 2 * P8, 0, 0, 0, DEC, DEC, INC, P8, P7, 2 * P8
        );
        let add_2 = new_transaction_param(
            P8, P7, 0, INC, INC, INC, INC, INC, INC, P8, P7, 2 * P8, 0, 0, 0, DEC, DEC, INC, P8, P7, 2 * P8
        );
        let swap = new_transaction_param(
            P6, 0, 0, INC, DEC, INC, INC, INC, INC, P6, 99982, 0, 0, 0, 0, DEC, INC, INC, P6, 99982, 0
        );
        let remove_1 = new_transaction_param(
            0, 0, 2 * P8,
            DEC, DEC, DEC, INC, INC, INC,
            P8 + 5 * P5, P7 - 5 * P4 + 9, 2 * P8, 0, 0, 0,
            INC, INC, DEC,
            P8 + 5 * P5, P7 - 5 * P4 + 9, 2 * P8
        );
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, POOL_TYPE_STABLE_CURVE, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_3(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));

        // This case demonstrates the stability of exchange rate when decimal varies.
        // the case test_pool_stable_curve_standard results decimal 7 of y 9892678
        // which is equivalent 989267 of decimal 6 below.
        // And the fee was 98 of decimal 7 : 9 of decimal 6.

        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 6, 100, 100000);
        let add_1 = add_param(P8, P6, P8, P6, 2 * P8, 0, 0);
        let add_2 = add_param(P8, P6, P8, P6, 2 * P8, 0, 0);
        let swap = swap_param(P8, 0, P8, 989267, 0, 9, 989258);
        let remove_1 = remove_param(2 * P8, 15 * P7, 505366);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, POOL_TYPE_STABLE_CURVE, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }


    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_tiny_amt(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // When exchange a very small amount like 1e-5 unit, the outcoming accuracy is good.
        // And the fees are lost.
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 6, 100, 100000);
        let add_1 = add_param(P8, P6, P8, P6, 2 * P8, 0, 0);
        let add_2 = add_param(P8, P6, P8, P6, 2 * P8, 0, 0);
        let swap = swap_param(P3, 0, P3, 10, 0, 0, 10);
        let remove_1 = remove_param(2 * P8, P8 + 500, P6 - 5);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, POOL_TYPE_STABLE_CURVE, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }


    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_4(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // Demonstrates the stability of exchange rate accuracy in large difference of decimals.
        // The change rate was exactly the same when the decimal changes.
        let (decimal_x, decimal_y, fee, protocal_fee) = (10, 6, 100, 100000);
        let add_1 = add_param(P10, P6, P10, P6, 2 * P10, 0, 0);
        let add_2 = add_param(P10, P6, P10, P6, 2 * P10, 0, 0);
        let swap = swap_param(P10, 0, P10, 989267, 0, 9, 989258);
        let remove_1 = remove_param(2 * P10, 15 * P9, 505366);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, POOL_TYPE_STABLE_CURVE, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_5(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // Accuracy and precisions pretty good when the reserve amount much bigger than swap amount.
        // Only 0.01% pool fee charged.
        let (pool_type, print_debug) = (POOL_TYPE_STABLE_CURVE, false);
        let (decimal_x, decimal_y, fee, protocal_fee) = (10, 10, 100, 100000);
        let add_1 = add_param(P10, P10, P10, P10, 2 * P10, 0, 0);
        let add_2 = add_param(P10, P10, P10, P10, 2 * P10, 0, 0);
        let swap = swap_param(P4, 0, P4, 9999, 0, 0, 9999);
        let remove_1 = remove_param(2 * P10, P10 + 5 * P3, P10 - 5 * P3);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, pool_type, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
        TestShared::fund_for_participants<WUSDC, WDAI>(swapper, 0, P4);
        TestShared::sync_wallet_save_point<WUSDC, WDAI>(swapper, pool_type);
        // reverse swap.
        let swap_2 = swap_param(0, P4, 9999, P4, 0, 0, 9999);
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, swap_2);
    }


    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_6(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // The capacity of the stable curve pool size, nealy 10^17.
        let (pool_type, print_debug) = (POOL_TYPE_STABLE_CURVE, false);
        let (decimal_x, decimal_y, fee, protocal_fee) = (10, 10, 100, 100000);
        let add_1 = add_param(P17, P17, P17, P17, 2 * P17, 0, 0);
        let add_2 = add_param(P17, P17, P17, P17, 2 * P17, 0, 0);
        let swap = swap_param(P4, 0, P4, 9999, 0, 0, 9999);
        let remove_1 = remove_param(2 * P10, P10, P10 - 1);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    #[expected_failure]         // ARITHMETIC_ERROR
    public fun test_pool_stable_curve_7(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // Overflow
        let (pool_type, print_debug) = (POOL_TYPE_STABLE_CURVE, false);
        let (decimal_x, decimal_y, fee, protocal_fee) = (10, 10, 100, 100000);
        let add_1 = add_param(P18, P18, P18, P18, 2 * P18, 0, 0);               // overflow
        let add_2 = add_param(P18, P18, P18, P18, 2 * P18, 0, 0);
        let swap = swap_param(P4, 0, P4, 9999, 0, 0, 9999);
        let remove_1 = remove_param(2 * P10, P10, P10 - 1);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_8(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));

        // Usually the pool reserves are much bigger than the swap amount. And proportion of x and y is in between 1 : 5.
        // This case reveals a typical fee charges of a swap proc.
        // The pool reserve of target coin increase 9/100000 (91 here bias 1)
        // Protocal fee increased 9 (which should be ideally 10), 1/1000000 in acceptance of design.
        // And the swapper received a 1/10000 loss.

        let (pool_type, print_debug) = (POOL_TYPE_STABLE_CURVE, false);
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 6, 100, 100000);
        let add_1 = add_param(P17, P15, P17, P15, 2 * P17, 0, 0);
        let add_2 = add_param(P17, P15, P17, P15, 2 * P17, 0, 0);
        let swap = swap_param(P8, 0, P8, P6 - 91, 0, 9, P6 - 100);
        let remove_1 = remove_param(2 * P10, P10 + 5, P8 - 1);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_accumulative_giant(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));

        // We perform trading actions continiously in this case.
        // The fee charged in add_liquidity comes from the inequality between the proportion of incoming x y and reserve x y.
        // The pool charged the swap fee implicitly in the process of add liquidity.
        // And the other way is the direct charge during the swap process.
        // It shows that as the base of reserve increases, traders afford less for the slippage of the same amount of imbalanced reserve.
        // And the remove liquidity actions reverse the process which took away all the reserve by steps.

        let (pool_type, print_debug) = (POOL_TYPE_STABLE_CURVE, false);
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 6, 100, 100000);
        let add_1 = add_param(P17, P15, P17, P15, 2 * P17, 0, 0);
        let add_2 = add_param(P17 - P8, P15 + P6, P17 - P8 - 500, P15 + P6 - 5, 2 * P17 - P4, 500, 5);
        let add_3 = add_param(P17 - P8, P15 + P6, P17 - P8 - 249, P15 + P6 - 2, 2 * P17 - P4 + 501, 249, 2);
        let add_4 = add_param(P17 - P8, P15 + P6, P17 - P8 - 166, P15 + P6 - 1, 2 * P17 - P4 + 717, 166, 1);
        // The fee was based on the deviation between the proportion of reserve coins and the input coins.

        TestShared::prepare_for_test<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core, pool_type, decimal_x, decimal_y, 0, 0, 0, 0, 0, fee, protocal_fee);
        TestShared::fund_for_participants<WUSDC, WDAI>(investor, 4 * P17 - 3 * P8, 4 * P15 + 3 * P6);
        TestShared::sync_wallet_save_point<WUSDC, WDAI>(investor, pool_type);

        perform_transaction<WUSDC, WDAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_1);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_2);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_3);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_4);

        TestShared::fund_for_participants<WUSDC, WDAI>(swapper, P9, P7);
        TestShared::sync_wallet_save_point<WUSDC, WDAI>(swapper, pool_type);
        let swap_1 = swap_param(P8, 0, P8, P6 - 91, 0, 9, P6 - 100);  // swap 1 doller
        let swap_2 = swap_param(P8, 0, P8, P6 - 91, 0, 9, P6 - 100);  // swap 1 doller
        let swap_3 = swap_param(P8, 0, P8, P6 - 91, 0, 9, P6 - 100);  // swap 1 doller
        let swap_4 = swap_param(P8, 0, P8, P6 - 91, 0, 9, P6 - 100);  // swap 1 doller
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, swap_1);
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, swap_2);
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, swap_3);
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, swap_4);

        let rev_swap_1 = swap_param(0, P6, P8 - 9001, P6, 999, 0, P8 - 10000);  // swap 1 doller
        let rev_swap_2 = swap_param(0, P6, P8 - P4 + 999, P6, 999, 0, P8 - 10000);  // swap 1 doller
        let rev_swap_3 = swap_param(0, P6, P8 - P4 + 999, P6, 999, 0, P8 - 10000);  // swap 1 doller
        let rev_swap_4 = swap_param(0, P6, P8 - P4 + 999, P6, 999, 0, P8 - 10000);  // swap 1 doller
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, rev_swap_1);
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, rev_swap_2);
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, rev_swap_3);
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, rev_swap_4);

        // reverse action
        let remove_1 = remove_param(2 * P17 - P4 + 717, P17 - 74992272, P15 + 750078); // erned x: 25007728, 0.25    y: -249922, -0.25
        let remove_2 = remove_param(2 * P17 - P4 + 501, P17 - 74992380, P15 + 750077); // erned x: 25007620, 0.25    y: -249923, -0.25
        let remove_3 = remove_param(2 * P17 - P4, P17 - 74992630, P15 + 750075);
        let remove_4 = remove_param(2 * P17, P17 - 74987629, P15 + 750126);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_1);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_2);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_3);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_4);
    }


    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_accumulative_loop_swap(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // Demonstrates the stability in large number of transactions
        // Slippage happens when swapping accumulatively.
        let (pool_type, print_debug) = (POOL_TYPE_STABLE_CURVE, false);
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 6, 100, 100000);


        let add_1 = add_param(P17, P15, P17, P15, 2 * P17, 0, 0);
        // The fee was based on the deviation between the proportion of reserve coins and the input coins.

        TestShared::prepare_for_test<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core, pool_type, decimal_x, decimal_y, 0, 0, 0, 0, 0, fee, protocal_fee);
        TestShared::fund_for_participants<WUSDC, WDAI>(investor, 4 * P17 - 3 * P8, 4 * P15 + 3 * P6);
        TestShared::sync_wallet_save_point<WUSDC, WDAI>(investor, pool_type);

        perform_transaction<WUSDC, WDAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_1);

        let i = 0;
        while (i < 1000) {
            i = i + 1;
            TestShared::fund_for_participants<WUSDC, WDAI>(swapper, P8, P6);
            TestShared::sync_wallet_save_point<WUSDC, WDAI>(swapper, pool_type);
            let swap_1 = swap_param(P8, 0, P8, P6 - 91, 0, 9, P6 - 100);  // swap 1 doller
            perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, false, swap_1);
        };
        let i = 0;
        while (i < 1000) {
            i = i + 1;
            let ddx = i / 256;          // Slippage
            let rev_swap_1 = swap_param(0, P6, P8 - 8997 - ddx , P6, 1000, 0, P8 - 10000 + 3 - ddx);  // swap 1 doller
            perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, false, rev_swap_1);
        };
    }


    #[test(admin = @hippo_swap, coin_list_admin = @coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_stable_curve_deviant(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // If we change the proportion evidently in the add liquidity process, we'll get much more fee lost.
        let (pool_type, print_debug) = (POOL_TYPE_STABLE_CURVE, false);
        let (decimal_x, decimal_y, fee, protocal_fee) = (8, 6, 100, 100000);
        let add_1 = add_param(P17, P15, P17, P15, 2 * P17, 0, 0);
        let add_2 = add_param(P17, 2*P15, 99999750426479329, 1999997495735207, 299824406454391189, 249573520671,  2504264793);
        let swap = swap_param(P8, 0, P8,  1007033, 0, 10,  1007023);

        let remove_1 = remove_param(2 * P10,  8002800501, 120042057);
        test_pool_case<WUSDC, WDAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type, decimal_x, decimal_y, fee, protocal_fee, add_1, add_2, swap, remove_1
        );
        let swap_2 = swap_param(0, P6,  99283755, P6, 992, 0, 99282763);  // swap 1 doller
        perform_transaction<WUSDC, WDAI>(swapper, pool_type, SWAP, print_debug, swap_2);
        let remove_2 = remove_param(  499824386454391189,     199999742424395073,   2999997375686117);
        perform_transaction<WUSDC, WDAI>(investor, pool_type, REMOVE_LIQUIDITY, false, remove_2);
    }
}

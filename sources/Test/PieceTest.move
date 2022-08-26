#[test_only]
module hippo_swap::piece_test {

    use hippo_swap::TestShared;
    use hippo_swap::router;
    use hippo_swap::piece_swap_script;
    use coin_list::devnet_coins::{DevnetUSDC as USDC, DevnetSOL as DAI};
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
    fun perform_transaction<X, Y>(trader: &signer, pool_type: u8, action: u8, print_debug: bool, param: TransactionParams) {
        if (action == ADD_LIQUIDITY) {
            router::add_liquidity_route<X, Y>(trader, pool_type, param.amt_x, param.amt_y);
        } else if (action == SWAP) {
            piece_swap_script::swap<X, Y>(trader, param.amt_x, param.amt_y, 0, 0);
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
        k: u128,
        n1: u128,
        d1: u128,
        n2: u128,
        d2: u128,
        fee: u64,
        protocal_fee: u64,
        add_1: TransactionParams,
        add_2: TransactionParams,
        swap_1: TransactionParams,
        remove_1: TransactionParams
    ) {
        TestShared::prepare_for_test<X, Y>(admin, coin_list_admin, investor, swapper, core, pool_type, decimal_x, decimal_y,
            k, n1, d1, n2, d2, fee, protocal_fee,
            //0, 0, 0, 0, 0, fee, protocal_fee
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

    #[test(admin = @hippo_swap, coin_list_admin=@coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_piece_swap_4(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        let (decimal_x, decimal_y, ) = (10, 6);
        let (k, n1, d1, n2, d2, fee, protocal_fee) = ((P18 as u128), 110, 100, 105, 100, 100, 100);
        let add_1 = add_param(P10, P6, P10, P6, P10, 0, 0);
        let add_2 = add_param(P10, P6, P10, P6, P10, 0, 0);
        let swap = swap_param(P10, 0, P10, 977172, 0, 9, 977163);
        let remove_1 = remove_param(2 * P10, 3 * P10, 1022828);
        test_pool_case<USDC, DAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, POOL_TYPE_PIECEWISE,
            decimal_x, decimal_y,
            k, n1, d1, n2, d2, fee, protocal_fee,
            add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin=@coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_piece_swap_5(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        let (decimal_x, decimal_y, ) = (10, 10);
        let (k, n1, d1, n2, d2, fee, protocal_fee) = ((P18 as u128), 110, 100, 105, 100, 100, 100);
        let add_1 = add_param(P10, P10, P10, P10, P10, 0, 0);
        let add_2 = add_param(P10, P10, P10, P10, P10, 0, 0);
        let swap = swap_param(P4, 0, P4, 9999, 0, 0, 9999);
        let remove_1 = remove_param(2 * P10, 2 * P10 + P4, 2 * P10 - P4 + 1);
        test_pool_case<USDC, DAI>(admin, coin_list_admin, investor, swapper, core,
            false, false, POOL_TYPE_PIECEWISE,
            decimal_x, decimal_y,
            k, n1, d1, n2, d2, fee, protocal_fee,
            add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin=@coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_piece_swap_6(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // The capacity of the stable curve pool size, nealy 10^17.
        let (pool_type, print_debug) = (POOL_TYPE_PIECEWISE, false);
        let (decimal_x, decimal_y, ) = (10, 10);
        let (k, n1, d1, n2, d2, fee, protocal_fee) = ((P18 as u128), 110, 100, 105, 100, 100, 100);
        let add_1 = add_param(P17, P17, P17, P17, P17, 0, 0);
        let add_2 = add_param(P17, P17, P17, P17, P17, 0, 0);
        let swap = swap_param(P4, 0, P4, 8000, 0, 0, 8000);
        // TODO: 20% deviation.
        let remove_1 = remove_param(P10, P10, P10 - 1);
        test_pool_case<USDC, DAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type,
            decimal_x, decimal_y,
            k, n1, d1, n2, d2, fee, protocal_fee,
            add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin=@coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_piece_swap_7(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        // Overflow
        let (pool_type, print_debug) = (POOL_TYPE_PIECEWISE, false);
        let (decimal_x, decimal_y, ) = (10, 10);
        let (k, n1, d1, n2, d2, fee, protocal_fee) = ((P18 as u128), 110, 100, 105, 100, 100, 100);
        let add_1 = add_param(P18, P18, P18, P18, P18, 0, 0);               // overflow
        let add_2 = add_param(P18, P18, P18, P18, P18, 0, 0);
        let swap = swap_param(P4, 0, P4, 0, 0, 0, 0);
        // TODO: totally loss.
        let remove_1 = remove_param(P10, P10, P10);
        test_pool_case<USDC, DAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type,
            decimal_x, decimal_y,
            k, n1, d1, n2, d2, fee, protocal_fee,
            add_1, add_2, swap, remove_1
        );


        TestShared::fund_for_participants<USDC, DAI>(swapper, P8, 0);
        TestShared::sync_wallet_save_point<USDC, DAI>(swapper, pool_type);

        let swap_2 = swap_param(P8, 0, P8, P8 - 48997, 0, 999, P8 - 49996);  //ideal: dy: P8 - 9000, dfy: 900, receive: P8 - 10000
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, swap_2);
    }

    #[test(admin = @hippo_swap, coin_list_admin=@coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_piece_swap_8(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        let (pool_type, print_debug) = (POOL_TYPE_PIECEWISE, false);
        let (decimal_x, decimal_y, ) = (8, 6);
        let (k, n1, d1, n2, d2, fee, protocal_fee) = ((P18 as u128), 110, 100, 105, 100, 100, 100);
        let add_1 = add_param(P17, P15, P17, P15, P17, 0, 0);
        let add_2 = add_param(P17, P15, P17, P15, P17, 0, 0);
        let swap = swap_param(P8, 0, P8, P6 - 130, 0, 9, P6 - 139);
        let remove_1 = remove_param(P10, P10 + 5, P8 - 1);
        test_pool_case<USDC, DAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type,
            decimal_x, decimal_y,
            k, n1, d1, n2, d2, fee, protocal_fee,
            add_1, add_2, swap, remove_1
        );
    }

    #[test(admin = @hippo_swap, coin_list_admin=@coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_piece_swap_accumulative_giant(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        // We perform trading actions continiously in this case.
        // The fee charged in add_liquidity comes from the inequality between the proportion of incoming x y and reserve x y.
        // The pool charged the swap fee implicitly in the process of add liquidity.
        // And the other way is the direct charge during the swap process.
        // It shows that as the base of reserve increases, traders afford less for the slippage of the same amount of imbalanced reserve.
        // And the remove liquidity actions reverse the process which took away all the reserve by steps.
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));
        let (pool_type, print_debug) = (POOL_TYPE_PIECEWISE, false);
        let (decimal_x, decimal_y, ) = (8, 6);
        let (k, n1, d1, n2, d2, fee, protocal_fee) = ((P18 as u128), 110, 100, 105, 100, 100, 100);

        let add_1 = add_param(P17, P15, P17, P15, P17, 0, 0);
        let add_2 = add_param(P17 - P8, P15 - P6, P17 - P8, P15 - P6, P17 - P8, 0, 0);
        let add_3 = add_param(P17 - P8, P15 - P6, P17 - P8, P15 - P6, P17 - P8, 0, 0);
        let add_4 = add_param(P17 - P8, P15 - P6, P17 - P8, P15 - P6, P17 - P8, 0, 0);
        // The fee was based on the deviation between the proportion of reserve coins and the input coins.

        TestShared::prepare_for_test<USDC, DAI>(admin, coin_list_admin, investor, swapper, core, pool_type, decimal_x, decimal_y, k, n1, d1, n2, d2, fee, protocal_fee);
        TestShared::fund_for_participants<USDC, DAI>(investor, 4 * P17 - 3 * P8, 4 * P15 + 3 * P6);
        TestShared::sync_wallet_save_point<USDC, DAI>(investor, pool_type);

        perform_transaction<USDC, DAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_1);
        perform_transaction<USDC, DAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_2);
        perform_transaction<USDC, DAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_3);
        perform_transaction<USDC, DAI>(investor, pool_type, ADD_LIQUIDITY, print_debug, add_4);

        TestShared::fund_for_participants<USDC, DAI>(swapper, P9, P7);
        TestShared::sync_wallet_save_point<USDC, DAI>(swapper, pool_type);
        let swap_1 = swap_param(P8, 0, P8, P6 - 130, 0, 9, P6 - 139);  // swap 1 doller
        let swap_2 = swap_param(P8, 0, P8, P6 - 130, 0, 9, P6 - 139);  // swap 1 doller
        let swap_3 = swap_param(P8, 0, P8, P6 - 130, 0, 9, P6 - 139);  // swap 1 doller
        let swap_4 = swap_param(P8, 0, P8, P6 - 210, 0, 9, P6 - 219);  // swap 1 doller
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, swap_1);
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, swap_2);
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, swap_3);
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, swap_4);

        let rev_swap_1 = swap_param(0, P6, P8 - 20999, P6, 999, 0, P8 - 21998);  // swap 1 doller
        let rev_swap_2 = swap_param(0, P6, P8 - 20999, P6, 999, 0, P8 - 21998);  // swap 1 doller
        let rev_swap_3 = swap_param(0, P6, P8 - 13000, P6, 999, 0, P8 - 13999);  // swap 1 doller
        let rev_swap_4 = swap_param(0, P6, P8 - 13000, P6, 999, 0, P8 - 13999);  // swap 1 doller
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, rev_swap_1);
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, rev_swap_2);
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, rev_swap_3);
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, rev_swap_4);

        // reverse action
        let remove_1 = remove_param(P17 - P8, P17 - P8 + 16999, P15 - P6 + 149);
        let remove_2 = remove_param(P17 - P8, P17 - P8 + 16999, P15 - P6 + 150); // erned x: 25007620, 0.25    y: -249923, -0.25
        let remove_3 = remove_param(P17 - P8, P17 - P8 + 16999, P15 - P6 + 150);
        let remove_4 = remove_param(P17, P17 + 17001, P15 + 151);
        perform_transaction<USDC, DAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_1);
        perform_transaction<USDC, DAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_2);
        perform_transaction<USDC, DAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_3);
        perform_transaction<USDC, DAI>(investor, pool_type, REMOVE_LIQUIDITY, print_debug, remove_4);
    }

    #[test(admin = @hippo_swap, coin_list_admin=@coin_list, investor = @0x2FFF, swapper = @0x2FFE, core = @aptos_framework)]
    public fun test_pool_piece_swap_deviant(admin: &signer, coin_list_admin: &signer, investor: &signer, swapper: &signer, core: &signer) {
        use std::signer;
        use aptos_framework::aptos_account;
        aptos_account::create_account(signer::address_of(admin));
        aptos_account::create_account(signer::address_of(investor));
        aptos_account::create_account(signer::address_of(swapper));

        let (pool_type, print_debug) = (POOL_TYPE_PIECEWISE, false);
        let (decimal_x, decimal_y, ) = (8, 6);
        let (k, n1, d1, n2, d2, fee, protocal_fee) = ((P18 as u128), 110, 100, 105, 100, 100, 100);

        let add_1 = add_param(P17, P15, P17, P15, P17, 0, 0);
        let add_2 = add_param(P17, P15, P17, P15, P17, 0, 0);
        let swap = swap_param(P17, 0, P17,  977172461764492, 0, 9772604152,  977162689160340);

        let remove_1 = remove_param(2 * P10,   30000000000,  102282753);
        test_pool_case<USDC, DAI>(admin, coin_list_admin, investor, swapper, core,
            print_debug, false, pool_type,
            decimal_x, decimal_y,
            k, n1, d1, n2, d2, fee, protocal_fee,
            add_1, add_2, swap, remove_1
        );
        let swap_2 = swap_param(0, P6,  104695577, P6, 1047, 0,  104694530);  // swap 1 doller
        perform_transaction<USDC, DAI>(swapper, pool_type, SWAP, print_debug, swap_2);
        let remove_2 = remove_param(  199999980000000000,      299999969895304423,    1022827436952755);
        perform_transaction<USDC, DAI>(investor, pool_type, REMOVE_LIQUIDITY, false, remove_2);

    }
}

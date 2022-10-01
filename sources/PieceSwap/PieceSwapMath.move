address hippo_swap {
module piece_swap_math {
    use hippo_swap::math;

    #[test_only]
    use std::debug;

    const FRACTION_MULT:u128 = 1000000000;
    const BILLION:u128 = 1000000000;
    const PRECISION_FACTOR:u128 = 1000000;
    const ENABLE_PLOT:bool = false;
    const NUM_STEPS:u128 = 40;

    const E_X_Y_NOT_EQUAL:u64 = 0;

    fun div_w(multiplier: u128, numerator: u128, denominator: u128): u128 {
        multiplier * denominator / numerator
    }
    fun mul_w(multiplier: u128, numerator: u128, denominator: u128): u128 {
        multiplier * numerator / denominator
    }

    public fun compute_initialization_constants(
        k: u128,
        w1_numerator: u128,      // w1: w_end
        w1_denominator: u128,
        w2_numerator: u128,      // w2: w_switch
        w2_denominator: u128,
    ): (u128, u128, u128, u128, u128) { // returns (Xa, Xb, m, n, k2)

        let m = math::sqrt(div_w(k, w1_numerator, w1_denominator));
        let xa = math::sqrt(div_w(k, w2_numerator, w2_denominator)) - m;
        let xb = k / (xa + m) - m;
        let k2 = mul_w(xa * xa, w2_numerator, w2_denominator);
        let n = xb - k2 / xa;

        return (xa, xb, m, n, k2)
    }

    public fun get_add_liquidity_actual_amount(
        current_x: u128,
        current_y: u128,
        current_lp: u128,
        add_amt_x: u128,
        add_amt_y: u128
    ) : (u128, u128, u128) {
        if (add_amt_x == 0 || add_amt_y == 0) {
            return (0, 0, 0)
        };
        if (current_x == 0 || current_y == 0) {
            // we do require that, at initialization, equal amount of x and y are added
            // initialize Lp amount to be same as x & y
            std::debug::print(&add_amt_x);
            std::debug::print(&add_amt_y);
            assert!(add_amt_x == add_amt_y, E_X_Y_NOT_EQUAL);
            return (add_amt_x, add_amt_y, add_amt_x)
        };
        let current_x_to_y = current_x * FRACTION_MULT / current_y;
        let add_x_to_y = add_amt_x * FRACTION_MULT / add_amt_y;
        if (current_x_to_y > add_x_to_y) {
            // use all of x, and fraction of y
            let optimal_amt_y = current_y * add_amt_x / current_x;
            let optimal_lp = current_lp * add_amt_x / current_x;
            return (add_amt_x, optimal_amt_y, optimal_lp)
        }
        else {
            // use all of y, and fraction of x
            let optimal_amt_x = current_x * add_amt_y / current_y;
            let optimal_lp = current_lp * add_amt_y / current_y;
            return (optimal_amt_x, add_amt_y, optimal_lp)
        }
    }

    public fun get_remove_liquidity_amounts(
        current_x: u128,
        current_y: u128,
        current_lp_amt: u128,
        remove_lp_amt: u128,
    ): (u128, u128) {
        if(remove_lp_amt == 0 || current_lp_amt == 0) {
            return (0,0)
        };
        (current_x * remove_lp_amt / current_lp_amt, current_y * remove_lp_amt / current_lp_amt)
    }


    public fun get_swap_x_to_y_out(
        current_x: u128,
        current_y: u128,
        input_x: u128,
        k: u128,
        k2: u128,
        xa: u128,
        xb: u128,
        m: u128,
        n: u128,
    ): u128 {
        /*
        Steps:
        1. normalize (current_x, current_y, input_x) to have max(current_x, current_y) within [100M, 1B]
        2. invoke get_swap_x_to_y_out_preprocessed
        3. denormalize output

        Why normalize current_x, current_y to the range of [100M, 1B]?
        - when solving one of those quadratic equations, some of the computed quantities can reach the scale of
          (max_x_y * max_x_y)^2

        Given that our maximum is u128::MAX, we need to keep max_x_y under u32::MAX, which is about 4 billion
        */
        let max_x_y = math::max(current_x, current_y);
        let numerator = 1;
        let denominator = 1;
        while (max_x_y > BILLION  ) {
            max_x_y = max_x_y / 10;
            denominator = denominator * 10;
        };
        while (max_x_y < BILLION / 10) {
            max_x_y = max_x_y * 10;
            numerator = numerator * 10;
        };
        let preprocessed_input_x = input_x * numerator / denominator;
        // we need to make sure pre-processed input has enough significant digits, so if it's too small, we push the
        // preprocessing inside get_swap_x_to_y_out_preprocessed_inner
        if (preprocessed_input_x < 10000) {
            get_swap_x_to_y_out_preprocessed_inner(
                current_x * numerator / denominator,
                current_y * numerator / denominator,
                input_x,
                numerator,
                denominator,
                k,
                k2,
                xa,
                xb,
                m,
                n
            ) * denominator / (numerator * PRECISION_FACTOR)
        } else {
            get_swap_x_to_y_out_preprocessed_inner(
                current_x * numerator / denominator,
                current_y * numerator / denominator,
                preprocessed_input_x,
                1,
                1,
                k,
                k2,
                xa,
                xb,
                m,
                n
            ) * denominator / (numerator * PRECISION_FACTOR)
        }
    }
    fun get_swap_x_to_y_out_preprocessed(
        current_x: u128,
        current_y: u128,
        input_x: u128,
        k: u128,
        k2: u128,
        xa: u128,
        xb: u128,
        m: u128,
        n: u128,
    ): u128 {
        get_swap_x_to_y_out_preprocessed_inner(
            current_x,
            current_y,
            input_x,
            1,
            1,
            k,
            k2,
            xa,
            xb,
            m,
            n
        )
    }

    fun get_swap_x_to_y_out_preprocessed_inner(
        current_x: u128,
        current_y: u128,
        input_x: u128,
        preprocessing_numerator: u128,
        preprocessing_denominator: u128,
        k: u128,
        k2: u128,
        xa: u128,
        xb: u128,
        m: u128,
        n: u128,
    ): u128 {

        /*
        Steps:
        0. normalize (current_x, current_y, input_x) to appropriate range
        1. Use ratio to find out which stage we're on
        2. Use stage to compute normalization factor
        3. Use curve to compute new position
        4. return delta y
        */

        /*
        if x-to-y < xa-to-xb: upper-left stage
        if x-to-y < xb-to-xa: middle stage
        if x-to-y > xb-to-xa: bottom-right stage
        */

        // cheat for better precision
        let p_xa = xa * PRECISION_FACTOR;
        let p_xb = xb * PRECISION_FACTOR;
        let p_m = m * PRECISION_FACTOR;
        let p_n = n * PRECISION_FACTOR;
        let p_k = k * PRECISION_FACTOR * PRECISION_FACTOR;
        let p_k2 = k2 * PRECISION_FACTOR * PRECISION_FACTOR;

        if (compare_fraction(current_x, current_y, xa, xb)) {
            // upper-left stage
            // (xF) (yF - n) = k2
            // xyF^2 - (xn)F - k2 = 0
            // F = [ (xn) + sqrt((xn)^2 + 4xy*k2)] / 2xy
            let (f_numerator, f_denominator, dydx_numerator, dydx_denominator) =
                solve_F_upper_left(current_x, current_y, n, k2);
            // [(x+dx)F] [(y-dy)F - n] = (xF)(yF - n)
            // dy = y - [(xF)(yF - n) / [(x+dx)F] + n] / F    // also = y - [k2 / (new_x)F + n] / F
            //    = y - ( (xyF - xn) / (x+dx) + n] / F        // also = y - k2/(new_x)FF - n/F
            // (new_y)F - n = k2 / newxF
            // new_y = (k2/new_xF + n) / F
            // which solution has better numerical stability&precision?
            let p_current_xF = current_x * f_numerator * PRECISION_FACTOR / f_denominator;
            let p_current_yF = current_y * f_numerator  * PRECISION_FACTOR/ f_denominator;
            let p_input_xF = input_x * f_numerator  * PRECISION_FACTOR/ f_denominator * preprocessing_numerator / preprocessing_denominator;
            let p_new_xF = p_current_xF + p_input_xF;

            if (p_new_xF > p_xa) {
                // crossed into the middle stage
                let p_output_y_max = mul_w(
                    input_x * PRECISION_FACTOR * preprocessing_numerator / preprocessing_denominator,
                    dydx_numerator,
                    dydx_denominator
                );
                let p_delta_yF_this_stage = p_current_yF - p_xb; // xb = ya
                let input_xF_next_stage = (p_new_xF - p_xa) / PRECISION_FACTOR;
                let p_output_yF_next_stage = get_swap_x_to_y_out_preprocessed(
                    xa,
                    xb,
                    input_xF_next_stage,
                    k,
                    k2,
                    xa,
                    xb,
                    m,
                    n
                );
                let p_output_y = (p_delta_yF_this_stage + p_output_yF_next_stage) * f_denominator / f_numerator;
                math::min(p_output_y, p_output_y_max)
            }
            else {
                let p_new_yF = p_k2 / p_new_xF + p_n;
                let p_delta_yF = if (p_current_yF > p_new_yF) {p_current_yF - p_new_yF} else {0};
                let p_output_y = p_delta_yF * f_denominator / f_numerator;
                p_output_y
            }
        }
        else if(compare_fraction(current_x, current_y, xb, xa)) {
            // middle stage
            // (xF + m) (yF + m) = k
            // xyF^2 + (x + y)mF + (mm -k) = 0
            // F = [-(x+y)m + sqrt( ((x+y)m)^2 - 4xy(mm-k) ) ] / 2xy
            let (f_numerator, f_denominator, dydx_numerator, dydx_denominator) =
                solve_F_middle(current_x, current_y, m, k);
            let p_current_xF = current_x * f_numerator * PRECISION_FACTOR / f_denominator;
            let p_current_yF = current_y * f_numerator * PRECISION_FACTOR / f_denominator;
            let p_input_xF = input_x * f_numerator * PRECISION_FACTOR / f_denominator * preprocessing_numerator / preprocessing_denominator;
            let p_new_xF = p_current_xF + p_input_xF;
            if (p_new_xF > p_xb) {
                // crossed into the bottom-right stage
                let p_output_y_max = mul_w(
                    input_x * PRECISION_FACTOR * preprocessing_numerator / preprocessing_denominator,
                    dydx_numerator,
                    dydx_denominator
                );
                let p_delta_yF_this_stage = p_current_yF - p_xa; // xa = yb
                let input_xF_next_stage = (p_new_xF - p_xb) / PRECISION_FACTOR;
                let p_output_yF_next_stage = get_swap_x_to_y_out_preprocessed(
                    xb,
                    xa,
                    input_xF_next_stage,
                    k,
                    k2,
                    xa,
                    xb,
                    m,
                    n
                );
                let p_output_y = (p_delta_yF_this_stage + p_output_yF_next_stage) * f_denominator / f_numerator;
                math::min(p_output_y, p_output_y_max)
            }
            else {
                /*
                let p_new_yF = p_k / (p_new_xF + p_m) - p_m;
                let p_delta_yF = p_current_yF - p_new_yF;
                let output_y = p_delta_yF * f_denominator * 10000 / (f_numerator * PRECISION_FACTOR);
                */
                let p_new_yF = p_k / (p_new_xF + p_m) - p_m;
                let p_delta_yF = p_current_yF - p_new_yF;
                let p_output_y = p_delta_yF * f_denominator / f_numerator;
                p_output_y
            }
        }
        else {
            // bottom-right stage
            // (xF - n) (yF) = k2
            // xyF^2 -nyF -k2 = 0
            // [ny + sqrt( (ny)^2 +4xyk2) ] / 2xy
            let (f_numerator, f_denominator, _dydx_numerator, _dydx_denominator) =
                solve_F_bottom_right(current_x, current_y, n, k2);
            let p_current_xF = current_x * f_numerator * PRECISION_FACTOR / f_denominator;
            let p_current_yF = current_y * f_numerator * PRECISION_FACTOR / f_denominator;
            let p_input_xF = input_x * f_numerator * PRECISION_FACTOR / f_denominator * preprocessing_numerator / preprocessing_denominator;
            let p_new_xF = p_current_xF + p_input_xF;
            let p_new_yF = p_k2 / (p_new_xF - p_n);
            let p_delta_yF = if (p_current_yF > p_new_yF) {p_current_yF - p_new_yF} else {0};
            let p_output_y = p_delta_yF * f_denominator / f_numerator;
            p_output_y
        }
    }

    public fun get_swap_y_to_x_out(
        current_x: u128,
        current_y: u128,
        input_y: u128,
        k: u128,
        k2: u128,
        xa: u128,
        xb: u128,
        m: u128,
        n: u128,
    ): u128 {
        get_swap_x_to_y_out(
            current_y,
            current_x,
            input_y,
            k,
            k2,
            xa,
            xb,
            m,
            n
        )
    }

    fun solve_F_upper_left(
        x: u128,
        y: u128,
        n: u128,
        k2: u128,
    ): (u128, u128, u128, u128) { // (F_numerator, F_denominator, -dyF, dxF)
        // (xF)(yF - n) = k2
        // xy*FF -nx*F - k2 = 0
        // F = [ (xn) + sqrt((xn)^2 + 4xy*k2)] / 2xy
        let xn = x * n;
        let xy = x * y;
        let numerator = xn + math::sqrt(xn * xn + 4 * xy * k2);
        let denominator = 2 * xy;

        // compute dydx
        // yF - n = k2 /(xF)
        // yF = k2 /(xF) + n
        // dyF/dxF = -k2/(xF)^2
        let xF = mul_w(x, numerator, denominator);
        (numerator, denominator, k2, xF*xF)
    }

    fun solve_F_middle(
        x: u128, // max u64
        y: u128, // max u64
        m: u128,
        k: u128,
    ): (u128, u128, u128, u128) { // (F_numerator, F_denominator, -dyF, dxF)
        // (xF + m)(yF + m) = k
        // xy*FF + (x + y)m*F + (mm - k) = 0
        // F = [-(x+y)m + sqrt( ((x+y)m)^2 - 4xy(mm-k) ) ] / 2xy

        let xy = x * y;
        let x_plus_y = x + y;
        let b = x_plus_y * m;
        let numerator = math::sqrt(b*b + 4 * xy * (k - m*m)) - b; // k > mm is guaranteed
        let denominator = 2 * xy;

        // compute dydx
        // (yF + m) = k /(xF + m)
        // yF = k / (xF + m) - m
        // dyF/dxF = -k / (xF+m)^2
        let xF = mul_w(x, numerator, denominator);
        let xf_plus_m = xF + m;
        (numerator, denominator, k, xf_plus_m* xf_plus_m)
    }


    fun solve_F_bottom_right(
        x: u128,
        y: u128,
        n: u128,
        k2: u128,
    ): (u128, u128, u128, u128) { // (F_numerator, F_denominator, dy, dx)
        // (xF-n)(yF) = k2
        solve_F_upper_left(y, x, n, k2)
    }

    fun compare_fraction(
        first_numerator: u128,
        first_denominator: u128,
        second_numerator: u128,
        second_denominator: u128,
    ): bool { // returns true if first_fraction < second_fraction
        first_numerator * second_denominator < second_numerator * first_denominator
    }

    #[test]
    fun test_initialization_constants() {
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            BILLION * BILLION,
            110,
            100,
            105,
            100,
        );
        debug::print(&xa);
        debug::print(&xb);
        debug::print(&m);
        debug::print(&n);
        debug::print(&k2);
    }

    #[test]
    fun test_get_add_liquidity_actual_amount_1() {
        let million = 1000000;
        let (actual_x, actual_y, actual_lp) = get_add_liquidity_actual_amount(
            million,
            million,
            million,
            10,
            10,
        );
        assert!(actual_x == 10, 0);
        assert!(actual_y == 10, 0);
        assert!(actual_lp == 10, 0);
    }

    #[test]
    fun test_get_add_liquidity_actual_amount_2() {
        let million = 1000000;
        let (actual_x, actual_y, actual_lp) = get_add_liquidity_actual_amount(
            million * 10,
            million * 2,
            million * 3,
            10,
            10,
        );
        assert!(actual_x == 10, 0);
        assert!(actual_y == 2, 0);
        assert!(actual_lp == 3, 0);
    }

    #[test]
    fun test_get_add_liquidity_actual_amount_3() {
        let million = 1000000;
        let (actual_x, actual_y, actual_lp) = get_add_liquidity_actual_amount(
            million * 2,
            million * 10,
            million * 3,
            10,
            10,
        );
        assert!(actual_x == 2, 0);
        assert!(actual_y == 10, 0);
        assert!(actual_lp == 3, 0);
    }

    #[test]
    fun test_get_remove_liquidity_amounts_1() {
        let million = 1000000;
        let (removed_x, removed_y) = get_remove_liquidity_amounts(
            million,
            million,
            million,
            10,
        );
        assert!(removed_x == 10, 0);
        assert!(removed_y == 10, 0);
    }

    #[test]
    fun test_get_remove_liquidity_amounts_2() {
        let million = 1000000;
        let (removed_x, removed_y) = get_remove_liquidity_amounts(
            million * 10,
            million * 2,
            million,
            10,
        );
        assert!(removed_x == 100, 0);
        assert!(removed_y == 20, 0);
    }

    #[test]
    fun test_get_remove_liquidity_amounts_3() {
        let million = 1000000;
        let (removed_x, removed_y) = get_remove_liquidity_amounts(
            million * 2,
            million * 10,
            million,
            10,
        );
        assert!(removed_x == 20, 0);
        assert!(removed_y == 100, 0);
    }
    #[test]
    fun test_get_swap_x_to_y_out_1() {
        // K = 10E9 * 10E9
        // W1 = 1.1
        // W2 = 1.05
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 100000000;
        let current_x = BILLION * multiplier;
        let current_y = BILLION * multiplier;
        let mid_point = (BILLION - m) * multiplier;
        let step_size = (mid_point * 40) / NUM_STEPS;
        let i = 0;
        while(i < NUM_STEPS) {
            // sell Y
            let input_y = step_size * (NUM_STEPS - i);
            let x_out = get_swap_y_to_x_out(current_x, current_y, input_y, k, k2, xa, xb, m, n);
            let new_x = current_x - x_out;
            let new_y = current_y + input_y;
            if (ENABLE_PLOT) {
                debug::print(&new_x);
                debug::print(&new_y);
            };
            i = i + 1;
        };
        i = 0;
        while (i < NUM_STEPS) {
            // sell X
            let input_x = step_size * i;
            let y_out = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
            let new_x = current_x + input_x;
            let new_y = current_y - y_out;
            if (ENABLE_PLOT) {
                debug::print(&new_x);
                debug::print(&new_y);
            };
            i = i + 1;
        };
    }

    #[test]
    fun test_get_swap_x_to_y_out_2() {
        // K = 10E9 * 10E9
        // W1 = 1.1
        // W2 = 1.05
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1;
        let current_x = BILLION / 100 * multiplier;
        let current_y = BILLION * multiplier;
        let mid_point = (BILLION - m) * multiplier;
        let step_size = (mid_point * 40) / NUM_STEPS;
        let i = 0;
        while (i < NUM_STEPS) {
            // sell X
            let input_x = step_size * i;
            let y_out = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
            let new_x = current_x + input_x;
            let new_y = current_y - y_out;
            if (ENABLE_PLOT) {
                debug::print(&new_x);
                debug::print(&new_y);
            };
            i = i + 1;
        };
    }

    #[test]
    fun test_swap_small_amount_precision() {
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1000000;
        let current_x = BILLION * multiplier;
        let current_y = BILLION * multiplier;
        let input_x = 1 * multiplier / 100;
        let output_y = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
        debug::print(&output_y);
        assert!(output_y > input_x * 999 / 1000, 0);
        assert!(output_y < input_x * 1001 / 1000, 0);
    }

    #[test]
    fun test_small_pool_small_amount_precision() {
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1000000;
        let current_x = 1000 * multiplier;
        let current_y = 1000 * multiplier;
        let input_x = 1 * multiplier;
        let output_y = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
        debug::print(&output_y);
        assert!(output_y > input_x * 999 / 1000, 0);
        assert!(output_y < input_x * 1001 / 1000, 0);
    }

    #[test]
    fun test_swap_small_amount_precision_at_joint() {
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1000000;
        // place curve at bottom-right joint
        let current_x = (xb-1) * multiplier;
        let current_y = xa * multiplier;
        let input_x = 100 * multiplier;
        let output_y = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
        debug::print(&output_y);
        assert!(output_y * 105 / 100 > input_x * 99 / 100, 0);
        assert!(output_y * 105 / 100 < input_x * 101 / 100, 0);
    }

    #[test]
    fun test_swap_smaller_amount_precision_at_joint() {
        /*
        Our current implementation lacks precision at the point where the pieces join.
        */
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1000000;
        // place curve at bottom-right joint
        let current_x = (xb-1) * multiplier;
        let current_y = xa * multiplier;
        let input_x = 10 * multiplier;
        let output_y = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
        debug::print(&output_y);
        assert!(output_y * 105 / 100 > input_x * 99 / 100, 0);
        assert!(output_y * 105 / 100 < input_x * 101 / 100, 0);
    }

    #[test]
    fun test_swap_large_amount_precision_at_joint() {
        /*
        Our current implementation lacks precision at the point where the pieces join.
        */
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1000000;
        // place curve at bottom-right joint
        let current_x = (xb-1) * multiplier;
        let current_y = xa * multiplier;
        let input_x = 1000000 * multiplier;
        let output_y = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
        debug::print(&output_y);
        assert!(output_y * 105 / 100 < input_x, 0);
    }

    #[test]
    fun test_swap_small_amount_precision_past_joint_b() {
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1000000;
        // place curve at bottom-right joint
        let current_x = (xb+1) * multiplier;
        let current_y = xa * multiplier;
        let input_x = 1 * multiplier;
        let output_y = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
        debug::print(&output_y);
        assert!(output_y * 105 / 100 > input_x * 999 / 1000, 0);
        assert!(output_y * 105 / 100 < input_x * 1001 / 1000, 0);
    }

    #[test]
    fun test_swap_small_amount_precision_past_joint_a() {
        let k = BILLION * BILLION;
        let (xa, xb, m, n, k2) = compute_initialization_constants(
            k,
            110,
            100,
            105,
            100,
        );
        let multiplier = 1000000;
        // place curve at bottom-right joint
        let current_x = xa * multiplier;
        let current_y = (xb+10) * multiplier;
        let input_x = 1 * multiplier;
        let output_y = get_swap_x_to_y_out(current_x, current_y, input_x, k, k2, xa, xb, m, n);
        debug::print(&output_y);
        assert!(output_y * 100 / 105 > input_x * 990 / 1000, 0);
        assert!(output_y * 100 / 105 < input_x * 1001 / 1000, 0);
    }
}
}

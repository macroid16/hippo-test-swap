// Math implementation for number manipulation.
module HippoSwap::Math {
    /// babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    public fun sqrt(y: u128): u128 {
        if (y < 4) {
            if (y == 0) {
                0u128
            } else {
                1u128
            }
        } else {
            let z = y;
            let x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            };
            z
        }
    }

    public fun min(a: u128, b: u128): u128 {
        if (a > b) b else a
    }

    // ================ Tests ================
    #[test]
    public fun sqrt_works() {
        assert!(sqrt(4) == 2, 0);
    }
}
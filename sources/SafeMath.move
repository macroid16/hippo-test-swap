// Safe math implementation for number manipulation.
// TODO: make it into more sophosticated math operations. Currently
// TODO: just some place holder for the interfaces for functionalities.
module HippoSwap::SafeMath {
    public fun add(a: u64, b: u64): u64 {
        a + b
    }

    public fun sub(a: u64, b: u64): u64 {
        a - b
    }

    // ================ Tests ================
    #[test]
    public fun add_works() {
        assert!(add(1, 1) == 2, 0);
    }
}
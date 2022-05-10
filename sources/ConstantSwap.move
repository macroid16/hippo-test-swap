module HippoSwap::ConstantSwap {
    use AptosFramework::Coin;
    public fun mint(): bool { true }


    // ================ Tests ================
    #[test_only]
    struct Token1 {}
    #[test_only]
    struct Token2 {}

    #[test(admin = @HippoSwap)]
    public(script) fun mint_works(admin: signer) {
        let decimals: u64 = 18;
        let total_supply: u64 = 1000000 * 10 ^ decimals;

        Coin::initialize<Token1>(&admin, b"token1", total_supply, true);
        assert!(mint(), 0);
    }
}
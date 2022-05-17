module HippoSwap::SwapConfig {

    public fun admin_address(): address {
        @HippoSwap
    }

    public fun fee_address(): address {
        @HippoSwapFee
    }

}

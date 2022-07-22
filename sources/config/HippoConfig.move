module HippoSwap::hippo_config {

    public fun admin_address(): address {
        @HippoSwap
    }

    #[test(admin = @HippoSwap, core_resource_account = @CoreResources)]
    fun addresses() {
        admin_address();
    }

}

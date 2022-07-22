module hippo_swap::hippo_config {

    public fun admin_address(): address {
        @hippo_swap
    }

    #[test]
    fun addresses() {
        admin_address();
    }

}

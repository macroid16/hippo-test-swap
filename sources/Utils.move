module hippo_swap::utils {
    use std::vector;
    use std::signer;

    struct PoolInfo has store, copy, drop {
        pool_type: u8,
        pool_idx: u8,
    }

    struct PoolList has key, copy, drop, store {
        list: vector<PoolInfo>,
    }

    public fun compute_pool_list(): PoolList {
        let list = vector::empty<PoolInfo>();
        vector::push_back(&mut list, PoolInfo {
            pool_type: 0,
            pool_idx: 0,
        });

        PoolList { list }
    }

    #[query]
    public entry fun get_pool_list(user: &signer) acquires PoolList {
        if (exists<PoolList>(signer::address_of(user))) {
            move_from<PoolList>(signer::address_of(user));
        };
        move_to<PoolList>(user, compute_pool_list())
    }

}

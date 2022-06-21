#[test_only]
module HippoSwap::Proc {

    // A use case which including 3 characters, the admin, the investor, and the swap guest.
    // We could observe the functionality by tracking the activity and the changes of the user account.
    //
    // The proc set up a system wide environment, prepare the pools of different kinds,
    // simulate the trading process continuously, gathering and verifing results to test
    // that the system acts as desired.
    //
    // The testing goals are:
    //
    // A standard set of procedures (state machine) that the pool follows:
    //   * initialize ( create pool )
    //   * add_liquidity
    //   * remove_liquidity
    //   * swap
    //   * withdraw_admin_fee
    //
    // Methods that we use to acquire the data in the interaction between users and pools:
    //   * Token Registry
    //   * Coin value
    //   * Pool info
    //
    // Verifications functions. We give some input and expect the predicted results.
    // Criterial indices:
    //   * accuracy
    //   * precision
    //   * numeric overflow
    //   * fees
    //   * pool balance
    //   * in out amount
    // These test should be able to perform continuously and get observable accumulation.

    use HippoSwap::TestShared;

    const ADMIN: address = @HippoSwap;
    const INVESTOR: address = @0x2FFF;
    const SWAPPER: address = @0x2FFE;

    const POOL_TYPE_CONSTANT_PRODUCT:u8 = 1;
    const POOL_TYPE_STABLE_CURVE:u8 = 2;
    const POOL_TYPE_PIECEWISE:u8 = 3;

    const E_UNKNOWN_POOL_TYPE: u64 = 1;

    // 10 to the power of n.
    const P3: u64 = 1000;
    const P4: u64 = 10000;
    const P5: u64 = 100000;
    const P6: u64 = 1000000;
    const P7: u64 = 10000000;
    const P8: u64 = 100000000;
    const P9: u64 = 1000000000;
    const P10: u64 = 10000000000;
    const P11: u64 = 100000000000;
    const P12: u64 = 1000000000000;
    const P13: u64 = 10000000000000;
    const P14: u64 = 100000000000000;
    const P15: u64 = 1000000000000000;
    const P16: u64 = 10000000000000000;
    const P17: u64 = 100000000000000000;        // 10 ** 8  * 10 ** 9  (billion)
    const P18: u64 = 1000000000000000000;



    #[test_only]
    public fun the_begining(admin: &signer, core: &signer) {
        TestShared::time_start(core);
        TestShared::init_regitry_and_mock_coins(admin);
    }

    // #[test(admin = @HippoSwap, investor = @0x2FFF, swapper = @0x2FFE, core = @0xa550c18)]
    // public fun test_process(admin: &signer, investor: &signer, swapper: &signer, core: &signer) {

    // }
}

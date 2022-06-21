#[test_only]
module HippoSwap::CPTest {

    use HippoSwap::MockCoin::{WUSDT, WUSDC, WDAI, WETH, WBTC, WDOT, WSOL};
    use HippoSwap::CPScripts::{create_new_pool};
    use Std::Signer;

    #[test_only]
    public fun create_pools(signer: &signer) {
        let addr = Signer::address_of(signer);
        let (fee_on, logo_url, project_url) = (true, b"", b"");

        let (lp1, lp2, lp3, lp4) = ( b"BTC-USDC-LP", b"ETH-USDT-LP", b"DOT-DAI-LP", b"SOL-USDC-LP");
        create_new_pool<WBTC, WUSDC>(signer, addr, fee_on, lp1, lp1, lp1, logo_url, project_url );
        create_new_pool<WETH, WUSDT>(signer, addr, fee_on, lp2, lp2, lp2, logo_url, project_url );
        create_new_pool<WDOT, WDAI>(signer, addr, fee_on, lp3, lp3, lp3, logo_url, project_url );
        create_new_pool<WSOL, WUSDC>(signer, addr, fee_on, lp4, lp4, lp4, logo_url, project_url );
    }


}

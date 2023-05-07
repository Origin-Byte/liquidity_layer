#[test_only]
/// This test focuses on integration between bidding contract, Kiosk,
/// a allowlist and royalty collection.
///
/// We simulate a trade between two Safes, end to end.
///
/// In this test, we use a generic collection, which means that the NFT is not
/// wrapped in our protocol's [`nft::Nft`] type.
module liquidity_layer::test_bidding {
    use sui::coin;
    use sui::package;
    use sui::transfer;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::test_scenario::{Self, ctx};

    use liquidity_layer::bidding::{Self, Bid};

    use ob_kiosk::ob_kiosk;
    use ob_request::transfer_request;

    const OFFER_SUI: u64 = 100;

    const CREATOR: address = @0xA1C05;
    const SELLER: address = @0xA1C06;
    const BUYER: address = @0xA1C07;

    struct Foo has key, store {
        id: UID,
    }

    struct Witness has drop {}

    #[test]
    fun test_successful_bid() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create TransferPolicy
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 3. Add NFT to Seller Kiosk
        let nft = Foo { id: object::new(ctx(&mut scenario)) };
        let nft_id = object::id(&nft);
        ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

        // 4. Create bid for NFT
        test_scenario::next_tx(&mut scenario, BUYER);
        let coins = coin::mint_for_testing<SUI>(OFFER_SUI, ctx(&mut scenario));

        bidding::create_bid(
            object::id(&buyer_kiosk),
            nft_id,
            OFFER_SUI,
            &mut coins,
            ctx(&mut scenario),
        );

        // 5. Accept Bid for NFT
        test_scenario::next_tx(&mut scenario, SELLER);

        let bid = test_scenario::take_shared<Bid<SUI>>(&mut scenario);

        let request = bidding::sell_nft_from_kiosk(
            &mut bid,
            &mut seller_kiosk,
            &mut buyer_kiosk,
            nft_id,
            ctx(&mut scenario),
        );

        transfer_request::confirm<Foo, SUI>(request, &tx_policy, ctx(&mut scenario));

        coin::burn_for_testing(coins);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        test_scenario::return_shared(bid);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = ob_kiosk::ob_kiosk::ENotAuthorized)]
    fun fail_accept_bid_if_not_seller() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create TransferPolicy
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 3. Add NFT to Seller Kiosk
        let nft = Foo { id: object::new(ctx(&mut scenario)) };
        let nft_id = object::id(&nft);
        ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

        // 4. Create bid for NFT
        test_scenario::next_tx(&mut scenario, BUYER);
        let coins = coin::mint_for_testing<SUI>(OFFER_SUI, ctx(&mut scenario));

        bidding::create_bid(
            object::id(&buyer_kiosk),
            nft_id,
            OFFER_SUI,
            &mut coins,
            ctx(&mut scenario),
        );

        // 5. Accept Bid for NFT
        test_scenario::next_tx(&mut scenario, CREATOR);

        let bid = test_scenario::take_shared<Bid<SUI>>(&mut scenario);

        let request = bidding::sell_nft_from_kiosk(
            &mut bid,
            &mut seller_kiosk,
            &mut buyer_kiosk,
            nft_id,
            ctx(&mut scenario),
        );

        transfer_request::confirm<Foo, SUI>(request, &tx_policy, ctx(&mut scenario));

        coin::burn_for_testing(coins);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        test_scenario::return_shared(bid);
        test_scenario::end(scenario);
    }

}

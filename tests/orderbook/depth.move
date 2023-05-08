#[test_only]
/// This test focuses on integration between OB, Safe, a allowlist and
/// royalty collection.
///
/// We simulate a trade between two Safes, end to end, including royalty
/// collection.
module liquidity_layer::test_orderbook_depth {
    use std::vector;

    use sui::coin;
    use sui::object::{Self, UID};
    use sui::package;
    use sui::transfer;
    use sui::sui::SUI;
    use sui::tx_context::TxContext;
    use sui::transfer_policy::TransferPolicy;
    use sui::test_scenario::{Self, ctx};

    use ob_permissions::witness;
    use ob_kiosk::ob_kiosk;
    use ob_request::transfer_request;

    use critbit::critbit_u64 as critbit;
    use liquidity_layer::orderbook::{Self, Orderbook};

    const OFFER_SUI: u64 = 100;

    const CREATOR: address = @0xA1C05;
    const SELLER: address = @0xA1C06;
    const BUYER: address = @0xA1C07;

    struct Foo has key, store {
        id: UID,
    }

    struct Witness has drop {}

    fun init_orderbook(policy: &TransferPolicy<Foo>, ctx: &mut TxContext) {
        let dw = witness::from_witness(Witness {});
    
        let ob = orderbook::new_unprotected<Foo, SUI>(dw, policy, ctx);
        orderbook::change_tick_size_with_witness(dw, &mut ob, 1);
        transfer::public_share_object(ob);
    }

    #[test]
    fun test_limit_ask_insert_and_popping_with_market_buy_with_depth() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        init_orderbook(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 5. Create asks order for NFT
        test_scenario::next_tx(&mut scenario, SELLER);   

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&scenario);

        // We had one here to account for the first iteration
        let price_levels = critbit::size(orderbook::borrow_asks(&book)) + 1;

        let quantity = 100;
        let depth = 10;
        let j = 0;

        let i = quantity;
        let price = 1;

        while (i > 0) {
            // debug::print(&i);
            test_scenario::next_tx(&mut scenario, SELLER);

            // Create and deposit NFT
            let nft = Foo { id: object::new(ctx(&mut scenario)) };
            let nft_id = object::id(&nft);
            ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

            orderbook::create_ask(
                &mut book,
                &mut seller_kiosk,
                price,
                nft_id,
                ctx(&mut scenario),
            );

            j = j + 1;

            // Assersions
            // 1. NFT is exclusively listed in the Seller Kiosk
            ob_kiosk::assert_exclusively_listed(&mut seller_kiosk, nft_id);

            // 2. New price level gets added with new Ask
            assert!(critbit::size(orderbook::borrow_asks(&book)) == price_levels, 0);

            if (j == depth) {
                price_levels = price_levels + 1;
                price = price + 1;
                j = 0;
            };

            i = i - 1;
        };

        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 1)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 2)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 3)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 4)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 5)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 6)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 7)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 8)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 9)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 10)) == 10, 0);
        assert!(critbit::has_leaf(orderbook::borrow_asks(&book), 11) == false, 0);

        test_scenario::next_tx(&mut scenario, BUYER);

        let i = quantity;
        // Buyer gets best price (lowest)
        let price = 1;
        let j = 0;

        // 6. Create market bids

        let coin = coin::mint_for_testing<SUI>(1_000_000, ctx(&mut scenario));

        while (i > 0) {
            test_scenario::next_tx(&mut scenario, BUYER);

            let trade_info = orderbook::market_buy(
                &mut book,
                &mut buyer_kiosk,
                &mut coin,
                price,
                ctx(&mut scenario),
            );

            j = j + 1;

            assert!(orderbook::trade_price(&trade_info) == price, 0);

            if (j == depth) {
                price_levels = price_levels - 1;
                price = price + 1;
                j = 0;
            };

            i = i - 1;
        };

        // Assert that orderbook is empty
        assert!(critbit::is_empty(orderbook::borrow_bids(&book)), 0);
        assert!(critbit::is_empty(orderbook::borrow_asks(&book)), 0);

        coin::burn_for_testing(coin);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        test_scenario::return_shared(book);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_limit_bid_insert_and_popping_with_market_sell_with_depth() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        init_orderbook(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 5. Create bid order for NFTs
        test_scenario::next_tx(&mut scenario, SELLER);

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&scenario);

        // We had one here to account for the firs iteration
        let initial_funds = 1_000_000;
        let funds_locked = 0;

        let price_levels = critbit::size(orderbook::borrow_bids(&book)) + 1;
        let coin = coin::mint_for_testing<SUI>(initial_funds, ctx(&mut scenario));

        let quantity = 100;
        let depth = 10;
        let j = 0;

        let i = quantity;
        let price = 1;

        while (i > 0) {
            test_scenario::next_tx(&mut scenario, BUYER);

            orderbook::create_bid(
                &mut book,
                &mut buyer_kiosk,
                price,
                &mut coin,
                ctx(&mut scenario),
            );

            j = j + 1;

            // Register funds locked in the Bid
            funds_locked = funds_locked + price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. New price level gets added with new Bid
            assert!(critbit::size(orderbook::borrow_bids(&book)) == price_levels, 0);

            if (j == depth) {
                price_levels = price_levels + 1;
                price = price + 1;
                j = 0;
            };

            i = i - 1;
        };

        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 1)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 2)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 3)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 4)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 5)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 6)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 7)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 8)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 9)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 10)) == 10, 0);
        assert!(critbit::has_leaf(orderbook::borrow_bids(&book), 11) == false, 0);


        test_scenario::next_tx(&mut scenario, SELLER);

        let i = quantity;
        // Buyer gets best price (lowest)
        let price = 10;
        let j = 0;

        // 6. Create market sells

        while (i > 0) {
            test_scenario::next_tx(&mut scenario, SELLER);

            // Create and deposit NFT
            let nft = Foo { id: object::new(ctx(&mut scenario)) };
            let nft_id = object::id(&nft);
            ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

            let trade_info = orderbook::market_sell(
                &mut book,
                &mut seller_kiosk,
                price,
                nft_id,
                ctx(&mut scenario),
            );

            j = j + 1;

            assert!(orderbook::trade_price(&trade_info) == price, 0);

            if (j == depth) {
                price_levels = price_levels - 1;
                price = price - 1;
                j = 0;
            };

            i = i - 1;
        };

        // Assert that orderbook is empty
        assert!(critbit::is_empty(orderbook::borrow_bids(&book)), 0);
        assert!(critbit::is_empty(orderbook::borrow_asks(&book)), 0);

        coin::burn_for_testing(coin);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        test_scenario::return_shared(book);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_asks_with_depth() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        init_orderbook(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 5. Create bid order for NFTs
        test_scenario::next_tx(&mut scenario, SELLER);

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&scenario);

        // We had one here to account for the first iteration
        let price_levels = critbit::size(orderbook::borrow_asks(&book)) + 1;

        let quantity = 100;
        let depth = 10;
        let j = 0;

        let i = quantity;
        let price = 1;

        let nfts = vector::empty();

        while (i > 0) {
            // debug::print(&i);
            test_scenario::next_tx(&mut scenario, SELLER);

            // Create and deposit NFT
            let nft = Foo { id: object::new(ctx(&mut scenario)) };
            let nft_id = object::id(&nft);
            vector::push_back(&mut nfts, nft_id);

            ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

            orderbook::create_ask(
                &mut book,
                &mut seller_kiosk,
                price,
                nft_id,
                ctx(&mut scenario),
            );

            j = j + 1;

            // Assersions
            // 1. NFT is exclusively listed in the Seller Kiosk
            ob_kiosk::assert_exclusively_listed(&mut seller_kiosk, nft_id);

            // 2. New price level gets added with new Ask
            assert!(critbit::size(orderbook::borrow_asks(&book)) == price_levels, 0);

            if (j == depth) {
                price_levels = price_levels + 1;
                price = price + 1;
                j = 0;
            };

            i = i - 1;
        };

        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 1)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 2)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 3)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 4)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 5)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 6)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 7)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 8)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 9)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_asks(&book), 10)) == 10, 0);
        assert!(critbit::has_leaf(orderbook::borrow_asks(&book), 11) == false, 0);

        let i = quantity;
        let price = 10;
        let j = 0;

        // // 6. Cancel orders
        while (i > 0) {
            test_scenario::next_tx(&mut scenario, SELLER);
            let nft_id = vector::pop_back(&mut nfts);

            orderbook::cancel_ask(
                &mut book,
                &mut seller_kiosk,
                price,
                nft_id,
                ctx(&mut scenario),
            );

            j = j + 1;

            if (j == depth) {
                price_levels = price_levels - 1;
                price = price - 1;
                j = 0;
            };

            i = i - 1;
        };

        // Assert that orderbook state
        assert!(critbit::is_empty(orderbook::borrow_asks(&book)), 0);

        // coin::burn_for_testing(coin);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        test_scenario::return_shared(book);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_cancel_bids_with_depth() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        init_orderbook(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 5. Create bid order for NFTs
        test_scenario::next_tx(&mut scenario, SELLER);

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&scenario);

        // We had one here to account for the firs iteration
        let initial_funds = 1_000_000;
        let funds_locked = 0;

        let price_levels = critbit::size(orderbook::borrow_bids(&book)) + 1;
        let coin = coin::mint_for_testing<SUI>(initial_funds, ctx(&mut scenario));

        let quantity = 100;
        let depth = 10;
        let j = 0;

        let i = quantity;
        let price = 1;

        while (i > 0) {
            test_scenario::next_tx(&mut scenario, BUYER);

            orderbook::create_bid(
                &mut book,
                &mut buyer_kiosk,
                price,
                &mut coin,
                ctx(&mut scenario),
            );

            j = j + 1;

            // Register funds locked in the Bid
            funds_locked = funds_locked + price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. New price level gets added with new Bid
            assert!(critbit::size(orderbook::borrow_bids(&book)) == price_levels, 0);

            if (j == depth) {
                price_levels = price_levels + 1;
                price = price + 1;
                j = 0;
            };

            i = i - 1;
        };

        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 1)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 2)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 3)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 4)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 5)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 6)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 7)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 8)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 9)) == 10, 0);
        assert!(vector::length(critbit::borrow_leaf_by_key(orderbook::borrow_bids(&book), 10)) == 10, 0);
        assert!(critbit::has_leaf(orderbook::borrow_bids(&book), 11) == false, 0);

        let i = quantity;
        let price = 10;

        // 6. Cancel orders
        while (i > 0) {
            test_scenario::next_tx(&mut scenario, BUYER);

            orderbook::cancel_bid(
                &mut book,
                price,
                &mut coin,
                ctx(&mut scenario),
            );

            j = j + 1;

            if (j == depth) {
                price_levels = price_levels - 1;
                price = price - 1;
                j = 0;
            };


            i = i - 1;
        };

        // Assert that orderbook state
        assert!(critbit::is_empty(orderbook::borrow_bids(&book)), 0);

        coin::burn_for_testing(coin);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        test_scenario::return_shared(book);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_edit_asks() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        init_orderbook(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 5. Create bid order for NFTs
        test_scenario::next_tx(&mut scenario, SELLER);

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&scenario);

        let coin = coin::mint_for_testing<SUI>(1_000_000, ctx(&mut scenario));

        let quantity = 300;
        let i = quantity;
        let price = 300;

        let nfts = vector::empty();

        while (i > 0) {
            test_scenario::next_tx(&mut scenario, SELLER);

            // Create and deposit NFT
            let nft = Foo { id: object::new(ctx(&mut scenario)) };
            let nft_id = object::id(&nft);
            vector::push_back(&mut nfts, nft_id);

            ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

            orderbook::create_ask(
                &mut book,
                &mut seller_kiosk,
                price,
                nft_id,
                ctx(&mut scenario),
            );

            i = i - 1;
            price = price - 1;
        };

        // Assert that orderbook state
        let (max_key, _) = critbit::max_leaf(orderbook::borrow_asks(&book));
        assert!(max_key == 300, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_asks(&book));
        assert!(min_key == 1, 0);
        assert!(critbit::size(orderbook::borrow_asks(&book)) == 300, 0);

        let i = quantity;
        let price = 1;

        // 6. Cancel orders
        while (i > 0) {
            test_scenario::next_tx(&mut scenario, SELLER);
            let nft_id = vector::pop_back(&mut nfts);

            orderbook::edit_ask(
                &mut book,
                &mut seller_kiosk,
                price,
                nft_id,
                500,
                ctx(&mut scenario),
            );

            price = price + 1;
            i = i - 1;
        };

        // Assert that orderbook state
        // All orders are concentrated into one price level
        assert!(critbit::size(orderbook::borrow_asks(&book)) == 1, 0);

        let (max_key, _) = critbit::max_leaf(orderbook::borrow_asks(&book));
        assert!(max_key == 500, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_asks(&book));
        assert!(min_key == 500, 0);

        coin::burn_for_testing(coin);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        test_scenario::return_shared(book);
        test_scenario::end(scenario);
    }
}

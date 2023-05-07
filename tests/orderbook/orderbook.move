#[test_only]
/// This test focuses on integration between OrderBook and Kiosk.
module liquidity_layer::test_orderbook {
    use std::option;
    use std::vector;

    use sui::coin;
    use sui::object::{Self, UID};
    use sui::kiosk;
    use sui::package;
    use sui::transfer;
    use sui::sui::SUI;
    use sui::test_scenario::{Self, ctx};
    use sui::transfer_policy::{Self, TransferPolicy};
    use sui::tx_context::TxContext;

    // TODO:
    // fun it_fails_if_buyer_safe_eq_seller_safe()
    // fun it_fails_if_buyer_safe_eq_seller_safe_with_generic_collection()
    // fun it_fails_if_buyer_safe_eq_seller_safe_with_generic_collection() {
    use ob_permissions::witness;
    use ob_request::transfer_request;
    use ob_kiosk::ob_kiosk::{Self, OwnerToken};

    use liquidity_layer::orderbook::{Self, Orderbook};

    use critbit::critbit_u64 as critbit;

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
        orderbook::change_tick_size(dw, &mut ob, 1);
        orderbook::share(ob);
    }

    #[test]
    fun create_exclusive_orderbook_as_originbyte_collection() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create OriginByte TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (transfer_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        // This function can only be called if the TransferPolicy is created
        // from OriginByte's transfer_request module, or if at any time the
        // creator adds an OriginByte rule to their TransferPolicy object.
        init_orderbook(&transfer_policy, ctx(&mut scenario));

        transfer::public_share_object(transfer_policy);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(publisher, CREATOR);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = orderbook::ENotOriginBytePolicy)]
    fun fail_create_exclusive_orderbook_as_non_originbyte_collection() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create OriginByte TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (transfer_policy, policy_cap) = transfer_policy::new<Foo>(&publisher, ctx(&mut scenario));

        // This function can only be called if the TransferPolicy is created
        // from OriginByte's transfer_request module, or if at any time the
        // creator adds an OriginByte rule to their TransferPolicy object.
        init_orderbook(&transfer_policy, ctx(&mut scenario));

        transfer::public_share_object(transfer_policy);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(publisher, CREATOR);
        test_scenario::end(scenario);
    }

    #[test]
    fun create_non_exclusive_orderbook_as_non_originbyte_collection() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create OriginByte TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (transfer_policy, policy_cap) = transfer_policy::new<Foo>(&publisher, ctx(&mut scenario));

        // This function can only be called if the TransferPolicy is external
        // to OriginByte, in other words, if the creator did not use OriginByte
        // transfer_request module to initiate the policy or never added OriginByte
        // rules to the policy.
        orderbook::create_for_external<Foo, SUI>(
            &transfer_policy, ctx(&mut scenario),
        );

        // When this is the case, anyone can come in a create an orderbook
        orderbook::create_for_external<Foo, SUI>(
            &transfer_policy, ctx(&mut scenario),
        );

        transfer::public_share_object(transfer_policy);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(publisher, CREATOR);
        test_scenario::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = orderbook::ENotExternalPolicy)]
    fun fail_create_non_exclusive_orderbook_as_originbyte_collection() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create OriginByte TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (transfer_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        // When this is the case, anyone can come in a create an orderbook
        orderbook::create_for_external<Foo, SUI>(
            &transfer_policy, ctx(&mut scenario),
        );

        transfer::public_share_object(transfer_policy);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(publisher, CREATOR);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_trade_in_ob_kiosk() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_request::init_policy<Foo>(&publisher, ctx(&mut scenario));

        init_orderbook(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 3. Add NFT to Seller Kiosk
        let nft = Foo { id: object::new(ctx(&mut scenario)) };
        let nft_id = object::id(&nft);
        ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

        // 4. Create ask order for NFT
        test_scenario::next_tx(&mut scenario, SELLER);
        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        orderbook::create_ask(
            &mut book,
            &mut seller_kiosk,
            100,
            nft_id,
            ctx(&mut scenario),
        );

        // 5. Create bid for NFT
        test_scenario::next_tx(&mut scenario, BUYER);

        let coin = coin::mint_for_testing<SUI>(100, ctx(&mut scenario));

        let trade_opt = orderbook::create_bid(
            &mut book,
            &mut buyer_kiosk,
            100,
            &mut coin,
            ctx(&mut scenario),
        );

        let trade = option::destroy_some(trade_opt);

        // 6. Finish trade
        test_scenario::next_tx(&mut scenario, CREATOR);

        let request = orderbook::finish_trade(
            &mut book,
            orderbook::trade_id(&trade),
            &mut seller_kiosk,
            &mut buyer_kiosk,
            ctx(&mut scenario),
        );

        transfer_request::confirm<Foo, SUI>(request, &tx_policy, ctx(&mut scenario));

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
    fun test_trade_with_sui_policy() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_policy::new<Foo>(&publisher, ctx(&mut scenario));

        orderbook::create_for_external<Foo, SUI>(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        let (buyer_kiosk, _) = ob_kiosk::new_for_address(BUYER, ctx(&mut scenario));
        let (seller_kiosk, _) = ob_kiosk::new_for_address(SELLER, ctx(&mut scenario));

        // 3. Add NFT to Seller Kiosk
        let nft = Foo { id: object::new(ctx(&mut scenario)) };
        let nft_id = object::id(&nft);
        ob_kiosk::deposit(&mut seller_kiosk, nft, ctx(&mut scenario));

        // 4. Create ask order for NFT
        test_scenario::next_tx(&mut scenario, SELLER);
        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);
        
        orderbook::create_ask(
            &mut book,
            &mut seller_kiosk,
            100_000_000,
            nft_id,
            ctx(&mut scenario),
        );

        // 5. Create bid for NFT
        test_scenario::next_tx(&mut scenario, BUYER);
        let coin = coin::mint_for_testing<SUI>(100_000_000, ctx(&mut scenario));

        let trade_opt = orderbook::create_bid(
            &mut book,
            &mut buyer_kiosk,
            100_000_000,
            &mut coin,
            ctx(&mut scenario),
        );

        let trade = option::destroy_some(trade_opt);

        // 6. Finish trade
        test_scenario::next_tx(&mut scenario, CREATOR);

        let request = orderbook::finish_trade(
            &mut book,
            orderbook::trade_id(&trade),
            &mut seller_kiosk,
            &mut buyer_kiosk,
            ctx(&mut scenario),
        );

        let sui_request = transfer_request::into_sui<Foo>(request, &tx_policy, ctx(&mut scenario));
        transfer_policy::confirm_request<Foo>(&tx_policy, sui_request);

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
    fun test_trade_from_sui_kiosk() {
        let scenario = test_scenario::begin(CREATOR);

        // 1. Create Collection, TransferPolicy and Orderbook
        let publisher = package::test_claim(Witness {}, ctx(&mut scenario));
        let (tx_policy, policy_cap) = transfer_policy::new<Foo>(&publisher, ctx(&mut scenario));

        orderbook::create_for_external<Foo, SUI>(&tx_policy, ctx(&mut scenario));

        // 2. Create Kiosks
        test_scenario::next_tx(&mut scenario, BUYER);
        let (buyer_kiosk, buyer_cap) = kiosk::new(ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, SELLER);
        let (seller_kiosk, seller_cap) = kiosk::new(ctx(&mut scenario));

        // 4. Add NFT to Seller Kiosk
        let nft = Foo { id: object::new(ctx(&mut scenario)) };
        let nft_id = object::id(&nft);
        kiosk::place(&mut seller_kiosk, &seller_cap, nft);

        // 5. Create ask order for NFT
        ob_kiosk::install_extension(&mut seller_kiosk, seller_cap, ctx(&mut scenario));
        ob_kiosk::register_nft<Foo>(&mut seller_kiosk, nft_id, ctx(&mut scenario));

        // 6. Create ask for NFT
        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        orderbook::create_ask(
            &mut book,
            &mut seller_kiosk,
            100_000_000,
            nft_id,
            ctx(&mut scenario),
        );

        test_scenario::next_tx(&mut scenario, BUYER);

        // 6. Create bid for NFT
        let coin = coin::mint_for_testing<SUI>(100_000_000, ctx(&mut scenario));
        ob_kiosk::install_extension(&mut buyer_kiosk, buyer_cap, ctx(&mut scenario));

        let trade_opt = orderbook::create_bid(
            &mut book,
            &mut buyer_kiosk,
            100_000_000,
            &mut coin,
            ctx(&mut scenario),
        );

        let trade = option::destroy_some(trade_opt);

        let request = orderbook::finish_trade(
            &mut book,
            orderbook::trade_id(&trade),
            &mut seller_kiosk,
            &mut buyer_kiosk,
            ctx(&mut scenario),
        );

        let sui_request = transfer_request::into_sui<Foo>(request, &tx_policy, ctx(&mut scenario));
        transfer_policy::confirm_request<Foo>(&tx_policy, sui_request);

        // 7. Leave OriginByte
        let seller_token = test_scenario::take_from_address<OwnerToken>(
            &scenario, SELLER
        );

        test_scenario::next_tx(&mut scenario, SELLER);
        ob_kiosk::uninstall_extension(&mut seller_kiosk, seller_token, ctx(&mut scenario));

        coin::burn_for_testing(coin);
        transfer::public_transfer(publisher, CREATOR);
        transfer::public_transfer(policy_cap, CREATOR);
        transfer::public_transfer(tx_policy, CREATOR);
        transfer::public_transfer(seller_kiosk, CREATOR);
        transfer::public_transfer(buyer_kiosk, CREATOR);
        test_scenario::return_shared(book);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_limit_ask_insert_and_popping_with_market_buy() {
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
    
        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        let price_levels = critbit::size(orderbook::borrow_asks(&book));

        let quantity = 300;
        let i = quantity;
        let price = 1;

        while (i > 0) {
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

            // Assersions
            // 1. NFT is exclusively listed in the Seller Kiosk
            ob_kiosk::assert_exclusively_listed(&mut seller_kiosk, nft_id);

            // 2. New price level gets added with new Ask
            price_levels = price_levels + 1;
            assert!(critbit::size(orderbook::borrow_asks(&book)) == price_levels, 0);

            i = i - 1;
            price = price + 1;
        };

        test_scenario::next_tx(&mut scenario, BUYER);

        let i = quantity;
        // Buyer gets best price (lowest)
        let price = 1;

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

            assert!(orderbook::trade_price(&trade_info) == price, 0);
            price = price + 1;
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
    fun test_limit_bid_insert_and_popping_with_market_sell() {
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

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        let initial_funds = 1_000_000;
        let price_levels = critbit::size(orderbook::borrow_bids(&book));
        let funds_locked = 0;

        let coin = coin::mint_for_testing<SUI>(initial_funds, ctx(&mut scenario));

        let quantity = 300;
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

            // Register funds locked in the Bid
            funds_locked = funds_locked + price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. New price level gets added with new Bid
            price_levels = price_levels + 1;
            assert!(critbit::size(orderbook::borrow_bids(&book)) == price_levels, 0);

            price = price + 1;
            i = i - 1;
        };

        test_scenario::next_tx(&mut scenario, BUYER);

        let i = quantity;
        // Seller gets best price (highest)
        let price = 300;

        // 6. Create market bids

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

            assert!(orderbook::trade_price(&trade_info) == price, 0);

            i = i - 1;
            price = price - 1;
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
    fun test_limit_ask_insert_and_popping_with_limit_buy() {
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
    
        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        let price_levels = critbit::size(orderbook::borrow_asks(&book));

        let quantity = 300;
        let i = quantity;
        let price = 1;

        while (i > 0) {
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

            // Assersions
            // 1. NFT is exclusively listed in the Seller Kiosk
            ob_kiosk::assert_exclusively_listed(&mut seller_kiosk, nft_id);

            // 2. New price level gets added with new Ask
            price_levels = price_levels + 1;
            assert!(critbit::size(orderbook::borrow_asks(&book)) == price_levels, 0);

            i = i - 1;
            price = price + 1;
        };

        test_scenario::next_tx(&mut scenario, BUYER);

        // Buyer gets best price (lowest)
        let price = 1;
        let i = quantity;

        // 6. Create market bids
        let initial_funds = 1_000_000;
        let funds_sent = 0;
        let coin = coin::mint_for_testing<SUI>(initial_funds, ctx(&mut scenario));

        while (i > 0) {
            test_scenario::next_tx(&mut scenario, BUYER);

            let trade_info_opt = orderbook::create_bid(
                &mut book,
                &mut buyer_kiosk,
                price,
                &mut coin,
                ctx(&mut scenario),
            );

            // Register funds sent
            funds_sent = funds_sent + price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_sent, 0);

            // 2. Ask gets popped and price level removed
            price_levels = price_levels - 1;
            assert!(critbit::size(orderbook::borrow_asks(&book)) == price_levels, 0);

            // 3. Assert trade match
            let trade_info = option::extract(&mut trade_info_opt);
            option::destroy_none(trade_info_opt);
            assert!(orderbook::trade_price(&trade_info) == price, 0);

            price = price + 1;
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
    fun test_limit_bid_and_limit_sell_inserts() {
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

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        let initial_funds = 1_000_000;
        let bid_price_levels = critbit::size(orderbook::borrow_bids(&book));
        let funds_locked = 0;

        let coin = coin::mint_for_testing<SUI>(1_000_000, ctx(&mut scenario));

        let quantity = 300;
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

            // Register funds locked in the Bid
            funds_locked = funds_locked + price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. New price level gets added with new Bid
            bid_price_levels = bid_price_levels + 1;
            assert!(critbit::size(orderbook::borrow_bids(&book)) == bid_price_levels, 0);

            price = price + 1;
            i = i - 1;
        };

        test_scenario::next_tx(&mut scenario, BUYER);

        // Seller gets best price (highest)
        let ask_price_levels = critbit::size(orderbook::borrow_asks(&book));
        let price = 301;
        let i = quantity;

        // 6. Create limit ask

        while (i > 0) {
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

            // Assersions
            // 1. NFT is exclusively listed in the Seller Kiosk
            ob_kiosk::assert_exclusively_listed(&mut seller_kiosk, nft_id);

            // 2. New price level gets added with new Ask
            ask_price_levels = ask_price_levels + 1;
            assert!(critbit::size(orderbook::borrow_asks(&book)) == ask_price_levels, 0);

            i = i - 1;
            price = price + 1;
        };

        // Assert orderbook state
        let (max_key, _) = critbit::max_leaf(orderbook::borrow_bids(&book));
        assert!(max_key == 300, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_bids(&book));
        assert!(min_key == 1, 0);

        let (max_key, _) = critbit::max_leaf(orderbook::borrow_asks(&book));
        assert!(max_key == 600, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_asks(&book));
        assert!(min_key == 301, 0);

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
    fun test_cancel_asks() {
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

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

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

        let i = quantity;
        let price = 1;

        // 6. Cancel orders
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

            price = price + 1;
            i = i - 1;
        };

        // Assert that orderbook state
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
    fun test_cancel_bids() {
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

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        let initial_funds = 1_000_000;
        let price_levels = critbit::size(orderbook::borrow_bids(&book));
        let funds_locked = 0;

        let coin = coin::mint_for_testing<SUI>(initial_funds, ctx(&mut scenario));

        let quantity = 300;
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

            // Register funds locked in the Bid
            funds_locked = funds_locked + price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. New price level gets added with new Bid
            price_levels = price_levels + 1;
            assert!(critbit::size(orderbook::borrow_bids(&book)) == price_levels, 0);

            price = price + 1;
            i = i - 1;
        };

        // Assert that orderbook state
        let (max_key, _) = critbit::max_leaf(orderbook::borrow_bids(&book));
        assert!(max_key == 300, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_bids(&book));
        assert!(min_key == 1, 0);

        let i = quantity;
        let price = 1;

        // 6. Cancel orders
        while (i > 0) {
            test_scenario::next_tx(&mut scenario, BUYER);

            orderbook::cancel_bid(
                &mut book,
                price,
                &mut coin,
                ctx(&mut scenario),
            );

            // Register funds unlocked with the Bid cancellation
            funds_locked = funds_locked - price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. New price level gets removed with Bid popped
            price_levels = price_levels - 1;
            assert!(critbit::size(orderbook::borrow_bids(&book)) == price_levels, 0);

            price = price + 1;
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

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

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
        assert!(critbit::size(orderbook::borrow_asks(&book)) == 300, 0);

        let (max_key, _) = critbit::max_leaf(orderbook::borrow_asks(&book));
        assert!(max_key == 300, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_asks(&book));
        assert!(min_key == 1, 0);

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

    #[test]
    fun test_edit_bids() {
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

        let book = test_scenario::take_shared<Orderbook<Foo, SUI>>(&mut scenario);

        let initial_funds = 1_000_000;
        let price_levels = critbit::size(orderbook::borrow_bids(&book));
        let funds_locked = 0;

        let coin = coin::mint_for_testing<SUI>(initial_funds, ctx(&mut scenario));

        let quantity = 300;
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

            // Register funds locked in the Bid
            funds_locked = funds_locked + price;

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. New price level gets added with new Bid
            price_levels = price_levels + 1;
            assert!(critbit::size(orderbook::borrow_bids(&book)) == price_levels, 0);

            price = price + 1;
            i = i - 1;
        };

        // Assert orderbook state
        let (max_key, _) = critbit::max_leaf(orderbook::borrow_bids(&book));
        assert!(max_key == 300, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_bids(&book));
        assert!(min_key == 1, 0);

        let i = quantity;
        let price = 1;

        // 6. Cancel orders
        while (i > 0) {
            test_scenario::next_tx(&mut scenario, BUYER);

            orderbook::edit_bid(
                &mut book,
                &mut buyer_kiosk,
                price,
                500,
                &mut coin,
                ctx(&mut scenario),
            );

            // Register funds locked in the Bid
            funds_locked = funds_locked + (500 - price);

            // Assersions
            // 1. Funds withdrawn from Wallet
            assert!(coin::value(&coin) == initial_funds - funds_locked, 0);

            // 2. Number of Bids however they all get concentrated into the same
            // price level - In the first iteration the length does not really change because
            // we are just swapping one price level for another.
            price_levels = if (i == quantity) {price_levels} else {price_levels - 1};
            assert!(critbit::size(orderbook::borrow_bids(&book)) == price_levels, 0);

            price = price + 1;
            i = i - 1;
        };

        // Assert orderbook state
        // All orders are concentrated into one price level
        assert!(critbit::size(orderbook::borrow_bids(&book)) == 1, 0);

        let (max_key, _) = critbit::max_leaf(orderbook::borrow_bids(&book));
        assert!(max_key == 500, 0);
        let (min_key, _) = critbit::min_leaf(orderbook::borrow_bids(&book));
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

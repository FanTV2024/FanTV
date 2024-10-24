module xfantv::xfantv{
    // use std::option;
    use sui::coin::{Self, TreasuryCap};
    use sui::token::{Self,Token};
    // use sui::transfer;
    // use sui::tx_context::{Self, TxContext};
    // use sui::object::{Self,UID};
    use sui::url::{new_unsafe_from_bytes};
    use sui::event;


    public struct XFANTV has drop{}
    // public struct AdminCap has key { id: UID }

    const BalanceIsZero: u64 = 0;
    const LIMIT_EXCEEDED: u64 = 1;
    const NOT_AN_ADMIN: u64 = 2;
    
    public struct CoinStore has key {
        id: UID,
        coin_treasury : TreasuryCap<XFANTV>
    }
    
    public struct Wallet has key, store {
        id:UID,
        beneficiary:address,
        amount: u64
    }

    public struct SuperAdminCap has key { id: UID }

    public struct AdminCap has key {
        id: UID,
        admins: vector<address>,
    }

    public struct WalletCap has key {
        id: UID    
    }

    public struct MaxCredit has key , store {
        id:UID,
        amount: u64
    }

    public struct SpendCoin has drop {}

    // events
   
    public struct TokenCredited has copy, drop {
        beneficiary: address,
        amount: u64,
    }

     public struct TokenMinted has copy, drop {
        beneficiary: address,
        amount: u64,
    }

     public struct TokenDebited has copy, drop {
        spender: address,
        amount: u64,
    }

    public struct AdminAdded has copy, drop{
        admin: address
    }

     public struct AdminRemoved has copy, drop{
        admin: address
    }
 

    public struct WalletCapGranted has copy, drop{
        to_address: address
    }
    
    fun init(witness:XFANTV, ctx: &mut TxContext,){
            let url = new_unsafe_from_bytes(b"https://assets.artistfirst.in/uploads/1715789262935-FanTV.png");
            let (treasuryCap, metaData) = coin::create_currency(
                witness,
                9,
                b"$FAN",
                b"xFanTV",
                b"xFanTV represents the platform token linked to FanTV, offering ownership in the platform",
                option::some(url),
                ctx,
            );

        let (mut policy, policy_cap) = token::new_policy(&treasuryCap, ctx);

        // but we constrain spend by this
        token::add_rule_for_action<XFANTV, SpendCoin>(
            &mut policy,
            &policy_cap,
            token::spend_action(),
            ctx
        );

        token::share_policy(policy);
        transfer::public_transfer(policy_cap, tx_context::sender(ctx));
        transfer::public_transfer(metaData,tx_context::sender(ctx));

        transfer::transfer(SuperAdminCap{id: object::new(ctx)},tx_context::sender(ctx));

        transfer::transfer(WalletCap{id: object::new(ctx)},tx_context::sender(ctx));


         let admin_cap = AdminCap {
            id:object::new(ctx),
            admins: vector[tx_context::sender(ctx)]
        };
        let max_limit = MaxCredit{
             id:object::new(ctx),
             amount: 0
        };

        transfer::share_object(admin_cap);

        transfer::share_object(max_limit);

        transfer::share_object(CoinStore {
            id: object::new(ctx),
            coin_treasury: treasuryCap
        });

    }


    // init user wallet to store credit_coins
    
    public fun init_wallet(_: &WalletCap,beneficiary: address, ctx: &mut TxContext){
        let wallet = Wallet {
            id: object::new(ctx),
            beneficiary,
            amount: 0,
        };
        transfer::share_object(wallet);
    }


    public fun grant_wallet_cap(_:&SuperAdminCap,to_address:address, ctx: &mut TxContext ){
        transfer::transfer(WalletCap{id: object::new(ctx)},to_address);
        event::emit(WalletCapGranted{to_address:to_address});
    }

   
    public fun mint_and_transfer(_:&SuperAdminCap,coin_store:&mut CoinStore,amount:u64, recipient:address, ctx: &mut TxContext ){
        let coin = token::mint(&mut coin_store.coin_treasury, amount, ctx);
        let req = token::transfer(coin, recipient, ctx);
        token::confirm_with_treasury_cap(&mut coin_store.coin_treasury, req, ctx);
        event::emit(TokenMinted{beneficiary:recipient, amount:amount});

    }

    public fun ern_xft(
        admin_cap: &AdminCap,
        max_credit:&MaxCredit,
        wallet: &mut Wallet,
        credit_amount:u64,
        ctx: &mut TxContext
    ) {
        assert!(is_admin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
        assert!(credit_amount <  max_credit.amount , LIMIT_EXCEEDED);
        wallet.amount = wallet.amount + credit_amount;
        event::emit(TokenCredited{beneficiary:wallet.beneficiary, amount:credit_amount});
    }

     public fun spnd_xft(
        payment: Token<XFANTV>,
        coin_store:&mut CoinStore,
        ctx: &mut TxContext
    ){
        event::emit(TokenDebited{spender:tx_context::sender(ctx), amount: token::value(&payment)});
        let mut req = token::spend(payment, ctx);
        token::add_approval(SpendCoin {}, &mut req, ctx);
        token::confirm_with_treasury_cap(&mut coin_store.coin_treasury, req, ctx);
    }

     public fun claim_token(
     wallet: &mut Wallet,coin_store:&mut CoinStore,  ctx: &mut TxContext
    ){
        assert!(wallet.amount > 0, BalanceIsZero);

        event::emit(TokenMinted{beneficiary:wallet.beneficiary, amount:wallet.amount});

        let coins = token::mint(&mut coin_store.coin_treasury, wallet.amount, ctx);
        let req = token::transfer(coins, wallet.beneficiary, ctx);
        wallet.amount=0;
        token::confirm_with_treasury_cap(&mut coin_store.coin_treasury, req, ctx);
    }

     // check if an address is admin 

    fun is_admin(admin_cap: &AdminCap, admin_address: address):(bool) {

        let (existed, _) = vector::index_of(&admin_cap.admins, &admin_address);
        existed
    }


    // update Max Credit 

    public fun update_max_credit(_: &SuperAdminCap, amount: u64, max_credit: &mut MaxCredit){
        max_credit.amount = amount;
    }

    // add admin by admins 
    public fun add_admin(admin_cap: &mut AdminCap, admin_address: address, ctx: &mut TxContext) {

            assert!(is_admin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);

            vector::push_back(&mut admin_cap.admins, admin_address);

            event::emit(AdminAdded{admin:admin_address});
    }

    // remove admin 
    public fun remove_admin(admin_cap: &mut AdminCap, admin_address: address, ctx: &mut TxContext) {

            assert!(is_admin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
            assert!(is_admin(admin_cap,admin_address), NOT_AN_ADMIN);

            let (_,index) = vector::index_of(&admin_cap.admins, &admin_address);

            vector::remove(&mut admin_cap.admins, index);
            event::emit(AdminRemoved{admin:admin_address});
    }

}
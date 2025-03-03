#[allow(unused_field)]
module fantv_user_creator_vesting::fantv_user_creator_vesting {
    use fan::fan::{FAN};
    use sui::event;
    use std::string::{String};
    use sui::{clock::Clock,};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};

    const EMPTY_VECTOR: u64 = 0;
    const VALUE_SHOULD_BE_NON_ZERO: u64 = 1;
    const NOT_AN_ADMIN: u64 = 2;
    const WALLET_ASSETS_FREEZED: u64 =3;
    const BENEFICIARY_MATCH_FAILED: u64 =4;
    const INVALID_VESTING_START: u64 = 1;
    const MAX_CREDIT_LIMIT_EXCEEDED: u64 =5;
    const MAX_CREDIT_LIMIT: u64 = 100000000000000;
    const DUPLICATE_ADMIN: u64 = 8;
    const CREDIT_ADDITION_INTERVAL: u64 = 86400000; 
    const SUPERADMIN_CANNOT_REMOVE_SELF : u64 = 9;
    const DAILY_CREDIT_LIMIT_EXCEEDED: u64 = 10;





    public struct SuperAdminCap has key { id: UID }

    public struct AdminCap has key, store {
        id: UID,
        admins: vector<address>,
    }


   public struct WalletCap has key {
        id: UID    
    }


    public struct Credit has copy, drop, store {
        amount: u64, // token amount
        time: u64 // data-timeStamp to release tokens
    }

   public struct CoinTreasury has key, store {
        id: UID,
        balance: Balance<FAN>,
        last_fund_add_date:u64,
        creator: address
    }

    public struct MaxCredit has key , store {
        id:UID,
        amount: u64
    }


    public struct AddFundCap has key, store {
        id: UID,
    }

    public struct Wallet has key , store{
        id: UID,
        beneficiary: address,
        balance: Balance<FAN>,
        total_amount: u64, 
        total_vesting_amount:u64,
        total_instant_amount:u64,
        instant_credit_amount: u64,
        vesting_credit_array: vector<Credit>,
        total_withdrawn: u64, 
        total_instant_withdrawn: u64,
        total_vested_withdrawn: u64,
        last_withdrawn_at: u64,
        last_credit_at: u64, 
        freezed: bool,
    }

    public struct CreditSummary has copy, drop {
        beneficiary: address,
        vesting_start:  u64,
        duration: u64,
        vesting_period : u64, 
        instant_amount: u64,
        vesting_amount:u64,
        credit_types: vector<String>,
        credit_amounts: vector<u64>,
    }

    // events

   public struct AdminAdded has copy, drop{
        admin: address
    }

     public struct AdminRemoved has copy, drop{
        admin: address
    }


    public struct WalletCapGranted has copy, drop{
        to_address: address
    }

    public struct AddFundCapGranted has copy, drop{
        to_address: address
    }


    public struct CoinReleased has copy, drop {
        beneficiary: address,
        amount: u64,
    }


    public struct FundAdded has copy, drop{
        amount: u64,
        sender: address,
        beneficiary: object::ID,
    }

    public struct CreditSummaryEvent has copy, drop  {
        beneficiary:address,
        vesting_start:  u64,
        duration: u64,
        vesting_period : u64, 
        instant_amount: u64,
        vesting_amount:u64,
        credit_types: vector<String>,
        credit_amounts: vector<u64>,
    }

    // public struct VESTINGMONTHLY has drop {}


    fun init(ctx: &mut TxContext) {

        transfer::transfer(SuperAdminCap{id: object::new(ctx)},tx_context::sender(ctx));

        let admin_cap = AdminCap {
            id:object::new(ctx),
            admins: vector[tx_context::sender(ctx)]
        };

        let coin_treasury = CoinTreasury {
            id:object::new(ctx),
            balance: balance::zero(),
            creator: tx_context::sender(ctx),
            last_fund_add_date:0
        };
        
        let max_limit = MaxCredit{
             id:object::new(ctx),
             amount: 0
        };


        transfer::share_object(admin_cap);
        transfer::share_object(coin_treasury);
        transfer::share_object(max_limit);
        transfer::transfer(WalletCap{id: object::new(ctx)},tx_context::sender(ctx));
        transfer::transfer(AddFundCap{id: object::new(ctx)},tx_context::sender(ctx));


    }


    // update Max Credit 
    public fun update_max_credit(_: &SuperAdminCap, amount: u64, max_credit: &mut MaxCredit){
        assert!(amount < MAX_CREDIT_LIMIT, MAX_CREDIT_LIMIT_EXCEEDED);
        max_credit.amount = amount;
    }

    // grant WalletCap
     public fun grant_wallet_cap(_:&SuperAdminCap,to_address:address, ctx: &mut TxContext ){
        transfer::transfer(WalletCap{id: object::new(ctx)},to_address);
        event::emit(WalletCapGranted{to_address:to_address});
    }



    // grant AddFundCap
     public fun grant_add_fund_cap(_:&SuperAdminCap,to_address:address, ctx: &mut TxContext ){
        transfer::transfer(AddFundCap{id: object::new(ctx)},to_address);
        event::emit(AddFundCapGranted{to_address:to_address});
    }

    // check if an address is admin 

    fun isAdmin(admin_cap: &AdminCap, admin_address: address):(bool) {
        let (existed, _) = vector::index_of(&admin_cap.admins, &admin_address);
        existed
    }


    // add new admin
    public fun add_admin(_: &SuperAdminCap, admin_cap: &mut AdminCap, admin_address: address) {

            // check admin_address is not already an admin
            assert!(!isAdmin(admin_cap,admin_address), DUPLICATE_ADMIN);

            vector::push_back(&mut admin_cap.admins, admin_address);

            event::emit(AdminAdded{admin:admin_address});
    }

    // remove new admin 
    public fun remove_admin(_: &SuperAdminCap, admin_cap: &mut AdminCap, admin_address: address, ctx: &mut TxContext) {

            assert!(isAdmin(admin_cap,admin_address), NOT_AN_ADMIN);
            assert!(admin_address != tx_context::sender(ctx),SUPERADMIN_CANNOT_REMOVE_SELF);


            let (_,index) = vector::index_of(&admin_cap.admins, &admin_address);
            vector::remove(&mut admin_cap.admins, index);
            event::emit(AdminRemoved{admin:admin_address});
    }


    // init user wallet to store credit_coins
    public fun init_wallet(_: &WalletCap, beneficiary: address, ctx: &mut TxContext){
        let wallet = Wallet {
            id: object::new(ctx),
            beneficiary,
            total_amount: 0,
            total_instant_amount:0,
            total_vesting_amount:0,
            vesting_credit_array: vector[],
            total_vested_withdrawn:0,
            total_instant_withdrawn:0,
            total_withdrawn: 0,
            freezed:false,
            instant_credit_amount: 0,
            last_withdrawn_at:0,
            last_credit_at:0,
            balance: balance::zero()
        };
        transfer::share_object(wallet);
    }

   

     // method to release vested tokens

    public fun claim(wallet: &mut Wallet,coin_treasury: &mut CoinTreasury, clock: &Clock, ctx: &mut TxContext){
        // check if wallet is not freezed 
        assert!(!wallet.freezed, WALLET_ASSETS_FREEZED);

        let credits_len = vector::length(&wallet.vesting_credit_array);
        assert!(credits_len > 0, EMPTY_VECTOR);

        let mut releaseable_amount = wallet.instant_credit_amount;
        let currTime = clock.timestamp_ms();
        
        let i = 0;

        while (i < vector::length(&wallet.vesting_credit_array)) {
            let credit = vector::borrow_mut(&mut wallet.vesting_credit_array, i);
            if (currTime >= credit.time) {
                // Unlock the amount if criteria are met
                releaseable_amount = releaseable_amount + credit.amount;
                wallet.total_vested_withdrawn = wallet.total_vested_withdrawn + credit.amount;
                let _ = vector::remove(&mut wallet.vesting_credit_array, i);
                // Do not increment `i` since the next element shifts into the current index
            } else {
                // Stop processing further if the current credit is not yet unlockable
                break
            };
        };



       assert!((releaseable_amount > 0 && coin_treasury.balance.value() >= releaseable_amount) , VALUE_SHOULD_BE_NON_ZERO);

       wallet.total_instant_withdrawn = wallet.total_instant_withdrawn + wallet.instant_credit_amount;
       wallet.total_withdrawn = wallet.total_withdrawn + releaseable_amount;
       wallet.last_withdrawn_at = clock.timestamp_ms();
       wallet.instant_credit_amount = 0;

       // check if treasury holds that amount 
        let release_coins = coin::from_balance(
            balance::split(&mut coin_treasury.balance, releaseable_amount),
            ctx,
        );
       transfer::public_transfer(release_coins, wallet.beneficiary);
       event::emit(CoinReleased{beneficiary: wallet.beneficiary, amount:releaseable_amount});

    }

    // freeze wallets assets 
     public fun freeze_assets(admin_cap: &mut AdminCap, wallet: &mut Wallet, ctx: &mut TxContext){
        assert!(isAdmin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
        wallet.freezed = true;
    }   

    // unfreeze wallets assets 

     public fun unfreeze_assets(admin_cap: &mut AdminCap, wallet: &mut Wallet, ctx: &mut TxContext) {
        assert!(isAdmin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
        wallet.freezed = false;
    } 


    fun update_new_credit_vesting(wallet: &mut Wallet, credit: Credit,){

        let cred_len = vector::length(&wallet.vesting_credit_array);
        let mut vesting_updated = false;
        if(cred_len > 0){
            let mut i = 0 ; 
             while( i < cred_len){
                let cred_elem = vector::borrow_mut(&mut wallet.vesting_credit_array, i);
                if(cred_elem.time >= credit.time){
                    cred_elem.amount = cred_elem.amount + credit.amount;
                    vesting_updated = true;
                    break
                };
                i = i +1;
             };
            if(vesting_updated == false){
                vector::push_back(&mut wallet.vesting_credit_array, credit);
            }
        }
        else{
            vector::push_back(&mut wallet.vesting_credit_array, credit);
        }
    }


    // update_daily_credit
    fun update_daily_credit(
        credit: CreditSummary,
        wallet: &mut Wallet,
        ){ 
        assert!(credit.vesting_period > 0, VALUE_SHOULD_BE_NON_ZERO);
        
        let mut vestable_credit = credit.vesting_amount;
        let mut vest_time = credit.vesting_start+credit.vesting_period;

       if (vestable_credit > 0){

        wallet.total_vesting_amount = wallet.total_vesting_amount + vestable_credit;

        let totalSteps = credit.duration/ credit.vesting_period;
       
        if (totalSteps > 0){
            let stepAmount = vestable_credit / totalSteps ; 
            let mut i = 1;
            while(i <= totalSteps && vestable_credit > 0){
                if (vestable_credit > stepAmount){
                update_new_credit_vesting(wallet,Credit{amount:stepAmount,time:vest_time});
                vestable_credit = vestable_credit - stepAmount; 
                }
                else{
                update_new_credit_vesting(wallet,Credit{amount:vestable_credit,time:vest_time});
                vestable_credit = 0;
                };
                i = i + 1;
                vest_time =vest_time + credit.vesting_period;
            };
        }
        else{
            vest_time = credit.vesting_start + credit.duration;
            update_new_credit_vesting(wallet,Credit{amount:vestable_credit,time:vest_time});
        };

       
       };
      event::emit(CreditSummaryEvent{
        beneficiary:wallet.beneficiary,
        vesting_start:  credit.vesting_start,
        duration: credit.duration,
        vesting_period : credit.vesting_period, 
        instant_amount:  credit.instant_amount,
        vesting_amount: credit.vesting_amount,
        credit_types: credit.credit_types,
        credit_amounts: credit.credit_amounts,
    });          
    }

// updates daily earning amount in shared wallet object (instant,vesting)

  public fun add_new_credit(
    admin_cap : &mut AdminCap,  
    beneficiary: address,
    vesting_start: u64,
    duration: u64,
    vesting_period: u64,
    instant_amount: u64,
    vesting_amount: u64,
    credit_types: vector<String>,
    credit_amounts: vector<u64>,
    wallet: &mut Wallet, 
    clock: &Clock, 
    max_credit: &MaxCredit,
    ctx: &mut TxContext
    ){
        let currTime = clock.timestamp_ms();
        assert!(isAdmin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
        // credit only after 24 hours after last_credit_at
        assert!( currTime >= wallet.last_credit_at + CREDIT_ADDITION_INTERVAL, DAILY_CREDIT_LIMIT_EXCEEDED);
        assert!(beneficiary == wallet.beneficiary, BENEFICIARY_MATCH_FAILED);
        assert!( vesting_start > currTime , INVALID_VESTING_START);
        assert!(instant_amount+vesting_amount <= max_credit.amount, MAX_CREDIT_LIMIT_EXCEEDED );
        
        wallet.last_credit_at = currTime;
        
        if(instant_amount > 0){
            wallet.instant_credit_amount = wallet.instant_credit_amount + instant_amount;
            wallet.total_instant_amount= wallet.total_instant_amount + instant_amount;
        };

        wallet.total_amount = wallet.total_amount + instant_amount+vesting_amount;

        let credit_data = CreditSummary {
            beneficiary,
            vesting_start,
            duration,
            vesting_period,
            instant_amount,
            vesting_amount,
            credit_types,
            credit_amounts,
        };
        update_daily_credit(credit_data,wallet); 

    }

    // Add funds to coin_treasury
    public fun add_funds(_: &AddFundCap, coin_treasury: &mut CoinTreasury,  token:Coin<FAN>,clock: &Clock, ctx: &mut TxContext ){
        let amount = token.value();
        assert!(amount > 0, VALUE_SHOULD_BE_NON_ZERO );
        balance::join(&mut coin_treasury.balance,coin::into_balance(token));
        coin_treasury.last_fund_add_date = clock.timestamp_ms();

        event::emit(FundAdded{
                amount:amount,
                sender: tx_context::sender(ctx),
                beneficiary: object::id(coin_treasury)
            });

        }

}



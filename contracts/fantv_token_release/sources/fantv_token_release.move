#[allow(unused_field)]
module fantv_token_release::fantv_token_release {
    use fan::fan::{FAN};
    use sui::balance::{Balance};
    use sui::coin::{Self,Coin};
    use sui::event;
    use std::string::{String};
    use sui::{clock::Clock,};
    use sui::balance;


    const NON_FREEZABLE_WALLET: u64 = 0;
    const VALUE_SHOULD_BE_NON_ZERO: u64 = 1;
    const NOT_AN_ADMIN: u64 = 2;
    const NOT_WALLET_CREATOR: u64 =4;
    const INVALID_VESTING_START: u64 = 5;
    const FREEZED_WALLET: u64 = 6;
    const SHOULD_NOT_EXCEED_AMOUNT: u64 = 7;
    const DUPLICATE_ADMIN: u64 = 8;
    const SUPERADMIN_CANNOT_REMOVE_SELF : u64 = 9;
    const SHOULD_BE_EQUAL: u64 = 10;



    public struct SuperAdminCap has key { id: UID }

     public struct AdminCap has key, store {
        id: UID,
        admins: vector<address>
    }



    public struct CreditAddress has copy, drop, store {
        beneficiary: address, // beneficiary
        total_amount: u64
    }

    public struct CreatorCap has key , store {
        id: UID,
        wallet_id: object::ID,
    } 

    public struct ContractWallet has key , store{
        id: UID,
        beneficiary_addresses: vector<CreditAddress>,
        instant_credit_amount: u64,
        creator: address,
        identifier: String,
        total_amount: u64,
        vesting_amount_per_period:u64,
        withdrawn_amount: u64, 
        balance: Balance<FAN>,
        cliff_amount: u64,
        cliff_date: u64,
        vesting_start_date: u64,
        vesting_duration: u64,
        vesting_period: u64,
        last_withdrawn_at:u64,
        created_at: u64,
        vesting_end_date: u64,
        clawbacked: u64,
        freezable:bool,
        freezed:bool,
    }
   
    // events

   public struct AdminAdded has copy, drop{
        admin: address
    }

     public struct AdminRemoved has copy, drop{
        admin: address
    }

    public struct CoinReleased has copy, drop {
        beneficiary: address,
        amount: u64,
    }

    public struct VestingEvent has copy, drop {
        beneficiary: address,
        identifier: String,
        amount:u64,
        withdrawn_amount: u64, 
        cliff_amount: u64,
        vesting_start_date: u64,
        vesting_duration: u64,
        vesting_period: u64,
        last_withdrawn_at:u64,
        created_at: u64,
        vesting_end_date: u64,
        clawbacked: u64,
    }

    fun init(ctx: &mut TxContext) {

        transfer::transfer(SuperAdminCap{id: object::new(ctx)},tx_context::sender(ctx));

        let admin_cap = AdminCap {
            id:object::new(ctx),
            admins: vector[tx_context::sender(ctx)]
        };
        
        transfer::share_object(admin_cap);

    }

    // check if an address is admin 

    fun isAdmin(admin_cap: &AdminCap, admin_address: address):(bool) {

        let (existed, _) = vector::index_of(&admin_cap.admins, &admin_address);
        existed
    }


    // add admin by SuperAdmin only 
    public fun add_admin(_: &SuperAdminCap, admin_cap: &mut AdminCap, admin_address: address) {

        // check admin_address is not already an admin
        assert!(!isAdmin(admin_cap,admin_address), DUPLICATE_ADMIN);

        vector::push_back(&mut admin_cap.admins, admin_address);

        event::emit(AdminAdded{admin:admin_address});
    }

    // remove admin by SuperAdmin only
    public fun remove_admin(_: &SuperAdminCap, admin_cap: &mut AdminCap, admin_address: address, ctx: &mut TxContext) {
        
        assert!(isAdmin(admin_cap,admin_address), NOT_AN_ADMIN);
        assert!(admin_address != tx_context::sender(ctx),SUPERADMIN_CANNOT_REMOVE_SELF);

        let (_,index) = vector::index_of(&admin_cap.admins, &admin_address);

        vector::remove(&mut admin_cap.admins, index);
        event::emit(AdminRemoved{admin:admin_address});
    }


   public fun vested_amount_contract(wallet: &ContractWallet, clock: &Clock,): u64 {
        // initial vesting amount
        let mut vested = wallet.instant_credit_amount;
        let current_time = clock.timestamp_ms();
        
        if(current_time > wallet.cliff_date){
            vested = vested + wallet.cliff_amount;
        };

        if (current_time < wallet.vesting_start_date) {
            return vested
        };

        // If current time is beyond the vesting end, all tokens are vested
        if (current_time >= wallet.vesting_end_date) {
            return wallet.total_amount
        };


        let time_elapsed = (current_time - wallet.vesting_start_date);
        // Remaining amount to be vested after the cliff
        
        let period_completed = time_elapsed / wallet.vesting_period;

        if(period_completed > 0){
            vested = vested+period_completed * wallet.vesting_amount_per_period;
        };

        vested
    }


    // freeze wallets assets 
     public fun freeze_assets_contract(admin_cap: &mut AdminCap, wallet: &mut ContractWallet, ctx: &mut TxContext){
        assert!(isAdmin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
        assert!(wallet.creator == tx_context::sender(ctx), NOT_WALLET_CREATOR);
        assert!(wallet.freezable == true, NON_FREEZABLE_WALLET);

        wallet.freezed = true;
    }   

    // unfreeze wallets assets 

     public fun unfreeze_assets_contract(admin_cap: &mut AdminCap, wallet: &mut ContractWallet, ctx: &mut TxContext) {
        assert!(isAdmin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
        assert!(wallet.creator == tx_context::sender(ctx), NOT_WALLET_CREATOR);
        wallet.freezed = false;
    } 


     public fun clawback_contract(
        admin_cap : &mut AdminCap,  
        wallet: &mut ContractWallet,
        clock: &Clock,
        ctx: &mut TxContext,
    ){
        assert!(isAdmin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);
        assert!(wallet.creator == tx_context::sender(ctx), NOT_WALLET_CREATOR);

        let vested = vested_amount_contract(wallet, clock);

        let mut remaining_value = wallet.total_amount - vested;

        assert!(remaining_value > 0, VALUE_SHOULD_BE_NON_ZERO);

        if(remaining_value > wallet.balance.value()){
            remaining_value = wallet.balance.value();
        };

        wallet.clawbacked = remaining_value;

        let clawbacked_coins = coin::from_balance(
            balance::split(&mut wallet.balance, remaining_value),
            ctx,
        );

       transfer::public_transfer(clawbacked_coins, wallet.creator);

    }

    public fun claim_coins_to_contract(creator_cap: &CreatorCap, wallet: &mut ContractWallet, clock: &Clock, ctx: &mut TxContext) {

    assert!(creator_cap.wallet_id == object::id(wallet), NOT_WALLET_CREATOR);
    assert!(wallet.freezed == false, FREEZED_WALLET);

    
    // Calculate the vested and releasable amount
    let vested = vested_amount_contract(wallet, clock);
    let mut relaseable_amount = vested - wallet.withdrawn_amount;
    assert!(relaseable_amount > 0, VALUE_SHOULD_BE_NON_ZERO);

    // Ensure the wallet has enough balance to release the amount
    let current_balance = wallet.balance.value();
    if (current_balance < relaseable_amount) {
        relaseable_amount = current_balance;
    };

 
    // Iterate over the beneficiary addresses
    let mut i = vector::length(&wallet.beneficiary_addresses);
    let mut allocated_amount;
    while (i > 0) {
        i = i - 1;
        let credit = vector::borrow(&wallet.beneficiary_addresses, i);

        // Calculate the allocated amount for this beneficiary
        let allocated_amount_u256 : u256 = ((relaseable_amount as u256) * (credit.total_amount as u256) )/ (wallet.total_amount as u256);
        allocated_amount = allocated_amount_u256 as u64;
        // Safeguard: Check if allocated_amount is valid
        if (allocated_amount > 0) {
            assert!(wallet.balance.value() >= allocated_amount, VALUE_SHOULD_BE_NON_ZERO);

            // Release coins
            let release_coins = coin::from_balance(
                balance::split(&mut wallet.balance, allocated_amount),
                ctx,
            );

            // Transfer coins and update the wallet
            transfer::public_transfer(release_coins, credit.beneficiary);
            wallet.withdrawn_amount = wallet.withdrawn_amount + allocated_amount;
            wallet.last_withdrawn_at = clock.timestamp_ms();

            // Emit event to track the released coins
            event::emit(CoinReleased {
                beneficiary: credit.beneficiary,
                amount: allocated_amount,
            });
        }
    };
    }

    public fun add_new_vesting_contract(
        admin_cap : &mut AdminCap,  
        beneficiary_addresses: vector<address>,
        amounts: vector<u64>,
        identifier: String,
        vesting_start_date: u64,
        vesting_duration: u64,
        vesting_period: u64,
        cliff_date: u64,
        token:Coin<FAN>,
        cliff_amount: u64,
        instant_amount: u64,
        freezable: bool,
        clock: &Clock, 
        ctx: &mut TxContext
        ): CreatorCap {
            let currTime = clock.timestamp_ms();
            let amount = token.value();

            assert!(isAdmin(admin_cap,tx_context::sender(ctx)), NOT_AN_ADMIN);

            assert!( vesting_start_date > currTime , INVALID_VESTING_START);
            
            assert!(cliff_amount + instant_amount <= amount,  SHOULD_NOT_EXCEED_AMOUNT);

            
            let end = vesting_start_date+vesting_duration;
            let vesting_amount_per_period;
            let mut total_period_count = 0;
            if(vesting_period > 0){
             total_period_count = vesting_duration/vesting_period;
            };
           
            if(total_period_count > 0){
             vesting_amount_per_period= (amount-cliff_amount-instant_amount)/total_period_count
            } else {
                vesting_amount_per_period = amount-cliff_amount-instant_amount;
            };

            let len_cred = vector::length(&beneficiary_addresses);
            
            let mut allocations: vector<CreditAddress> = vector::empty();

            let mut i =0;
            let mut total_amount =0; 
            while(i < len_cred) {
                let amount =  *vector::borrow(&amounts, i);
                let address_b = *vector::borrow(&beneficiary_addresses, i);
                let credits = CreditAddress { total_amount:amount, beneficiary:  address_b};
                vector::push_back(&mut allocations, credits);
                i = i+1;
                total_amount = total_amount + amount;
            };

            assert!( total_amount == token.value() , SHOULD_BE_EQUAL);

            let wallet = ContractWallet {
                id: object::new(ctx),
                instant_credit_amount: instant_amount,
                beneficiary_addresses: allocations,
                creator: tx_context::sender(ctx),
                identifier: identifier,
                vesting_amount_per_period:vesting_amount_per_period,
                total_amount:total_amount,
                withdrawn_amount: 0, 
                balance: coin::into_balance(token),
                cliff_amount: cliff_amount,
                cliff_date:cliff_date,
                vesting_start_date:vesting_start_date,
                vesting_duration: vesting_duration,
                vesting_period: vesting_period,
                last_withdrawn_at:0,
                created_at: currTime,
                vesting_end_date: end,
                clawbacked: 0,
                freezable:freezable,
                freezed:false
            };
            let creator_cap = CreatorCap{
                id: object::new(ctx),
                wallet_id: object::id(&wallet),
            };
            transfer::share_object(wallet);
            creator_cap
        }



}



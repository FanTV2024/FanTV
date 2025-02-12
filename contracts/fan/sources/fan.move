module fan::fan {
    use sui::coin::{Self};
    use sui::url::{new_unsafe_from_bytes};
    const MAX_SUPPLY: u64 = 10000000000;
    const DECIMALS: u64 = 1000000000;

    public struct FAN has drop {}

    fun init(witness: FAN, ctx: &mut TxContext) {
        // Create the URL for the token metadata
        let url = new_unsafe_from_bytes(b"https://assets.artistfirst.in/uploads/1739349932784-FAN_logo.png");

        // Create the new currency using the witness and context
        let (mut treasury_cap, meta_data) = coin::create_currency<FAN>(
            witness,               // Pass the witness by reference
            9,                     // Decimal places
            b"FAN",                // Symbol
            b"FanTV AI",                // Name
            b"FAN is the native token of FanTV Platform", // short description
            option::some(url),     // Metadata URL
            ctx                    // Transaction context
        );

        // Freeze the metadata object to prevent further modification
        transfer::public_freeze_object(meta_data);

        //mint max supply to sender
        coin::mint_and_transfer(&mut treasury_cap, MAX_SUPPLY*DECIMALS, tx_context::sender(ctx), ctx);
        
        // Freeze treasury cap to avoid future mints
        transfer::public_freeze_object(treasury_cap);

    }
}
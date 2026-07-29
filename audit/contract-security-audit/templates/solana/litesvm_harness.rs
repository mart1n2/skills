//! litesvm_harness.rs — Base harness for Solana PoCs (LiteSVM, in-process SVM).
//!
//! cargo add litesvm solana-sdk spl-token spl-associated-token-account
//! Build the target first: `anchor build` (→ target/deploy/<name>.so) or `cargo build-sbf`.
//!
//! This is the Solana analogue of templates/simulation/BaseTest.sol: it sets up the SVM,
//! loads the target program, funds an attacker, and provides token helpers. Concrete
//! exploits build on it (see exploit_*.rs).

use litesvm::LiteSVM;
use solana_sdk::{
    account::Account,
    instruction::{AccountMeta, Instruction},
    program_pack::Pack,
    pubkey::Pubkey,
    signature::{Keypair, Signer},
    transaction::Transaction,
};
use spl_token::state::{Account as TokenAccount, AccountState, Mint};

/// Replace with the audited program's deployed id (or a fresh id for pre-deployment audits).
pub const TARGET_PROGRAM_SO: &str = "../target/deploy/target_program.so";

pub struct Harness {
    pub svm: LiteSVM,
    pub program_id: Pubkey,
    pub attacker: Keypair,
}

impl Harness {
    pub fn new() -> Self {
        let mut svm = LiteSVM::new();
        let program_id = Pubkey::new_unique();
        svm.add_program_from_file(program_id, TARGET_PROGRAM_SO)
            .expect("load target .so — run `anchor build` first");
        let attacker = Keypair::new();
        // Fresh attacker, no pre-funding beyond what's needed for fees (mirrors EVM makeAddr).
        svm.airdrop(&attacker.pubkey(), 10_000_000_000).unwrap();
        Self { svm, program_id, attacker }
    }

    /// Create an SPL mint owned by `mint_authority`.
    pub fn create_mint(&mut self, authority: &Pubkey, decimals: u8) -> Pubkey {
        let mint = Pubkey::new_unique();
        let mut data = vec![0u8; Mint::LEN];
        Mint {
            mint_authority: solana_sdk::program_option::COption::Some(*authority),
            supply: 0,
            decimals,
            is_initialized: true,
            freeze_authority: solana_sdk::program_option::COption::None,
        }
        .pack_into_slice(&mut data);
        self.svm
            .set_account(mint, Account { lamports: 1_000_000, data, owner: spl_token::ID, executable: false, rent_epoch: 0 })
            .unwrap();
        mint
    }

    /// Create an SPL token account holding `amount`, owned (authority) by `owner`.
    pub fn create_token_account(&mut self, mint: &Pubkey, owner: &Pubkey, amount: u64) -> Pubkey {
        let ata = Pubkey::new_unique();
        let mut data = vec![0u8; TokenAccount::LEN];
        TokenAccount {
            mint: *mint,
            owner: *owner,
            amount,
            state: AccountState::Initialized,
            ..Default::default()
        }
        .pack_into_slice(&mut data);
        self.svm
            .set_account(ata, Account { lamports: 2_000_000, data, owner: spl_token::ID, executable: false, rent_epoch: 0 })
            .unwrap();
        ata
    }

    pub fn token_amount(&self, token_account: &Pubkey) -> u64 {
        let acc = self.svm.get_account(token_account).unwrap();
        TokenAccount::unpack(&acc.data).unwrap().amount
    }

    /// Send a single instruction signed by the attacker (fee payer).
    pub fn send(&mut self, accounts: Vec<AccountMeta>, data: Vec<u8>) -> Result<(), String> {
        let ix = Instruction { program_id: self.program_id, accounts, data };
        let tx = Transaction::new_signed_with_payer(
            &[ix],
            Some(&self.attacker.pubkey()),
            &[&self.attacker],
            self.svm.latest_blockhash(),
        );
        self.svm.send_transaction(tx).map(|_| ()).map_err(|e| format!("{e:?}"))
    }
}

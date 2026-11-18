//! What a block holds anywhere in it: under every `if`, every case of a
//! `switch` and every loop, its continuing too. A barrier the group waits
//! at (group.rs), a return out of a loop (uniform.rs) and a call for the
//! moment (lib.rs) are each found so.

use naga::{Block, Statement};

/// Whether a statement `is` says yes to stands anywhere in `block`.
pub(crate) fn holds(block: &Block, is: &impl Fn(&Statement) -> bool) -> bool {
    block.iter().any(|statement| {
        is(statement)
            || match statement {
                Statement::Block(inner) => holds(inner, is),
                Statement::If { accept, reject, .. } => holds(accept, is) || holds(reject, is),
                Statement::Switch { cases, .. } => cases.iter().any(|case| holds(&case.body, is)),
                Statement::Loop { body, continuing, .. } => holds(body, is) || holds(continuing, is),
                _ => false,
            }
    })
}

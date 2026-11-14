//! The SDK's example (sdk/fx/example) — the plugin a maker starts from —
//! built from its own source against the same spec crate, for the tests to
//! open beside the sample.

// The checkout this example is built from (lib.rs says why).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

#[path = "../../../../../../sdk/fx/example/src/lib.rs"]
mod example;

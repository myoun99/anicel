//! The sample plugin (invert.rs), as the spec crate exports it.

// The checkout this example is built from (lib.rs says why).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

mod invert;

anicel_fx::export!(invert::Invert);

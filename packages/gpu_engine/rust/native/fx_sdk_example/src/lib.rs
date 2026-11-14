//! The fx SDK's example as a maker builds it (sdk/fx/README.md), from its
//! own source: Cargo.toml says why it is a crate of its own.

// The checkout this crate is built from, different in each: a build that
// another checkout left in the shared target folder is built again here,
// never run as this one's (gpu_engine's kernels/shared/one_checkout.rs).
const _CHECKOUT: Option<&str> = option_env!("QA_CHECKOUT");

#[path = "../../../../../../sdk/fx/example/src/lib.rs"]
mod example;

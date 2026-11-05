//! What more than one area's kernels compute, one WGSL file per function
//! family, in one place (gpu-canonical-store, 관제 14:51): the same integer
//! formula written in two areas' folders is a copy however different the
//! text (CLAUDE.md, absolute rule 1). Before writing one, look here.
//!
//! A kernel prepends the files it uses, each once, in the order their
//! heads ask — a function prepended twice does not compile, so a second
//! copy has nowhere to hide. Each is pinned through its users' tests.

/// `isqrt_round` — the blend family's soft light, the timeline's coverage.
pub(crate) const ISQRT_WGSL: &str = include_str!("isqrt.wgsl");

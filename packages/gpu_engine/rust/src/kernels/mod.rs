//! One folder per area's kernels, and each area's session writes only its
//! own: the shaders, the driver with the C ABI it exports, and `tests.rs`,
//! which runs them on a real GPU.
//!
//! ⛔NO CPU COPY OF A KERNEL'S FORMULA, NOT EVEN AS THE TESTS' ORACLE
//! (관제's ruling on gpu-engine-skeleton, 2026-11-05). The same algorithm
//! written for the CPU and for the GPU is a copy however different the text
//! (CLAUDE.md, absolute rule 1), and brush/rendering dropped its CPU
//! reference for the same reason. A kernel is checked three ways instead:
//! the ledger `test/fixtures/fingerprints.json` — pinned once on the first
//! device that ran it, reproduced by every other —, cases worked out by
//! hand from the formula, and mutation.

pub mod fill;

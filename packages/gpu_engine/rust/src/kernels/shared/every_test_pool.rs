//! Every test's pool keeps to its own bytes, not to the OS's budget — the
//! machine's VRAM as it happens to stand — but where the test's name says
//! so (🗣️관제 2026-11-16, pool-tests-ride-the-os-vram-budget: 「시험은 기계의
//! 살아 있는 상태에 기대지 않는다」). A pool is made with none
//! (`pool::BUDGET_TILL_ONE_IS_SET`); a test that rides the OS's sets that
//! none back, and is seen by the word `os` in its name. ⛔A test of
//! behaviour cannot tell: a pool kept to the OS's passes on a machine with
//! VRAM to spare.

use super::source_scan::sources;

/// A budget of none set in the OS's place, and one set over the C ABI —
/// spelled apart, so the scan's own words are no test's.
const NONE_SET: &str = concat!(".set_budget_instead", "(None)");
const OVER_THE_ABI: &str = concat!("gpu_engine_pool_budget_instead", "(");

#[test]
fn a_test_keeps_to_the_os_s_budget_only_by_name() {
    let mut riders: Vec<_> = sources().values().flat_map(|text| tests_riding_the_os_s_budget(text)).collect();
    riders.sort();
    assert_eq!(
        riders,
        [
            "a_budget_kept_to_instead_stands_in_the_os_s_place",
            "a_page_past_the_budget_the_os_gives_is_not_made",
            "the_c_abi_keeps_a_pool_to_a_budget_in_the_os_s_place",
        ],
        "LIVENESS — the scan finds the tests that keep to the OS's budget",
    );
    for rider in &riders {
        assert!(rider.split('_').any(|word| word == "os"), "{rider} keeps to the OS's budget: say `os` in its name");
    }
    let planted = format!(
        "#[test]\nfn a_cel_is_stored() {{\n    pool{NONE_SET};\n}}\n\
         #[test]\nfn the_most_is_kept() {{\n    {OVER_THE_ABI}pool, -1);\n}}\n\
         #[test]\nfn a_page_is_made() {{\n    {OVER_THE_ABI}pool, 0);\n}}\n"
    );
    assert_eq!(tests_riding_the_os_s_budget(&planted), ["a_cel_is_stored", "the_most_is_kept"], "the scan sees a plant");
}

/// The tests in `text` that keep a pool to the OS's budget: a budget of
/// none set in its place, or a negative one over the C ABI — each test
/// read to the next.
fn tests_riding_the_os_s_budget(text: &str) -> Vec<String> {
    let rides = |body: &str| {
        body.contains(NONE_SET)
            || body.split(OVER_THE_ABI).skip(1).any(|call| {
                call.split(')').next().and_then(|args| args.split(',').nth(1)).is_some_and(|bytes| bytes.trim().starts_with('-'))
            })
    };
    text.split("#[test]")
        .skip(1)
        .filter(|body| rides(body))
        .filter_map(|body| body.split("fn ").nth(1)?.split('(').next().map(str::to_owned))
        .collect()
}

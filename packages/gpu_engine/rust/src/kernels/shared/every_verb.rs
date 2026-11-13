//! Every verb of the C ABI that is handed the engine runs its body on the
//! engine's thread (`EngineThread`, in `device.rs`, has why). A body left
//! on its caller's takes the device in hand there, and waits there for the
//! engine's thread with whatever lock it holds, which a body on that thread
//! may be waiting for. A test of behaviour passes a verb nobody calls from
//! a thread that matters, so this one reads the sources: each such verb
//! goes through the door, or is on the ledger with why it stays on its
//! caller's.

use std::cell::RefCell;
use std::collections::BTreeMap;

use super::source_scan::files_where;

/// The verbs that stay on their caller's thread, each with why: none takes
/// the device in hand, and none hands the engine's thread anything it
/// waits for.
const ON_THEIR_CALLERS: [(&str, &str); 10] = [
    ("gpu_engine_adapter_name", "the adapter's own word of itself: no device is asked"),
    ("gpu_engine_video_memory", "asks the OS of the adapter's memory (DXGI), not the device"),
    ("gpu_engine_gone", "reads the engine's own word of its device (`Refusals`)"),
    ("gpu_engine_noted", "takes the engine's own word of its device (`Refusals`)"),
    (
        "gpu_engine_done_then",
        "hands its wait to the engine's thread and returns: waiting for that thread here, its \
         caller would stay for what it asked not to stay for",
    ),
    ("gpu_engine_done_failure", "takes the engine's own word of a wait (`Ended`)"),
    ("gpu_engine_apart_hold", "the engine's own count (`Apart`)"),
    ("gpu_engine_apart_let", "the engine's own count (`Apart`)"),
    (
        "gpu_engine_apart_wait",
        "waits till the holds are let go: on the engine's thread every verb would stand behind it",
    ),
    ("gpu_engine_apart_held", "the engine's own count (`Apart`)"),
];

/// The verbs `text` exports that are handed the engine, each with its body:
/// an `extern "C"` function named `gpu_engine_…` whose signature takes
/// `engine`, from the line its body opens on to the brace that closes it at
/// the line's start.
fn verbs_in(text: &str) -> Vec<(String, String)> {
    const EXPORTED: &str = "extern \"C\" fn ";
    let text = text.replace("\r\n", "\n");
    let verb = |at: usize| {
        let after = &text[at + EXPORTED.len()..];
        let name = &after[..after.find('(')?];
        let opens = after.find(" {\n")?;
        let closes = opens + after[opens..].find("\n}")?;
        let signature = &after[..opens];
        let handed = ["engine: *const Engine", "engine: *mut Engine"]
            .iter()
            .any(|engine| signature.contains(engine));
        (name.starts_with("gpu_engine_") && handed)
            .then(|| (name.to_owned(), after[opens..closes].to_owned()))
    };
    text.match_indices(EXPORTED).filter_map(|(at, _)| verb(at)).collect()
}

/// Every verb the sources export that is handed the engine, with its body.
fn verbs() -> BTreeMap<String, String> {
    let found = RefCell::new(BTreeMap::new());
    files_where("rs", |text| {
        found.borrow_mut().extend(verbs_in(text));
        false
    });
    found.into_inner()
}

/// Whether `body` hands itself to the engine's thread.
fn on_the_engines_thread(body: &str) -> bool {
    // `run_lent` is the thread's own hand, where the engine is let go on it
    // (`gpu_engine_close`).
    body.contains(".on_thread(") || body.contains(".run_lent(")
}

#[test]
fn every_verb_handed_the_engine_runs_its_body_on_the_engines_thread() {
    let verbs = verbs();
    assert!(verbs.contains_key("gpu_engine_pool_store"), "LIVENESS — the scan finds the verbs");
    let stays = |name: &str| ON_THEIR_CALLERS.iter().any(|(stays, _)| *stays == name);
    let off: Vec<_> = verbs
        .iter()
        .filter(|(name, body)| !stays(name) && !on_the_engines_thread(body))
        .map(|(name, _)| name)
        .collect();
    assert!(
        off.is_empty(),
        "a verb's body on its caller's thread — hand it to `Engine::on_thread`: {off:?}"
    );
    for (name, why) in ON_THEIR_CALLERS {
        let body = verbs.get(name).unwrap_or_else(|| panic!("{name} is no verb the sources export"));
        assert!(
            !on_the_engines_thread(body),
            "{name} runs on the engine's thread — off the ledger with it ({why})"
        );
    }
}

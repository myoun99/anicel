//! Every verb of the C ABI does what it does of the device on the engine's
//! thread (`EngineThread`, in `device.rs`, has why). A body left on its
//! caller's takes the device in hand there, and waits there for the
//! engine's thread with whatever lock it holds, which a body on that thread
//! may be waiting for. A test of behaviour passes a verb nobody calls from
//! a thread that matters, so this one reads the sources — every verb they
//! export, by what it is handed:
//!
//! - the engine: its body goes through the door (`Engine::on_thread`, or
//!   `Engine::posted`, its caller waiting for none of it), or
//!   it is handed the engine for nothing but to hand its thing out by it
//!   ([`hands_out_alone`]), or it is on the ledger with why it stays on its
//!   caller's ([`ON_THEIR_CALLERS`]);
//! - a thing to free: it lets go of it through a door — the engine's
//!   (`device::let_go`, `device::let_go_unwaited`), or the bytes'
//!   (`device::let_go_bytes`: what holds nothing of a device);
//! - neither: it reaches the engine's thread by the thing it is handed
//!   (`device::on_thread_of`), or it makes a thing of bytes
//!   (`device::hands_bytes`), or it is on the ledger with why it has no
//!   hand on the device ([`NO_HAND_ON_THE_DEVICE`]).
//!
//! ↩️Till 2026-11-14 (the-ui-thread-never-enters-the-driver 1b) it read the
//! verbs handed the engine alone, and three handed none took a hand on the
//! device past it (`device::on_thread_of` names them).

use super::source_scan::{Verb, hands_out_bytes, verbs};

/// The verbs handed the engine that stay on their caller's thread, each
/// with why: none takes the device in hand, and none hands the engine's
/// thread anything it waits for.
const ON_THEIR_CALLERS: [(&str, &str); 13] = [
    ("gpu_engine_adapter_name", "the adapter's own word of itself: no device is asked"),
    (
        "gpu_engine_video_memory",
        "asks the OS of the adapter's memory (DXGI) and the adapter of its kind, not the device",
    ),
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
    ("gpu_engine_apart_held", "the engine's own count (`Apart`)"),
    (
        "gpu_engine_pictures_idle_bytes",
        "the engine's own counts of the pictures' idle slots and its work buffer \
         (`Pictures::idle_bytes`, `Work::bytes`): no device is asked, and the memory census \
         asks it on the UI's thread, which behind a compile would stand",
    ),
    (
        "gpu_engine_pictures_unowned_bytes",
        "the engine's own count of the pictures' tiles no picture weighs, as the last release \
         left it (`Pictures::unowned_bytes`): no device is asked, and no book is waited for — \
         the playback's budget asks it on the UI's thread, where a frame is built",
    ),
    (
        "gpu_engine_unfinished",
        "the engine's own ledger of its submits, under a lock of its own (`Submits`): no device \
         is asked, and it is read after the device went, when the engine's thread may answer \
         nothing",
    ),
    (
        "gpu_engine_pool_give_back",
        "the pool's books, kept where its verbs are called, and each page given back handed to \
         the pages' thread, which it waits for none of (`Pool::give_back`): no buffer is made — \
         what stands in a page's place is the engine's, made with it (`Engine::no_page`) — and \
         none is let go here. A memory warning asks it on the UI's thread",
    ),
];

/// The verbs handed neither the engine nor a thing to free that have no
/// hand on the device — each named, under why: its body was read for it
/// (2026-11-14), and a verb that comes after is read for it before it is
/// written here.
const NO_HAND_ON_THE_DEVICE: [(&str, &[&str]); 12] = [
    (
        "opens an engine, on a thread made for it (`opened`)",
        &["gpu_engine_open", "gpu_engine_open_sole", "gpu_engine_open_first"],
    ),
    (
        "the calling thread's own count, or its last error",
        &[
            "gpu_engine_waits_here",
            "gpu_engine_device_entered_here",
            "gpu_engine_kernels_built_here",
            "gpu_engine_last_error",
        ],
    ),
    (
        "a number reckoned of what it is handed, or a constant of the crate's",
        &[
            "gpu_engine_tile_side",
            "gpu_engine_grid_atlas_side",
            "gpu_engine_fingerprint_bytes",
            "gpu_engine_export_png_row_bytes",
            "gpu_engine_composited_bytes",
            "gpu_engine_crc32_update",
            "gpu_engine_mix_ground",
            "gpu_engine_rub_ground",
        ],
    ),
    (
        "the name of the folder compiled shaders are kept in, for the engines opened after",
        &["gpu_engine_keep_shaders_in"],
    ),
    (
        "a count the crate keeps of the bytes of its things",
        &[
            "gpu_engine_mask_bytes",
            "gpu_engine_held_bytes",
            "gpu_engine_kept_bytes",
            "gpu_engine_stamp_picture_bytes",
            "gpu_engine_readout_live_bytes",
            "gpu_engine_flood_bytes",
        ],
    ),
    (
        "reads what its thing keeps on the heap — a number, a list, where its bytes or its \
         texture are — and asks the device nothing",
        &[
            "gpu_engine_cel_passed_walked",
            "gpu_engine_cel_passed_tiles",
            "gpu_engine_cel_passed_run_count",
            "gpu_engine_cel_passed_runs",
            "gpu_engine_held_bytes_of",
            "gpu_engine_plan_steps",
            "gpu_engine_plan_weighed",
            "gpu_engine_plugin_reads_the_moment",
            "gpu_engine_screen_bytes",
            "gpu_engine_stroke_bytes",
            "gpu_engine_blurs_by_strips",
            "gpu_engine_blurs_bytes",
            "gpu_engine_selection_masks_bytes",
            "gpu_engine_readout_bytes",
            "gpu_engine_selection_runs_read",
            "gpu_engine_run_contours_read",
            "gpu_engine_pool_bytes",
            "gpu_engine_pool_ahead_bytes",
            "gpu_engine_grid_kept_bytes",
            "gpu_engine_grid_most_side",
            "gpu_engine_window_direct",
            "gpu_engine_surface_texture",
            "gpu_engine_surface_handle",
        ],
    ),
    (
        "adds to a plan, to a picture of letters or to a word, on its caller's heap: it takes a \
         hold on what it names, and lets go of nothing",
        &[
            "gpu_engine_plan_set",
            "gpu_engine_plan_matrix",
            "gpu_engine_plan_row",
            "gpu_engine_plan_open",
            "gpu_engine_plan_close",
            "gpu_engine_plan_close_row",
            "gpu_engine_plan_close_atop",
            "gpu_engine_plan_solid",
            "gpu_engine_plan_mask",
            "gpu_engine_plan_mark",
            "gpu_engine_plan_keys",
            "gpu_engine_plan_key_run",
            "gpu_engine_plan_chain",
            "gpu_engine_plan_chain_held",
            "gpu_engine_plan_chain_read",
            "gpu_engine_plan_chain_put",
            "gpu_engine_plan_chain_matrix",
            "gpu_engine_plan_chain_keys",
            "gpu_engine_plan_chain_gaussian",
            "gpu_engine_plan_chain_line",
            "gpu_engine_plan_chain_lens",
            "gpu_engine_plan_map_laid",
            "gpu_engine_plan_map_drawn",
            "gpu_engine_letters_pass",
            "gpu_engine_letters_run",
            "gpu_engine_letters_rect",
            "gpu_engine_word_run",
        ],
    ),
    (
        "the pool's books alone — a cel's number, a slot's holds, a budget: no page is made or \
         let go of",
        &[
            "gpu_engine_pool_cel",
            "gpu_engine_pool_release",
            "gpu_engine_pool_unwritten",
            "gpu_engine_pool_most_bytes",
            "gpu_engine_pool_budget_instead",
        ],
    ),
    (
        "copies rows out of a buffer the engine mapped for the CPU: wgpu's own word of where \
         its bytes are, no call of the driver's (wgpu-core 30.0.1, `Buffer::get_mapped_range`)",
        &["gpu_engine_readout_rows"],
    ),
    ("the plug-in's reach, run on the CPU (fx_wgsl's `Kernel::reach`)", &["gpu_engine_plugin_reach"]),
    (
        "copies a face's file into the faces being handed, on its caller's heap: no device \
         is asked till they are set up (`gpu_engine_faces_of`)",
        &["gpu_engine_faces_file"],
    ),
    (
        "sets a word in the faces on the CPU, where it is called — which of its letters they have \
         (`words::whole`), and its coverage (`words::rastered`), and a picture of letters its \
         covers (`letters::set`, kept for its land to lay): the faces are bytes \
         (`hands_bytes`), their files and what each weight is set in — behind a lock under which \
         nothing waits for the engine's thread — and no device is asked. The paint that asks for \
         a tile's word bakes it (a-grid-row-paints-its-cells-on-a-canvas-beside-its-tiles-Q3)",
        &["gpu_engine_word_whole", "gpu_engine_word_raster", "gpu_engine_letters_cover"],
    ),
];

/// Whether `verb` is handed the engine.
fn handed_the_engine(verb: &Verb) -> bool {
    ["engine: *const Engine", "engine: *mut Engine"].iter().any(|engine| verb.signature.contains(engine))
}

/// Whether `body` hands itself to the engine's thread — waited for there,
/// or not (`Engine::posted`).
fn on_the_engines_thread(body: &str) -> bool {
    // `run_lent` is the thread's own hand, where the engine is let go on it
    // (`gpu_engine_close`); `lands_unwaited` hands its put over by
    // `Engine::posted`, its books the caller's (`Pool::lands_unwaited`),
    // and so a fold and its settle hand over theirs
    // (`Pool::folds_unwaited`, `Pool::settles_unwaited`).
    const DOORS: [&str; 6] =
        [".on_thread(", ".run_lent(", ".posted(", ".lands_unwaited(", ".folds_unwaited(", ".settles_unwaited("];
    DOORS.iter().any(|door| body.contains(door))
}

/// Whether `body` names the engine for nothing but to hand out by it the
/// thing it made (`Engine::hands`). Such a thing takes nothing of the
/// device as it is made — it comes to hold what the verbs handed the
/// engine give it (`device::Handed` names the six) — so its making asks
/// the device nothing, and stays on its caller's thread, where it was
/// before its maker was handed an engine. One hand more on the engine, and
/// it is a body for that thread.
fn hands_out_alone(body: &str) -> bool {
    const HANDS: &str = "engine.hands(";
    const ITS_OWN: [&str; 2] = ["let engine = unsafe { &*engine };", HANDS];
    let code: Vec<&str> = body.lines().filter(|line| !line.trim_start().starts_with("//")).collect();
    let code = code.join("\n");
    let rest = ITS_OWN.iter().fold(code.clone(), |rest, own| rest.replace(own, ""));
    let names_it = rest.split(|c: char| !(c.is_alphanumeric() || c == '_')).any(|word| word == "engine");
    code.contains(HANDS) && !names_it
}

/// Whether `body` lets go of what it is handed through a door — the
/// engine's or the bytes'; a function of the door's, not a method of the
/// thing's own that is named alike.
fn lets_go_through_a_door(body: &str) -> bool {
    [" let_go(", " let_go_unwaited(", " let_go_bytes("].iter().any(|door| body.contains(door))
}

/// Whether `verb` does what it does of the device on the engine's thread
/// — or has, by its door, nothing of a device to do anything of — by what
/// it is handed (the head of this file).
fn through_the_door(verb: &Verb) -> bool {
    if handed_the_engine(verb) {
        on_the_engines_thread(&verb.body) || hands_out_alone(&verb.body)
    } else if verb.name.ends_with("_free") {
        lets_go_through_a_door(&verb.body)
    } else {
        verb.body.contains("on_thread_of(") || hands_out_bytes(&verb.body)
    }
}

/// The ledger's verbs, each with why and whether its ledger is of the
/// verbs handed the engine.
fn ledgers() -> impl Iterator<Item = (&'static str, &'static str, bool)> {
    let on_their_callers = ON_THEIR_CALLERS.iter().map(|&(name, why)| (name, why, true));
    let no_hand = NO_HAND_ON_THE_DEVICE
        .iter()
        .flat_map(|&(why, names)| names.iter().map(move |&name| (name, why, false)));
    on_their_callers.chain(no_hand)
}

#[test]
fn every_verb_does_what_it_does_of_the_device_on_the_engines_thread() {
    let verbs = verbs();
    assert!(verbs.contains_key("gpu_engine_pool_store"), "LIVENESS — the scan finds the verbs");
    let stays = |verb: &Verb| {
        let handed = handed_the_engine(verb);
        let free = !handed && verb.name.ends_with("_free");
        !free && ledgers().any(|(stays, _, of_the_handed)| stays == verb.name && of_the_handed == handed)
    };
    let off = verbs.values().filter(|verb| !through_the_door(verb) && !stays(verb));
    let off: Vec<_> = off.map(|verb| &verb.name).collect();
    assert!(
        off.is_empty(),
        "a verb's hand on the device on its caller's thread — hand its body to `Engine::on_thread` \
         (`device::on_thread_of`, handed no engine; a door of `device.rs`, a free), or read it and write \
         it on its ledger with why it has none: {off:?}"
    );
    for (name, why, handed) in ledgers() {
        let verb = verbs.get(name).unwrap_or_else(|| panic!("{name} is no verb the sources export"));
        assert_eq!(handed_the_engine(verb), handed, "{name} is on the other ledger's side ({why})");
        assert!(!through_the_door(verb), "{name} goes through a door — off the ledger with it ({why})");
    }
}

#[test]
fn a_maker_hands_out_alone_only_where_it_names_the_engine_for_nothing_else() {
    let alone = " {\n    // SAFETY: the engine is live.\n    let engine = unsafe { &*engine };\n    \
                 engine.hands(Made::default())";
    assert!(hands_out_alone(alone));
    // Made of the engine's own, or asking it anything, it is a body for the
    // engine's thread.
    assert!(!hands_out_alone(&alone.replace("Made::default()", "Made::new(engine)")));
    assert!(!hands_out_alone(&format!("{alone};\n    engine.wait()")));
    // And one that hands nothing out is no maker.
    assert!(!hands_out_alone(" {\n    let engine = unsafe { &*engine };\n    7"));
    // What the sources' own makers read as.
    let verbs = verbs();
    assert!(hands_out_alone(&verbs["gpu_engine_plan_new"].body), "a plan takes nothing of the device as it is made");
    assert!(!hands_out_alone(&verbs["gpu_engine_pool_new"].body), "a pool's pages are the device's");
}

#[test]
fn a_verb_goes_through_the_door_by_what_it_is_handed() {
    let verb = |name: &str, handed: bool, body: &str| Verb {
        name: name.to_owned(),
        signature: (if handed { "(engine: *const Engine, thing: *mut Thing)" } else { "(thing: *mut Thing)" }).into(),
        body: body.to_owned(),
    };
    let run = |handed, body| verb("gpu_engine_thing_run", handed, body);
    let free = |body| verb("gpu_engine_thing_free", false, body);
    let other = |body| verb("gpu_engine_thing_let_go", false, body);
    let on_thread = " {\n    engine.on_thread(|| thing.run(engine))";
    let by_its_thing = " {\n    unsafe { on_thread_of(thing, || (*thing).let_go()) };";
    let let_go = " {\n    unsafe { let_go(thing) };";
    let unwaited = " {\n    unsafe { let_go_unwaited(thing) };";
    let its_own = " {\n    unsafe { &mut *thing }.let_go();";
    let bytes = " {\n    unsafe { let_go_bytes(thing) };";
    let made_of_bytes = " {\n    hands_bytes(Thing::default())";
    let made_or_not = " {\n    Thing::new(of).map_or(std::ptr::null_mut(), hands_bytes)";
    // Handed the engine: through `Engine::on_thread`, and by nothing less.
    assert!(through_the_door(&run(true, on_thread)));
    assert!(!through_the_door(&run(true, by_its_thing)));
    assert!(!through_the_door(&run(true, its_own)));
    assert!(!through_the_door(&run(true, made_of_bytes)));
    // A free: through a door's own letting go — the thing's own method of
    // the name is the thing let go of where its caller is.
    assert!(through_the_door(&free(let_go)));
    assert!(through_the_door(&free(unwaited)));
    assert!(through_the_door(&free(bytes)));
    assert!(!through_the_door(&free(its_own)));
    assert!(!through_the_door(&free(by_its_thing)));
    // Handed neither: by the thing's own engine's thread, or a maker of
    // bytes.
    assert!(through_the_door(&other(by_its_thing)));
    assert!(through_the_door(&other(made_of_bytes)));
    assert!(through_the_door(&other(made_or_not)));
    assert!(!through_the_door(&other(its_own)));
    assert!(!through_the_door(&other(let_go)));
}

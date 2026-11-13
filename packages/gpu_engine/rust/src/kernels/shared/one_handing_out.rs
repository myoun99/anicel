//! What the C ABI hands out goes out and comes back by a door of
//! `device.rs` (the-ui-thread-never-enters-the-driver 1b, 2026-11-14), one
//! of two:
//!
//! - the engine's — `Engine::hands`, and `let_go` and `let_go_unwaited`,
//!   which let go of a thing on the thread of the engine that made it
//!   (`Handed` has why) — for what holds, or comes to hold, anything of the
//!   device;
//! - the bytes' — `hands_bytes` and `let_go_bytes` — for what holds nothing
//!   of one: no engine's, let go of where its free is called.
//!
//! A thing boxed past the doors is let go of by them as a box of another
//! shape; one that goes out by one door and comes back by the other, the
//! same; and a thing of bytes that came to hold a buffer would let go of it
//! where its caller is, with no word. A test of behaviour passes each — the
//! free it never calls, the type as it stood — so these read the sources.
//!
//! ⏳The last of the three reads each type's fields (🗣️관제 2026-11-14 05:16,
//! the-ui-thread-never-enters-the-driver: 「그 타입의 구조체가 디바이스 것을
//! 필드로 쥐지 않는다는 것을 소스 스캔이 읽는다 … 2단계에서 타입 토큰이 서면
//! 스캔은 컴파일러의 일로 넘어간다 — 그때 지운다」): it goes where the
//! device's things are told by a type of their own (stage 2).

use std::collections::{BTreeMap, BTreeSet};

use super::source_scan::{Verb, assert_home_and_ledger, files_where, hands_out_bytes, sources, verbs};

/// What makes a bare pointer of a box, and a box of one. Each spelled in
/// two halves, so this file is none of theirs.
const CALLS: [&str; 2] = [concat!("Box::into", "_raw("), concat!("Box::from", "_raw(")];

/// Where the doors are.
const HOME: &str = "device.rs";

/// The files that box for something else, each with why.
const LEDGER: [(&str, &str); 0] = [];

#[test]
fn what_the_abi_hands_out_is_boxed_and_unboxed_by_the_doors_alone() {
    let found = files_where("rs", |text| CALLS.iter().any(|call| text.contains(call)));
    let fix = "hand these out with `Engine::hands` or `hands_bytes`, and let go of them by the same door";
    assert_home_and_ledger(found, HOME, &LEDGER, fix);
}

/// The door a thing goes out or comes back by.
#[derive(Clone, Copy, Debug, PartialEq)]
enum Door {
    Engines,
    Bytes,
}

/// The door `body` hands its thing out by, where it names one itself.
fn hands_out_by(body: &str) -> Option<Door> {
    match (body.contains(".hands("), hands_out_bytes(body)) {
        (true, false) => Some(Door::Engines),
        (false, true) => Some(Door::Bytes),
        _ => None,
    }
}

/// The door `body` lets its thing go by.
fn lets_go_by(body: &str) -> Option<Door> {
    let engines = body.contains(" let_go(") || body.contains(" let_go_unwaited(");
    match (engines, body.contains(" let_go_bytes(")) {
        (true, false) => Some(Door::Engines),
        (false, true) => Some(Door::Bytes),
        _ => None,
    }
}

/// The type named in `signature` right after `before`.
fn named_after<'a>(signature: &'a str, before: &str) -> Option<&'a str> {
    let after = &signature[signature.find(before)? + before.len()..];
    let end = after.find(|c: char| !(c.is_alphanumeric() || c == '_')).unwrap_or(after.len());
    (end > 0).then(|| &after[..end])
}

/// Each type a verb of `verbs` hands out by a door it names, with the door
/// and the verb.
fn handed_out<'a>(verbs: &'a BTreeMap<String, Verb>) -> Vec<(&'a str, Door, &'a str)> {
    let made = |verb: &'a Verb| {
        let door = hands_out_by(&verb.body)?;
        Some((named_after(&verb.signature, "-> *mut ")?, door, verb.name.as_str()))
    };
    verbs.values().filter_map(made).collect()
}

#[test]
fn a_thing_comes_back_by_the_door_it_went_out_by() {
    let verbs = verbs();
    // Each type's free, and its door: the first thing a free is handed.
    let frees: BTreeMap<&str, (Door, &str)> = verbs
        .values()
        .filter(|verb| verb.name.ends_with("_free"))
        .filter_map(|verb| Some((named_after(&verb.signature, ": *mut ")?, (lets_go_by(&verb.body)?, &*verb.name))))
        .collect();
    assert_eq!(frees.get("Texture"), Some(&(Door::Bytes, "gpu_engine_dab_texture_free")), "LIVENESS");
    assert_eq!(frees.get("Planned"), Some(&(Door::Engines, "gpu_engine_plan_free")), "LIVENESS");
    let handed_out = handed_out(&verbs);
    assert!(handed_out.contains(&("Texture", Door::Bytes, "gpu_engine_dab_texture_new")), "LIVENESS");
    let other_way = |(thing, door, maker): &(&str, Door, &str)| {
        let back = frees.get(thing);
        (back.map(|(back, _)| back) != Some(door))
            .then(|| format!("{maker} hands a {thing} out by {door:?}, and its free is {back:?}"))
    };
    let off: Vec<_> = handed_out.iter().filter_map(other_way).collect();
    assert!(off.is_empty(), "a thing let go of as a box of another shape: {off:#?}");
}

/// A type the sources define — a struct, an enum or a name for another —
/// as it is written, less its comments, with the file it is in.
struct Defined {
    file: String,
    text: String,
}

/// The kinds of type the scan reads, as each is opened.
const KINDS: [&str; 3] = ["struct ", "enum ", "type "];

/// The type the line `head` opens — its kind, of [`KINDS`], and its name
/// — and what closes it where it goes on past the line: a brace or a
/// bracket at the line's own indent.
fn opened(head: &str) -> Option<(&'static str, &str, Option<char>)> {
    let named = ["pub(crate) ", "pub(super) ", "pub "].iter().find_map(|open| head.strip_prefix(open)).unwrap_or(head);
    let (kind, named) = KINDS.iter().find_map(|kind| Some((*kind, named.strip_prefix(kind)?)))?;
    let name = named.split(|c: char| !(c.is_alphanumeric() || c == '_')).next().filter(|name| !name.is_empty())?;
    let closes = match head.trim_end().chars().last() {
        Some('{') => Some('}'),
        Some('(') => Some(')'),
        _ => None,
    };
    Some((kind, name, closes))
}

/// `line` of an enum less the variant it names: a variant is no type the
/// enum holds, though a type elsewhere has its name (`Paint::Fill` is no
/// `fill::Fill`). What the variant holds stays.
fn less_its_variant(line: &str) -> &str {
    let inside = line.trim_start();
    let named = inside.find(|c: char| !(c.is_alphanumeric() || c == '_')).unwrap_or(inside.len());
    if inside.starts_with(char::is_uppercase) { &inside[named..] } else { line }
}

/// Every type `sources` define, by its name: a name can be several, in
/// several files.
fn defined(sources: &BTreeMap<String, String>) -> BTreeMap<String, Vec<Defined>> {
    let mut found: BTreeMap<String, Vec<Defined>> = BTreeMap::new();
    for (file, text) in sources {
        let mut at = 0;
        for line in text.split_inclusive('\n') {
            let (begins, indent) = (at, line.len() - line.trim_start().len());
            at += line.len();
            let Some((kind, name, closes)) = opened(line.trim_start()) else {
                continue;
            };
            let rest = &text[begins..];
            let ends = closes.map(|closes| format!("\n{}{closes}", &line[..indent])).map_or(line.len(), |closes| {
                rest.find(&closes).map_or(rest.len(), |end| end + closes.len())
            });
            let code = rest[..ends].lines().filter(|line| !line.trim_start().starts_with("//"));
            let code = code.map(|line| if kind == "enum " { less_its_variant(line) } else { line });
            let text = code.collect::<Vec<_>>().join("\n");
            found.entry(name.to_owned()).or_default().push(Defined { file: file.clone(), text });
        }
    }
    found
}

/// How many folders `one` and `other` are in together, from the top.
fn folders_shared(one: &str, other: &str) -> usize {
    let folders = |file: &str| file.rsplit_once('/').map_or("", |(folders, _)| folders).to_owned();
    let (one, other) = (folders(one), folders(other));
    one.split('/').zip(other.split('/')).take_while(|(one, other)| !one.is_empty() && one == other).count()
}

/// Why the type `name`, as a file `from` names it, holds something of a
/// device — the way down to what does, each type after the one that holds
/// it — or nothing, where it holds none: a field of wgpu's, or of a type
/// of the crate's that holds one. A name several files define is the one
/// defined nearest `from`: in its file, else in the most folders with it.
fn holds_of_a_device(
    name: &str,
    from: &str,
    defined: &BTreeMap<String, Vec<Defined>>,
    seen: &mut BTreeSet<(String, String)>,
) -> Option<Vec<String>> {
    let all = defined.get(name)?;
    let near = |one: &Defined| (one.file == from, folders_shared(&one.file, from));
    let nearest = all.iter().map(near).max()?;
    for one in all.iter().filter(|one| near(one) == nearest) {
        if !seen.insert((name.to_owned(), one.file.clone())) {
            continue;
        }
        let here = format!("{name} ({})", one.file);
        if one.text.contains("wgpu::") {
            return Some(vec![here]);
        }
        let words = one.text.split(|c: char| !(c.is_alphanumeric() || c == '_'));
        let held: BTreeSet<&str> = words.filter(|word| *word != name && defined.contains_key(*word)).collect();
        for word in held {
            if let Some(mut down) = holds_of_a_device(word, &one.file, defined, seen) {
                down.insert(0, here);
                return Some(down);
            }
        }
    }
    None
}

#[test]
fn a_thing_of_bytes_holds_nothing_of_a_device() {
    let (sources, verbs) = (sources(), verbs());
    let defined = defined(&sources);
    let holds = |thing: &str, maker: &str| {
        let made_in = sources.iter().find(|(_, text)| text.contains(&format!("fn {maker}(")));
        let from = made_in.map_or("", |(file, _)| file.as_str());
        holds_of_a_device(thing, from, &defined, &mut BTreeSet::new())
    };
    // LIVENESS: a thing of the engine's is seen to hold what it holds — a
    // readout its buffer, and a plan what a type it names holds.
    assert!(holds("Readout", "gpu_engine_readout_free").is_some(), "a readout holds a buffer");
    let down = holds("Planned", "gpu_engine_plan_new");
    assert!(down.as_ref().is_some_and(|down| down.len() > 1), "a plan holds a buffer through what it names: {down:?}");
    let of_bytes: Vec<_> = handed_out(&verbs).into_iter().filter(|(_, door, _)| *door == Door::Bytes).collect();
    assert!(of_bytes.iter().any(|(thing, ..)| *thing == "Faces"), "LIVENESS — the scan finds the things of bytes");
    let off: Vec<_> = of_bytes
        .iter()
        .filter_map(|(thing, _, maker)| Some(format!("{maker}: {}", holds(thing, maker)?.join(" → "))))
        .collect();
    assert!(
        off.is_empty(),
        "a thing of bytes holds something of a device — hand it out with `Engine::hands`, its maker handed the \
         engine, and let go of it with `let_go`: {off:#?}"
    );
}

#[test]
fn the_scan_reads_a_type_down_to_what_it_holds() {
    let sources: BTreeMap<String, String> = [
        (
            "a/kept.rs",
            "pub(crate) struct Kept {\n    words: Vec<u32>,\n    shape: Shape,\n}\n\nenum Shape {\n    Round,\n    Paged,\n}\n",
        ),
        (
            "a/shown.rs",
            "struct Shown {\n    kept: Kept,\n    page: Page,\n}\n\ntype Page = Paged;\n\nenum Either {\n    Neither,\n    One(Paged),\n}\n",
        ),
        ("b/paged.rs", "pub struct Paged(wgpu::Buffer);\n\nstruct Shape {\n    of: wgpu::Texture,\n}\n"),
    ]
    .into_iter()
    .map(|(file, text)| (file.to_owned(), text.to_owned()))
    .collect();
    let defined = defined(&sources);
    assert_eq!(defined["Shape"].len(), 2);
    let holds = |name: &str, from: &str| holds_of_a_device(name, from, &defined, &mut BTreeSet::new());
    // Its own fields, a name several files define read as the nearest, and
    // a variant of the name of a type that holds one as no type held.
    assert_eq!(holds("Kept", "a/kept.rs"), None);
    // What a variant holds, as held.
    let down = ["Either (a/shown.rs)", "Paged (b/paged.rs)"].map(str::to_owned);
    assert_eq!(holds("Either", "a/shown.rs"), Some(down.to_vec()));
    // Through a type of the crate's, and a name for another.
    let down = ["Shown (a/shown.rs)", "Page (a/shown.rs)", "Paged (b/paged.rs)"].map(str::to_owned);
    assert_eq!(holds("Shown", "a/shown.rs"), Some(down.to_vec()));
    // And the same name from where the other one is the nearest.
    assert_eq!(holds("Shape", "b/paged.rs"), Some(vec!["Shape (b/paged.rs)".to_owned()]));
}

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/engine_verbs.dart';

/// 🚨A FREE THE GC CALLS WAITS FOR NOTHING — AND NO OTHER FREE DOES.
///
/// The engine lets go of what its ABI handed out on the engine's thread
/// (the-ui-thread-never-enters-the-driver 1b, 2026-11-14 — `Handed`, in
/// packages/gpu_engine/rust/src/device.rs, has why). A free waits there
/// till its thing is gone (`let_go`), so what the thing counted is counted
/// off as the free returns. But a native finalizer's callback holds every
/// isolate of its group for as long as it takes — 🔬Dart 3.13.3, the main
/// PC, 2026-11-14: a callback of 300 ms, and the main isolate and a worker
/// each stood 315 ms, six times of six — and waiting there the GC would
/// hold the UI for every body ahead on the engine's thread, a save's read
/// back among them. So a free a finalizer is bound to hands its thing over
/// and returns (`let_go_unwaited`), and the rest wait.
///
/// ⏳브러시/렌더링 2026-11-14, the user asleep — theirs to overturn (관제
/// 03:43, on the card: taken as it stands).
///
/// Nor does one a verb handed over unwaited still reads and that counts
/// nothing — a plan (B1-a, 2026-11-15; the test has why) —, nor one the
/// app lets go of by the hundred and that counts nothing — a frame grid's
/// tile picture (B1, 2026-11-15; the same) —, nor a screen's, which counts
/// and counts its part off first (「다음 문」, 2026-11-16; the same) —,
/// nor a landing's finished with no wait, freed behind the put it handed
/// over and counting nothing (2026-11-20; the same).
///
/// What holds nothing of a device is no engine's (`hands_bytes` — 🗣️관제
/// 2026-11-14 05:16, the same card): its free lets go of its bytes where it
/// is called, the GC's thread among them as before, and waits for nothing
/// either (`let_go_bytes`).
///
/// ⛔SO THIS SCANS BOTH SIDES. The app binds a finalizer in Dart and the
/// free waits or not in Rust; a test of behaviour passes each alone — a
/// finalizer bound to a free that waits stalls nothing till the GC meets a
/// long body — and a landing runs the crate's own tests only where the
/// crate changed (tool/lane.sh), which a finalizer bound in Dart is not.
void main() {
  final verbs = engineVerbBodies();
  final dart = [
    for (final file in dartFilesUnder('packages/gpu_engine/lib'))
      file.readAsStringSync(),
    for (final file in dartFilesUnder('lib')) file.readAsStringSync(),
  ].join('\n');

  test('a free a finalizer is bound to waits for nothing, and no other', () {
    final collected = _collectedFrees(dart);
    final unwaited = _freesThrough('let_go_unwaited(', verbs);
    final ofBytes = _freesThrough('let_go_bytes(', verbs);
    expect(
      collected,
      containsAll([
        'gpu_engine_dab_texture_free',
        'gpu_engine_stamp_picture_free',
      ]),
      reason: 'LIVENESS — the scan reads the finalizers the app binds',
    );
    expect(
      [unwaited, ofBytes],
      [
        contains('gpu_engine_stamp_picture_free'),
        contains('gpu_engine_dab_texture_free'),
      ],
      reason: 'LIVENESS — the scan reads the door a free goes through',
    );
    expect(
      collected.difference({...unwaited, ...ofBytes}),
      isEmpty,
      reason: 'the GC calls these, and they wait for the engine\'s thread: '
          'let go of their thing with `let_go_unwaited` (device.rs), and '
          'count off what it counted before that, in the verb',
    );
    // 🚨BUT ONE A VERB HANDED OVER UNWAITED STILL READS, AND THAT COUNTS
    // NOTHING (the-ui-thread-never-enters-the-driver B1-a, 2026-11-15): a
    // plan, which a screen's compose reads on the engine's thread once it
    // is handed over (`GpuScreen.compose`) — its free waiting there stood
    // the UI behind every compose it had just handed over, and nothing it
    // counted is to be counted off as it returns. ⏳브러시/렌더링, the user
    // asleep; theirs to overturn.
    const readByWhatWasHandedOver = {'gpu_engine_plan_free'};
    expect(
      unwaited,
      containsAll(readByWhatWasHandedOver),
      reason: 'LIVENESS — a free handed over as a verb still reads its thing',
    );
    // 🚨AND ONE THE APP LETS GO OF BY THE HUNDRED, AND THAT COUNTS NOTHING
    // (the-ui-thread-never-enters-the-driver B1, 2026-11-15): a frame grid's
    // tile picture, a texture (grid/mod.rs) — a whole cut's tiles baked
    // again let go of theirs on the UI's thread, each free a trip that
    // waited 39–44 µs on an idle engine (🔬타임라인/콘티 09:20, the main PC,
    // debug) and behind every compose handed over where one was. ↩️Not
    // let go of in one trip at a flush, as the batch makes them: that trip
    // still waits in the same line, and is a verb more. ⏳브러시/렌더링;
    // the user's to overturn.
    const freedByTheHundred = {'gpu_engine_grid_picture_free'};
    expect(
      unwaited,
      containsAll(freedByTheHundred),
      reason: 'LIVENESS — a free of a thing counting nothing waits for nothing',
    );
    // 🚨AND ONE THE UI CALLS BEHIND THE BODIES IT HANDED OVER, OF A THING
    // THAT COUNTS (the-ui-thread-never-enters-the-driver, 「다음 문」,
    // 2026-11-16): a screen, which its compose and show read on the
    // engine's thread once handed over (`GpuScreen.compose`) — its free
    // waiting there stood the UI 44.2 ms as a row's onion came on, 80.4 and
    // 36.0 ms with every one on (🔬캔버스 베이스 패널, the Surface, profile,
    // 11-15 18:17). What it counts is counted off in the verb before it
    // hands the screen over (`ScreenAndBytes::counted_off`,
    // kernels/composite/abi.rs). ⏳브러시/렌더링; the user's to overturn.
    const standingBehindItsBodies = {'gpu_engine_screen_free'};
    expect(
      unwaited,
      containsAll(standingBehindItsBodies),
      reason: 'LIVENESS — a free the UI stood behind its bodies for',
    );
    // 🚨AND ONE THE UI CALLS RIGHT BEHIND THE PUT IT HANDED OVER, OF A
    // THING THAT COUNTS NOTHING (opening-a-transform-box-holds-the-ui-
    // over-half-a-second, 2026-11-20): what a landing finished with no
    // wait, freed in the turn that is told once its tiles are on their
    // way (`EngineTileLedger.landOnceTold`) — the put holds the tiles
    // made as its own (`gpu_engine_finished_land_unwaited`), so nothing
    // reads it after; its free waiting there stood that turn behind the
    // put and every body ahead of it, the wait the door is there to
    // take off the UI's thread (🗣️the user 11-19, Q1 「상자가 뜰 때 미리
    // 들기」; 🔬공통's, on the card: a turn that waited stood 5–14 ms
    // behind the GPU, 31–63 with its line full). The crate pins that
    // it waits for no turn and that its put lands all the same
    // (dab/finished_tests.rs).
    // ⏳브러시/렌더링; the user's to overturn.
    const freedBehindItsOwnPut = {'gpu_engine_finished_free'};
    expect(
      unwaited,
      containsAll(freedBehindItsOwnPut),
      reason: 'LIVENESS — a free the told turn calls behind its put',
    );
    expect(
      unwaited
          .difference(collected)
          .difference(readByWhatWasHandedOver)
          .difference(freedByTheHundred)
          .difference(standingBehindItsBodies)
          .difference(freedBehindItsOwnPut),
      isEmpty,
      reason: 'nothing collects these, and their thing is not gone as they '
          'return: let go of it with `let_go` (device.rs)',
    );
  });

  test('a finalizer names its free where this scan reads it', () {
    expect(
      _finalizersNamedElsewhere(dart),
      isEmpty,
      reason: 'bind a finalizer to `Native.addressOf<…>(theFree)`: a free '
          'named any other way is one this scan cannot hold to its law',
    );
  });

  test('the scan reads a finalizer, a binding and a free as they are '
      'written', () {
    const bound = '''
@Native<Void Function(Pointer<Kept>)>(
  symbol: 'gpu_engine_kept_free',
)
external void keptFree(Pointer<Kept> kept);

@Native<Void Function(Pointer<Shown>)>(symbol: 'gpu_engine_shown_free')
external void shownFree(Pointer<Shown> shown);

static final NativeFinalizer _freed = NativeFinalizer(
  Native.addressOf<NativeFunction<Void Function(Pointer<rust.Kept>)>>(
    rust.keptFree,
  ).cast(),
);
// Another library's free is none of the engine's.
final other = Native.addressOf<NativeFinalizerFunction>(_free);

@Native<Void Function(Int64, Int32, Uint64)>(symbol: 'gpu_engine_told')
external void told(int texture, int kind, int count);

// A function handed out to be told by, not a free.
final address = Native.addressOf<
  NativeFunction<Void Function(Int64, Int32, Uint64)>
>(rust.told).address;
''';
    expect(_collectedFrees(bound), {'gpu_engine_kept_free'});
    expect(_finalizersNamedElsewhere(bound), isEmpty);
    expect(
      _finalizersNamedElsewhere(
        'final freed = NativeFinalizer(library.lookup(name));\n'
        'static final Pointer<NativeFinalizerFunction> _freed =\n'
        '    library.lookup(name);\n',
      ),
      hasLength(2),
    );
    final frees = engineVerbBodiesIn('''
/// A comment that names let_go_unwaited(kept) lets go of nothing.
pub unsafe extern "C" fn gpu_engine_kept_free(kept: *mut Kept) {
    // SAFETY: see the function's contract.
    unsafe { let_go_unwaited(kept) };
}

pub unsafe extern "C" fn gpu_engine_shown_free(shown: *mut Shown) {
    // What the GC lets go of goes through let_go_unwaited(…); not this.
    unsafe { let_go(shown) };
}

pub unsafe extern "C" fn gpu_engine_words_free(words: *mut Words) {
    // SAFETY: see the function's contract.
    unsafe { let_go_bytes(words) };
}
''');
    expect(_freesThrough('let_go_unwaited(', frees), {'gpu_engine_kept_free'});
    expect(_freesThrough('let_go_bytes(', frees), {'gpu_engine_words_free'});
  });
}

/// The engine's frees [dart] binds a native finalizer to, each by the name
/// the engine exports it under: what `Native.addressOf` is asked the
/// address of, where it is one of the engine's bindings.
Set<String> _collectedFrees(String dart) {
  final exported = {
    for (final binding in _binding.allMatches(dart))
      binding.group(2)!: binding.group(1)!,
  };
  return {
    for (final asked in _addressOf.allMatches(dart))
      if (_aFreesShape.hasMatch(asked.group(0)!))
        ?exported[asked.group(1)!.split('.').last],
  };
}

/// A finalizer's callback takes the one pointer it was attached with
/// (`NativeFinalizerFunction`, `Void Function(Pointer<…>)`). ↩️Every
/// `Native.addressOf` of the engine's was a finalizer's till a screen's
/// texture was handed Flutter a function to tell its reads to
/// (`gpu_engine_screen_read`, patch 0007, 2026-11-24) — called by Flutter's
/// raster and fence threads, never by the GC.
final _aFreesShape = RegExp(
  r'<\s*(NativeFinalizerFunction|NativeFunction<\s*Void\s+Function\(\s*'
  r'Pointer<[^,()]*>\s*\)\s*>)\s*>',
);

/// A binding of the engine's: the name it is exported under, then the name
/// Dart calls it by.
final _binding = RegExp(
  r"symbol:\s*'(gpu_engine_\w+)'[^;]*?\)\s*external\s[^(;]*?(\w+)\(",
);

/// What `Native.addressOf` is asked the address of.
final _addressOf = RegExp(r'Native\.addressOf<[^;{]*?>\(\s*([\w.]+)\s*,?\s*\)');

/// The finalizers of [dart] that take their free from anything but
/// `Native.addressOf`, each as it is written — one named in a comment is
/// none.
List<String> _finalizersNamedElsewhere(String dart) => [
  for (final made in RegExp(
    r'(NativeFinalizer\(|Pointer<NativeFinalizerFunction>\s+\w+\s*=)'
    r'(?!\s*Native\.addressOf<)[^;]*;',
  ).allMatches(dart.replaceAll(RegExp(r'//[^\n]*'), '')))
    made.group(0)!,
];

/// The frees of [verbs] that let go of their thing through [door], a door
/// of device.rs as a body calls it.
Set<String> _freesThrough(String door, Map<String, String> verbs) => {
  for (final MapEntry(key: name, value: body) in verbs.entries)
    if (name.endsWith('_free') && body.contains(' $door')) name,
};

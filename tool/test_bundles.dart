// A crowd batch's files run as bundles: entries that each import up to
// [kFilesPerBundle] test files and run each one's `main` as a group named by
// its path — one compile and one tester start for ten files.
//
// 🗣️유저 2026-11-20, card the-wide-check-takes-five-hours-Q3 「a 묶는다 —
// 혼자 서야 하는 파일만 따로」. `flutter test` compiles every file into a
// program of its own (92–108 MB of kernel, copied), starts a tester for it,
// loads and warms it. 🧪200 light files at eight suites (11-20): the
// compile 153 · 149 s → 27 · 29 s, each test 0.83–0.90 s → 0.46–0.52 s.
//
// ⚠️WHAT IT COSTS IS ISOLATION. The files of an entry share one isolate and
// one binding, and every file's `main` runs — declares its tests — before
// any test of any of them. A file that starts a binding of its own cannot
// stand beside another ([whyAlone]); a file that leans on what one before
// it left, or leaves what one after it trips on, goes red there and green
// alone — `affected_tests` runs every bundled red again alone, and names
// those ([kRunsAlone] is where the census puts them).

import 'dart:io' show FileSystemException;

import 'source_brackets.dart';
import 'test_seconds.dart' show SuiteRun, isBundleEntry;

/// The most files one entry runs.
const kFilesPerBundle = 10;

/// The test config beside a batch's entries ([kBundleFolder]), from
/// [toRoot] — the way from their folder up to the checkout's root.
/// `flutter test` finds a file's config by walking up from it, so an entry
/// is wrapped as a test file is: the same `testExecutable`, once an entry.
String bundleConfigSource(String toRoot) =>
    "export '$toRoot/test/flutter_test_config.dart';\n";

/// The files that lose what they read in company — red in a bundle, green
/// alone — each with what it leans on. They run as files of their own.
/// ⚖️Where the census measured that one file, green itself, leaves what
/// every file after it trips on, that file is the line and the ones it
/// trips are not: run alone, it leaves nothing to anyone. ↩️The one so far
/// (11-23, the_shell_says_the_device_started_again) left the opening of
/// the app's engine made on its own test's clock, and left the line once
/// that was kept as itself (`MadeOnce`, card
/// an-engine-setup-hangs-in-a-batch).
/// 🧭The census fills it (전 파일을 묶어 정순 · 역순 두 번 + 파일별 대조,
/// 관제 11-20); a file leaves it when its test stops leaning.
/// Where what a file leans on is not read yet, its line says what the
/// census saw — its place in the bundle, the file before it, the first
/// error — and card the-wide-check-takes-five-hours lists those by area,
/// to be read and mended there.
const Map<String, String> kRunsAlone = {
  'test/home_cut_switching_test.dart':
      'census 11-21 reversed: red 10/10 in a bundle, after '
      'the_format_window_gives_cuts_their_camera_room (9 of 9 tests red); '
      'green alone.',
  'test/services/a_selection_lifts_on_the_engine_test.dart':
      'census 11-21 reversed: red 5/5 in a bundle, after '
      'the_next_page_is_baked_while_the_page_before_plays (1 of 49 tests red) '
      '— Expected: a value greater than <0> / Actual: <0>; green alone.',
  'test/services/a_stamp_lands_on_the_engine_test.dart':
      'census 11-20 forward: red 3/3 in a bundle, after '
      'a_frame_on_screen_stands_again_on_the_next_engine (4 red) — Expected: '
      '<255> / Actual: <128>; green alone.',
  'test/services/brush_stroke_blend_test.dart':
      'census 11-20 forward: red 5/10 in a bundle, after '
      'a_lay_the_gpu_did_not_lay_is_answered_with_why (4 red) — Bad state: '
      'the graphics device is gone: Destroyed; green alone.',
  'test/services/media/a_closed_movie_leaves_nothing_behind_test.dart':
      'it weighs the whole process\'s heap across two hundred opens, and a '
      'GPU engine a file ahead of it opened moves that heap as it works — '
      'the engine is never closed, by law (census 11-21 reversed: red 10/10 '
      'in a bundle; read by 저장 11-22, card '
      'bundled-files-find-stores-left-behind: 36,189 B behind a bundle that '
      'only opened the engine, 16,392 B behind a tile test, the bar 16,384); '
      'green alone.',
  'test/services/persistence/a_picked_file_is_read_in_under_its_wait_test.dart':
      'census 11-21 reversed: red 5/9 in a bundle, after '
      'the_keyboard_tilde_is_nanums (1 of 5 tests red) — Expected: a value '
      'less than Duration:<0:00:00.334539> / Actual: '
      'Duration:<0:00:00.334539>; green alone.',
  'test/services/persistence/a_save_reads_the_next_cel_while_one_is_written_test.dart':
      'census 11-21 reversed: red 8/10 in a bundle, after '
      'the_edit_button_never_creates (2 of 2 tests red) — Bad state: the '
      'graphics device is gone: Destroyed; green alone.',
  'test/ui/a_drive_project_opens_in_a_tab_and_saves_back_test.dart':
      'census 11-21 reversed: red 10/10 in a bundle, after '
      'every_sheet_takes_its_photo_with_the_tool (4 of 4 tests red); green '
      'alone.',
  'test/ui/brush/the_eyedropper_swatch_keeps_its_place_test.dart':
      'census 11-20 forward and 11-21 reversed: red 5/10 in a bundle, after '
      'toolbar_buttons_do_not_fade (2 red) — Expected: Object or closure '
      'painting: / \'a circle with a mask filter\' / \'a circle with …; green '
      'alone.',
  'test/ui/canvas/an_overlay_holds_what_it_shows_test.dart':
      'census 11-20 forward and 11-22 reversed: red 4/10 in a bundle, after '
      'an_se_rows_box_is_a_layers (1 red) — Expected: true / Actual: <false>; '
      'green alone.',
  'test/ui/canvas/the_pointer_that_moves_wears_the_cursor_test.dart':
      'census 11-21 reversed: red 10/10 in a bundle, after '
      'an_se_tag_stands_in_the_shot (6 of 6 tests red); green alone.',
  'test/ui/export/an_export_holds_two_frames_not_its_cut_test.dart':
      'census 11-21 reversed: red 8/9 in a bundle, after '
      'a_placed_carry_holds_its_bytes (35 of 35 tests red); green alone.',
  'test/ui/export/an_output_looks_at_no_head_of_the_cut_test.dart':
      'census 11-21 reversed: red 8/10 in a bundle, after '
      'xsheet_reveals_the_selection (8 of 8 tests red); green alone.',
  'test/ui/playback/a_warmer_handed_the_real_clock_ends_with_the_test_test.dart':
      'census 11-20 forward: red 2/9 in a bundle, after '
      'the_colour_edit_head_lights_with_its_block (1 red) — premise: the '
      'engine makes a picture in the lent clock, and the walk lands it when '
      'the …; green alone.',
  'test/ui/playback/voice_record_preview_test.dart':
      'census 11-20 forward: red 3/10 in a bundle, after export_preview_panel '
      '(1 red) — REC1-C: the timeline shows the growing take WITHOUT a '
      'session notify — the preview …; green alone.',
  'test/ui/session/a_cut_crossed_in_the_storyboard_is_stood_on_like_a_press_test.dart':
      'census 11-20 forward and 11-21 reversed: red 9/10 in a bundle, after '
      'track_fx (3 red) — Expected: CutId:<cut-1> / Actual: CutId:<cut-2> / '
      'premise: playback crossed; green alone.',
  'test/ui/sheet/every_sheet_takes_its_photo_with_the_tool_test.dart':
      'census 11-21 reversed: red 9/10 in a bundle, after '
      'an_output_looks_at_no_head_of_the_cut (6 of 6 tests red); green alone.',
  'test/ui/storyboard_se_track_test.dart':
      'census 11-21 reversed: red 9/9 in a bundle, after '
      'a_run_edge_press_acts_on_the_band (1 of 5 tests red); green alone.',
  'test/ui/the_held_piece_is_counted_test.dart':
      'census 11-21 reversed: red 8/9 in a bundle, after '
      'a_cut_obeys_the_symmetry_guide (1 of 1 tests red); green alone.',
  'test/ui/the_link_window_answers_for_cuts_and_rows_test.dart':
      'census 11-21 reversed: red 10/10 in a bundle, after '
      'workspace_flip_axis_follows_the_timeline (1 of 17 tests red); green '
      'alone.',
  'test/ui/timeline/a_block_warning_says_why_and_follows_the_hand_test.dart':
      'census 11-21 reversed: red 10/10 in a bundle, after '
      'a_row_that_takes_no_strokes_draws_no_line (1 of 12 tests red); green '
      'alone.',
  'test/ui/timeline/a_drag_step_repaints_only_its_tick_layers_test.dart':
      'census 11-21 reversed: red 10/10 in a bundle, after '
      'the_linked_paste_asks_before_it_joins (3 of 21 tests red); green '
      'alone.',
  'test/ui/timeline/a_row_paints_its_substrate_and_its_glyphs_test.dart':
      'census 11-20 forward: red 5/9 in a bundle, after no_import_cycles (1 '
      'red) — with the engine on and the store COLD, a span waiting for its '
      'tile paints the same …; green alone.',
  'test/ui/timeline/a_row_reads_each_cell_once_a_pass_test.dart':
      'census 11-21 reversed: red 5/5 in a bundle, after '
      'a_tile_keeps_what_an_edit_left_alone (1 of 5 tests red) — Expected: '
      'null / Actual: <Instance of \'TimelineGridTilePicture\'>; green alone.',
  'test/ui/timeline/a_test_hands_the_next_an_empty_tile_store_test.dart':
      'census 11-20 forward: red 4/10 in a bundle, after '
      'the_camera_row_carries_its_path_button (2 red) — a test that ends with '
      'its drain waiting and rasters queued…; green alone.',
  'test/ui/timeline/one_inbetween_mark_everywhere_test.dart':
      'census 11-20 forward and 11-21 reversed: red 6/10 in a bundle, after '
      'workspace_layout_store (1 red) — Expected: an object with length of '
      '<1> / Actual: WhereIterable<Rect>:[] / Which: has …; green alone.',
};

/// The test bindings flutter_test starts itself; any other is a file's own.
const _sharedBindings = {
  'TestWidgetsFlutterBinding',
  'AutomatedTestWidgetsFlutterBinding',
  'WidgetsFlutterBinding',
};

/// Why the test file [source] cannot share an isolate with others — or
/// null when it can.
String? whyAlone(String source) {
  final code = codeOnly(source);
  if (RegExp(r'\bclass\s+\w+\s+extends\s+\w*Binding\b').hasMatch(code)) {
    return 'it declares a test binding of its own, and an isolate holds one';
  }
  for (final start in RegExp(
    r'\b(\w+Binding)\.ensureInitialized\(',
  ).allMatches(code)) {
    if (!_sharedBindings.contains(start[1])) {
      return 'it starts ${start[1]}, and an isolate holds one binding';
    }
  }
  if (RegExp(r'\bmain\s*\([^)]*\)\s*async\b').hasMatch(code) ||
      RegExp(r'\bFuture<\w+>\s+main\s*\(').hasMatch(code)) {
    return 'its main is async, and a group is declared at once';
  }
  if (!RegExp(r'(^|\s)(void\s+)?main\s*\(\s*\)', multiLine: true)
      .hasMatch(code)) {
    return 'it has no main a group can call';
  }
  return null;
}

/// [source]'s library annotations, as written — what stands before its
/// `library;` — each on one line.
List<String> libraryAnnotations(String source) {
  final code = withoutComments(source);
  final found = <String>[];
  var at = 0;
  while (true) {
    while (at < code.length && code[at].trim().isEmpty) {
      at++;
    }
    if (at >= code.length || code[at] != '@') return found;
    final name = RegExp(r'[\w.]+').matchAsPrefix(code, at + 1);
    if (name == null) return found;
    final start = at;
    at = name.end;
    if (code.startsWith('(', at)) {
      final close = matchingClose(code, at);
      if (close == null) return found;
      at = close + 1;
    }
    found.add(code.substring(start, at).replaceAll(RegExp(r'\s+'), ' '));
  }
}

/// Whether [file] — or a test file it imports, at any depth — loads a font
/// into its isolate (a `FontLoader`, `loadFontFromList`). [read] gives a
/// file's source by its path from the checkout's root.
///
/// 🎯A FONT ONCE LOADED IS THE ISOLATE'S (card
/// bundled-files-measure-text-differently, 보드/인프라 2026-11-22).
/// flutter_test measures every glyph in its test font until a file loads
/// the app's faces (test/helpers/app_faces.dart), and nothing unloads them.
/// Bundled with two files that load them, each of three that measure in the
/// test font went red behind one and stayed green ahead of both, in either
/// order — and green alone.
bool loadsFonts(String file, {required String Function(String path) read}) =>
    _reaches(file, _loadsAFont, read);

final _loadsAFont = RegExp(r'\b(FontLoader|loadFontFromList)\(');

/// Whether [file] — or a test file it imports, at any depth — starts a
/// test binding (a `testWidgets`, an `ensureInitialized`). [read] gives a
/// file's source by its path from the checkout's root.
///
/// 🎯A BINDING ONCE STARTED IS THE ISOLATE'S, as a font is (card
/// bundled-files-read-timeline-values-left-behind, 타임라인/콘티 →
/// 보드/인프라 2026-11-23). A `testWidgets` starts it as it is declared, and
/// in a bundle every file declares before any test runs. A file that never
/// starts one takes the ways lib goes where there is no binding — a frame's
/// wait at once, an image let go at once, a shadow painted — and three such
/// files went red behind widget tests and green alone.
bool startsABinding(
  String file, {
  required String Function(String path) read,
}) =>
    _reaches(file, _startsABinding, read);

final _startsABinding = RegExp(r'\b(testWidgets|ensureInitialized)\(');

/// Whether code [pattern] matches is in [file] or in a test file it
/// imports, at any depth.
bool _reaches(
  String file,
  RegExp pattern,
  String Function(String path) read,
) {
  final seen = {file};
  final next = [file];
  while (next.isNotEmpty) {
    final path = next.removeLast();
    final String source;
    try {
      source = read(path);
    } on FileSystemException {
      // ⚠️A file a test uses that is not there is passed over: the test
      // fails to compile alone and says so there — it is no reason to fail
      // the whole batch's bundling.
      continue;
    }
    if (pattern.hasMatch(codeOnly(source))) return true;
    for (final imported in _testFilesUsed(path, source)) {
      if (seen.add(imported)) next.add(imported);
    }
  }
  return false;
}

/// The test files [source] — the file at [path] — imports or exports by a
/// relative path, as paths from the checkout's root. Only its directives
/// are read, before its first declaration: a scan test plants an `import`
/// line in a string of its own (a_gone_device_is_asked_of_the_engine_begun_
/// on_test), and that names no file.
Iterable<String> _testFilesUsed(String path, String source) sync* {
  final code = withoutComments(source);
  final declared = RegExp(
    r'^(?!(?:import|export|library|part)\b)[A-Za-z_]',
    multiLine: true,
  ).firstMatch(code);
  final directives = code.substring(0, declared?.start ?? code.length);
  final uses = RegExp(r'''\b(?:import|export)\s+['"]([^'"]+)['"]''');
  for (final use in uses.allMatches(directives)) {
    final target = use[1]!;
    if (target.contains(':')) continue;
    final parts = path.split('/')..removeLast();
    for (final part in target.split('/')) {
      if (part == '..') {
        if (parts.isEmpty) break;
        parts.removeLast();
      } else if (part != '.') {
        parts.add(part);
      }
    }
    final used = parts.join('/');
    if (used.startsWith('test/')) yield used;
  }
}

/// A batch's [files] — longest first — as entries of at most
/// [kFilesPerBundle], dealt in turn so each starts on a heavy file and the
/// entries weigh about alike, a file only with files of its own library
/// annotations ([entrySource] makes them the entry's), with files that
/// load fonts as it does or does not ([loadsFonts]) and that start a
/// binding as it does or does not ([startsABinding]); and the files that
/// cannot share ([whyAlone], [kRunsAlone]) as they are. [reversed] runs
/// each entry's files the other way round — the census's second order.
({List<List<String>> bundles, List<String> alone}) bundlesOf(
  List<String> files, {
  required String Function(String path) read,
  bool reversed = false,
}) {
  final sources = <String, String>{};
  String readOnce(String path) => sources[path] ??= read(path);
  final alone = <String>[];
  final alike = <String, List<String>>{};
  for (final file in files) {
    final source = readOnce(file);
    if (kRunsAlone.containsKey(file) || whyAlone(source) != null) {
      alone.add(file);
    } else {
      final kind = [
        ...libraryAnnotations(source),
        if (loadsFonts(file, read: readOnce)) 'loads fonts',
        if (startsABinding(file, read: readOnce)) 'starts a binding',
      ];
      (alike[kind.join('\n')] ??= []).add(file);
    }
  }
  return (
    bundles: [
      for (final shared in alike.values)
        for (final bundle in _dealt(shared))
          [if (reversed) ...bundle.reversed else ...bundle],
    ],
    alone: alone,
  );
}

/// [files] dealt in turn into as few entries of [kFilesPerBundle] as hold
/// them.
List<List<String>> _dealt(List<String> files) {
  final count = (files.length / kFilesPerBundle).ceil();
  final bundles = [for (var i = 0; i < count; i++) <String>[]];
  for (var i = 0; i < files.length; i++) {
    bundles[i % count].add(files[i]);
  }
  return bundles;
}

/// The source of an entry that runs [files] — paths from the checkout's
/// root, of one set of library annotations ([bundlesOf]) — each as a group
/// named by its path, from a folder [toRoot] below the root. [read] gives
/// each file's source; its annotations are the entry's.
///
/// 🪦THE ENTRY'S, NOT THE GROUP'S (census 11-20): under flutter_test a
/// group takes a skip and a retry and nothing else (`test_compat.dart`).
/// Each group was handed its file's time limit and platform, and 74
/// entries did not compile — their files ran alone, and were read as
/// having lost their isolation.
///
/// 🎯EACH FILE STARTS FROM WHAT A FILE ALONE STARTS FROM (card
/// bundled-files-read-timeline-values-left-behind, 2026-11-23): its group
/// sets it again — `startATestFile` in test/flutter_test_config.dart, the
/// code `testExecutable` sets it with — before its first test. The config
/// wraps an entry once, and each file after the first had started from
/// what the one before it left.
String entrySource(
  List<String> files,
  String Function(String path) read, {
  required String toRoot,
}) {
  final source = StringBuffer()
    ..writeln('// Written by tool/affected_tests.dart for one batch, and '
        'gone when it ends.');
  final annotations = files.isEmpty
      ? const <String>[]
      : libraryAnnotations(read(files.first));
  if (annotations.isNotEmpty) {
    source
      ..writeAll(annotations, '\n')
      ..writeln()
      ..writeln('library;');
  }
  source
    ..writeln("import 'package:flutter_test/flutter_test.dart';")
    ..writeln("import '$toRoot/test/flutter_test_config.dart' "
        'show startATestFile;');
  for (var i = 0; i < files.length; i++) {
    source.writeln("import '$toRoot/${files[i]}' as f$i;");
  }
  source.writeln('void main() {');
  for (var i = 0; i < files.length; i++) {
    source
      ..writeln("  group('${files[i]}', () {")
      ..writeln('    setUpAll(startATestFile);')
      ..writeln('    f$i.main();')
      ..writeln('  });');
  }
  source.writeln('}');
  return source.toString();
}

/// Where [file] ran in [bundle] — the files of its entry, in the order they
/// ran ([entrySource]): its place, and the file that ran just before it.
///
/// 🔬WHAT THE CENSUS READS, SAID WHERE IT IS READ (2026-11-23, ⑮): a
/// ledger line names a file's place and the one before it, and the wide
/// run's log could not give either — a passed test prints no line, and the
/// batch's entries are gone as it ends — so the 12 files red there were
/// only named. Said beside each one that lost its isolation, one log is
/// the census.
String placeInBundle(String file, List<String> bundle) {
  final at = bundle.indexOf(file);
  if (at < 0) return 'not in its bundle';
  final place = '${at + 1}/${bundle.length} in its bundle';
  return at == 0 ? '$place, first' : '$place, after ${bundle[at - 1]}';
}

/// What each file of a bundled batch did, out of its report's [runs]
/// (`suiteRuns`) and the files each entry ran ([entries], by the entry's
/// path from the root). An entry's own run says what its files' groups
/// cannot: a red one — it failed to load, or its own tests failed — makes
/// every file of it red, to be run again alone; one that never ended leaves
/// what its files did unknown, but a red; a green one stands for a file
/// that declared no test, as a file of its own would.
List<SuiteRun> runsOfFiles(
  List<SuiteRun> runs,
  Map<String, List<String>> entries,
) {
  final byPath = {
    for (final run in runs)
      if (!isBundleEntry(run.path)) run.path: run,
  };
  for (final entry in runs.where((run) => isBundleEntry(run.path))) {
    for (final file in entries[entry.path] ?? const <String>[]) {
      final own = byPath[file];
      byPath[file] = switch (entry.green) {
        false => (path: file, ms: own?.ms, green: false),
        null => (
          path: file,
          ms: own?.ms,
          green: own?.green == false ? false : null,
        ),
        true => own ?? (path: file, ms: null, green: true),
      };
    }
  }
  return byPath.values.toList();
}

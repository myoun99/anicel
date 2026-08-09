// Generates .anicel project files holding N cuts, for the picture-cache
// SCALE probe.
//
// Why this exists: every memory measurement this program has taken was on an
// EMPTY project with ONE cut, and the two painters still recorded at scroll-
// CONTENT size rather than viewport size (`TimelineBeatLinesPainter`,
// `_StoryboardFrameLinesPainter`) are invisible at that scale — with one cut
// the content IS the viewport, so a content-sized display list and a
// viewport-sized one are the same rectangle. They only separate once the
// timeline is long. At the default 24 frames a cut, 1500 cuts is 36,000
// frames of content, which is where the question actually gets asked.
//
// Run with:
//   flutter test tool/cut_scale_project.dart \
//     --dart-define=CUTS=40,400,1500 --dart-define=OUT=C:/tmp/probe
//
// ⚠️ `flutter test`, NOT `dart run`. The standalone VM has no `dart:ui`, and
// the model chain reaches it (`Layer` → `BrushBlendMode` → `BlendMode`), so
// `dart run` dies at compile time on a file that has nothing to do with this
// tool. The test VM is the shortest way to get a `dart:ui` and a `main()` in
// the same place. Living under tool/ rather than test/ keeps it out of CI:
// a bare `flutter test` walks test/ only.
//
// The generation runs inside a `test()` so the exit code means something —
// each file is round-tripped through the archive reader before it is
// written, and a tool that always exits 79 ("No tests ran") is a tool whose
// failures nobody would notice.
//
// Then open each file, open the timeline, hold the pointer still for two
// seconds and read the `picture cache` and `RASTER p50` lines. Linear in the
// cut count means content-sized entries are real and windowing is worth
// writing; flat means the angle is closed.
//
// This is a dev tool only: it is not imported by lib/ or test/ runtime code
// and does not change runtime behavior.
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_cut_helpers.dart';
import 'package:anicel/src/controllers/default_layer_helpers.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/core/timeline/timeline_defaults.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';

/// Comma-separated cut counts, e.g. `--dart-define=CUTS=40,400,1500`.
const String _cutsDefine = String.fromEnvironment('CUTS');

/// Where the files land, e.g. `--dart-define=OUT=C:/tmp/probe`. Defaults to
/// the working directory, which under `flutter test` is the package root.
const String _outDefine = String.fromEnvironment('OUT');

void main() {
  test('writes one .anicel per requested cut count', () {
    final counts = <int>[];
    for (final field in _cutsDefine.split(',')) {
      final text = field.trim();
      if (text.isEmpty) {
        continue;
      }
      final count = int.tryParse(text);
      expect(
        count,
        isNotNull,
        reason: 'Not a cut count: "$text". Expected a positive integer.',
      );
      expect(count, greaterThan(0), reason: 'Cut counts start at 1.');
      counts.add(count!);
    }

    expect(
      counts,
      isNotEmpty,
      reason:
          'Usage: flutter test tool/cut_scale_project.dart '
          '--dart-define=CUTS=40,400,1500 [--dart-define=OUT=<dir>]',
    );

    final directory = Directory(
      _outDefine.isEmpty ? Directory.current.path : _outDefine,
    );
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    for (final count in counts) {
      final path = _write(count: count, directory: directory);
      final frames = count * defaultCutDurationFrames;
      print(
        '${path.padRight(52)}  $count cuts  '
        '$frames frames  '
        '${(File(path).lengthSync() / 1024).toStringAsFixed(1)} KB',
      );
    }
  });
}

String _write({required int count, required Directory directory}) {
  // The default project is the fixture: one track carrying the SE rows that
  // every timeline draws, and its own transform track. Only the cut LIST
  // changes, so anything the probe measures is the cut count and nothing
  // else about how the file was built.
  final base = createDefaultProject(createdAt: DateTime.utc(2026, 1, 1));
  final track = base.tracks.single;

  final cuts = <Cut>[
    for (var i = 1; i <= count; i++)
      createDefaultCut(
        cutId: CutId('cut-$i'),
        // Bare numbers, the sheet convention — displays add no prefix.
        name: '$i',
        // Distinct per cut: two cuts sharing a layer id is a state the app
        // never produces, and a probe fixture that produces it would be
        // measuring a bug rather than the timeline's length.
        layerId: defaultLayerIdForSequence(i),
      ),
  ];

  final project = base.copyWith(
    name: 'Cut scale $count',
    tracks: [track.copyWith(cuts: cuts)],
  );

  final bytes = buildAnicelArchiveBytes(project: project, cels: const []);

  // Round-trip BEFORE writing. Handing over a file that does not open would
  // cost a whole measurement session to discover, and the check is one call.
  // Asserting the cut count rather than "it parsed" is the anti-vacuity
  // half: an archive that read back with one cut would parse just fine and
  // measure nothing.
  final reopened = parseAnicelArchiveBytes(bytes).project;
  expect(
    reopened.tracks.single.cuts.length,
    count,
    reason: 'Round-trip lost cuts.',
  );

  final path =
      '${directory.path}${Platform.pathSeparator}'
      'cut-scale-$count$anicelProjectSuffix';
  File(path).writeAsBytesSync(bytes);
  return path;
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★**A REPORT THAT NAMES A PATH THAT IS GONE IS WORSE THAN NO REPORT.**
///
/// Preferences > System exists to make silent runtime choices visible. Until
/// 2026-09-01 it told anyone without the native core that audio import was on
/// an 「ffmpeg fallback」. There is no such path — the EXPORT-AUDIO round took
/// ffmpeg out of every audio path, and the only two places in `lib/` that
/// start a process are both video export. So the panel answered「something
/// still works」 for a subsystem that had stood down.
///
/// ⚠️**Source-scanning, and not by preference.** The lying branch is the one
/// taken when there is no engine, and a test cannot get there: a bogus
/// `debugQaEngineLibraryPathOverride` falls THROUGH to the platform defaults
/// by design, so on any machine that has an engine the absent branch is
/// unreachable. Calling `collectRuntimePathReport()` would assert the branch
/// that was never wrong.
///
/// The law it pins is one line: **in that file, ffmpeg is a video-export
/// word.** If a real audio fallback is ever built, this test is the place
/// that says so out loud.
void main() {
  test('the runtime path report mentions ffmpeg only for video export', () {
    final source = File(
      'lib/src/services/runtime_path_report.dart',
    ).readAsStringSync();

    // ⚠️Blocks start at the `// ---` banner, NOT at `subsystem:`. The first
    // draft cut at `subsystem:` and immediately failed on 「Audio engine」,
    // which does not contain the word at all — an entry's LEADING comment
    // belongs to it, and cutting late hands every comment to the entry
    // above. The instrument was wrong before the code was.
    final starts = RegExp(
      r'^\s*// --- ',
      multiLine: true,
    ).allMatches(source).map((m) => m.start).toList();
    expect(
      starts,
      isNotEmpty,
      reason: 'the `// ---` banners are gone — this test reads the entries by '
          'them and has just stopped checking anything',
    );

    for (var index = 0; index < starts.length; index += 1) {
      final end =
          index + 1 < starts.length ? starts[index + 1] : source.length;
      // ⛔COMMENTS DO NOT COUNT — only what the panel prints. The entry that
      // stopped naming ffmpeg carries a tombstone saying it used to, and
      // this repo never deletes those. A law that cannot tell an explanation
      // from a claim would force the explanation out.
      final block = source
          .substring(starts[index], end)
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      if (!block.toLowerCase().contains('ffmpeg')) {
        continue;
      }
      final named = RegExp("subsystem: '([^']+)'").firstMatch(block);
      expect(
        named?.group(1),
        'Video export encoder',
        reason:
            'the ${named?.group(1) ?? '(unnamed)'} entry names ffmpeg. Video '
            'export is the only subsystem that still has an ffmpeg path — if '
            'this is not that one, the panel is describing a fallback that '
            'was removed, which reads to the user as "something still works"',
      );
    }
  });

  test('nothing in lib starts an ffmpeg process outside video export', () {
    // The other half of the same law: the report above is only true while
    // this is. ⛔A new ffmpeg caller elsewhere is not forbidden — it just has
    // to be a deliberate decision, and this is where it gets noticed.
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final text = entity.readAsStringSync();
      if (!text.contains('Process.run') && !text.contains('Process.start')) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      if (name == 'export_format_availability.dart' ||
          name == 'video_export_service.dart') {
        continue;
      }
      offenders.add(entity.path);
    }
    expect(
      offenders,
      isEmpty,
      reason: 'a new process launcher appeared. If it is an ffmpeg path, the '
          'report above has to learn about it; if it is something else, add '
          'it here with a word about what it runs',
    );
  });
}

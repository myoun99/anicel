@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

import '../../tool/affected_tests.dart'
    show
        BatchKind,
        carriesTag,
        gcTag,
        gcTagMarker,
        partitionByTag,
        realtimeTag,
        realtimeTagMarker,
        runInBatches;

/// ⏱️**A PIN THAT READS A RUNNING DEVICE ON TIME CANNOT RUN IN COMPANY**
/// (transport-real-time-pins-fail-under-load ⓑ, 2026-11-05).
///
/// A null device is a thread that plays on whatever its reader does, and
/// the lap pin must read it inside a step of its wrap. Pacing the waits by
/// what the device handed mended every wait (10-17, ⓐ); a starved reader
/// still reads late. The Mac and TestFlight builds 1089 read no wrap step
/// in twelve laps inside a parity batch of 161 files at 10 suites, and went
/// green alone in the same job — so each such file runs as a batch of one.
///
/// ⚠️This file never writes a marker out whole: a file that holds one IS
/// such a file, to the split here and to CI's.
void main() {
  Map<BatchKind, List<String>> split(Map<String, String> tree) =>
      partitionByTag(tree.keys.toList(), (path) => tree[path]!);

  test('a file carrying the marker goes to the real-time pins — and one '
      'that also waits for the collector goes there too: alone is out of '
      'the pins\' company as well', () {
    final kinds = split({
      'a_test.dart': 'void main() {}',
      'b_test.dart': '$realtimeTagMarker\nlibrary;\nvoid main() {}',
      'c_test.dart': "@Tags(['$gcTag', '$realtimeTag'])\nlibrary;",
      'd_test.dart': '$gcTagMarker\nlibrary;',
    });
    expect(kinds[BatchKind.crowd], ['a_test.dart']);
    expect(kinds[BatchKind.realtime], ['b_test.dart', 'c_test.dart']);
    expect(kinds[BatchKind.collector], ['d_test.dart']);
  });

  test('🚨each real-time pin runs as a batch of its own, after the crowd and '
      'before the collector\'s pins — another real-time pin beside it is '
      'company too', () async {
    const tree = {
      'a_test.dart': '',
      'b_test.dart': '$realtimeTagMarker\n',
      'c_test.dart': '$gcTagMarker\n',
      'd_test.dart': '$realtimeTagMarker\n',
      'e_test.dart': '',
    };
    final ran = <(String, BatchKind)>[];
    final asked = <List<String>>[];
    await runInBatches(
      tree.keys.toList(),
      known: const {},
      inTheLine: true,
      read: (path) => tree[path]!,
      take: (left) async {
        asked.add(left);
        return 5;
      },
      run: (batch, suites, {required kind}) async =>
          ran.add((batch.join(' '), kind)),
    );
    expect(ran, [
      ('a_test.dart e_test.dart', BatchKind.crowd),
      ('b_test.dart', BatchKind.realtime),
      ('d_test.dart', BatchKind.realtime),
      ('c_test.dart', BatchKind.collector),
    ]);
    expect(
      asked,
      [
        ['a_test.dart', 'e_test.dart'],
        ['b_test.dart'],
        ['d_test.dart'],
        ['c_test.dart'],
      ],
      reason: 'each real-time pin stands in the line for itself alone',
    );
  });

  test('the tag the pins carry is one the suite declares', () {
    expect(
      File('dart_test.yaml').readAsStringSync(),
      contains('\n  $realtimeTag:'),
      reason: "a file's @Tags names a tag; one dart_test.yaml does not "
          'declare is a warning in every run that loads the file',
    );
  });

  test('🚨THE LEDGER: these are the files that read a running device on '
      'time', () {
    final root = Directory.current.path;
    final tagged = <String>[];
    for (final entity in dartFilesUnder('$root/test')) {
      if (!entity.path.endsWith('_test.dart')) continue;
      if (!carriesTag(entity.readAsStringSync(), realtimeTag)) continue;
      tagged.add(
        entity.path.substring(root.length + 1).replaceAll(r'\', '/'),
      );
    }
    expectSetMatchesLedger(
      tagged,
      const [
        // The lap pin and the play-once pin (2026-11-05, builds 1089).
        'test/ui/playback/audio_device_transport_test.dart',
      ],
      unledgered:
          'Adding the tag takes a file OUT of the main run and runs it alone '
          '— cheap to do by accident, dear in time and invisible afterwards. '
          'It is for a pin whose reader must keep up with a running device; '
          'a wait on what a device does is paced by the device '
          '(test/helpers/device_paced.dart), not moved. If this list grew on '
          'purpose, say so here.',
      paidOff:
          'These no longer carry the tag (or are gone) and run in the crowd '
          'again — take them off the list here.',
    );
  });
}

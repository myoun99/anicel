import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';

/// 🚨**A TEST WAITS FOR THE TILE STORE TO GO IDLE IN ONE PLACE** —
/// `test/ui/timeline/tile_store_idle.dart` (board
/// `the-tile-store-drain-wait-is-written-four-times`, 2026-10-17).
///
/// Four files waited on the store's word (`debugBusy`) in a function of
/// their own — two alike to the letter, two that gave up a turn first and
/// failed in other words — and a fifth asked the word and never read the
/// answer, so a store that stayed busy passed it. Every copy passes on its
/// own, so the ratchet is a source scan: a wait (`pollUntil` ·
/// `settleAsync`) whose whole question is the word is one written by hand.
/// A wait that asks the word AND something more — the resize test's landing
/// and idle — asks another question, and stays its own.
void main() {
  const seat = 'test/ui/timeline/tile_store_idle.dart';
  const itself =
      'test/architecture/the_tile_store_is_waited_for_in_one_place_test.dart';

  /// A wait whose question is the store's word and nothing else: an arrow
  /// or a body that only says it.
  final handWait = RegExp(
    r'(?:pollUntil|settleAsync)\(\s*(?:\w+,\s*)?\(\)\s*'
    r'(?:=>\s*![\w.]+\.debugBusy\s*[,)]'
    r'|\{\s*return\s+![\w.]+\.debugBusy;\s*\})',
  );

  /// The lines in [source] where such a wait starts.
  List<int> handWaitsIn(String source) {
    final code = source.replaceAll(RegExp(r'//[^\n]*'), '');
    return [
      for (final wait in handWait.allMatches(code))
        '\n'.allMatches(code.substring(0, wait.start)).length + 1,
    ];
  }

  test('premise: the scan sees every form the waits took', () {
    // As the five stood on 2026-10-17, and the two other ways to say it.
    const forms = [
      'expect(\n'
          '  await pollUntil(() => !store.debugBusy),\n'
          '  isTrue,\n'
          "  reason: 'the store never went idle',\n"
          ');',
      'final idle = await pollUntil(\n'
          '  () => !store.debugBusy,\n'
          '  beat: const Duration(milliseconds: 5),\n'
          ');',
      'await pollUntil(() => !store.debugBusy);',
      'await settleAsync(\n'
          '  tester,\n'
          '  () => !TimelineGridTileStore.instance.debugBusy,\n'
          ');',
      'await pollUntil(() {\n  return !store.debugBusy;\n});',
    ];
    for (final form in forms) {
      expect(handWaitsIn(form), hasLength(1), reason: form);
    }
    const notOne = [
      // Another question: a landing and idle.
      'await settleAsync(tester, () {\n'
          '  final landed = shown.isNotEmpty;\n'
          '  return landed && !store.debugBusy;\n'
          '});',
      // A premise read, not a wait.
      "expect(store.debugBusy, isTrue, reason: 'cold');",
      // A wait for something else.
      'await pollUntil(() => out.isNotEmpty);',
    ];
    for (final line in notOne) {
      expect(handWaitsIn(line), isEmpty, reason: line);
    }
  });

  test('premise: the seat holds the one wait the scan forbids elsewhere', () {
    expect(handWaitsIn(File(seat).readAsStringSync()), hasLength(1));
  });

  test('no test waits on the tile store\'s word but through its seat', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('test')) {
      final path = file.path.replaceAll(r'\', '/');
      if (path.endsWith(seat) || path.endsWith(itself)) {
        continue;
      }
      final found = handWaitsIn(file.readAsStringSync());
      if (found.isNotEmpty) {
        offenders.add('$path:${found.join(',')}');
      }
    }
    expect(offenders, isEmpty, reason: 'await tileStoreIdle(store)');
  });
}

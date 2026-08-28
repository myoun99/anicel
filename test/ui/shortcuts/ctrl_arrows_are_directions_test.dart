import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show SingleActivator;
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';

/// **F-28 — Ctrl+ARROWS ARE DIRECTIONS; COMMA AND PERIOD ARE NOT.**
///
/// 유저 2026-08-27, Q2=2: 「축을 따라 뒤집고, 반대편에는 행 이동을 준다」 ⇒ on
/// an X-sheet Ctrl+↑↓ steps a frame and Ctrl+←→ steps a row; on the
/// horizontal timeline it is the arrangement it always was.
///
/// The plain arrows already did this. The Ctrl ones did not: they went
/// straight to `selectPreviousFrame`, so an X-sheet's Ctrl+← moved along a
/// direction the frames do not run in.
///
/// 🚨The split is the load-bearing part. Comma and period say "previous /
/// next frame" — a UNIT, not a direction — so they must keep stepping
/// frames whatever the sheet reads. Putting them on the same action as the
/// arrows is what would quietly turn them into row moves.
///
/// The axis question itself is guarded elsewhere
/// (`the_frame_axis_is_asked_in_one_place_test`); this pins the two links
/// on either side of it — which key reaches which action, and which
/// direction that action walks.
void main() {
  EditorActionDefinition definitionFor(String id) =>
      editorActionDefinitions.firstWhere((d) => d.id == id);

  Set<LogicalKeyboardKey> triggersOf(String id) => {
    for (final a in definitionFor(id).defaultActivators)
      if (a is SingleActivator) a.trigger,
  };

  test('each Ctrl+arrow has its own action, and no other key rides along', () {
    final byKey = <LogicalKeyboardKey, String>{
      LogicalKeyboardKey.arrowLeft: EditorActionIds.frameWalkLeft,
      LogicalKeyboardKey.arrowRight: EditorActionIds.frameWalkRight,
      LogicalKeyboardKey.arrowUp: EditorActionIds.frameWalkUp,
      LogicalKeyboardKey.arrowDown: EditorActionIds.frameWalkDown,
    };
    byKey.forEach((key, id) {
      final activators = definitionFor(id).defaultActivators;
      expect(
        activators.length,
        1,
        reason: '$id is one key; a second one here would be a unit sharing '
            'a direction\'s action, which is the bug F-28 split apart',
      );
      final only = activators.single as SingleActivator;
      expect(only.trigger, key);
      expect(only.control, isTrue, reason: 'the plain arrow is a nudge');
    });
  });

  test('comma and period keep the axis-blind frame step', () {
    expect(triggersOf(EditorActionIds.framePrevious), {
      LogicalKeyboardKey.comma,
    });
    expect(triggersOf(EditorActionIds.frameNext), {
      LogicalKeyboardKey.period,
    });
  });

  test('each direction action walks the axis its key points along', () {
    // Source-scanned, because the walker is private and the mapping is the
    // whole fix: a swapped pair compiles, passes every behaviour test that
    // does not drive an X-sheet, and is wrong on exactly the surface the
    // report came from.
    final source = File('lib/src/ui/home_page.dart').readAsStringSync();
    const expected = <String, String>{
      'frameWalkLeft': 'horizontal: true, forward: false',
      'frameWalkRight': 'horizontal: true, forward: true',
      'frameWalkUp': 'horizontal: false, forward: false',
      'frameWalkDown': 'horizontal: false, forward: true',
    };
    expected.forEach((action, walk) {
      final at = source.indexOf('EditorActionIds.$action:');
      expect(at, isNot(-1), reason: '$action lost its case arm');
      final arm = source.substring(at, at + 200);
      expect(
        arm.contains('_walkTimeline($walk, byFrame: true)'),
        isTrue,
        reason:
            '$action must walk `$walk` with a FRAME-sized step. Anything '
            'else and Ctrl+arrows disagree with the plain arrows about '
            'which way the frames run.',
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/lane_script.dart';

/// bash reads a script LAZILY: a `land` that changes `tool/lane.sh` swaps
/// the file out from under the interpreter in its `merge --ff-only`, and
/// whatever bash reads after that comes out of the NEW file, from a byte
/// offset that means nothing there. Until 2026-10-09 a sentence at the head
/// of the script said to land such a lane through a copy, and that day a
/// session landed one without it.
///
/// A command is read whole before it runs. The dispatch is therefore ONE
/// command that ends in `exit`, and nothing comes after it: once a land has
/// begun, bash has nothing left to read. 🧪Measured on this machine that
/// day with a script rewritten in place while it ran: the old shape — a
/// bare `case` as the last command — read on into the new file and failed
/// on a line torn in half; this shape read nothing more.
void main() {
  test('🚨the dispatch is one command that ends in `exit`, and it is the '
      'last thing in the script', () {
    final text = LaneScript(File('tool/lane.sh').readAsStringSync())
        .text
        .trimRight();
    final opens = RegExp(r'^\{ case "\$\{1:-\}" in$', multiLine: true)
        .allMatches(text)
        .toList();
    expect(opens, hasLength(1), reason: 'one dispatch, opened as a group');
    final dispatch = text.substring(opens.single.start);
    expect(dispatch, endsWith('\nesac; exit; }'));
    expect(
      RegExp(r'^esac', multiLine: true).allMatches(dispatch),
      hasLength(1),
      reason: 'the group closes on the one case it holds',
    );
    expect(
      dispatch,
      contains(r'land) shift; cmd_land "$@" ;;'),
      reason: 'LIVENESS — the land is dispatched from inside it',
    );
  });
}

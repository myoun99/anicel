import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';
import 'package:anicel/src/ui/sheet/paper_editing.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_key_funnel.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_bindings.dart';
import 'package:anicel/src/ui/timesheet/timesheet_ink_controller.dart';

/// What the workspace hands a window that edits the sheets' papers
/// (I-127) — their ink over [session]'s stores, their switches (off) and the
/// tool in hand — let go when the test ends.
PaperEditing paperEditingKit(EditorSessionManager session) {
  final caches = session.renderCaches;
  final tool = ValueNotifier<BrushToolState>(BrushToolState.defaults);
  final timesheetInk = TimesheetInkController(store: caches.timesheetInkStore);
  final envelopeInk = CutEnvelopeInkController(store: caches.envelopeInkStore);
  final timesheetAllowed = ValueNotifier(false);
  final envelopeAllowed = ValueNotifier(false);
  final repaint = ChangeNotifier();
  addTearDown(() {
    tool.dispose();
    timesheetInk.dispose();
    envelopeInk.dispose();
    timesheetAllowed.dispose();
    envelopeAllowed.dispose();
    repaint.dispose();
  });
  return (
    tool: tool,
    timesheetInk: timesheetInk,
    timesheetBrushAllowed: timesheetAllowed,
    envelopeInk: envelopeInk,
    envelopeBrushAllowed: envelopeAllowed,
    imageFor: (path, {width}) => null,
    imageRepaint: repaint,
  );
}

/// The shell's key road as a test lays it: the editor's bindings, the
/// actions that came down it, in order — an undo and a redo taken as the
/// shell takes them, on [session] — and every key the held keys were asked
/// about.
({EditorKeyRoad road, List<String> invoked, List<KeyEvent> held})
recordingKeyRoad(EditorSessionManager session) {
  final bindings = EditorShortcutBindings();
  addTearDown(bindings.dispose);
  final invoked = <String>[];
  final held = <KeyEvent>[];
  return (
    road: (
      bindings: bindings,
      onHoldKey: (event) {
        held.add(event);
        return KeyEventResult.ignored;
      },
      invoke: (actionId) {
        invoked.add(actionId);
        switch (actionId) {
          case EditorActionIds.undo:
            session.undo();
          case EditorActionIds.redo:
            session.redo();
        }
      },
    ),
    invoked: invoked,
    held: held,
  );
}

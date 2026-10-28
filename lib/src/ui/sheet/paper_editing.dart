import 'package:flutter/foundation.dart';

import '../brush/brush_tool_state.dart';
import '../envelope/cut_envelope_ink.dart';
import '../timesheet/timesheet_ink_controller.dart';
import 'sheet_image_cache.dart' show SheetImageLookup;

/// WHAT A PAPER IS EDITED WITH — the workspace's own, handed to a window
/// that edits the papers its panels edit (I-127, 유저 2026-10-25: 「동일하게
/// 선택중인 도구로 편집하는느낌」): the tool in hand, each sheet's ink and
/// brush switch, and the pictures the photos and logos are drawn from.
///
/// The panels' own controllers and switches, so a page edited in the window
/// is the page the panel shows, and its switch the panel's.
typedef PaperEditing = ({
  ValueListenable<BrushToolState> tool,
  TimesheetInkController timesheetInk,
  ValueNotifier<bool> timesheetBrushAllowed,
  CutEnvelopeInkController envelopeInk,
  ValueNotifier<bool> envelopeBrushAllowed,
  SheetImageLookup imageFor,
  Listenable imageRepaint,
});

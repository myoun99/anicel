// PANEL-SCOPED finders (R26 #31).
//
// The default workspace docks the TIMESHEET open on the right, and the
// sheet is not a picture of a canvas — it mounts real
// InteractiveBrushEditCanvasViews (its ink planes) inside a real
// BrushCanvasPanel shell (its paper viewport, panbars and bottom bar).
// So an app-wide `find.byType(InteractiveBrushEditCanvasView)` matches
// twice and blows up with `Bad state: Too many elements`, and a bare
// `find.byKey('canvas-viewport-zoom-label')` finds the sheet's zoom, not
// the drawing canvas's.
//
// The answer is to name the panel, not to hide the sheet: a test that
// means "the drawing canvas" says so. Reach for these whenever a finder
// targets something a panel OWNS rather than something the app has
// exactly one of.

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// The drawing canvas panel (the editor's center dock).
Finder mainCanvasPanel() => find.byType(MainCanvasBrushHost);

/// The timesheet panel (the right dock by default).
Finder timesheetPanel() => find.byType(TimesheetTabHost);

/// [matching], restricted to the drawing canvas panel.
Finder inMainCanvas(Finder matching) =>
    find.descendant(of: mainCanvasPanel(), matching: matching);

/// [matching], restricted to the timesheet panel.
Finder inTimesheet(Finder matching) =>
    find.descendant(of: timesheetPanel(), matching: matching);

/// The drawing canvas's interactive view — the one a stroke goes into.
Finder mainCanvasView() =>
    inMainCanvas(find.byType(InteractiveBrushEditCanvasView));

/// The drawing canvas's panel shell (its status strip, panbars and the
/// bottom bar's zoom/rotate controls all live under here).
Finder mainCanvasPanelShell() => inMainCanvas(find.byType(BrushCanvasPanel));

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/services/canvas_flood_fill.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/brush/tool_settings_panel.dart';
import 'package:anicel/src/ui/brush/tool_settings_section.dart';

/// EVERY TOOL'S SETTINGS SECTION NAMES ITSELF — all of them, not the ones
/// somebody happened to write a test for.
///
/// 🚨The panel switches on the ACTIVE tool, so "which tool am I looking at"
/// is the one question every arm has to answer, and the key is the answer a
/// test can read. Before this sweep, four of the eleven arms were reachable
/// only through a test written for something else, and one (`cut-stamp` with
/// no slot) rendered nothing at all — findable only because someone had
/// remembered to hang the key on the empty box.
///
/// ⚠️THE LEDGER IS THE POINT. A new tool arrives as one more `case` and the
/// panel compiles happily without a section; this map is what makes it stop.
/// Two arms deliberately answer with keys of their own rather than the
/// shell's, and they are the two whose settings are a whole panel elsewhere:
/// the brush (its own framed panel, shared with the eraser) and the guides.
const Map<CanvasTool, String> _sectionKeys = <CanvasTool, String>{
  CanvasTool.brush: 'brush-settings-panel',
  CanvasTool.eraser: 'brush-settings-panel',
  CanvasTool.eyedropper: 'tool-settings-eyedropper',
  CanvasTool.fill: 'tool-settings-fill',
  CanvasTool.fillShape: 'tool-settings-fill-shape',
  CanvasTool.select: 'tool-settings-selection',
  CanvasTool.move: 'tool-settings-move',
  CanvasTool.guide: 'guide-settings-none',
  CanvasTool.cut: 'tool-settings-cut-grab',
  CanvasTool.cutStamp: 'tool-settings-cut-stamp',
};

void main() {
  Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

  test('the ledger covers every tool there is', () {
    expect(
      _sectionKeys.keys.toSet(),
      CanvasTool.values.toSet(),
      reason: 'a new tool must name its settings section here too',
    );
  });

  testWidgets('every tool renders a section that says which tool it is', (
    tester,
  ) async {
    for (final entry in _sectionKeys.entries) {
      await tester.pumpWidget(
        app(
          ToolSettingsPanel(
            state: BrushToolState.defaults.copyWith(tool: entry.key),
            onChanged: (_) {},
            fillOptions: const FloodFillOptions(),
            onFillOptionsChanged: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(ValueKey<String>(entry.value)),
        findsOneWidget,
        reason: '${entry.key} shows no section keyed "${entry.value}"',
      );
    }
  });

  testWidgets('the shell keys the section it is told to key', (tester) async {
    // The shell's own contract, so the sweep above is reading a name the
    // shell really mints rather than one the sections still spell by hand.
    await tester.pumpWidget(
      app(
        const ToolSettingsSection(
          tool: 'a-made-up-tool',
          title: 'Heading',
          children: <Widget>[Text('row')],
        ),
      ),
    );

    expect(
      find.byKey(ToolSettingsSection.keyFor('a-made-up-tool')),
      findsOneWidget,
    );
    expect(find.text('Heading'), findsOneWidget);
    expect(find.text('row'), findsOneWidget);

    // ⛔The heading is a STYLE, not a layout: the shell must not slip its
    // own gap between the heading and the first row, because the sections
    // do not agree on what belongs there — the shape fill puts its polygon
    // confirm between the two. A shell that owned the gap would have moved
    // every section by eight pixels to look tidier in one file.
    expect(
      tester.getTopLeft(find.text('row')).dy,
      tester.getBottomLeft(find.text('Heading')).dy,
      reason: 'the shell inserted a gap of its own under the heading',
    );
  });
}

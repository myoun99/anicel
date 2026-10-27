import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/timeline_command_bar.dart';

import '../../helpers/frame_census.dart';

/// I-57 (10-14): a notify that changed nothing on a frame panel's command
/// bar laid it out and painted it again — the host hands the bar a toolbar
/// made anew on every notify, and the bar built its seat in a build scope
/// of its own. The bar has none: the seat is built in the host's, and the
/// toolbar's gate hands back the buttons it had.
///
/// 🔬F-463 (10-27) took the bar's counter, whose layer this was, and the
/// layer with it — and the timeline's bar was painted with its host's layer
/// on a notify. The bar keeps a layer of its own for that.
void main() {
  EditorSessionManager sessionOf(WidgetTester tester) =>
      tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;

  /// The app with the storyboard's panel showing when [storyboard] is.
  Future<void> pumpApp(WidgetTester tester, {required bool storyboard}) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    if (storyboard) {
      await tester.tap(
        find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
      );
      await tester.pumpAndSettle();
    }
  }

  /// The bar's own layer: the first repaint boundary under it.
  RenderObject layerOf(RenderObject bar) {
    var node = bar;
    while (!node.isRepaintBoundary) {
      late RenderObject child;
      node.visitChildren((only) => child = only);
      node = child;
    }
    return node;
  }

  for (final panel in ['timeline', 'storyboard']) {
    testWidgets('a notify that changes nothing lays out and paints none of '
        'the $panel\'s command bar', (tester) async {
      await pumpApp(tester, storyboard: panel == 'storyboard');
      final bar = layerOf(
        tester.renderObject(
          find.descendant(
            of: find.byKey(ValueKey<String>('panel-content-$panel')),
            matching: find.byType(TimelineCommandBar),
          ),
        ),
      );

      final frame = await frameCensus(tester, sessionOf(tester).notifyChanged);

      expect(
        frame.rebuilt,
        contains(TimelineCommandBar),
        reason: 'premise: the host built its bar again',
      );
      expect(
        paintedInside(frame.painted, bar),
        isFalse,
        reason: '↩️the bar built its toolbar\'s seat in a scope of its own, '
            'and was laid out and painted for it — 24 render objects',
      );
    });
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_horizontal_scrollbar_rail.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline/timeline_vertical_scrollbar_rail.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/timeline_host.dart';

/// A page turn — the playhead crossing the frame window's bucket while it
/// plays — repaints what follows the bucket, each on its own layer, and
/// leaves the rows' layers as they were
/// (playback-page-turn-repaints-the-whole-timeline (나), 10-11).
///
/// 🔬The row's edit chrome follows the bucket and had no layer of its own,
/// so every crossing re-recorded every row whole — 1,134 render objects
/// over 27 rows at 24 layers, the gesture layers and overlays with them.
void main() {
  for (final orientation in TimelineOrientation.values) {
    final sheet = orientation == TimelineOrientation.vertical;
    final prefix = sheet ? 'xsheet' : 'timeline';
    testWidgets('🚨a bucket crossing repaints the chrome on its own layer and '
        'leaves the row\'s layer alone — ${orientation.name}', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = EditorSessionManager(
        initialProject: createDefaultProject(),
      );
      session.repository.updateCutDuration(
        cutId: session.activeCutId!,
        duration: 200,
      );
      session.layerStack.addLayer();
      final layer = session.layers.first;
      session.selectLayer(layer.id);
      // Blocks for the chrome to stand on, across the window and past it.
      for (var frame = 0; frame < 200; frame += 4) {
        session.selectFrameIndex(frame);
        if (session.frameVerbs.canCreateDrawingAtCurrentFrame) {
          session.createDrawingAtCurrentFrame();
        }
      }
      session.selectFrameIndex(0);

      const cell = 24.0;
      await pumpTimelineHostOn(
        tester,
        session,
        surface: const Size(1200, 800),
        orientation: orientation,
        pixelsPerFrame: cell,
      );

      final controller = sheet
          ? tester
                .widget<TimelineVerticalScrollbarRail>(
                  find.byKey(
                    const ValueKey<String>('xsheet-vertical-scrollbar'),
                  ),
                )
                .controller
          : tester
                .widget<TimelineHorizontalScrollbarRail>(
                  find.byType(TimelineHorizontalScrollbarRail).first,
                )
                .controller;

      // The row's own layer: the first boundary down its box.
      var rowLayer = tester.renderObject(
        sheet
            ? find.named('xsheet-column-${layer.id}-cells')
            : find.named('timeline-row-${layer.id}-cells'),
      );
      while (!rowLayer.isRepaintBoundary) {
        RenderObject? first;
        rowLayer.visitChildren((child) => first ??= child);
        rowLayer = first!;
      }
      final chrome = tester.renderObject(
        find.named('$prefix-edit-chrome-${layer.id}'),
      );

      RenderObject? layerOf(RenderObject painted) {
        for (var at = painted.parent; at != null; at = at.parent) {
          if (at.isRepaintBoundary) {
            return at;
          }
        }
        return null;
      }

      bool under(RenderObject painted, RenderObject root) {
        for (RenderObject? at = painted; at != null; at = at.parent) {
          if (identical(at, root)) {
            return true;
          }
        }
        return false;
      }

      var rowLayerPaints = 0;
      var chromePaints = 0;
      debugOnProfilePaint = (painted) {
        if (identical(layerOf(painted), rowLayer)) {
          rowLayerPaints += 1;
        }
        if (under(painted, chrome)) {
          chromePaints += 1;
        }
      };
      try {
        // One bucket: four cells.
        controller.jumpTo(4 * cell);
        await tester.pump();
        controller.jumpTo(0);
        await tester.pump();
      } finally {
        // Unset inside the body: the binding checks its debug switches
        // before a tear-down would run.
        debugOnProfilePaint = null;
      }

      expect(
        chromePaints,
        greaterThanOrEqualTo(2),
        reason: 'fixture: each crossing repainted the chrome — it follows '
            'the bucket',
      );
      expect(
        rowLayerPaints,
        0,
        reason: '↩️the chrome had no layer of its own, and each crossing '
            're-recorded the row\'s whole layer with it',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      await tester.pumpAndSettle();
    });
  }
}

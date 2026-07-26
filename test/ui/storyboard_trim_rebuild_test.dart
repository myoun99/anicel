import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quick_animaker_v2/src/models/canvas_size.dart';
import 'package:quick_animaker_v2/src/models/cut.dart';
import 'package:quick_animaker_v2/src/models/cut_id.dart';
import 'package:quick_animaker_v2/src/models/layer.dart';
import 'package:quick_animaker_v2/src/models/layer_id.dart';
import 'package:quick_animaker_v2/src/models/layer_kind.dart';
import 'package:quick_animaker_v2/src/models/project.dart';
import 'package:quick_animaker_v2/src/models/project_id.dart';
import 'package:quick_animaker_v2/src/models/track.dart';
import 'package:quick_animaker_v2/src/models/track_id.dart';
import 'package:quick_animaker_v2/src/ui/storyboard_panel.dart';
import 'storyboard_cut_block_probe.dart';
import 'package:quick_animaker_v2/src/ui/timeline/timeline_drag_preview.dart';

/// R10-③: the storyboard consumes the drag-preview channel INTERNALLY —
/// a cut-trim step rebuilds the cut blocks but hands the SE rows (the
/// waveform-heavy subtrees) IDENTICAL widget instances, which Flutter
/// skips wholesale.
void main() {
  Cut cut(String id) => Cut(
    id: CutId(id),
    name: id,
    duration: 24,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: [
      Layer(
        id: LayerId('$id-cel'),
        name: 'A',
        frames: const [],
        timeline: const {},
      ),
    ],
  );

  Project twoCutProject() => Project(
    id: const ProjectId('project'),
    name: 'P',
    createdAt: DateTime.utc(2026, 7, 12),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [cut('cut-1'), cut('cut-2')],
        seLayers: [
          Layer(
            id: const LayerId('se-row-1'),
            name: 'S1',
            kind: LayerKind.se,
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
    ],
  );

  testWidgets('a trim preview step rebuilds blocks but not SE rows', (
    tester,
  ) async {
    final project = twoCutProject();
    final preview = ValueNotifier<TimelineDragPreview?>(null);
    addTearDown(preview.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: project,
            dragPreview: preview,
            activeCutId: const CutId('cut-1'),
          ),
        ),
      ),
    );
    await tester.pump();

    const seRowKey = ValueKey<String>('storyboard-se-row-0-1');
    final seRowBefore = tester.widget(
      find.byKey(seRowKey, skipOffstage: false),
    );
    final blockWidthBefore = requireCutBlock(tester, 'cut-1').rect.width;

    // One trim step through the channel — NO panel rebuild from above.
    preview.value = CutTrimDragPreview(
      previewDurations: {const CutId('cut-1'): 30},
    );
    await tester.pump();

    // The trimmed block followed the preview…
    expect(
      requireCutBlock(tester, 'cut-1').rect.width,
      isNot(blockWidthBefore),
    );
    // …while the SE row kept its exact widget identity (subtree skipped).
    expect(
      identical(
        tester.widget(find.byKey(seRowKey, skipOffstage: false)),
        seRowBefore,
      ),
      isTrue,
      reason: 'SE rows must not rebuild during cut trims',
    );

    // Clearing the preview restores the base layout.
    preview.value = null;
    await tester.pump();
    expect(requireCutBlock(tester, 'cut-1').rect.width, blockWidthBefore);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// The rail row memo's gate (frame-axis round): the row is ~200 Material
/// widgets and a timesheet edit changes nothing it renders, so the memo asks
/// what the row SHOWS instead of which Layer instance it came from.
///
/// The completeness contract lives on [timelineLayerControlsRowShowsSameState];
/// this drives one mutation per compared field so an entry cannot be dropped
/// silently, and pins the two behaviors that matter at the widget level.
void main() {
  final base = Layer(
    id: const LayerId('rail-memo-layer'),
    name: 'A',
    frames: const [],
    kind: LayerKind.animation,
  );

  group('display token', () {
    final mutations = <String, Layer Function(Layer)>{
      'name': (layer) => layer.copyWith(name: 'B'),
      'kind': (layer) => layer.copyWith(kind: LayerKind.se),
      'opacity': (layer) => layer.copyWith(opacity: layer.opacity / 2),
      'isVisible': (layer) => layer.copyWith(isVisible: !layer.isVisible),
      'muted': (layer) => layer.copyWith(muted: !layer.muted),
      'mark': (layer) => layer.copyWith(
        mark: layer.mark == LayerMark.none ? LayerMark.red : LayerMark.none,
      ),
      'onTimesheet': (layer) =>
          layer.copyWith(onTimesheet: !layer.onTimesheet),
      'blendMode': (layer) => layer.copyWith(
        blendMode: layer.blendMode == LayerBlendMode.normal
            ? LayerBlendMode.multiply
            : LayerBlendMode.normal,
      ),
      'collapsed': (layer) => layer.copyWith(collapsed: !layer.collapsed),
      'isFillReference': (layer) =>
          layer.copyWith(isFillReference: !layer.isFillReference),
      'attachedToLayerId': (layer) =>
          layer.copyWith(attachedToLayerId: const LayerId('other')),
      'attachedPlacement': (layer) => layer.copyWith(
        attachedPlacement: layer.attachedPlacement == AttachedPlacement.above
            ? AttachedPlacement.below
            : AttachedPlacement.above,
      ),
    };

    for (final entry in mutations.entries) {
      test('${entry.key} is a shown field — it must break the token', () {
        final mutated = entry.value(base);
        expect(
          timelineLayerControlsRowShowsSameState(base, mutated),
          isFalse,
          reason:
              'the rail row renders ${entry.key}; a memo that survives its '
              'change shows stale state',
        );
      });
    }

    test('the same instance always matches', () {
      expect(timelineLayerControlsRowShowsSameState(base, base), isTrue);
    });

    test('a fresh instance with identical shown fields matches', () {
      expect(
        timelineLayerControlsRowShowsSameState(base, base.copyWith()),
        isTrue,
        reason: 'copyWith hands back a NEW instance — that alone must not '
            'rebuild the row',
      );
    });
  });

  testWidgets('a timesheet edit does NOT rebuild the rail row, a rename does',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final session = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(session.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => TimelineTabHost(
              session: session,
              orientation: TimelineOrientation.horizontal,
              onOrientationChanged: (_) {},
              pixelsPerFrame: 24,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activeId = session.activeLayerId;
    TimelineLayerControlsRow rowFor(LayerId id) => tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .firstWhere((row) => row.layer.id == id);

    final before = rowFor(activeId!);

    // A drawing lands on the active layer: a full session notify, a new
    // Layer instance — and nothing the rail row renders.
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pump();
    expect(
      identical(rowFor(activeId), before),
      isTrue,
      reason: 'a timesheet edit changes no rail-visible field — the row must '
          'come back as the cached instance',
    );

    // A rename does change what it shows.
    session.renameLayer(activeId, 'renamed');
    await tester.pump();
    expect(
      identical(rowFor(activeId), before),
      isFalse,
      reason: 'a rename must refresh the rail row',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}

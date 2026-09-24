import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_mark.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show LayerMarkChip;
import 'package:anicel/src/ui/timeline/timeline_layer_controls_row.dart';
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/timeline_tab_host.dart';

/// The rail row memo's gate (frame-axis round): the row is ~200 Material
/// widgets and a timesheet edit changes nothing it renders, so the memo asks
/// what the row SHOWS instead of which Layer instance it came from.
///
/// The completeness contract lives on [ControlsRowFace];
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
      'muted': (layer) => layer.copyWith(muted: !layer.muted),
      'mark': (layer) => layer.copyWith(
        mark: layer.mark == LayerMark.none ? const LayerMark(process: LayerProcess.layout) : LayerMark.none,
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
          ControlsRowFace(base) == ControlsRowFace(mutated),
          isFalse,
          reason:
              'the rail row renders ${entry.key}; a memo that survives its '
              'change shows stale state',
        );
      });
    }

    test('🚨the EYE is not in the token — it rides RailEyes past the memo '
        '(an-eye-rebuilds-its-whole-row)', () {
      expect(
        ControlsRowFace(base) ==
            ControlsRowFace(base.copyWith(isVisible: !base.isVisible)),
        isTrue,
        reason: 'a solo flips most rows\' eyes at once, and with the eye in '
            'the token every one of those rows rebuilt all twelve slots — '
            '3,051 elements in one frame',
      );
    });

    test('the same instance always matches', () {
      expect(ControlsRowFace(base), ControlsRowFace(base));
    });

    test('a fresh instance with identical shown fields matches', () {
      expect(
        ControlsRowFace(base) == ControlsRowFace(base.copyWith()),
        isTrue,
        reason: 'copyWith hands back a NEW instance — that alone must not '
            'rebuild the row',
      );
    });
  });

  testWidgets('㉞ the ROW SELECTION invalidates the memo', (tester) async {
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

    final activeId = session.activeLayerId!;
    TimelineLayerControlsRow rowFor(LayerId id) => tester
        .widgetList<TimelineLayerControlsRow>(
          find.byType(TimelineLayerControlsRow),
        )
        .firstWhere((row) => row.layer.id == id);

    expect(rowFor(activeId).selected, isFalse);

    // ⑨'s select drag, at its first step. The wash is SESSION state — the
    // Layer never changes — so only the memo's own record can carry it.
    session.rowSelectionVerbs.beginRowSelection(LayerRowAddress(activeId));
    await tester.pump();

    expect(
      rowFor(activeId).selected,
      isTrue,
      reason:
          '㉞: the row selection must reach the rail. A memo that does not '
          'compare `selected` hands back the unselected row and the wash '
          'never appears — the state was right, the cache said "unchanged"',
    );
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
    session.layerVerbs.renameLayer(activeId, 'renamed');
    await tester.pump();
    expect(
      identical(rowFor(activeId), before),
      isFalse,
      reason: 'a rename must refresh the rail row',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });

  testWidgets('🚨an eye flip keeps the CACHED row, and the eye and the plate '
      'still show it (an-eye-rebuilds-its-whole-row)', (tester) async {
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

    final activeId = session.activeLayerId!;
    final rowFinder = find.byWidgetPredicate(
      (widget) =>
          widget is TimelineLayerControlsRow && widget.layer.id == activeId,
    );
    IconData? eyeGlyph() => tester
        .widget<Icon>(
          find.descendant(
            of: find.byKey(
              ValueKey<String>('timeline-layer-visibility-$activeId'),
            ),
            matching: find.byType(Icon),
          ),
        )
        .icon;
    bool plateLit() => tester
        .widget<LayerMarkChip>(
          find.descendant(of: rowFinder, matching: find.byType(LayerMarkChip)),
        )
        .isVisible;

    final before = tester.widget<TimelineLayerControlsRow>(rowFinder.first);
    expect(eyeGlyph(), Icons.visibility, reason: '⛔전제: the row shows');
    expect(plateLit(), isTrue);

    session.layerSwitches.toggleLayerVisibility(activeId);
    await tester.pump();

    expect(
      identical(
        tester.widget<TimelineLayerControlsRow>(rowFinder.first),
        before,
      ),
      isTrue,
      reason: 'the eye is the one thing that changed — the rest of the row '
          'must come back as the cached instance',
    );
    expect(eyeGlyph(), Icons.visibility_off, reason: 'the eye shows the flip');
    expect(
      plateLit(),
      isFalse,
      reason: 'and the plate dims with it (F-56) — a cached row that kept '
          'the old eye would show the layer as on',
    );
  });
}

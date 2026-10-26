import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId;

import '../../helpers/named_finders.dart';

/// 🗣️F-476 (유저 2026-10-26): 「지금 레이어에서 서있는상태로, fx선택범위
/// 작동할때, 보통 레이어 선택범위 작동할땐 그 레이어에 서고나서 선택범위
/// 적용되는데 지금 fx에는 서는게 안됨. 법 멋대로 만들어냈으니 통일」.
///
/// A lane's label picks on the PRESS, as the layer row's does (T10, 유저
/// 2026-08-14 「행이든 뭐든 동일하게」), and a press that turns out to be a
/// tap clears on the release (「클릭하고 떼면 뭐든 비우게」). ↩️It stood on
/// the release, which a sweep never reaches.
void main() {
  late EditorSessionManager session;
  late LaneRowAddress header;

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    // Room for the lanes under the row.
    await tester.drag(
      find.byKey(const ValueKey<String>('dock-resize-bottom')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final layer = session.activeLayer!;
    final twirl = find.named('timeline-lane-toggle-${layer.id}');
    await tester.ensureVisible(twirl);
    await tester.pumpAndSettle();
    await tester.tap(twirl);
    await tester.pumpAndSettle();
    session.effectsAndFx.addEffectToActiveLayer(EffectKind.blur);
    await tester.pumpAndSettle();
    header = LaneRowAddress(
      layer.id,
      effectGroupLaneId(session.activeLayer!.effects.single.id),
    );
    session.standOnRow(LayerRowAddress(layer.id));
    await tester.pumpAndSettle();
  }

  Finder labelOf(LaneRowAddress row) => find.byKey(
    ValueKey<String>('timeline-lane-stand-cell-${row.layerId}-${row.laneId}'),
  );

  testWidgets('the press on an fx header\'s label stands there, and a sweep '
      'from it keeps standing there while it selects', (tester) async {
    await open(tester);
    expect(session.currentRow, isNot(header), reason: '⛔전제');
    final label = labelOf(header);
    expect(label, findsOneWidget, reason: '⛔전제: the header is drawn');

    final gesture = await tester.startGesture(
      tester.getCenter(label),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(session.currentRow, header, reason: 'on the PRESS');

    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(session.currentRow, header);
    expect(
      session.rowSelectionVerbs.rowSelection.value,
      contains(header),
      reason: 'the sweep selected from where it stood',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('on the conte panel\'s rail too: the V row\'s fx header stands '
      'at the press, and a tap clears on the release', (tester) async {
    await open(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('timeline-mode-storyboard-button')),
    );
    await tester.pumpAndSettle();
    final track = session.repository.requireProject().tracks.first.id;
    session.effectsAndFx.addEffectToTrack(track, EffectKind.blur);
    await tester.pumpAndSettle();
    final fx = session.repository.requireProject().tracks.first.effects.single;
    final vHeader = LaneRowAddress(
      trackTransformLaneCarrierId(track),
      effectGroupLaneId(fx.id),
    );
    final label = find.byKey(
      ValueKey<String>(
        'storyboard-lane-stand-cell-${vHeader.layerId}-${vHeader.laneId}',
      ),
    );
    if (label.evaluate().isEmpty) {
      // The V row twirls once it carries an fx.
      final twirl = find.named('storyboard-track-lane-toggle-${track.value}');
      await tester.ensureVisible(twirl);
      await tester.pumpAndSettle();
      await tester.tap(twirl);
      await tester.pumpAndSettle();
    }
    expect(label, findsOneWidget, reason: '⛔전제: the header is drawn');
    session.rowSelectionVerbs.beginRowSelection(vHeader);
    session.rowSelectionVerbs.endRowSelection();
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(label),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(session.currentRow, vHeader, reason: 'on the PRESS');
    expect(session.rowSelectionVerbs.rowSelection.value, [vHeader]);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(session.rowSelectionVerbs.rowSelection.value, isEmpty);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a tap on it inside the selection holds it on the press and '
      'clears it on the release, as the layer row\'s does', (tester) async {
    await open(tester);
    session.rowSelectionVerbs.beginRowSelection(header);
    session.rowSelectionVerbs.endRowSelection();
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(labelOf(header)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(session.currentRow, header);
    expect(
      session.rowSelectionVerbs.rowSelection.value,
      [header],
      reason: 'a press inside the selection may be a move: it holds',
    );

    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      session.rowSelectionVerbs.rowSelection.value,
      isEmpty,
      reason: '「클릭하고 떼면 뭐든 비우게」',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });
}

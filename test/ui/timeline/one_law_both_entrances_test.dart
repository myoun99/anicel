import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// F-13 · F-28 — 유저 2026-08-27: 「플립이랑 화살표랑 **입구는 달라도 통하는건
/// 하나**니까 둘 다 적용해야하는거지」 · 「플립으로 레이어이동이든 화살표든
/// 레이어이동도 똑같이 해야지」.
///
/// The law itself is older (유저 2026-08-24): standing somewhere OUTSIDE the
/// live selection releases it, and a ruler scrub — which is seeking, not
/// moving — keeps it. It has a house: `standOnRow`.
///
/// The frame flip walks through that door. The ARROW-key layer step used to
/// call `selectLayer` instead, which is the same thing minus the law, so the
/// two entrances to "move to another row" disagreed.
void main() {
  /// A project whose drawing rows carry cels, so a frame range has something
  /// to be drawn across.
  Project projectWithCels() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    return base.copyWith(
      tracks: [
        track.copyWith(
          cuts: [
            cut.copyWith(
              layers: [
                for (final layer in cut.layers)
                  if (layer.frames.isEmpty)
                    layer.copyWith(
                      frames: [
                        for (var i = 0; i < 3; i++)
                          Frame(
                            id: FrameId('${layer.id.value}-cel-$i'),
                            duration: 1,
                            strokes: const [],
                          ),
                      ],
                      timeline: {
                        for (var i = 0; i < 3; i++)
                          i: TimelineExposure.drawing(
                            FrameId('${layer.id.value}-cel-$i'),
                            length: 1,
                          ),
                      },
                    )
                  else
                    layer,
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: projectWithCels())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  /// Selects a frame range on a drawing row and returns that row.
  Future<Layer> selectARange(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    final row = session.layers.firstWhere(
      (l) => layerAcceptsBrushInput(l) && l.frames.isNotEmpty,
    );
    session.selectLayer(row.id);
    // 🚨THE LAYER RANGE, not the frame range. 유저 2026-08-27: 「구체적으로
    // 적을게 **레이어 선택범위** 작동한것도 레이어이동같은거로 풀리게」.
    //
    // ⚠️Measured first: `selectLayer` already drops a FRAME range whose
    // layer changed, so a test written on that one goes green with this
    // round deleted — it did, and the mutation caught it.
    session.rowSelection.value = [
      for (final l in session.layers.take(2)) LayerRowAddress(l.id),
    ];
    await tester.pump();
    expect(
      session.rowSelection.value.length,
      greaterThan(1),
      reason: '🚨the fixture has to actually be holding a layer range, or '
          'every assertion below passes on an empty board',
    );
    return row;
  }

  testWidgets('the ARROW-key layer step releases the selection, the way the '
      'flip and a row click already do', (tester) async {
    final session = await pump(tester);
    await selectARange(tester, session);

    // The entrance itself: `EditorActionIds.layerDown` calls exactly this,
    // canvas selection or none (F-86).
    //
    // ⚠️NOT a synthetic arrow key — measured, one never arrives in this
    // harness (nothing holds focus), and a test that sent one would be
    // asserting about a keystroke that was never delivered. The key→action
    // binding is not what this round changed; what the action DOES is.
    final nav = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .layerNav;
    expect(nav, isNotNull, reason: 'the workspace owns the arrow channel');
    final rowBefore = session.activeLayerId;
    nav!.step(-1);
    await tester.pumpAndSettle();
    expect(
      session.activeLayerId,
      isNot(rowBefore),
      reason: '🚨the key has to have MOVED something — otherwise this test '
          'is measuring a keystroke that never arrived, which is how a '
          'guard goes green while the law it names is broken',
    );

    expect(
      session.rowSelection.value,
      isEmpty,
      reason: '유저: 「플립으로 레이어이동이든 화살표든 레이어이동도 똑같이 '
          '해야지」 — moving to another row is moving, whichever key did it',
    );
  });

  testWidgets('the FLIP entrance agrees — it always did, and that is the '
      'agreement being restored', (tester) async {
    final session = await pump(tester);
    await selectARange(tester, session);

    session.frameVerbs.flipRow(forward: true);
    await tester.pumpAndSettle();

    expect(session.rowSelection.value, isEmpty);
  });

  testWidgets('a ruler SCRUB still keeps it — seeking is not moving', (
    tester,
  ) async {
    final session = await pump(tester);
    await selectARange(tester, session);

    // ⛔The clear lives in the flip and NOT in `selectFrameIndex`, because
    // the ruler goes through that one too (유저 2026-08-24: 「룰러쪽 조작은
    // 지금처럼 그대로 취소안되도록」). A fix that moved the law down into the
    // seek would take this with it.
    session.frameScrub.scrubFrameIndex(2);
    await tester.pumpAndSettle();

    expect(
      session.rowSelection.value,
      isNotEmpty,
      reason: '유저: 「룰러 스크럽시 취소안되는건 그대로 남김」',
    );
  });
}

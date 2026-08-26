import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// 유저 2026-08-27, 실기: 「지금 아직도 캔버스에 반영안되고 블록도 반영안되는데」
/// + 「버튼 자체도 블록에 따라 활성화 비활성화 제대로 갱신 안되고있어」.
///
/// The pixel verbs landed with the LADDER pinned — which cel a press touches —
/// and nothing at all pinning whether the answer ever reaches the screen.
///
/// ⚠️Only ONE of these guards a fix. The tint test does: it goes red the
/// moment its listener is removed. The button test guards a law that already
/// holds — `bar_buttons_follow_the_playhead_test` enumerates the bar and pins
/// that every button answers DURING a scrub, but its assertion is that the
/// WHOLE map changed, which one stale button cannot break. This names these
/// two so that it can.
void main() {
  /// A project whose drawing rows have cels on frames 0-2 and NOTHING after,
  /// so stepping the playhead crosses a real 「그림 있음 → 없음」 edge.
  Project projectWithEarlyCels() {
    final base = createDefaultProject();
    final track = base.tracks.first;
    final cut = track.cuts.first;
    final drawn = [
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
    ];
    return base.copyWith(
      tracks: [
        track.copyWith(cuts: [cut.copyWith(layers: drawn)]),
      ],
    );
  }

  Future<EditorSessionManager> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: projectWithEarlyCels())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  /// Whether the button as MOUNTED is pressable. ⛔Not `canRunPixelVerb` —
  /// that getter was always right; a stale button means nobody re-read it, so
  /// asserting the getter asserts the half that cannot break.
  ///
  /// The key rides on the `IconButton` itself, the same handle
  /// `bar_buttons_follow_the_playhead_test` enumerates by.
  bool buttonEnabled(WidgetTester tester, String key) =>
      tester.widget<IconButton>(find.byKey(ValueKey<String>(key))).onPressed !=
      null;

  testWidgets(
    'the two pixel buttons answer DURING a scrub — the bar\'s own law, '
    'named for them',
    (tester) async {
      final session = await pump(tester);
      final row = session.layers.firstWhere(
        (l) => layerAcceptsBrushInput(l) && l.frames.isNotEmpty,
      );
      session.selectLayer(row.id);
      session.selectFrameIndex(0);
      await tester.pumpAndSettle();
      expect(
        buttonEnabled(tester, 'shared-replace-colour-button'),
        isTrue,
        reason: 'standing on a cel, so there is something to recolour',
      );

      // ⛔A SCRUB, not a committed seek, and no selection touched. A bar that
      // snaps on release 「was showing the wrong answer until then」 — that is
      // measured in the playhead file, nine of twenty-five buttons deep.
      session.scrubFrameIndex(8);
      await tester.pumpAndSettle();
      expect(
        buttonEnabled(tester, 'shared-replace-colour-button'),
        isFalse,
        reason: 'no drawing on this block — dim without anyone touching a '
            'selection',
      );
      expect(
        buttonEnabled(tester, 'shared-clear-pixels-button'),
        isFalse,
        reason: 'its twin reads the same gate',
      );

      // And back, so this cannot pass by simply never enabling.
      session.selectFrameIndex(0);
      await tester.pumpAndSettle();
      expect(buttonEnabled(tester, 'shared-replace-colour-button'), isTrue);
    },
  );

  testWidgets(
    'a pixel edit moves the block tint\'s revision — 유저: 「블록도 '
    '반영안되는데」',
    (tester) async {
      final session = await pump(tester);

      // 🚨The crossing detector the tint used to ride on asks whether the
      // store HOLDS a surface for the cel, not whether that surface has ink
      // in it — so 픽셀 비우기 leaves an all-transparent surface, `has ==
      // had`, and it never bumped. The block went on saying 「그려짐」 about a
      // cel with nothing in it. `celPixelRevision` is the signal that does
      // fire on every surface write.
      final before = session.celTintRevision.value;
      session.brushFrameStore.celPixelRevision.value += 1;
      await tester.pump();

      expect(
        session.celTintRevision.value,
        greaterThan(before),
        reason: 'the block cannot re-ask 「이 칸에 그림이 있나」 if its own '
            'revision never moves',
      );
    },
  );
}

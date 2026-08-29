import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';

/// 🚨★★★THE STORYBOARD RAIL SWIPES A COLUMN, LIKE THE TIMELINE RAIL DOES.
///
/// 유저 2026-08-29: 「스토리보드 행 순서 드래그가 일부러 가시성버튼 위에서
/// 시작? 무슨소리지? **타임라인이랑 왜 통일안한거지?**」
///
/// It was not unified because of a sentence that turned out to be invented —
/// the measurement is kept at `claimTapForControl`. With that gone the swipe
/// moved out of the layer grid's private state into [RailColumnSwipe], and
/// this rail wears it.
///
/// ⛔The band is the half that goes wrong silently. A column listed but
/// missed by its band is unreachable and nothing fails; the swipe simply
/// never starts. So the first case measures the band against the button it
/// is supposed to cover, before any case tries to use it.
void main() {
  Track track(String id, String name) => Track(
    id: TrackId(id),
    name: name,
    // SE rows on purpose: they stand BETWEEN two V rows, so a row resolver
    // counting in the V row's own height would name the wrong track. This
    // fixture is what reaches that defect.
    seLayers: [
      Layer(
        id: LayerId('$id-s1'),
        name: 'S1',
        kind: LayerKind.se,
        frames: const [],
        timeline: const {},
      ),
    ],
    cuts: [
      Cut(
        id: CutId('$id-cut'),
        name: '$name cut',
        duration: 12,
        canvasSize: const CanvasSize(width: 640, height: 360),
        layers: [
          Layer(
            id: LayerId('$id-cel'),
            name: 'A',
            frames: const [],
            timeline: const {},
          ),
        ],
      ),
    ],
  );

  EditorSessionManager threeTracks() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('swipe-project'),
      name: 'Swipe',
      createdAt: DateTime.utc(2026, 8, 29),
      tracks: [track('t1', 'One'), track('t2', 'Two'), track('t3', 'Three')],
    ),
  );

  Future<EditorSessionManager> pumpRail(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final session = threeTracks();
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: session,
            builder: (context, _) => StoryboardTabHost(
              session: session,
              pixelsPerFrame: 12,
              onPixelsPerFrameChanged: (_) {},
              showSeconds: false,
              onShowSecondsChanged: (_) {},
              thumbnailFor: null,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return session;
  }

  Finder eyeOf(String trackId) =>
      find.byKey(ValueKey<String>('storyboard-cut-visibility-$trackId-cut'));

  List<bool> pictureVisibility(EditorSessionManager session) => [
    for (final id in const ['t1-cut', 't2-cut', 't3-cut'])
      session.isCutPictureVisible(CutId(id)),
  ];

  /// The transition rows, the THIRD kind the rail stacks — one more eye on
  /// the same column, this one on the track's transition layer.
  List<bool> transitionVisibility(EditorSessionManager session) => [
    for (final track in session.repository.requireProject().tracks)
      track.transitionLayer.isVisible,
  ];

  /// The S rows the sweep CROSSES on its way down. They carry the SAME eye
  /// column, acting on the SE layer rather than a cut.
  List<bool> seVisibility(EditorSessionManager session) => [
    for (final track in session.repository.requireProject().tracks)
      track.seLayers.single.isVisible,
  ];

  testWidgets('🚨the swipe band COVERS the eye it is meant to paint', (
    tester,
  ) async {
    await pumpRail(tester);

    // The rail the swipe measures its bands inside — its own left edge is
    // the origin, which is the whole reason a band computed in row-local
    // numbers can miss.
    final rail = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-track-label-rail')),
    );
    final eye = tester.getRect(eyeOf('t1'));

    // The band's own arithmetic is private; what has to hold is that the
    // press the user makes — the middle of the eye — resolves INSIDE it,
    // and the only honest way to ask that is to make the press and see the
    // swipe start. That is the next case. This one pins the geometry the
    // arithmetic was written against, so a rail that moves its columns
    // fails HERE with a readable number instead of there with a silence.
    expect(
      eye.left - rail.left,
      greaterThan(0),
      reason: 'the eye stands inside the rail, or nothing below means much',
    );
    expect(
      rail.right - eye.right,
      lessThan(80),
      reason:
          'the eye is a TRAILING column: it sits near the rail\'s right '
          'edge, which is what the band arithmetic counts back from',
    );
  });

  testWidgets('a drag DOWN from one eye hides every track it crosses', (
    tester,
  ) async {
    final session = await pumpRail(tester);
    expect(
      pictureVisibility(session),
      [true, true, true],
      reason: 'the fixture starts visible, or the sweep proves nothing',
    );

    final first = tester.getCenter(eyeOf('t1'));
    final last = tester.getCenter(eyeOf('t3'));
    final gesture = await tester.startGesture(first);
    // Step down the rail so every row in between is crossed — a swipe
    // paints what it passes, and one jump to the end would not say whether
    // the middle row was seen.
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(
        Offset(first.dx, first.dy + (last.dy - first.dy) * step / 6),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      pictureVisibility(session),
      [false, false, false],
      reason:
          '유저 2026-08-24 I-1: 「탭 다운 한 채로 아래로 드래그하면 해당 '
          '다른 레이어들도 같은 버튼조작되도록」 — the storyboard rail is '
          'not a different rail',
    );
    expect(
      seVisibility(session),
      [true, false, false],
      reason:
          '⛔the sweep CROSSED t2 and t3, and their S rows carry the SAME '
          'eye — acting on the SE layer instead of a cut. t1 stays visible '
          'because its S row sits ABOVE its V row, where the drag began. A '
          'resolver naming only V rows painted NONE of them, and the cut '
          'assertion above still passed: 「초록이 빈 것을 쟀다」',
    );
    expect(
      transitionVisibility(session),
      [true, false, false],
      reason:
          'the third row kind, on the same column and the same sweep — a '
          'rail that stacks three kinds has to name all three',
    );
  });

  testWidgets('⛔a drag that starts OFF the column paints nothing', (
    tester,
  ) async {
    // The control, and it is the case a band that covered the whole row
    // would fail: the name area is not a column, so a drag from there is
    // the row's business and the eyes must be untouched.
    final session = await pumpRail(tester);
    final row = tester.getRect(
      find.byKey(const ValueKey<String>('storyboard-track-label-row-t1')),
    );
    final eye = tester.getRect(eyeOf('t1'));
    final from = Offset(row.left + 24, row.center.dy);
    expect(
      eye.contains(from),
      isFalse,
      reason: 'the press must genuinely miss the eye',
    );

    final gesture = await tester.startGesture(from);
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(pictureVisibility(session), [
      true,
      true,
      true,
    ], reason: 'a swipe only runs from a column it has');
  });
}

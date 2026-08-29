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

  /// Which S rows have their lanes twirled OPEN, read off the twirl itself
  /// rather than the host's set — the icon is what the user sees.
  Set<String> openSeRows(WidgetTester tester) => {
    for (final id in const ['t1', 't2', 't3'])
      if (tester
          .widgetList<Icon>(
            find.descendant(
              of: find.byKey(
                ValueKey<String>('storyboard-se-lane-toggle-$id-1'),
              ),
              matching: find.byType(Icon),
            ),
          )
          .any((icon) => icon.icon == Icons.arrow_drop_down))
        '$id-1',
  };

  /// The S rows' SHEET flags — the column this rail mounted but could not
  /// sweep until the two rails stopped keeping separate column lists.
  List<bool> sheetFlags(EditorSessionManager session) => [
    for (final track in session.repository.requireProject().tracks)
      track.seLayers.single.onTimesheet,
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

  testWidgets('🚨the SHEET column sweeps too — every button, not a list', (
    tester,
  ) async {
    // 유저 2026-08-29: 「버튼이면 다 가능하도록」·「로직적으로 다른규칙
    // 두지말고 통일」. This rail mounted a sheet toggle that no swipe could
    // reach while the layer rail swiped its own, purely because the two
    // rails hand-wrote their column lists. There is one list now.
    final session = await pumpRail(tester);
    final sheets = [
      for (final id in const ['t1-s1', 't2-s1', 't3-s1'])
        find.byKey(ValueKey<String>('storyboard-layer-timesheet-$id')),
    ];
    for (final sheet in sheets) {
      expect(sheet, findsOneWidget, reason: 'the fixture mounts the button');
    }
    expect(
      sheetFlags(session),
      [true, true, true],
      reason: 'S rows start on the sheet, or the sweep proves nothing',
    );

    final first = tester.getCenter(sheets.first);
    final last = tester.getCenter(sheets.last);
    final gesture = await tester.startGesture(first);
    for (var step = 1; step <= 6; step += 1) {
      await gesture.moveTo(
        Offset(first.dx, first.dy + (last.dy - first.dy) * step / 6),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      sheetFlags(session),
      [false, false, false],
      reason:
          'a LEADING column, so its band is measured from the rail edge '
          'rather than counted back from it — the other half of the shared '
          'construction, and the half this rail had never used',
    );
  });

  testWidgets('🚨and the LANE TWIRL sweeps, the last column that could not', (
    tester,
  ) async {
    // The fourth column, and the one that proves the law rather than a
    // list: nobody asked for a lane sweep. It arrived because the rails
    // stopped choosing which of their buttons could be swept.
    await pumpRail(tester);
    final twirls = [
      for (final id in const ['t1', 't2', 't3'])
        find.byKey(ValueKey<String>('storyboard-se-lane-toggle-$id-1')),
    ];
    for (final twirl in twirls) {
      expect(twirl, findsOneWidget, reason: 'the fixture mounts the twirl');
    }
    expect(
      openSeRows(tester),
      isEmpty,
      reason: 'all closed to start, or the sweep proves nothing',
    );

    final first = tester.getCenter(twirls.first);
    // ⚠️STEPPED, not aimed at a precomputed point: opening a row's lanes
    // makes the rail taller, so every row below the one just painted slides
    // DOWN under the finger. A drag to where t3's twirl used to be lands
    // above it — measured, and it left t3 unpainted.
    final gesture = await tester.startGesture(first);
    for (var step = 1; step <= 24; step += 1) {
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      openSeRows(tester),
      containsAll(<String>['t1-1', 't2-1', 't3-1']),
      reason:
          'every S row the sweep crossed opened its lanes — 유저: 「버튼이면 '
          '다 가능하도록」',
    );
  });

  /// 🚨★★★THE PRESS CAN START ON ANY ROW KIND, NOT JUST THE ONE I HAPPENED
  /// TO WRITE FIRST.
  ///
  /// The claim is what lets a sweep BEGIN somewhere: a row the drag merely
  /// crosses is painted without one. So a rail can pass every "the sweep
  /// crossed these rows" case while half its buttons cannot start a sweep
  /// at all — measured, and that is exactly the state this rail was in with
  /// the eye claimed on V rows only.
  ///
  /// ⛔This loop is the guard. Every row kind that MOUNTS the eye has to be
  /// able to start from it.
  for (final start in const <({String label, String key})>[
    (label: 'V row (the cut eye)', key: 'storyboard-cut-visibility-t1-cut'),
    (label: 'S row (the layer eye)', key: 'storyboard-layer-visibility-t1-s1'),
  ]) {
    testWidgets('🚨a sweep can START on the ${start.label}', (tester) async {
      final session = await pumpRail(tester);
      final from = find.byKey(ValueKey<String>(start.key));
      expect(from, findsOneWidget, reason: 'the fixture mounts ${start.key}');

      final gesture = await tester.startGesture(tester.getCenter(from));
      for (var step = 1; step <= 12; step += 1) {
        await gesture.moveBy(const Offset(0, 25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      // Whatever it started on, SOMETHING below it must have been painted —
      // the two eye columns are the same column and the sweep runs down
      // through both kinds.
      final painted = [
        ...pictureVisibility(session),
        ...seVisibility(session),
      ].where((visible) => !visible).length;
      expect(
        painted,
        greaterThan(1),
        reason:
            'a press on ${start.key} has to be able to BEGIN a sweep, not '
            'only be crossed by one — 유저: 「버튼이면 다 가능하도록」',
      );
    });
  }
}

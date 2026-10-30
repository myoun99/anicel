import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_frame_count_settings.dart';
import 'package:anicel/src/models/app_frame_grid_settings.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timeline_frame_range.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/shortcuts/editor_action_registry.dart';
import 'package:anicel/src/ui/shortcuts/editor_shortcut_scope.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart' show Pill;
import 'package:anicel/src/ui/text/app_strings.dart';

import '../../helpers/number_pad_keyboard.dart';
import '../../helpers/run_edge_fixtures.dart';

/// 🗣️I-58 (유저 2026-10-01): 「중간나누기 마크 자동추가. 대상은 중간나누기
/// 마크가 적용가능한 행의 선택된블록들or현재 인덱스 블록, 각자 현재 블록
/// 안에서 블록이 끝날때까지, n코마마다 중간나누기 마크 추가 … 3적고
/// 확인누르면 현재 블록에서 헤더부터 시작해서 3코마마다 점 찍음. 즉
/// 1--------- 이렇게있으면, 1--.--.--.」
///
/// 🗣️F-402 (유저 2026-10-19): 「선택된대상 블록이 있을때의 동작은 지금과
/// 같음. 다만 선택된게 없는 상황에서 … 현재 인덱스부터 시작해서 마크를
/// 추가함. 참고로 현재 인덱스에도 마크찍도록」 · 「중간나누기 마크는 토글이기
/// 때문에 마크가 존재하는 곳은 토글규칙에 따라서 마크 삭제」.
void main() {
  // The mark the window opens on is an app-wide value that outlives a test
  // — and so is the unnamed drawing's it opens on before a pick: each
  // starts from the product default.
  void resetSettings() {
    AppFrameCountSettings.settings.value = const AppFrameCountSettings();
    AppFrameGridSettings.settings.value = const AppFrameGridSettings();
  }
  setUp(resetSettings);
  tearDown(resetSettings);

  const idA = LayerId('every-a');
  const idB = LayerId('every-b');
  const idC = LayerId('every-c');
  const idD = LayerId('every-d');

  Frame cel(String id, int duration) =>
      Frame(id: FrameId(id), duration: duration, strokes: const []);

  /// A: ONE block ten frames long — the user's `1---------`. B: a block of
  /// four, a block of six that holds, and the hold's ghost to the cut's
  /// end. C: a single frame, then a block of two.
  Project project() => Project(
    id: const ProjectId('mark-every'),
    name: 'Every',
    createdAt: DateTime.utc(2026, 10, 18),
    tracks: [
      Track(
        id: const TrackId('track'),
        name: 'Video',
        cuts: [
          Cut(
            id: const CutId('cut-1'),
            name: '1',
            duration: 16,
            canvasSize: const CanvasSize(width: 640, height: 360),
            layers: [
              Layer(
                id: idA,
                name: 'A',
                kind: LayerKind.animation,
                frames: [cel('a1', 10)],
                timeline: {
                  0: const TimelineExposure.drawing(
                    FrameId('a1'),
                    length: 10,
                  ),
                },
              ),
              Layer(
                id: idB,
                name: 'B',
                kind: LayerKind.animation,
                frames: [cel('b1', 4), cel('b2', 6)],
                timeline: {
                  0: const TimelineExposure.drawing(FrameId('b1'), length: 4),
                  4: const TimelineExposure.drawing(
                    FrameId('b2'),
                    length: 6,
                    endEdge: holdMark,
                  ),
                  10: const TimelineExposure.drawing(
                    FrameId('b2'),
                    length: 6,
                    ghostOf: endHoldGhost,
                  ),
                },
              ),
              Layer(
                id: idC,
                name: 'C',
                kind: LayerKind.animation,
                frames: [cel('c1', 1), cel('c2', 2)],
                timeline: {
                  0: const TimelineExposure.drawing(FrameId('c1'), length: 1),
                  1: const TimelineExposure.drawing(FrameId('c2'), length: 2),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  EditorSessionManager rig() {
    final session = EditorSessionManager(initialProject: project());
    addTearDown(session.dispose);
    return session;
  }

  /// The marks of [id]'s entry at [start], as offsets from its head.
  List<int> marksAt(EditorSessionManager session, LayerId id, int start) {
    final layer = session.layers.firstWhere((l) => l.id == id);
    return [...?layer.timeline[start]?.breakdownOffsets]..sort();
  }

  void sweep(
    EditorSessionManager session,
    List<LayerId> ids, {
    required int from,
    required int toExclusive,
  }) {
    session.frameRangeSelection.value = TimelineFrameRangeSelection(
      layerId: ids.first,
      startIndex: from,
      endIndexExclusive: toExclusive,
      layerIds: ids,
    );
  }

  void standOn(EditorSessionManager session, LayerId id, int frame) {
    session.selectLayer(id);
    session.selectFrameIndex(frame);
    session.clearFrameRangeSelection();
  }

  test('the fixture holds what the pins below read (presence first)', () {
    final session = rig();
    final b = session.layers.firstWhere((l) => l.id == idB);
    expect(b.timeline[10]?.ghost, isTrue, reason: 'the hold\'s ghost');
    expect(b.timeline[10]?.length, 6);
    for (final (id, start) in [(idA, 0), (idB, 0), (idB, 4)]) {
      expect(marksAt(session, id, start), isEmpty);
    }
  });

  test('「현재 인덱스부터 … 현재 인덱스에도 마크찍도록」: with no band, 3 dots '
      'the block under the playhead from the playhead\'s cell to its end',
      () {
    final session = rig();
    standOn(session, idA, 2);

    expect(session.layerMarks.canMarkEvery, isTrue);
    session.layerMarks.markEvery(3, InbetweenMark.two);

    expect(marksAt(session, idA, 0), [2, 5, 8]);
    expect(
      [marksAt(session, idB, 0), marksAt(session, idB, 4)],
      everyElement(isEmpty),
      reason: 'no band: the block under the playhead, and only it',
    );
  });

  test('「1--------- 이렇게있으면, 1--.--.--.」: standing on the head, the '
      'head is passed by — the drawing itself takes no mark', () {
    final session = rig();
    standOn(session, idA, 0);

    session.layerMarks.markEvery(3, InbetweenMark.two);

    expect(marksAt(session, idA, 0), [3, 6, 9]);
  });

  test('「토글규칙에 따라서」: it toggles as the ● does over a band — a mix is '
      'marked whole, and all marked are cleared', () {
    final session = rig();
    standOn(session, idA, 4);
    session.layerMarks.toggleMarkAtCurrentFrame(InbetweenMark.two);
    expect(marksAt(session, idA, 0), [4], reason: '⛔전제');

    standOn(session, idA, 1);
    session.layerMarks.markEvery(3, InbetweenMark.two);
    expect(marksAt(session, idA, 0), [1, 4, 7], reason: 'a mix: all marked');

    session.layerMarks.markEvery(3, InbetweenMark.two);
    expect(marksAt(session, idA, 0), isEmpty, reason: 'all marked: cleared');
  });

  test('a band toggles by the same law', () {
    final session = rig();
    sweep(session, [idA, idB], from: 0, toExclusive: 10);
    session.layerMarks.markEvery(3, InbetweenMark.two);
    expect(marksAt(session, idA, 0), [3, 6, 9], reason: '⛔전제');

    session.layerMarks.markEvery(3, InbetweenMark.two);

    for (final (id, start) in [(idA, 0), (idB, 0), (idB, 4)]) {
      expect(marksAt(session, id, start), isEmpty);
    }
  });

  test('「선택된블록들」: every block the band takes, each from its OWN head',
      () {
    final session = rig();
    standOn(session, idA, 0);
    sweep(session, [idA, idB], from: 0, toExclusive: 10);

    session.layerMarks.markEvery(3, InbetweenMark.two);

    expect(marksAt(session, idA, 0), [3, 6, 9]);
    expect(marksAt(session, idB, 0), [3]);
    expect(
      marksAt(session, idB, 4),
      [3],
      reason: 'frame 7, three past ITS head — not frames 6 and 9, three '
          'apart from where the band starts',
    );
  });

  test('one press is ONE undo, and the rows hear it', () {
    final session = rig();
    sweep(session, [idA, idB], from: 0, toExclusive: 10);
    var notifies = 0;
    session.addListener(() => notifies += 1);

    session.layerMarks.markEvery(3, InbetweenMark.two);

    expect(marksAt(session, idB, 4), [3], reason: 'premise');
    expect(notifies, isPositive);

    session.undo();

    for (final (id, start) in [(idA, 0), (idB, 0), (idB, 4)]) {
      expect(marksAt(session, id, start), isEmpty);
    }
  });

  test('a band that takes no block is a NO-OP, never a redirect onto the '
      'active row', () {
    final session = rig();
    standOn(session, idA, 5);
    // Inside B's first block, past its head: no block STARTS in the band.
    sweep(session, [idB], from: 1, toExclusive: 3);

    expect(session.layerMarks.canMarkEvery, isFalse);
    session.layerMarks.markEvery(3, InbetweenMark.two);
    for (final (id, start) in [(idA, 0), (idB, 0), (idB, 4)]) {
      expect(marksAt(session, id, start), isEmpty);
    }
  });

  /// [rig] with D beside A: a SYNCED attach row of A — a row whose cell
  /// marks are its base's, never its own: D reads A's.
  EditorSessionManager rigWithSyncedRow() {
    final film = project();
    final track = film.tracks.single;
    final cut = track.cuts.single;
    final d = Layer(
      id: idD,
      name: 'D',
      kind: LayerKind.animation,
      attachedToLayerId: idA,
      attachedMode: AttachedMode.synced,
      frames: [cel('d1', 6)],
      timeline: {
        0: const TimelineExposure.drawing(FrameId('d1'), length: 6),
      },
    );
    final session = EditorSessionManager(
      initialProject: film.copyWith(
        tracks: [
          track.copyWith(
            cuts: [
              cut.copyWith(
                layers: [cut.layers.first, d, ...cut.layers.skip(1)],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  test('a band over a row that keeps no marks of its own takes nothing '
      'there: alone it lights nothing, beside A it dots A\'s block', () {
    final session = rigWithSyncedRow();
    standOn(session, idA, 0);
    sweep(session, [idD], from: 0, toExclusive: 6);
    expect(session.layerMarks.canMarkEvery, isFalse);

    sweep(session, [idA, idD], from: 0, toExclusive: 6);
    session.layerMarks.markEvery(3, InbetweenMark.two);
    expect(marksAt(session, idA, 0), [3, 6, 9]);
  });

  test('the playhead on a row that keeps no marks of its own lights nothing '
      'and dots nothing — the band\'s one predicate', () {
    final session = rigWithSyncedRow();
    standOn(session, idD, 2);
    expect(session.layerMarks.canMarkEvery, isFalse);
    session.layerMarks.markEvery(2, InbetweenMark.two);
    expect(marksAt(session, idD, 0), isEmpty);
  });

  test('nothing to dot stays dark and lands nothing: a hold\'s ghost is no '
      'block, a single frame has no cell past its head', () {
    final session = rig();
    standOn(session, idB, 12);
    expect(session.layerMarks.canMarkEvery, isFalse, reason: 'the ghost');

    standOn(session, idC, 0);
    expect(session.layerMarks.canMarkEvery, isFalse, reason: 'one frame');

    standOn(session, idA, 0);
    final undoBefore = session.canUndo;
    var notifies = 0;
    session.addListener(() => notifies += 1);
    session.layerMarks.markEvery(10, InbetweenMark.two);
    expect(marksAt(session, idA, 0), isEmpty, reason: '10 is past the end');
    expect((session.canUndo, notifies), (undoBefore, 0));
  });

  test('a block of two lights it: its one cell past the head takes the ●',
      () {
    final session = rig();
    standOn(session, idC, 1);

    expect(session.layerMarks.canMarkEvery, isTrue);
    session.layerMarks.markEvery(1, InbetweenMark.two);

    expect(marksAt(session, idC, 1), [1]);
  });

  Map<int, InbetweenMark> wornAt(
    EditorSessionManager session,
    LayerId id,
    int start,
  ) => session.layers.firstWhere((l) => l.id == id).timeline[start]!
      .breakdownMarks;

  test('🗣️I-130-Q2 「창에서 마크를 고른다」: the ○ goes down the cells the ● '
      'would, by the same law over many', () {
    final session = rig();
    standOn(session, idA, 0);

    session.layerMarks.markEvery(3, InbetweenMark.one);
    expect(wornAt(session, idA, 0), {
      3: InbetweenMark.one,
      6: InbetweenMark.one,
      9: InbetweenMark.one,
    });

    session.layerMarks.markEvery(3, InbetweenMark.two);
    expect(
      wornAt(session, idA, 0),
      {3: InbetweenMark.two, 6: InbetweenMark.two, 9: InbetweenMark.two},
      reason: 'cells wearing the other mark are not all the ●: they take it',
    );

    session.layerMarks.markEvery(3, InbetweenMark.two);
    expect(wornAt(session, idA, 0), isEmpty, reason: 'all the ●: cleared');
  });

  Future<EditorSessionManager> pumpEditor(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: project())),
    );
    await tester.pumpAndSettle();
    return tester.widget<EditorWorkspace>(find.byType(EditorWorkspace)).session;
  }

  final pill = find.descendant(
    of: find.byType(TimelineActionToolbar),
    matching: find.byKey(
      const ValueKey<String>('timeline-toolbar-frame-group'),
    ),
  );

  Finder inThePill(String keyValue) => find.descendant(
    of: pill,
    matching: find.byWidgetPredicate(
      (w) => w is AppIconButton && w.keyValue == keyValue,
    ),
  );

  final window = find.byKey(const ValueKey<String>('mark-every-dialog'));

  Future<void> typeAndApply(WidgetTester tester, String count) async {
    await typeOnThePad(tester, 'mark-every-field', count);
    await tester.tap(find.byKey(const ValueKey<String>('mark-every-apply')));
    await tester.pumpAndSettle();
  }

  // 🗣️I-58-Q1 (유저 2026-10-18): 「토글은 지금 자리, 새 버튼만 ● 오른쪽」.
  testWidgets('the button stands right after the ●, and its window takes '
      'the count the way every count of frames is typed', (tester) async {
    final session = await pumpEditor(tester);

    final order = [
      for (final button in tester.widgetList<AppIconButton>(
        find.descendant(of: pill, matching: find.byType(AppIconButton)),
      ))
        button.keyValue,
    ];
    expect(
      order.indexOf('mark-every-button'),
      order.indexOf('toggle-mark-button') + 1,
      reason: '● 바로 오른쪽 — and the toggle keeps its place before the ●: '
          '$order',
    );
    // 🗣️I-130: 「기존 중간나누기 버튼 왼쪽에 중간나누기 마크1 버튼 신설」.
    expect(
      order.indexOf('toggle-mark-one-button'),
      order.indexOf('toggle-mark-button') - 1,
    );
    expect(
      order.indexOf('auto-frame-toggle-button'),
      order.indexOf('toggle-mark-one-button') - 1,
    );

    standOn(session, idA, 1);
    await tester.pumpAndSettle();
    await tester.ensureVisible(inThePill('mark-every-button'));
    await tester.pumpAndSettle();
    await tester.tap(inThePill('mark-every-button'));
    await tester.pumpAndSettle();

    expect(window, findsOneWidget);
    expect(
      find.descendant(
        of: window,
        matching: find.text(
          AppText.strings.windowTitleOn(
            'Auto-add In-between Marks',
            AppText.strings.tlFrame,
          ),
        ),
      ),
      findsOneWidget,
      reason: 'the window is called what its button is',
    );
    await typeAndApply(tester, '3');

    expect(window, findsNothing);
    expect(marksAt(session, idA, 0), [1, 4, 7]);
    session.playbackRig.prerenderScheduler.cancel();
  });

  Finder markPick(InbetweenMark mark) =>
      find.byKey(ValueKey<String>('mark-every-mark-${mark.name}'));

  Future<void> openWindow(WidgetTester tester) async {
    await tester.ensureVisible(inThePill('mark-every-button'));
    await tester.pumpAndSettle();
    await tester.tap(inThePill('mark-every-button'));
    await tester.pumpAndSettle();
  }

  bool picked(WidgetTester tester, InbetweenMark mark) =>
      tester.widget<Pill>(markPick(mark)).selected;

  // 🗣️I-130-Q2 (유저 2026-10-25): 「창에서 마크를 고른다」 — 간격 숫자 옆에
  // ○ / ● 고르기(지난번 고른 것 기억). 자동 추가 버튼은 하나 그대로.
  testWidgets('🗣️I-130-Q2: the window picks the mark it lays, and opens on '
      'the one picked last', (tester) async {
    final session = await pumpEditor(tester);
    standOn(session, idA, 1);
    await tester.pumpAndSettle();

    await openWindow(tester);
    expect(
      (picked(tester, InbetweenMark.one), picked(tester, InbetweenMark.two)),
      (false, true),
      reason:
          'never picked: the unnamed drawing\'s, the ● to begin with — '
          '🗣️F-489-Q1 「둘 다 따라간다」',
    );
    await tester.tap(markPick(InbetweenMark.one));
    await tester.pumpAndSettle();
    expect(
      (picked(tester, InbetweenMark.one), picked(tester, InbetweenMark.two)),
      (true, false),
    );
    await typeAndApply(tester, '3');

    expect(wornAt(session, idA, 0), {
      1: InbetweenMark.one,
      4: InbetweenMark.one,
      7: InbetweenMark.one,
    });
    expect(
      AppFrameCountSettings.settings.value.lastEveryMark,
      InbetweenMark.one,
      reason: 'remembered where a restart reads it',
    );

    await openWindow(tester);
    expect(
      (picked(tester, InbetweenMark.one), picked(tester, InbetweenMark.two)),
      (true, false),
      reason: '지난번 고른 것 기억',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️F-489-Q1 「둘 다 따라간다」: never picked, the window opens on '
      'the mark Preferences ▸ Display gave the unnamed drawing — and a pick '
      'outlasts a later one there', (tester) async {
    final session = await pumpEditor(tester);
    standOn(session, idA, 1);
    await tester.pumpAndSettle();
    session.appSettings.setFrameGridSettings(
      const AppFrameGridSettings(unnamedMark: InbetweenMark.one),
    );

    await openWindow(tester);
    expect(
      (picked(tester, InbetweenMark.one), picked(tester, InbetweenMark.two)),
      (true, false),
    );
    await tester.tap(markPick(InbetweenMark.two));
    await tester.pumpAndSettle();
    await typeAndApply(tester, '3');
    session.appSettings.setFrameGridSettings(const AppFrameGridSettings());
    session.appSettings.setFrameGridSettings(
      const AppFrameGridSettings(unnamedMark: InbetweenMark.one),
    );

    await openWindow(tester);
    expect(
      (picked(tester, InbetweenMark.one), picked(tester, InbetweenMark.two)),
      (false, true),
      reason: '지난번 고른 것 기억 — the pick, not the unnamed drawing\'s',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('「간격 숫자 옆에」: the pick stands beside the number, either '
      'way it is typed', (tester) async {
    final session = await pumpEditor(tester);
    standOn(session, idA, 1);
    await tester.pumpAndSettle();
    await openWindow(tester);

    void besideTheNumber(String field) {
      final number = tester.getRect(find.byKey(ValueKey<String>(field)));
      for (final mark in InbetweenMark.values) {
        final pick = tester.getRect(markPick(mark));
        expect(pick.left, greaterThanOrEqualTo(number.right), reason: field);
        expect(
          (pick.top < number.bottom, pick.bottom > number.top),
          (true, true),
          reason: '$field: on the number\'s line',
        );
      }
    }

    besideTheNumber('mark-every-field');
    await tester.tap(markPick(InbetweenMark.two));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mark-every-entry-seconds')));
    await tester.pumpAndSettle();
    besideTheNumber('mark-every-koma-field');
    expect(
      AppFrameCountSettings.settings.value,
      const AppFrameCountSettings(
        lastEntry: FrameCountEntry.secondsPlusFrames,
        lastEveryMark: InbetweenMark.two,
      ),
      reason: 'switching the entry keeps the mark picked, and the other way',
    );
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a pick wears its button\'s face and name', (tester) async {
    final session = await pumpEditor(tester);
    standOn(session, idA, 1);
    await tester.pumpAndSettle();
    await openWindow(tester);

    // 🗣️I-130: 「속이 찬 점을 마크2, 속이 빈 그냥 선으로 된 원을 마크1」.
    for (final (mark, button, face, action) in [
      (
        InbetweenMark.one,
        'toggle-mark-one-button',
        Icons.circle_outlined,
        EditorActionIds.frameToggleMarkOne,
      ),
      (
        InbetweenMark.two,
        'toggle-mark-button',
        Icons.circle,
        EditorActionIds.frameToggleMarkTwo,
      ),
    ]) {
      final pressed = tester.widget<AppIconButton>(inThePill(button));
      final pick = tester.widget<Pill>(markPick(mark));
      expect(
        (pick.icon, pick.label),
        ((pressed.icon as Icon).icon, pressed.tooltip),
        reason: mark.name,
      );
      expect((pick.icon, pick.label), (face, editorActionLabel(action)));
      expect(
        pressed.shortcuts,
        [action],
        reason: 'its tooltip follows its own action\'s live key (I-19)',
      );
    }
    session.playbackRig.prerenderScheduler.cancel();
  });

  // ⚠️The pill is memoized on what its buttons read and baked into a
  // raster, so a change that only THIS button reads has to reach it too.
  testWidgets('it lights with the block under the playhead', (tester) async {
    final session = await pumpEditor(tester);
    final button = inThePill('mark-every-button');
    bool lit() => tester.widget<AppIconButton>(button).onPressed != null;

    // Each a block's head, where the ● is dark either way.
    standOn(session, idC, 0);
    await tester.pumpAndSettle();
    expect(lit(), isFalse, reason: 'one frame');
    standOn(session, idA, 0);
    await tester.pumpAndSettle();
    expect(lit(), isTrue, reason: 'ten frames');
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('a key recorded for it opens the same window', (tester) async {
    final session = await pumpEditor(tester);
    standOn(session, idA, 7);
    EditorShortcutScope.peek(
      tester.element(find.byType(EditorWorkspace)),
    )!.setActivators(EditorActionIds.frameMarkEvery, const [
      SingleActivator(LogicalKeyboardKey.keyK),
    ]);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(window, findsOneWidget);
    await typeAndApply(tester, '2');

    expect(marksAt(session, idA, 0), [7, 9]);
    session.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('🗣️I-130: a key recorded for the ○ or the ● presses that '
      'button', (tester) async {
    final session = await pumpEditor(tester);
    standOn(session, idA, 3);
    EditorShortcutScope.peek(tester.element(find.byType(EditorWorkspace)))!
      ..setActivators(EditorActionIds.frameToggleMarkOne, const [
        SingleActivator(LogicalKeyboardKey.keyK),
      ])
      ..setActivators(EditorActionIds.frameToggleMarkTwo, const [
        SingleActivator(LogicalKeyboardKey.keyJ),
      ]);
    await tester.pump();
    Map<int, InbetweenMark> worn() => session.layers
        .firstWhere((layer) => layer.id == idA)
        .timeline[0]!
        .breakdownMarks;

    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(worn(), {3: InbetweenMark.one});
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.pumpAndSettle();
    expect(worn(), {3: InbetweenMark.two});
    session.playbackRig.prerenderScheduler.cancel();
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/playback/canvas_playback_controller.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/timeline/comma_button.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';
import 'package:anicel/src/ui/timeline/timeline_lane_rows.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;
import 'package:anicel/src/ui/widgets/app_icon_button.dart';

import '../../helpers/home_page_probes.dart';

/// F-587 (유저 2026-11-13): 「타임라인 버튼들, 프레임알약이나 그런거 전부.
/// 재생할때 프레임 상태에 따라 갱신되서 바뀌는데 그냥 구조 변경. 재생중에는
/// 바꾸지않고 재생전 마지막 상태 유지하도록. 왜냐하면 재생중 어차피
/// 쓸데없는데 매번바꾸니 조금이라도 가볍게 하기위함이고, 재생중 깜빡이는게
/// 심해서 방해됨」
///
/// 🔬Before it (sixteen frames of a cut played alone, its lanes open): a
/// lane's value was built again on thirteen of them, the bar's shared and
/// frame pills on five, the shift pair on four — and a film crossing into
/// its next cut built the whole bar again.
///
/// ⚠️What stands in a bar or a row is ENUMERATED from the tree, never
/// listed here: 「그런거 전부」 is the ask, and a hand-written list is a
/// list of what existed the day it was written.
///
/// Pinned by widget identity: a widget instance only changes when the
/// widget above it is built again.
Map<String, Widget> _keyedUnder<T extends Widget>(WidgetTester tester) {
  final out = <String, Widget>{};
  for (final root in find.byType(T).evaluate()) {
    void visit(Element element) {
      final key = element.widget.key;
      if (key is ValueKey<String>) {
        out[key.value] = element.widget;
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
  }
  return out;
}

/// The keys under which [now] holds another widget than [before] did.
List<String> _builtAgain(
  Map<String, Widget> before,
  Map<String, Widget> now,
) => [
  for (final key in {...before.keys, ...now.keys})
    if (!identical(before[key], now[key])) key,
];

typedef _Read = ({Map<String, bool> presses, List<String> words});

/// A record is equal by its fields, and a map or a list only to itself:
/// what they hold is compared here.
Matcher _reads(_Read read) => isA<_Read>()
    .having((it) => it.presses, 'presses', read.presses)
    .having((it) => it.words, 'words', read.words);

/// What a press would find under each [T]: whether each keyed button takes
/// one, and every word written there.
_Read _readUnder<T extends Widget>(WidgetTester tester) {
  final presses = <String, bool>{};
  final words = <String>[];
  for (final root in find.byType(T).evaluate()) {
    void visit(Element element) {
      final widget = element.widget;
      final key = widget.key;
      if (key is ValueKey<String>) {
        final takes = switch (widget) {
          TextButton(:final onPressed) => onPressed != null,
          AppIconButtonFace(:final onPressed) => onPressed != null,
          CommaButton(:final onPressed) => onPressed != null,
          InkWell(:final onTap) => onTap != null,
          _ => null,
        };
        if (takes != null) {
          presses[key.value] = takes;
        }
      }
      if (widget is Text && widget.data != null) {
        words.add(widget.data!);
      }
      element.visitChildren(visit);
    }

    root.visitChildren(visit);
  }
  return (presses: presses, words: words);
}

bool _standsInABarOrARow(Element element) {
  bool held(Widget widget) =>
      widget is TimelineActionToolbar || widget is TimelineLaneControlsRow;
  var found = held(element.widget);
  if (!found) {
    element.visitAncestorElements((ancestor) {
      found = held(ancestor.widget);
      return !found;
    });
  }
  return found;
}

void main() {
  /// The editor, a drawing on [drawnAt] of its one cut, standing there.
  Future<EditorSessionManager> pumpEditor(
    WidgetTester tester, {
    required int drawnAt,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    session.selectFrameIndex(drawnAt);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    return session;
  }

  /// The active layer's lanes open, its transform group with them — the
  /// position keyed on 4 and 9, the opacity on 1 and 14, so a run from 0
  /// crosses keys and values both.
  Future<void> openLanesWithKeys(
    WidgetTester tester,
    EditorSessionManager session,
  ) async {
    final layer = session.activeLayerId!;
    session.layerSwitches.toggleLayerLanes(layer);
    session.layerSwitches.setLayerLaneGroupExpanded(
      layer,
      transformGroupHeaderLane.laneId,
      expanded: true,
    );
    await tester.pumpAndSettle();
    for (final (lane, frame, value) in const [
      ('position', 4, '100, 100'),
      ('position', 9, '300, 200'),
      ('opacity', 1, '100'),
      ('opacity', 14, '20'),
    ]) {
      session.laneVerbs.setLaneValueAt(
        layer,
        lane,
        frame,
        value,
        frameIsGlobal: false,
        scaleLinked: false,
        description: 'Set',
      );
    }
    await tester.pumpAndSettle();
  }

  /// Where the playhead's column stands: the timeline's, or the conte's.
  double playheadX(WidgetTester tester, {bool storyboard = false}) => tester
      .getRect(
        find.byKey(
          ValueKey<String>(
            storyboard ? 'storyboard-playhead' : 'timeline-playhead-column',
          ),
        ),
      )
      .left;

  testWidgets('a cut played alone builds nothing in the bar or in a lane '
      'row — they stand as they stood before it, and read where it '
      'stopped as it ends', (tester) async {
    final session = await pumpEditor(tester, drawnAt: 0);
    await openLanesWithKeys(tester, session);

    final bar = _keyedUnder<TimelineActionToolbar>(tester);
    final rows = _keyedUnder<TimelineLaneControlsRow>(tester);
    final barRead = _readUnder<TimelineActionToolbar>(tester);
    final rowsRead = _readUnder<TimelineLaneControlsRow>(tester);
    expect(barRead.presses, isNotEmpty, reason: 'premise: a bar stands');
    expect(rowsRead.presses, isNotEmpty, reason: 'premise: lane rows stand');
    final playheadBefore = playheadX(tester);

    session.playbackRig.playback.play(scope: PlaybackScope.activeCut);
    await tester.pump();
    final built = <Type>[];
    debugOnRebuildDirtyWidget = (element, _) {
      if (_standsInABarOrARow(element)) {
        built.add(element.widget.runtimeType);
      }
    };
    try {
      for (var tick = 0; tick < 12; tick += 1) {
        await tester.pump(const Duration(milliseconds: 42));
      }
    } finally {
      // Inside the body: the binding checks its switches before a
      // tear-down would run.
      debugOnRebuildDirtyWidget = null;
    }

    expect(
      session.currentFrameIndex,
      greaterThan(9),
      reason: 'premise: the run took the cursor past every key (F-296-Q6)',
    );
    expect(
      playheadX(tester),
      greaterThan(playheadBefore),
      reason: 'the playhead is the run\'s own, and moves with it',
    );
    expect(built, isEmpty, reason: 'no frame of it built anything there');
    expect(
      _builtAgain(bar, _keyedUnder<TimelineActionToolbar>(tester)),
      isEmpty,
    );
    expect(
      _builtAgain(rows, _keyedUnder<TimelineLaneControlsRow>(tester)),
      isEmpty,
    );
    expect(_readUnder<TimelineActionToolbar>(tester), _reads(barRead));
    expect(_readUnder<TimelineLaneControlsRow>(tester), _reads(rowsRead));

    session.playbackRig.transports.stopAll();
    await tester.pumpAndSettle();
    final stoppedAt = session.currentFrameIndex;
    final barStopped = _readUnder<TimelineActionToolbar>(tester);
    final rowsStopped = _readUnder<TimelineLaneControlsRow>(tester);
    expect(
      barStopped.presses,
      isNot(barRead.presses),
      reason: 'the bar reads the frame the run left the cursor on',
    );
    expect(rowsStopped.presses, isNot(rowsRead.presses));
    expect(rowsStopped.words, isNot(rowsRead.words));

    // ...which is what a hand reads there.
    session.selectFrameIndex(0);
    await tester.pumpAndSettle();
    expect(_readUnder<TimelineActionToolbar>(tester), _reads(barRead));
    expect(_readUnder<TimelineLaneControlsRow>(tester), _reads(rowsRead));
    session.selectFrameIndex(stoppedAt);
    await tester.pumpAndSettle();
    expect(_readUnder<TimelineActionToolbar>(tester), _reads(barStopped));
    expect(_readUnder<TimelineLaneControlsRow>(tester), _reads(rowsStopped));
  });

  /// A film crossing into its next cut takes the session's cut with it, and
  /// the whole panel is built again from above around the bar.
  ///
  /// The second cut stands two frames after the first — the conte's pull
  /// has slack on it and none on the first, the one thing its bar reads
  /// off the cut stood on.
  Future<void> aFilmCrossingACutLeavesTheBar(
    WidgetTester tester, {
    required bool storyboard,
  }) async {
    final session = await pumpEditor(tester, drawnAt: 16);
    final first = session.activeCutOrNull!.id;
    session.cutVerbs.createCut();
    await tester.pumpAndSettle();
    expect(
      session.activeCutOrNull!.id,
      isNot(first),
      reason: 'premise: a new cut is the one stood on',
    );
    session.cutShift.pushCuts(2);
    await tester.pumpAndSettle();
    session.selectCut(first);
    session.selectFrameIndex(16);
    await tester.pumpAndSettle();
    if (storyboard) {
      await showStoryboardPanel(tester);
      await tester.pumpAndSettle();
    }

    final bar = _keyedUnder<TimelineActionToolbar>(tester);
    final barRead = _readUnder<TimelineActionToolbar>(tester);
    expect(barRead.presses, isNotEmpty, reason: 'premise: a bar stands');
    final playheadBefore = playheadX(tester, storyboard: storyboard);

    session.playbackRig.playback.play(
      scope: PlaybackScope.allCuts,
      startGlobalFrame: 16,
    );
    await tester.pump();
    // The first cut is twenty-four frames: eight to its end, two of
    // nothing, six into the next.
    for (var tick = 0; tick < 16; tick += 1) {
      await tester.pump(const Duration(milliseconds: 42));
    }

    expect(
      session.activeCutOrNull!.id,
      isNot(first),
      reason: 'premise: the film crossed into its next cut',
    );
    expect(
      playheadX(tester, storyboard: storyboard),
      isNot(playheadBefore),
      reason: 'the playhead is the run\'s own, and moves with it',
    );
    expect(
      _builtAgain(bar, _keyedUnder<TimelineActionToolbar>(tester)),
      isEmpty,
      reason: 'the bar built again around them hands every button back',
    );
    expect(_readUnder<TimelineActionToolbar>(tester), _reads(barRead));

    session.playbackRig.transports.stopAll();
    await tester.pumpAndSettle();
    final second = session.activeCutOrNull!.id;
    final stoppedAt = session.currentFrameIndex;
    final barStopped = _readUnder<TimelineActionToolbar>(tester);
    expect(
      barStopped,
      isNot(_reads(barRead)),
      reason: 'the bar reads the cut the run left the session on',
    );

    // ...which is what a hand reads there.
    session.selectCut(first);
    session.selectFrameIndex(16);
    await tester.pumpAndSettle();
    expect(_readUnder<TimelineActionToolbar>(tester), _reads(barRead));
    session.selectCut(second);
    session.selectFrameIndex(stoppedAt);
    await tester.pumpAndSettle();
    expect(_readUnder<TimelineActionToolbar>(tester), _reads(barStopped));
  }

  testWidgets(
    'a film crossing into its next cut leaves the TIMELINE bar as it '
    'stood before the run',
    (tester) => aFilmCrossingACutLeavesTheBar(tester, storyboard: false),
  );

  testWidgets(
    'a film crossing into its next cut leaves the STORYBOARD bar as it '
    'stood before the run',
    (tester) => aFilmCrossingACutLeavesTheBar(tester, storyboard: true),
  );
}

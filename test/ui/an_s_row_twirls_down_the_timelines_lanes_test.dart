import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/storyboard_panel.dart';
import 'package:anicel/src/ui/timeline/transform_lane_policy.dart'
    show transformGroupHeaderLane;

/// 🚨F-101 (유저 2026-09-12): 「스토리보드패널 se랑 타임라인패널 se랑 통일
/// 안되어있음. 뭐냐면 타임라인패널 se엔 네임태그등 fx 있는데 스토리보드패널엔
/// 네임태그가 없음. 이런거 다른거 확인해서 법 하나로 통일」.
///
/// The same SE row, twirled down on both panels of the real app: the rails
/// show one list, in one order, and what a header or a take carries answers
/// on the storyboard the way it does on the timeline.
const _trackId = TrackId('twin-track');
const _seId = LayerId('twin-se');

Layer _seRow({bool clipped = false}) => Layer(
  id: _seId,
  name: 'S1',
  kind: LayerKind.se,
  frames: [
    Frame(id: const FrameId('twin-voice'), duration: 4, strokes: const []),
  ],
  timeline: {
    0: const TimelineExposure.drawing(FrameId('twin-voice'), length: 4),
  },
  audioClips: [
    AudioClip(
      filePath: 'voice.wav',
      frameId: const FrameId('twin-voice'),
      clipped: clipped,
    ),
  ],
  effects: [
    LayerEffect(
      id: const EffectId('twin-fx'),
      kind: EffectKind.brightnessContrast,
      parameters: {'brightness': EffectParameter(value: 20)},
    ),
  ],
);

Project _project({bool clipped = false}) => Project(
  id: const ProjectId('twin-project'),
  name: 'Twin Lanes',
  createdAt: DateTime.utc(2026, 9, 16),
  tracks: [
    Track(
      id: _trackId,
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('twin-cut'),
          name: 'Cut',
          duration: 12,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [
            Layer(
              id: const LayerId('twin-cel'),
              name: 'A',
              frames: const [],
              timeline: const {},
            ),
          ],
        ),
      ],
      seLayers: [_seRow(clipped: clipped)],
    ),
  ],
);

Future<void> _openApp(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1600, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(home: HomePage(initialProject: _project())),
  );
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key)).first;
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

/// The lane ids of [_seId]'s label rows under [prefix], top to bottom.
List<String> _laneIdsDownTheRail(WidgetTester tester, String prefix) {
  final rows = <({double top, String laneId})>[];
  for (final element in find
      .byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith(prefix);
      })
      .evaluate()) {
    final key = (element.widget.key! as ValueKey<String>).value;
    final box = element.renderObject! as RenderBox;
    rows.add((
      top: box.localToGlobal(Offset.zero).dy,
      laneId: key.substring(prefix.length),
    ));
  }
  rows.sort((a, b) => a.top.compareTo(b.top));
  return [for (final row in rows) row.laneId];
}

void main() {
  testWidgets('an SE row twirls down ONE list on both panels — the same '
      'lanes in the same order, the name tag and the effects included', (
    tester,
  ) async {
    await _openApp(tester);

    await _press(tester, 'timeline-lane-toggle-${_seId.value}');
    final timeline = _laneIdsDownTheRail(
      tester,
      'timeline-lane-label-${_seId.value}-',
    );

    await _press(tester, 'timeline-mode-storyboard-button');
    await _press(tester, 'storyboard-se-lane-toggle-${_trackId.value}-1');
    final storyboard = _laneIdsDownTheRail(
      tester,
      'storyboard-lane-label-${_seId.value}-',
    );

    expect(
      timeline,
      containsAll(<String>['se-audio', 'name-tag-group', 'transform-group']),
      reason: 'the timeline row carries every family this test compares',
    );
    expect(
      timeline.where((laneId) => laneId.startsWith('fx')),
      isNotEmpty,
      reason: 'and its effect',
    );
    expect(
      storyboard,
      timeline,
      reason: '「타임라인패널 se엔 네임태그등 fx 있는데 스토리보드패널엔 네임태그가 '
          '없음」 — one list, one order',
    );
  });

  testWidgets('the S row\'s Transform header switch bypasses the row\'s '
      'transform, as the timeline\'s does', (tester) async {
    await _openApp(tester);
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    bool transformOn() => session.repository
        .requireProject()
        .tracks
        .single
        .seLayers
        .single
        .transformEnabled;
    expect(transformOn(), isTrue);

    await _press(tester, 'timeline-mode-storyboard-button');
    await _press(tester, 'storyboard-se-lane-toggle-${_trackId.value}-1');
    await _press(
      tester,
      'storyboard-lane-group-fx-${_seId.value}-transform-group',
    );

    expect(
      transformOn(),
      isFalse,
      reason: 'the header wears the timeline\'s switch, and it switches',
    );
  });

  testWidgets('a clipped take wears its red corner on the S ROW with the '
      'row shut — where the timeline\'s SE row wears it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StoryboardPanel(
            project: _project(clipped: true),
            activeCutId: const CutId('twin-cut'),
            pixelsPerFrame: 12,
            projectFrameRate: ProjectFrameRate.fps24,
            seClipMarkerTooltip: 'clipped',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        ValueKey<String>(
          'storyboard-${_seId.value}-clip-marker-${_seId.value}-b0',
        ),
      ),
      findsOneWidget,
      reason: 'the marker rode the twirled-down Audio lane, so a shut row '
          'hid it',
    );
  });

  test('a Transform reset with no cut open resets nothing and throws '
      'nothing — a gap has no canvas to centre the pose on, and the '
      'storyboard\'s S rows can press it there', () {
    final session = EditorSessionManager(
      initialProject: createDefaultProject(),
    );
    addTearDown(session.dispose);
    session.cutVerbs.createCut();
    final track = session.repository.requireProject().tracks.first;
    session.repository.updateCutLeadingGap(
      cutId: track.cuts[1].id,
      leadingGapFrames: 4,
    );
    session.selectCut(track.cuts[0].id);
    session.selectGlobalFrame(track.cuts[0].duration + 1);
    expect(session.activeCutOrNull, isNull, reason: 'standing in the gap');

    final row = session.repository.requireProject().tracks.first.seLayers.first;
    expect(
      session.resetLaneGroup(row.id, transformGroupHeaderLane.laneId),
      isFalse,
    );
  });
}

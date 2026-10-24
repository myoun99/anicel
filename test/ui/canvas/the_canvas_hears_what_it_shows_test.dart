// THE CANVAS HEARS THE SESSION ONLY WHEN WHAT IT SHOWS CHANGED
// (session-news-rebuilds-unsliced ㉡, 2026-10-22): every session notify built
// the canvas area again, 77 elements and the panel laid out under them, for
// a guide picked with another tool in hand or a sheet's title typed.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/playback_mode.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_background.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/brush/main_canvas_brush_host.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

/// The project's fields nothing on the canvas reads — each with where it
/// IS read. Every other field is heard ([EditorCanvasArea.shownBy]).
const _drawnNowhereOnTheCanvas = {
  // Who the work is: its file, its tab, the export's names.
  'id', 'name', 'createdAt',
  // The sheet's: the timesheet, the conte and the envelope print it.
  'timesheetInfo',
  // The sound's: what the conforms are made at.
  'audioSampleRate',
  // The export window's own choices.
  'exportOverrides',
  // The media viewer's.
  'mediaViewerBookmarks',
};

DrawingGuide _guide(String id) => DrawingGuide(
  id: GuideId(id),
  name: id,
  shape: SymmetryShape(
    axis: GuideAxis(origin: CanvasPoint(x: 100, y: 100), angleDegrees: 90),
  ),
);

Layer _drawn(String id) => Layer(
  id: LayerId(id),
  name: id.toUpperCase(),
  frames: [
    Frame(id: FrameId('$id-1'), duration: 1, strokes: const [], name: '1'),
  ],
  timeline: {0: TimelineExposure.drawing(FrameId('$id-1'), length: 6)},
);

Project _project() => Project(
  id: const ProjectId('canvas-hears'),
  name: 'Canvas hears',
  createdAt: DateTime.utc(2026, 10, 22),
  tracks: [
    Track(
      id: const TrackId('t'),
      name: 'Video',
      cuts: [
        Cut(
          id: const CutId('c1'),
          name: 'c1',
          duration: 6,
          canvasSize: const CanvasSize(width: 640, height: 360),
          guides: CutGuides(guides: [_guide('g1'), _guide('g2')]),
          layers: [_drawn('a'), _drawn('b')],
        ),
        Cut(
          id: const CutId('c2'),
          name: 'c2',
          duration: 6,
          canvasSize: const CanvasSize(width: 640, height: 360),
          layers: [_drawn('c')],
        ),
      ],
    ),
  ],
);

/// Stands on whichever of the first cut's two rows is not stood on.
void _standOnTheOtherLayer(EditorSessionManager session) =>
    session.selectLayer(
      session.activeLayerId == const LayerId('a')
          ? const LayerId('b')
          : const LayerId('a'),
    );

void main() {
  EditorSessionManager sessionOf(Project project) {
    final session = EditorSessionManager(initialProject: project);
    addTearDown(session.dispose);
    return session;
  }

  // What the session keeps beside the project, each as one act that moves
  // it alone. A project's own fields are asked by the scan below.
  final shown = <String, void Function(EditorSessionManager session)>{
    'another layer stood on': _standOnTheOtherLayer,
    'another cut stood on': (session) => session.selectCut(const CutId('c2')),
    // Past both cuts: the canvas shows the parked stack where the cut was.
    'a gap stood in': (session) => session.parkGlobalFrame(20),
    'a cel laid by an open or an import': (session) =>
        session.renderCaches.brushFrameStore.celContentRevision.value += 1,
    'a cel\'s pixels written': (session) =>
        session.renderCaches.brushFrameStore.celPixelRevision.value += 1,
    'a layer\'s eye': (session) =>
        session.layerSwitches.toggleLayerVisibility(const LayerId('a')),
    'the paper': (session) => session.projectSettings.setProjectBackground(
      const ProjectBackground.color(0xFF336699),
    ),
  };
  for (final MapEntry(key: act, value: run) in shown.entries) {
    testWidgets('$act is shown on the canvas', (tester) async {
      final session = sessionOf(_project());
      final before = EditorCanvasArea.shownBy(session);
      run(session);
      expect(EditorCanvasArea.shownBy(session), isNot(before));
    });
  }

  // Two cuts with no rows both stand on the track's transitions: the cut
  // alone moves.
  testWidgets('another cut stood on, neither with a row, is shown on the '
      'canvas', (tester) async {
    Cut bare(String id) => Cut(
      id: CutId(id),
      name: id,
      duration: 6,
      canvasSize: const CanvasSize(width: 640, height: 360),
      layers: const [],
    );
    final session = sessionOf(
      _project().copyWith(
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'Video',
            cuts: [bare('e1'), bare('e2')],
          ),
        ],
      ),
    );
    session.selectCut(const CutId('e1'));
    final layer = session.activeLayerId;
    final before = EditorCanvasArea.shownBy(session);
    session.selectCut(const CutId('e2'));
    expect(session.activeLayerId, layer, reason: '⛔premise: the same row');
    expect(EditorCanvasArea.shownBy(session), isNot(before));
  });

  final notShown = <String, void Function(EditorSessionManager session)>{
    'a guide picked': (session) =>
        session.cutVerbs.selectedGuideId = const GuideId('g1'),
    'the sheet\'s title': (session) => session.updateTimesheetInfo(
      session.timesheetInfo.copyWith(title: 'A title of its own'),
    ),
    'the sound\'s rate': (session) =>
        session.projectAudio.setProjectAudioSampleRate(44100),
    'the playback mode': (session) =>
        session.playbackRig.setPlaybackMode(PlaybackMode.skipFrames),
  };
  for (final MapEntry(key: act, value: run) in notShown.entries) {
    testWidgets('$act is nothing the canvas shows', (tester) async {
      final session = sessionOf(_project());
      var heard = 0;
      void count() => heard += 1;
      session.addListener(count);
      final before = EditorCanvasArea.shownBy(session);
      run(session);
      session.removeListener(count);
      expect(heard, greaterThan(0), reason: '⛔premise: the session notified');
      expect(EditorCanvasArea.shownBy(session), before);
    });
  }

  test('every field of the project is heard on the canvas, or named as drawn '
      'nowhere there', () {
    final model = File('lib/src/models/project.dart').readAsStringSync();
    final start = model.indexOf(RegExp(r'^class Project\b', multiLine: true));
    final end = model.indexOf(RegExp('^}', multiLine: true), start);
    final fields = {
      for (final field in RegExp(
        r'^  final [^;=]+ (\w+);',
        multiLine: true,
      ).allMatches(model.substring(start, end)))
        field[1]!,
    };
    expect(fields, contains('tracks'), reason: '⛔premise: the fields read');

    final area = File('lib/src/ui/editor_canvas_area.dart').readAsStringSync();
    final shownBy = area.substring(
      area.indexOf('static Object shownBy('),
      area.indexOf('State<EditorCanvasArea> createState()'),
    );
    expect(
      {
        for (final field in fields)
          if (!shownBy.contains('project.$field')) field,
      },
      _drawnNowhereOnTheCanvas,
      reason:
          'a field the canvas does not hear is one it draws nowhere — a new '
          'one is heard or named here, never both',
    );
  });

  // The area hears the session through the slice, in the app: built again
  // for what it shows and for nothing else.
  testWidgets('in the app, the canvas is built again for what it shows and '
      'for nothing else, and the guides show the one picked', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: _project())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    MainCanvasBrushHost host() =>
        tester.widget<MainCanvasBrushHost>(find.byType(MainCanvasBrushHost));
    GuideId? pickedOnTheCanvas() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((paint) => paint.painter)
        .whereType<GuideOverlayPainter>()
        .single
        .selectedGuideId;
    final before = host();

    session.cutVerbs.selectedGuideId = const GuideId('g2');
    await tester.pump();
    expect(
      identical(host(), before),
      isTrue,
      reason: 'a guide picked is the guides\' to show, not the canvas\'s',
    );
    expect(pickedOnTheCanvas(), const GuideId('g2'));

    session.updateTimesheetInfo(
      session.timesheetInfo.copyWith(title: 'Titled'),
    );
    await tester.pump();
    expect(
      identical(host(), before),
      isTrue,
      reason: 'the sheet\'s title is printed on the sheet, not the canvas',
    );

    _standOnTheOtherLayer(session);
    await tester.pump();
    expect(
      identical(host(), before),
      isFalse,
      reason: 'the layer stood on is drawn on',
    );

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  });
}

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/native/engine_tile_ledger.dart';
import 'package:anicel/src/services/editing/default_cut_helpers.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart';
import '../../helpers/panel_finders.dart';

/// 🚨A STROKE'S TILES ARE THE ENGINE'S, AND NO BUILD OF THE APP READS ONE
/// BACK TO SHOW IT. A tile a stroke landed lies on the engine alone till
/// the hand rests (`EngineTileLedger.copyHereABatch`); reading it here is a
/// wait for the GPU on the thread the next stroke begins on.
///
/// ↩️Till 2026-11-20 the canvas panel did, at every stroke after the
/// first: its painter's memo compared the surface it was made for with the
/// one a commit had swapped in as RECORDS — `==`, which a surface answers
/// with its tiles' pixels (`_drawsTheSame` holds the measurement).
///
/// The whole app, and a pen: the reader was a build of the panel, which no
/// fixture below the workspace runs.
void main() {
  opensTheEnginesScreens();

  const cel = FrameId('nb-frame');

  Project aRowOfOneCel() => Project(
    id: const ProjectId('nb-project'),
    name: 'No Tile Back',
    createdAt: DateTime.utc(2026),
    tracks: [
      Track(
        id: const TrackId('nb-track'),
        name: 'Video Track',
        cuts: [
          Cut(
            id: const CutId('nb-cut'),
            name: 'No Tile Back Cut',
            duration: defaultCutDuration,
            canvasSize: defaultCutCanvasSize,
            layers: [
              Layer(
                id: const LayerId('nb-layer'),
                name: 'No Tile Back Layer',
                frames: [
                  Frame(id: cel, name: 'A', duration: 1, strokes: const []),
                ],
                timeline: {
                  0: const TimelineExposure.drawing(cel, length: 1),
                },
              ),
            ],
          ),
        ],
      ),
    ],
  );

  /// How far a stroke runs on screen from where it starts.
  const strokeRun = Offset(48, 24);

  Future<void> pumpFrames(WidgetTester tester, [int frames = 6]) async {
    for (var i = 0; i < frames; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> strokeAt(WidgetTester tester, Offset offset) async {
    final gesture = await tester.startGesture(
      visibleCanvasPoint(tester, offset: offset),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await gesture.moveBy(strokeRun / 2);
    await tester.pump();
    await gesture.moveBy(strokeRun / 2);
    await tester.pump();
    await gesture.up();
    await pumpFrames(tester);
  }

  testWidgets('strokes drawn one after another on a cel, and the builds '
      'that show them, read no tile back from the engine', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: aRowOfOneCel())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    final ledger = EngineTileLedger.instance;
    final undos = session.historyManager.undoCount;
    final slots = ledger.slotCount;
    final readBack = ledger.debugTileReads;

    // Each over the last one's tiles: the commit swaps tiles the build
    // before it showed.
    for (var stroke = 0; stroke < 4; stroke += 1) {
      await strokeAt(tester, Offset(-24, -12 + stroke * 3));
    }

    expect(
      session.historyManager.undoCount,
      undos + 4,
      reason: '⛔premise: four strokes landed',
    );
    expect(
      ledger.slotCount,
      greaterThan(slots),
      reason: '⛔premise: their tiles are the engine\'s',
    );
    expect(ledger.debugTileReads, readBack);
  });
}

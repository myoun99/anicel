import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_dab.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/brush_history_policy.dart';
import 'package:anicel/src/models/brush_tip_shape.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_frame_editing_coordinator.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart';
import '../helpers/temp_dir.dart';

/// 🚨★★★**PRESS SAVE WITH THE PEN DOWN AND THAT LINE IS IN THAT FILE.**
///
/// The store's save snapshot records each cel's edit tick, and
/// `BrushFrameStore.adoptSavedFile` refuses to mark clean anything whose
/// tick moved past it — so a stroke landing one line later is correctly
/// kept dirty for the NEXT save, and correctly missing from the file the
/// user just asked for. 유저 2026-09-10: 「그냥 스트로크 커밋시키고 저장로직
/// 발동시키면 되는거아닌가?」
///
/// ⚠️**WHAT MAKES THIS AN ORDER TEST AND NOT A 「WAS IT CALLED」 TEST.** The
/// lander below does a REAL cel commit and the assertion reads the file
/// back. Counting calls would pass just as happily with the landing moved
/// after the snapshot — which is the exact bug, and the only one worth
/// pinning here.
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anicel-pen-save-test');
  });

  tearDown(() => deleteTempQuietly(directory));

  /// A session with one drawing, and the key of the cel it made.
  (EditorSessionManager, BrushFrameKey) sessionWithADrawing() {
    final session = EditorSessionManager(initialProject: createDefaultProject());
    session.createDrawingAtCurrentFrame();
    final selection = session.editingCanvas.activeBrushEditorSelection!;
    return (
      session,
      session.brushFrameKeyForCut(
        session.requireActiveCut,
        selection.layerId,
        selection.frameId,
      ),
    );
  }

  /// Puts ink on [key] the way the canvas commit path does — what a real
  /// lander does when it lands the stroke the pen was holding.
  void inkTheCel(EditorSessionManager session, BrushFrameKey key) {
    BrushFrameEditingCoordinator(
      initialFrameKey: key,
      frameStore: session.renderCaches.brushFrameStore,
      sessionStore: BrushFrameEditSessionStore(
        canvasSize: session.requireActiveCut.canvasSize,
        tileSize: 256,
      ),
      historyPolicy: const BrushHistoryPolicy(),
    ).commitSourceStroke(
      sourceDabs: [
        BrushDab(
          center: CanvasPoint(x: 10, y: 10),
          color: 0xFF000000,
          size: 4,
          opacity: 1,
          flow: 1,
          hardness: 1,
          tipShape: BrushTipShape.round,
          pressure: 1,
          sequence: 0,
        ),
      ],
    );
  }

  test('🚨a save a PERSON asked for lands the pen first, so the file has the '
      'stroke that was still being drawn', () async {
    final (session, key) = sessionWithADrawing();
    addTearDown(session.dispose);
    var landed = 0;
    // The canvas publishes exactly this while it is mounted.
    session.liveStrokeLanding.lander = () {
      landed += 1;
      inkTheCel(session, key);
      return true;
    };

    final path = '${directory.path}/scene.anicel';
    await session.projectDoor.saveProjectToFile(
      path,
      asked: SaveAsked.byAPerson,
    );

    expect(landed, 1, reason: 'fixture premise: the lander ran');

    // ⚠️Read it back. An open replaces the whole session from the FILE, so
    // what the store answers afterwards is what the archive carried and not
    // what this session happened to still be holding.
    session.liveStrokeLanding.lander = null;
    await session.projectDoor.openProjectFromFile(path);

    expect(
      session.renderCaches.brushFrameStore.bakedSurfaceOrNull(key)?.tiles,
      isNotEmpty,
      reason: '⛔THE WHOLE ROUND: the landing has to happen BEFORE the store '
          'snapshots. Moved one line later and the save still succeeds, the '
          'lander still runs, and the file simply does not have the line — '
          'which is what the user reported',
    );
  });

  test('⛔a save the CLOCK asked for leaves the pen alone', () async {
    final (session, key) = sessionWithADrawing();
    addTearDown(session.dispose);
    var landed = 0;
    session.liveStrokeLanding.lander = () {
      landed += 1;
      inkTheCel(session, key);
      return true;
    };

    await session.projectDoor.saveProjectToFile(
      '${directory.path}/tick.anicel',
      asked: SaveAsked.byTheClock,
    );

    expect(
      landed,
      0,
      reason: 'the tick runs with no window and nobody watching, so the hand '
          'may be mid-stroke — ending it there would split one line into two '
          'with two undo entries. `AutosaveClock` holds the fire instead, and '
          'the dirty mark keeps the work for the next save',
    );
  });

  test('a save with no canvas up saves normally', () async {
    final (session, _) = sessionWithADrawing();
    addTearDown(session.dispose);
    expect(session.liveStrokeLanding.lander, isNull, reason: 'nothing registered');

    final path = '${directory.path}/headless.anicel';
    await session.projectDoor.saveProjectToFile(
      path,
      asked: SaveAsked.byAPerson,
    );

    expect(File(path).existsSync(), isTrue);
  });
}

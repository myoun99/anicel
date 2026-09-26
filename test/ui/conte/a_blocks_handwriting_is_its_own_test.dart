import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/exposure_memo.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/project_lookup.dart' show requireCut;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/storyboard_layer_policy.dart';

/// 🚨A CONTE BLOCK'S HANDWRITING IS ITS OWN.
///
/// 유저 2026-09-25 (conte-drawing-target): the part of a stroke outside the
/// picture is the BLOCK's handwriting, and blocks of the same name are not
/// linked. So a block writes on the sheet under its own id, put on it by
/// the first stroke that lands there — named before it exists, the way the
/// canvas names the cel its next press would make.
void main() {
  const cutId = CutId('1');

  /// One drawing exposed twice: two blocks of the same cel.
  EditorSessionManager session() {
    final manager = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('handwriting'),
        name: 'Conte',
        createdAt: DateTime.utc(2026, 9, 26),
        tracks: [
          Track(
            id: const TrackId('track'),
            name: 'Video',
            cuts: [
              Cut(
                id: cutId,
                name: '1',
                duration: 6,
                canvasSize: const CanvasSize(width: 64, height: 36),
                layers: [
                  Layer(
                    id: const LayerId('sb'),
                    name: 'SB',
                    kind: LayerKind.storyboard,
                    frames: [
                      Frame(
                        id: const FrameId('f'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: const {
                      0: TimelineExposure.drawing(FrameId('f'), length: 3),
                      3: TimelineExposure.drawing(FrameId('f'), length: 3),
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(manager.dispose);
    return manager;
  }

  ExposureMemo? memoAt(EditorSessionManager session, int start) =>
      storyboardLayerForCut(
        requireCut(session.repository.requireProject(), cutId),
      )!.timeline[start]!.memo;

  test('a block is named ahead ONCE — the same name until it is written, '
      'and its twin of the same cel another', () {
    final cursor = session().storyboardCursor;

    final first = cursor.conteInkIdFor(cutId, 0);

    expect(cursor.conteInkIdFor(cutId, 0), first);
    expect(cursor.conteInkIdFor(cutId, 3), isNot(first));
  });

  test('a name goes on the block it was given for — the twin\'s on the twin',
      () {
    final manager = session();
    final cursor = manager.storyboardCursor;
    cursor.conteInkIdFor(cutId, 0);
    final twin = cursor.conteInkIdFor(cutId, 3);

    cursor.writeConteBlockInk(cutId, twin);

    expect(memoAt(manager, 3)?.inkId, twin);
    expect(memoAt(manager, 0), isNull);
  });

  test('the landing puts the name on the block — one undo takes it off '
      'again, and the block keeps its ACTION throughout', () {
    final manager = session();
    final cursor = manager.storyboardCursor;
    cursor.setStoryboardCellAction(
      cutId: cutId,
      cellIndex: 0,
      action: 'ハヤト走る',
    );
    final named = cursor.conteInkIdFor(cutId, 0);

    cursor.writeConteBlockInk(cutId, named);

    expect(
      memoAt(manager, 0),
      ExposureMemo(actionMemo: 'ハヤト走る', inkId: named),
    );
    expect(memoAt(manager, 3), isNull, reason: 'its twin is not written on');
    manager.historyManager.undo();
    expect(memoAt(manager, 0), const ExposureMemo(actionMemo: 'ハヤト走る'));
    manager.historyManager.redo();
    expect(memoAt(manager, 0)?.inkId, named);
  });

  test('⚠️a name given up is never handed out again — the redo gives the '
      'block its own handwriting back, and no other block holds it', () {
    final manager = session();
    final cursor = manager.storyboardCursor;
    final named = cursor.conteInkIdFor(cutId, 0);
    cursor.writeConteBlockInk(cutId, named);
    manager.historyManager.undo();

    // Named for the first time while the first block has none: a name free
    // in the project, and still the undone one's.
    final twin = cursor.conteInkIdFor(cutId, 3);
    manager.historyManager.redo();

    expect(memoAt(manager, 0)?.inkId, named);
    expect(
      twin,
      isNot(named),
      reason: 'the twin would show the first block\'s handwriting as its own',
    );
  });

  test('🚨a stale name never overwrites a block\'s own — the redo gave the '
      'block its id back', () {
    final manager = session();
    final cursor = manager.storyboardCursor;
    final named = cursor.conteInkIdFor(cutId, 0);
    cursor.writeConteBlockInk(cutId, named);
    manager.historyManager.undo();
    final renamed = cursor.conteInkIdFor(cutId, 0);
    manager.historyManager.redo();

    cursor.writeConteBlockInk(cutId, renamed);

    expect(memoAt(manager, 0)?.inkId, named);
  });

  test('🚨a block that comes to open where a written one was deleted starts '
      'with no handwriting — the name went with the block it was put on', () {
    final manager = session();
    final cursor = manager.storyboardCursor;
    final named = cursor.conteInkIdFor(cutId, 0);
    cursor.writeConteBlockInk(cutId, named);

    manager.activeCutControllers.timelineController.deleteBlocksForLayers({
      const LayerId('sb'): [0],
    });

    expect(
      memoAt(manager, 0)?.inkId ?? '',
      isEmpty,
      reason: 'fixture: the twin slides back to open the cut',
    );
    expect(cursor.conteInkIdFor(cutId, 0), isNot(named));
  });

  test('a block written on keeps its id — writing again is no step', () {
    final manager = session();
    final cursor = manager.storyboardCursor;
    final named = cursor.conteInkIdFor(cutId, 0);
    cursor.writeConteBlockInk(cutId, named);
    final steps = manager.historyManager.undoCount;

    cursor.writeConteBlockInk(cutId, named);

    expect(manager.historyManager.undoCount, steps);
    expect(memoAt(manager, 0)?.inkId, named);
  });

  test('a name never given, or given where no block opens, writes nothing',
      () {
    final manager = session();
    final cursor = manager.storyboardCursor;
    final named = cursor.conteInkIdFor(cutId, 0);
    final nowhere = cursor.conteInkIdFor(cutId, 1);
    final steps = manager.historyManager.undoCount;

    cursor.writeConteBlockInk(cutId, 'never-named');
    cursor.writeConteBlockInk(const CutId('gone'), named);
    cursor.writeConteBlockInk(cutId, nowhere);

    expect(manager.historyManager.undoCount, steps);
    expect(memoAt(manager, 0), isNull);
  });
}

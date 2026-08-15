import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// The "+ add frames" run-edge drag (UI-R8), driven through the session's
/// own verbs.
///
/// Written when the family moved onto its drag object — and no test
/// anywhere drove these verbs before that move (found by mutating the
/// wiring: an always-refusing factory turned zero tests red). This file is
/// the family's seam: kill the wiring and something here dies.
void main() {
  /// A session with one drawing block at frame 0 on the active layer.
  EditorSessionManager sessionWithRun() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    s.createDrawingAtCurrentFrame();
    return s;
  }

  test('the drag previews on the channel, commits ONE undo, and every new '
      'frame gets a project-unique id', () {
    final s = sessionWithRun();
    addTearDown(s.dispose);
    final layer = s.activeLayer!;
    var notifies = 0;
    s.addListener(() => notifies += 1);

    expect(
      s.beginRunFramesAddDrag(
        layerId: layer.id,
        blockStartIndex: 0,
        atEnd: true,
      ),
      isTrue,
    );
    s.updateRunFramesAddDrag(3);

    // The in-flight form rides the channel; the repository stays put.
    final preview = s.dragPreview.value;
    expect(preview, isA<ExposureEdgeDragPreview>());
    final previewLayer = (preview as ExposureEdgeDragPreview).previewLayer;
    expect(previewLayer.timeline[3], isNotNull);
    expect(s.layers.firstWhere((l) => l.id == layer.id).timeline[3], isNull);
    expect(notifies, 0);

    s.endRunFramesAddDrag();
    expect(s.dragPreview.value, isNull);
    expect(notifies, 1);

    final committed = s.layers.firstWhere((l) => l.id == layer.id);
    final ids = [
      for (var i = 0; i <= 3; i++) committed.timeline[i]?.frameId,
    ];
    expect(ids, everyElement(isNotNull), reason: 'four one-frame drawings');
    expect(
      ids.toSet().length,
      ids.length,
      reason: 'reserved ids must be unique — preview == commit depends on it',
    );

    // ONE undo strips all three added frames.
    s.undo();
    final reverted = s.layers.firstWhere((l) => l.id == layer.id);
    expect(reverted.timeline[0], isNotNull);
    expect(reverted.timeline[1], isNull);
    expect(reverted.timeline[3], isNull);
  });

  test('the commit survives the display channel being cleared', () {
    // [dragPreview] is DISPLAY, shared by every drag family; a consumer may
    // clear it mid-drag. The commit reads the drag object's own stored
    // after-state.
    final s = sessionWithRun();
    addTearDown(s.dispose);
    final layer = s.activeLayer!;

    expect(
      s.beginRunFramesAddDrag(
        layerId: layer.id,
        blockStartIndex: 0,
        atEnd: true,
      ),
      isTrue,
    );
    s.updateRunFramesAddDrag(2);
    s.dragPreview.value = null; // A consumer dropped the preview.
    s.endRunFramesAddDrag();

    final committed = s.layers.firstWhere((l) => l.id == layer.id);
    expect(committed.timeline[1], isNotNull);
    expect(committed.timeline[2], isNotNull);
  });

  test('a count back at 0 commits nothing and leaves no undo', () {
    final s = sessionWithRun();
    addTearDown(s.dispose);
    final layer = s.activeLayer!;
    final undoProbe = s.canUndo;

    expect(
      s.beginRunFramesAddDrag(
        layerId: layer.id,
        blockStartIndex: 0,
        atEnd: true,
      ),
      isTrue,
    );
    s.updateRunFramesAddDrag(4);
    s.updateRunFramesAddDrag(0); // The hand came back to the edge.
    s.endRunFramesAddDrag();

    expect(s.layers.firstWhere((l) => l.id == layer.id).timeline[1], isNull);
    expect(s.canUndo, undoProbe);
  });

  test('a grip where no run starts is refused', () {
    final s = sessionWithRun();
    addTearDown(s.dispose);
    expect(
      s.beginRunFramesAddDrag(
        layerId: s.activeLayer!.id,
        blockStartIndex: 9,
        atEnd: true,
      ),
      isFalse,
    );
  });
}

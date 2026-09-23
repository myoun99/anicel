import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_frame_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// `relocateFileRefs` is what the in-place compaction (유저 2026-09-23,
/// deleting-save-compacts-Q1) waits on before it writes over bytes a cel
/// ref points at. It must move exactly the refs whose bytes moved — into
/// that file, at those offsets — and nothing else.
void main() {
  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  AnicelCelFileRef ref(String path, int dataOffset, int length) =>
      AnicelCelFileRef(
        filePath: path,
        dataOffset: dataOffset,
        length: length,
        canvasSize: const CanvasSize(width: 16, height: 16),
        tileSize: 8,
      );

  test('🎯a ref at a moved offset in THIS file reads its bytes where they '
      'went — length included (a rekeyed cel lands in a re-spliced entry)',
      () {
    final store = BrushFrameStore()
      ..restoreFromFile({
        key('a'): ref('C:/p/project.anicel', 100, 40),
        key('b'): ref('C:/p/project.anicel', 300, 50),
      });

    store.relocateFileRefs((path) => path == 'C:/p/project.anicel', {
      300: (dataOffset: 60, length: 52),
    });

    final refs = store.bakedSnapshotForSave().fileRefs;
    expect(
      (refs[key('b')]!.dataOffset, refs[key('b')]!.length),
      (60, 52),
    );
    expect(
      (refs[key('a')]!.dataOffset, refs[key('a')]!.length),
      (100, 40),
      reason: 'its bytes did not move',
    );
  });

  test('🚨a ref into ANOTHER file at the same offset stays put', () {
    final store = BrushFrameStore()
      ..restoreFromFile({
        key('a'): ref('C:/p/project.anicel', 300, 50),
        key('b'): ref('C:/elsewhere/rescued.anicel', 300, 50),
      });

    store.relocateFileRefs((path) => path == 'C:/p/project.anicel', {
      300: (dataOffset: 60, length: 50),
    });

    final refs = store.bakedSnapshotForSave().fileRefs;
    expect(refs[key('a')]!.dataOffset, 60);
    expect(
      refs[key('b')]!.dataOffset,
      300,
      reason: 'the offset matches, the file does not — those bytes did not '
          'move',
    );
  });

  test('🚨moving a ref leaves the cel as clean or dirty as it was', () {
    final store = BrushFrameStore()
      ..restoreFromFile({key('a'): ref('C:/p/project.anicel', 300, 50)});

    store.relocateFileRefs((path) => true, {
      300: (dataOffset: 60, length: 50),
    });

    expect(store.dirtyCelKeysSinceSave, isEmpty);
  });
}

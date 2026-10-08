import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/anicel_file_service.dart';
import 'package:anicel/src/services/persistence/anicel_incremental_writer.dart'
    show parseAnicelZipLayoutFile;
import 'package:anicel/src/services/persistence/anicel_project_archive.dart'
    show anicelCelEntryName;
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart'
    show
        AnicelCelBlob,
        AnicelCelEntry,
        anicelCelBinaryVersion,
        decodeCelEntry,
        encodeCelEntry;
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/project_file_door.dart' show SaveAsked;

import '../../helpers/draw_on_current_frame.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨F-304 (유저 2026-10-06): 「무거운 상태에서 저장버튼누르면 화면이 멈추고
/// … 멈추는게 아니라 뭔가 하고있다라는걸 제대로 표시하기위해」.
///
/// The save window comes up first now — but a window drawn over a frozen
/// isolate is a picture, not a spinner. What froze it was the cels still in
/// RAM: each one copied tile by tile into an entry, and the whole lot copied
/// again into the save isolate's message (🧪40 whole-canvas cels: 773ms and
/// 1,211ms of a 2,005ms block — `a_heavy_save_holds_the_screen_benchmark_
/// test`). A cel crosses the way the park road's do now, and the screen
/// gets its turn after each one.
void main() {
  test('🚨the event loop runs between two cels a save serialises', () async {
    final folder = Directory.systemTemp.createTempSync('screen-turns');
    deleteAfterSessionEnds(folder);
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    for (var i = 0; i < 3; i += 1) {
      s.cutVerbs.createCut();
      drawOnCurrentFrame(s);
    }
    final events = <String>[];
    // Something else that wants the UI isolate — a frame, a spinner — as a
    // zero timer that asks again each time it is answered, until the last
    // cel is out (past it, the isolate's own wait answers it anyway).
    var asking = true;
    AnicelFileService.debugAfterScreenTurn = () {
      events.add('cel');
      asking = events.where((event) => event == 'cel').length < 3;
    };
    addTearDown(() => AnicelFileService.debugAfterScreenTurn = null);
    void ask() {
      if (!asking) {
        return;
      }
      events.add('turn');
      Timer.run(ask);
    }

    Timer.run(ask);
    await s.projectDoor.saveProjectToFile(
      '${folder.path}/three.anicel',
      asked: SaveAsked.byAPerson,
    );
    asking = false;

    final cels = [
      for (final (index, event) in events.indexed)
        if (event == 'cel') index,
    ];
    expect(cels, hasLength(3), reason: '⛔premise: three cels in RAM');
    for (var i = 1; i < cels.length; i += 1) {
      expect(
        events.sublist(cels[i - 1], cels[i]),
        contains('turn'),
        reason: 'between cel ${i - 1} and cel $i the screen had no turn',
      );
    }
  });

  test('what lands says what the cel is: a saved cel\'s blob header is its '
      'payload\'s own', () async {
    final folder = Directory.systemTemp.createTempSync('blob-header');
    deleteAfterSessionEnds(folder);
    final path = '${folder.path}/one.anicel';
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    s.cutVerbs.createCut();
    drawOnCurrentFrame(s);
    final selection = s.editingCanvas.activeBrushEditorSelection!;
    final key = s.brushFrameKeyForCut(
      s.requireActiveCut,
      selection.layerId,
      selection.frameId,
    );
    final canvas = s.requireActiveCut.canvasSize;

    await s.projectDoor.saveProjectToFile(path, asked: SaveAsked.byAPerson);

    final entry = parseAnicelZipLayoutFile(path).entryNamed(
      anicelCelEntryName(key),
    )!;
    final file = File(path).openSync();
    addTearDown(file.closeSync);
    file.setPositionSync(entry.dataOffset);
    final blob = AnicelCelBlob(file.readSync(entry.length));
    final picture = blob.decode();
    expect(blob.key, key);
    expect(
      (blob.canvasSize, blob.tileSize),
      (picture.canvasSize, picture.tileSize),
      reason: 'the header and the payload are one answer',
    );
    expect(picture.canvasSize, canvas, reason: '⛔premise: the cut\'s canvas');
  });

  test('⛔and a cel stream from a newer build is refused by the one header '
      'reader — opened or blobbed', () {
    final payload = encodeCelEntry(
      const AnicelCelEntry(
        key: BrushFrameKey(
          projectId: ProjectId('p'),
          trackId: TrackId('t'),
          cutId: CutId('c'),
          layerId: LayerId('l'),
          frameId: FrameId('f'),
        ),
        canvasSize: CanvasSize(width: 8, height: 8),
        tileSize: 4,
        tiles: [],
      ),
    );
    expect(payload.first, anicelCelBinaryVersion, reason: '⛔premise');
    final newer = Uint8List.fromList(payload)
      ..[0] = anicelCelBinaryVersion + 1;
    expect(() => decodeCelEntry(newer), throwsFormatException);
    expect(() => AnicelCelBlob.ofPayload(newer), throwsFormatException);
    expect(AnicelCelBlob.ofPayload(payload).tileSize, 4);
  });

  test('a cel in RAM crosses as ONE serialised payload — never an entry of '
      'tile copies for the message to copy again', () {
    final source = File(
      'lib/src/services/persistence/anicel_file_service.dart',
    ).readAsStringSync();
    expect(source, contains('encodeCelEntryFromSurface('));
    expect(source, contains('TransferableTypedData.fromList('));
    expect(source, isNot(contains('AnicelCelEntry.fromSurface(')));
  });
}

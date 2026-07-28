import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/brush_drawing_binary_codec.dart';
import 'package:anicel/src/services/persistence/qap_incremental_writer.dart';
import 'package:anicel/src/services/persistence/qap_project_archive.dart';

/// R22-C incremental appender: appended entries shadow same-named ones,
/// the standard reader sees only the latest state, and cel data offsets
/// read back byte-exactly (the file-backed cold tier's contract).
void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('qap-incr');
  });

  tearDown(() => directory.delete(recursive: true));

  BrushFrameKey key(String frame) => BrushFrameKey(
    projectId: const ProjectId('p'),
    trackId: const TrackId('t'),
    cutId: const CutId('c'),
    layerId: const LayerId('l'),
    frameId: FrameId(frame),
  );

  QapCelBlob blob(String frame, int seed) {
    final pixels = Uint8List(4 * 4 * 4);
    for (var i = 0; i < pixels.length; i += 1) {
      pixels[i] = (i * seed + 3) & 0xFF;
    }
    return QapCelBlob.encode(
      QapCelEntry.fromSurface(
        key(frame),
        BitmapSurface(
          canvasSize: const CanvasSize(width: 4, height: 4),
          tileSize: 4,
          tiles: {
            TileCoord(x: 0, y: 0): BitmapTile(
              coord: TileCoord(x: 0, y: 0),
              size: 4,
              pixels: pixels,
            ),
          },
        ),
      ),
    );
  }

  test('append adds cels, shadows project.json, and the standard reader '
      'sees only the LATEST state; offsets read back byte-exactly', () {
    final path = '${directory.path}/incr.qap';
    final first = blob('f1', 1);
    File(path).writeAsBytesSync(
      buildQapArchiveBytes(project: createDefaultProject(), cels: [first]),
    );

    // Incremental save: one new cel + a superseding project.json.
    final second = blob('f2', 9);
    final layout = appendQapEntries(
      path: path,
      newEntries: {
        'cels/1.celz': second.bytes,
        'project.json': Uint8List.fromList(
          File(path).readAsBytesSync().isEmpty
              ? <int>[]
              : '{"formatVersion": $qapFormatVersion, '
                        '"project": ${'null'}}'
                    .codeUnits,
        ),
      },
    );
    // Shadowing: exactly one project.json survives.
    expect(
      layout.entries.where((entry) => entry.name == 'project.json').length,
      1,
    );

    // Round 2 append: replace cel 1's content under a NEW name and shadow
    // the old name outright.
    final third = blob('f1', 5);
    final layout2 = appendQapEntries(
      path: path,
      newEntries: {'cels/0.celz': third.bytes},
    );
    expect(
      layout2.entries.where((entry) => entry.name == 'cels/0.celz').length,
      1,
    );

    // File-backed cold tier contract: reading {dataOffset, length} yields
    // the blob bytes exactly.
    final bytes = File(path).readAsBytesSync();
    final celEntry = layout2.entryNamed('cels/1.celz')!;
    expect(
      Uint8List.sublistView(
        Uint8List.fromList(bytes),
        celEntry.dataOffset,
        celEntry.dataOffset + celEntry.length,
      ),
      second.bytes,
    );
    final replaced = layout2.entryNamed('cels/0.celz')!;
    expect(
      Uint8List.sublistView(
        Uint8List.fromList(bytes),
        replaced.dataOffset,
        replaced.dataOffset + replaced.length,
      ),
      third.bytes,
      reason: 'the shadowing entry is the one the offsets point at',
    );

    // parseQapZipLayout round trip on the appended file.
    final reparsed = parseQapZipLayout(Uint8List.fromList(bytes));
    expect(reparsed.entries.length, layout2.entries.length);
  });

  test('a file produced ONLY by full saves parses with the incremental '
      'layout reader (STORE entries, data offsets exact)', () {
    final path = '${directory.path}/full.qap';
    final cel = blob('f1', 7);
    File(path).writeAsBytesSync(
      buildQapArchiveBytes(project: createDefaultProject(), cels: [cel]),
    );
    final layout = parseQapZipLayout(
      Uint8List.fromList(File(path).readAsBytesSync()),
    );
    final entry = layout.entries.singleWhere(
      (entry) => entry.name.endsWith('.celz'),
    );
    final bytes = File(path).readAsBytesSync();
    expect(
      Uint8List.sublistView(
        Uint8List.fromList(bytes),
        entry.dataOffset,
        entry.dataOffset + entry.length,
      ),
      cel.bytes,
      reason: 'ZipEncoder STORE offsets line up with the layout parser',
    );
  });
}

import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/native/qa_video_encoder.dart';
import 'package:anicel/src/services/audio/wav16_header.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/session/trimmed_pieces.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/native_engine_path.dart';
import '../../helpers/temp_dir.dart';

/// 🚨The ROAD THE APP TAKES. `flutter_test_config.dart` cuts every piece
/// inline ([TrimmedPieces.debugCutInline]) because a widget test's clock
/// cannot await a worker — so without this file nothing would ever run the
/// cut in the isolate production uses, and a closure that reached for
/// something that cannot cross (the session, a callback holding it) would
/// only fail on a device. That exact failure shipped once already, in the
/// save's worker (2026-09-23).
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('anicel-piece-worker');
    TrimmedPieces.debugCutInline = false;
  });

  tearDown(() {
    TrimmedPieces.debugCutInline = true;
    deleteTempQuietly(tempDir);
  });

  EditorSessionManager session() {
    final s = EditorSessionManager(initialProject: createDefaultProject());
    addTearDown(s.dispose);
    return s;
  }

  String inTemp(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  test('a moving picture is encoded in a worker', () async {
    // Two frames, one pixel each: black, white.
    List<int> frame(int lzw) => [
      0x21, 0xF9, 0x04, 0x00, 0x0A, 0x00, 0x00, 0x00,
      0x2C, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
      0x02, 0x02, lzw, 0x01, 0x00,
    ];
    final gif = inTemp('two.gif');
    File(gif).writeAsBytesSync([
      ...'GIF89a'.codeUnits,
      0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
      0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF,
      ...frame(0x44), ...frame(0x4C),
      0x3B,
    ]);

    final cut = await session().trimmedPieces.cut(
      gif,
      MediaAssetKind.image,
      inFrame: 1,
    );

    expect(cut?.frames, 1);
    expect(File(cut!.path).existsSync(), isTrue);
  });

  group('with the engine', () {
    final libraryPath = nativeEngineLibraryPathOrNull();
    final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

    test('a sound is cut in a worker that finds the engine', () async {
      final samples = Int16List(48000 * 2);
      final data = samples.buffer.asUint8List();
      final wav = inTemp('line.wav');
      File(wav).writeAsBytesSync([
        ...wav16HeaderBytes(dataBytes: data.length, sampleRate: 48000, channels: 2),
        ...data,
      ]);

      final cut = await session().trimmedPieces.cut(
        wav,
        MediaAssetKind.audio,
        inFrame: 2,
        outFrame: 9,
      );

      expect(cut?.frames, 8);
    }, skip: skip);

    test('a movie is cut in a worker that finds the engine', () async {
      final encoder = QaVideoEncoder.instance;
      if (encoder == null || !encoder.isSupported) {
        return;
      }
      final movie = inTemp('take.mp4');
      expect(
        encoder.open(
          path: movie,
          width: 64,
          height: 48,
          fpsNumerator: 24,
          fpsDenominator: 1,
          sampleRate: 44100,
          channels: 2,
        ),
        isTrue,
        reason: encoder.lastError,
      );
      for (var frame = 0; frame < 6; frame += 1) {
        final rgba = Uint8List(64 * 48 * 4)..fillRange(0, 64 * 48 * 4, 128);
        expect(encoder.writeFrame(rgba), isTrue, reason: encoder.lastError);
      }
      expect(encoder.finish(), isTrue, reason: encoder.lastError);

      final cut = await session().trimmedPieces.cut(
        movie,
        MediaAssetKind.video,
        inFrame: 1,
        outFrame: 3,
      );

      expect(cut?.frames, 3);
    }, skip: skip);
  });
}

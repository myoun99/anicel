import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/native/qa_engine_abi.dart';
import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/services/persistence/media_blob_codec.dart';

import '../../helpers/encoded_movie.dart';
import '../../helpers/native_engine_path.dart';
import '../../helpers/os_video_codec.dart';
import '../../helpers/project_scratch_folder.dart';

/// 🚨★★★**A MOVIE KEPT FRAMED IS DECODED WHERE IT LIES.**
///
/// 유저 on board `carried-movie-compressed-Q1`: 「압축 유지 + 풀면서 디코더에
/// 먹이는 리더를 플랫폼마다 만든다」. The save compresses a movie that shrinks
/// (an MP4 by 6.7%), and until 2026-09-24 that made it a movie no decoder
/// could read without its original. Now the OS decoder is fed the blocks
/// decoded, through the engine's span reader — Media Foundation through an
/// `IMFByteStream` here, AVFoundation through its resource loader on the
/// macOS runner.
///
/// ⛔「It opened」 is not the assertion: a reader that served the wrong bytes
/// could still produce a picture. Every frame here is compared, byte for
/// byte, with the same movie decoded from a plain file.
void main() {
  final libraryPath = nativeEngineLibraryPathOrNull();
  final skip = libraryPath != null ? false : nativeEngineMissingSkipReason;

  setUp(() {
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = libraryPath;
  });

  tearDown(() {
    QaVideoDecoder.instance?.close();
    QaVideoDecoder.debugResetForTests();
    debugQaEngineLibraryPathOverride = null;
  });

  /// A movie made by the app's own encoder — every frame a different colour,
  /// so a frame read from the wrong place cannot pass for the right one —
  /// with a `free` box of zeros after it, so it shrinks and the writer that
  /// ships keeps it FRAMED. Null where this build cannot encode one.
  ({String plain, String framed, int framedLength})? movie() {
    final directory = Directory.systemTemp.createTempSync('qa_framed_movie');
    deleteAfterSessionEnds(directory);
    final encoded = '${directory.path}${Platform.pathSeparator}encoded.mp4';
    if (!writeEncodedMovie(
      encoded,
      frames: 8,
      picture: (frame, pixel) => (
        red: (frame * 30) & 0xFF,
        green: (pixel * 3) & 0xFF,
        blue: 255 - (frame * 30) & 0xFF,
      ),
    )) {
      return null;
    }

    // A `free` box is part of the format — every reader skips one — so the
    // movie in front of it is untouched, and a megabyte of zeros shrinks.
    const padding = 1024 * 1024;
    final box = ByteData(8)
      ..setUint32(0, 8 + padding)
      ..setUint8(4, 0x66) // f
      ..setUint8(5, 0x72) // r
      ..setUint8(6, 0x65) // e
      ..setUint8(7, 0x65); // e
    final bytes = (BytesBuilder(copy: false)
          ..add(File(encoded).readAsBytesSync())
          ..add(box.buffer.asUint8List())
          ..add(Uint8List(padding)))
        .takeBytes();
    final plain = '${directory.path}${Platform.pathSeparator}plain.mp4';
    File(plain).writeAsBytesSync(bytes);
    final written = writeMediaBlob(
      basePath: '${directory.path}${Platform.pathSeparator}carried.mp4',
      length: bytes.length,
      readInto: mediaBytesReader(bytes),
    );
    expect(written.framed, isTrue, reason: 'fixture: the free box shrinks');
    return (
      plain: plain,
      framed: written.path,
      framedLength: File(written.path).lengthSync(),
    );
  }

  test('🚨every frame of a FRAMED movie is the frame the plain file holds',
      () {
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    final made = movie();
    if (made == null) {
      return;
    }
    final plain = decoder.openDocument(made.plain)!;
    final framed = decoder.openDocument(
      made.framed,
      span: (offset: 0, length: made.framedLength, framed: true),
    );
    expect(framed, isNotNull, reason: decoder.lastError);
    expect(framed!.info.width, plain.info.width);
    expect(framed.info.height, plain.info.height);
    expect(framed.info.frameCount, plain.info.frameCount);

    // Backwards as well as forwards: a seek is where a byte stream that
    // answered the wrong window would show.
    for (final index in [0, 3, 7, 1, 6]) {
      final want = Uint8List.fromList(decoder.frameOf(plain, index)!);
      final got = decoder.frameOf(framed, index);
      expect(got, isNotNull, reason: 'frame $index: ${decoder.lastError}');
      expect(got, orderedEquals(want), reason: 'frame $index');
    }
  }, skip: skip);

  test('a framed movie INSIDE a bigger file is read from its own stretch', () {
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    final made = movie();
    if (made == null) {
      return;
    }
    // Junk on both sides, as an archive entry has its neighbours: a reader
    // that ignored the offset would find the junk.
    const prefix = 4096;
    final archive = '${made.framed}.anicel';
    final sink = File(archive).openSync(mode: FileMode.write);
    sink.writeFromSync(
      Uint8List.fromList(List.generate(prefix, (i) => (i * 13 + 7) & 0xFF)),
    );
    sink.writeFromSync(File(made.framed).readAsBytesSync());
    sink.writeFromSync(
      Uint8List.fromList(List.generate(512, (i) => (i * 29 + 3) & 0xFF)),
    );
    sink.closeSync();

    final plain = decoder.openDocument(made.plain)!;
    final carried = decoder.openDocument(
      archive,
      span: (offset: prefix, length: made.framedLength, framed: true),
    );
    expect(carried, isNotNull, reason: decoder.lastError);
    expect(
      decoder.frameOf(carried!, 5),
      orderedEquals(Uint8List.fromList(decoder.frameOf(plain, 5)!)),
    );
  }, skip: skip);

  test('⛔the same blocks read as if they were the movie are refused', () {
    final decoder = osVideoDecoderOrSkip();
    if (decoder == null) {
      return;
    }
    final made = movie();
    if (made == null) {
      return;
    }
    expect(
      decoder.openDocument(
        made.framed,
        span: (offset: 0, length: made.framedLength, framed: false),
      ),
      isNull,
      reason: 'a block index is not a container — the flag is what says how '
          'the stretch is to be read',
    );
  }, skip: skip);
}

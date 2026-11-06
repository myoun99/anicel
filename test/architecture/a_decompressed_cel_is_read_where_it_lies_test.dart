import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/source_body.dart';

/// a-collection-stops-a-frame (유저 「열 때 생기는 쓰레기를 줄인다」): a
/// cel's decompressed bytes are read where the engine put them and freed
/// when the read is done — not copied onto the Dart heap
/// (`QaCelCompressor.readFrame`).
///
/// ⚠️A SOURCE PIN, because a copy reads back the same bytes: what tells the
/// two apart is old-space garbage — 🔬~825MB from opening S5_BA to a cut's
/// pre-bake (타임라인/콘티, profile build, 2026-11-05) — which no test here
/// can see. That the bytes live only while their reader runs is pinned by
/// behaviour (`cel_blob_codec_test.dart`).
void main() {
  test('the zstd door hands its reader the native block, copies none of '
      'it, and frees it', () {
    final body = sourceBodyOf(
      File('lib/src/native/qa_cel_compressor.dart').readAsStringSync(),
      'R? readFrame<',
    );
    expect(body, contains('return read(dst.asTypedList(size));'));
    expect(body, isNot(contains('fromList')));
    expect(body, contains('malloc.free(dst);'));
  });
}

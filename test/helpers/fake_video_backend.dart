import 'dart:typed_data';

import 'package:anicel/src/native/qa_video_decoder.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';

/// A movie, without a movie — what makes the viewer's VIDEO arm reachable
/// on the bench at all.
///
/// 🚨★★★**THE WHOLE VIDEO ARM WAS UNMEASURED UNTIL THIS EXISTED** (card
/// `video-viewer-arm-is-unmeasured`). `debugVideoDecodeBackend` had been
/// there the whole time, and it was never enough: `VideoViewerDocument`
/// asked `QaVideoDecoder.instance` whether a reader existed, so on a
/// machine without the native library the gate said no and the injected
/// backend was never consulted. Moving that question onto the backend
/// ([VideoDecodeBackend.supported]) is what opened the door; this walks
/// through it.
class FakeVideoBackend implements VideoDecodeBackend {
  FakeVideoBackend({
    this.supported = true,
    this.frameCount = 12,
    this.fpsNumerator = 24,
    this.fpsDenominator = 1,
    this.width = 64,
    this.height = 36,
  });

  final int frameCount;
  final int fpsNumerator;
  final int fpsDenominator;
  final int width;
  final int height;

  /// Frames that will NOT come back — the buffer running dry, which is the
  /// state the viewer's law is about.
  final Set<int> held = <int>{};

  /// Every frame that was actually asked for, in order.
  final List<int> asked = <int>[];

  /// What this backend answers to 「can this build read a movie」.
  ///
  /// ⚠️Settable so a test can say NO while the machine running it has a
  /// native engine sitting right there — which is the only way to prove
  /// that the document asks the BACKEND and not the decoder. Taking the
  /// real engine away does not work: it is already loaded, and
  /// `openQaEngineLibrary` finds it by bare name whatever the override
  /// says (measured 2026-09-08).
  @override
  final bool supported;

  @override
  Future<({int token, QaVideoInfo info})?> open(
    String path, {
    ({int offset, int length})? range,
  }) async => (
    token: 1,
    info: QaVideoInfo(
      width: width,
      height: height,
      frameCount: frameCount,
      fpsNumerator: fpsNumerator,
      fpsDenominator: fpsDenominator,
    ),
  );

  @override
  Future<Uint8List?> frame(int token, int index) async {
    asked.add(index);
    if (held.contains(index)) {
      return null;
    }
    // Straight RGBA, opaque — the viewer only needs it to decode.
    return Uint8List.fromList(
      List<int>.filled(width * height * 4, 0xFF),
    );
  }

  @override
  Future<String> lastError() async => 'fake backend';

  @override
  Future<void> close(int token) async {}
}

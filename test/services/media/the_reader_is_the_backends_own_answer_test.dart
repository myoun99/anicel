import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';
import 'package:anicel/src/services/media/video_decode_worker.dart';
import 'package:anicel/src/services/media/video_viewer_document.dart';

import '../../helpers/fake_video_backend.dart';

/// 🚨★★★**「이 빌드가 영상을 읽을 수 있나」는 읽는 쪽이 답한다.**
///
/// `VideoViewerDocument` used to ask `QaVideoDecoder.instance?.isSupported`
/// while doing its actual reading through [VideoDecodeBackend] — one object
/// for the work and another for the permission. Two answers to one
/// question, and they part company the moment the backend is anything but
/// the default.
///
/// ⛔What that cost was not theoretical: it made the WHOLE video arm of the
/// viewer unmeasurable. `debugVideoDecodeBackend` had been there for
/// injecting a fake, and the gate in front of it answered from the native
/// library, so on any machine without one the fake was never consulted and
/// on a machine WITH one the fake was pointless. Card
/// `video-viewer-arm-is-unmeasured`, closed by moving the question.
void main() {
  const clip = MediaFileBytes('C:/work/clip.mp4');

  tearDown(() => debugVideoDecodeBackend = null);

  test('a backend that says NO means no document, whatever the machine has '
      'installed', () async {
    debugVideoDecodeBackend = FakeVideoBackend(supported: false);

    expect(
      await VideoViewerDocument.open(clip),
      isNull,
      reason: '⚠️THIS MACHINE MAY HAVE A REAL ENGINE, and that is the point: '
          'if the document still asked the decoder, this would open and the '
          'backend seam would be decoration',
    );
  });

  test('and a backend that says YES opens one, with no engine involved', () async {
    debugVideoDecodeBackend = FakeVideoBackend(frameCount: 7);

    final document = await VideoViewerDocument.open(clip);
    expect(document, isNotNull);
    expect(document!.pageCount, 7);
    await document.dispose();
  });
}

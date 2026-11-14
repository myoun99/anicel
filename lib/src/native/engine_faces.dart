import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:gpu_engine/gpu_engine.dart';

import '../ui/theme/app_theme.dart' show AppTypography;

/// THE FACES THE GPU ENGINE SETS LETTERS IN: the app's bundled families
/// ([AppTypography.canvasLetterFaces] — BIZ UDPGothic, 나눔고딕, Noto Sans
/// SC) read from its bundle once, as one [GpuFaces] the process keeps.
///
/// ⚠️ONE COPY OF THE FILES: they are 35 MB (BIZ UDPGothic 9.3, 나눔고딕
/// 4.1, Noto Sans SC 21.7), held from the first letters the engine sets to
/// the process' end — a second [GpuFaces] read from the bundle again would
/// hold them twice.
abstract final class EngineFaces {
  /// The bundled families, in [AppTypography.canvasLetterFaces]' order.
  ///
  /// ⚠️THE FACES ARE KEPT, NOT THE FUTURE OF THEM: a future answers whoever
  /// awaits it in the zone it was made in, and that zone may be gone — each
  /// widget test runs in one of its own, and a second test awaiting the
  /// first one's future never woke (11-08).
  static Future<GpuFaces> bundled() async =>
      _bundled ??= await (_reading ??= read());
  static GpuFaces? _bundled;
  static Future<GpuFaces>? _reading;

  /// The bundled families read anew — what [bundled] keeps; a test's own
  /// read is kept by no one. Each file handed to the engine as soon as the
  /// bundle has read it, so the copy it costs falls in the turn its read
  /// ends and not all six in one ([GpuFacesHanding]).
  @visibleForTesting
  static Future<GpuFaces> read() async {
    final handing = GpuFacesHanding();
    for (final (family, face) in AppTypography.canvasLetterFaces.indexed) {
      for (final file in face.files) {
        handing.add(family, Uint8List.sublistView(await rootBundle.load(file)));
      }
    }
    return handing.done();
  }
}

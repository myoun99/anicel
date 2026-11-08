import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/services.dart' show rootBundle;
import 'package:gpu_engine/gpu_engine.dart';

import '../ui/theme/app_theme.dart' show AppTypography;

/// THE FACES THE GPU ENGINE SETS LETTERS IN: the app's bundled families
/// ([AppTypography.canvasLetterFaces] — BIZ UDPGothic, 나눔고딕, Noto Sans
/// SC) read from its bundle once, as one [GpuFaces] the process keeps, and
/// laid in whatever order of them a style goes down — the canvas letters'
/// own, or the UI's, which a Chinese UI begins with Noto Sans SC
/// ([AppTypography.fallbackFor]) — sharing those files
/// ([GpuFaces.ordered]).
///
/// ⚠️ONE COPY OF THE FILES: they are 31 MB (BIZ UDPGothic 9.3, 나눔고딕
/// 4.1, Noto Sans SC 17.7), held from the first letters the engine sets to
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
      _bundled ??= await (_reading ??= _read());
  static GpuFaces? _bundled;
  static Future<GpuFaces>? _reading;

  static Future<GpuFaces> _read() async => GpuFaces([
    for (final face in AppTypography.canvasLetterFaces)
      [
        for (final file in face.files)
          Uint8List.sublistView(await rootBundle.load(file)),
      ],
  ]);

  /// The bundled families [families] names, in its order — made the first
  /// time that order is asked for and kept. Throws [UnsupportedError] for a
  /// family the app does not bundle: the engine is handed no other face.
  static Future<GpuFaces> inOrderOf(List<String> families) async {
    final all = await bundled();
    final order = [for (final family in families) _placeOf(family)];
    if (listEquals(order, _bundledOrder)) {
      return all;
    }
    return _ordered[order.join(',')] ??= all.ordered(order);
  }

  static final Map<String, GpuFaces> _ordered = {};

  static final List<int> _bundledOrder = [
    for (final (place, _) in AppTypography.canvasLetterFaces.indexed) place,
  ];

  static int _placeOf(String family) {
    final place = AppTypography.canvasLetterFaces.indexWhere(
      (face) => face.family == family,
    );
    if (place < 0) {
      throw UnsupportedError(
        'letters in a face the engine is not handed: $family',
      );
    }
    return place;
  }
}

import 'dart:typed_data';

import 'package:gpu_engine/gpu_engine.dart' show GpuMask;

import '../models/brush_stamp_image.dart';

/// The stamps made of a mask rather than of a picture (stamp.rs
/// `Source::Mask`): a selection's erase (`selectionEraseDab`) — the
/// selection's own mask on the engine, a pixel it covers at all taken
/// wholly where `whole`, else by its byte. The engine lays one from that
/// mask ([GpuStampLanding.landMask]); its bytes are built here only for
/// what reads them here ([BrushStampImage.rgba]).
///
/// ↩️Till 2026-11-14 the erase was a picture: the CPU made the selection's
/// mask, built an RGBA image of it and handed it up, at every lift and every
/// cut that takes — as much work as the selection is large (board
/// `a-selection-mask-is-built-on-the-cpu-at-every-move`).
abstract final class EngineStampMasks {
  static final Expando<({GpuMask Function() coverage, bool whole})> _of =
      Expando();

  /// A stamp named [id], [width] × [height], made of what [coverage] makes
  /// on the engine — taken wholly where [whole] — and of [rgba] for what
  /// reads its bytes here.
  static BrushStampImage made({
    required String id,
    required int width,
    required int height,
    required GpuMask Function() coverage,
    required bool whole,
    required Uint8List Function() rgba,
  }) {
    final stamp = BrushStampImage.read(
      id: id,
      width: width,
      height: height,
      rgba: rgba,
    );
    _of[stamp] = (coverage: coverage, whole: whole);
    return stamp;
  }

  /// What [stamp] is made of on the engine — null where it is a picture
  /// (`EngineStampPictures`).
  static ({GpuMask Function() coverage, bool whole})? of(
    BrushStampImage stamp,
  ) => _of[stamp];
}

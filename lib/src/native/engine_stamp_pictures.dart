import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../models/brush_stamp_image.dart';
import 'app_gpu_engine.dart';

/// The pictures of the stamps the engine lands, each on it once: a selection
/// moved lands the same one at each step of the drag. On the engine the
/// app has: a stamp is handed up again to the next one, once the app lets
/// this one go ([KeptOnTheAppsEngine]).
abstract final class EngineStampPictures {
  static final _pictures = KeptOnTheAppsEngine<Expando<GpuStampPicture>>();

  static Expando<GpuStampPicture> get _of => _pictures.of(Expando.new);

  /// [stamp]'s picture: its bytes handed over the first time it is asked
  /// for, or what the engine made it as ([carried]).
  static GpuStampPicture of(BrushStampImage stamp) =>
      _of[stamp] ??= _handedUp(stamp);

  static GpuStampPicture _handedUp(BrushStampImage stamp) {
    debugHandedUp += 1;
    return GpuStampPicture(
      appGpuEngine,
      stamp.rgba,
      stamp.width,
      stamp.height,
    );
  }

  /// Test seams: the stamps whose bytes were handed over, and the carried
  /// ones whose bytes were read back — the pin that a float carried over a
  /// posed row hands its picture up once, and that no step of the hand
  /// hands one up or reads one back.
  @visibleForTesting
  static int debugHandedUp = 0;
  @visibleForTesting
  static int debugReadBack = 0;

  /// [stamp] carried through [inverse] — a point of the output to [stamp]'s,
  /// the nine of a `ResampleTransform` — over an output [width] × [height],
  /// as [GpuStampLanding.carried] says: a stamp named [id] that is the
  /// engine's picture of the whole output, or of its [window]. It lands
  /// without its bytes ever coming here; what asks for them
  /// ([BrushStampImage.rgba]) reads them from the engine, once.
  ///
  /// 🗣️gpu-canonical-store ⑪ (관제 2026-11-10 18:14: 「자세 있음 … 선 =
  /// master 이하」) — 🔬a 26.7 MB stamp crossing a posed row on the CPU and
  /// coming up again was 87–112 ms of every step of the hand that carried
  /// it, main PC, 2026-11-11.
  static BrushStampImage carried(
    BrushStampImage stamp, {
    required String id,
    required List<double> inverse,
    required double radiusFloor,
    required GpuSampling sampling,
    required int width,
    required int height,
    (int, int, int, int)? window,
  }) => _kept(
    appGpuStampLanding.carried(
      of(stamp),
      inverse: inverse,
      radiusFloor: radiusFloor,
      sampling: sampling,
      width: width,
      height: height,
      window: window,
    ),
    id: id,
  );

  /// [stamp], its top-left pixel at [at] on the canvas, through a mesh as
  /// [GpuStampLanding.meshed] says: a stamp named [id] that is the engine's
  /// picture of [window] of the canvas, landed and read as [carried]'s.
  static BrushStampImage meshed(
    BrushStampImage stamp, {
    required String id,
    required (double, double) at,
    required int columns,
    required int rows,
    required List<double> source,
    required List<double> destination,
    required double radiusFloor,
    required GpuSampling sampling,
    required (int, int, int, int) window,
  }) => _kept(
    appGpuStampLanding.meshed(
      of(stamp),
      at: at,
      columns: columns,
      rows: rows,
      source: source,
      destination: destination,
      radiusFloor: radiusFloor,
      sampling: sampling,
      window: window,
    ),
    id: id,
  );

  /// [picture], the engine made, as a stamp named [id] whose bytes are read
  /// from there the first time they are asked for.
  static BrushStampImage _kept(GpuStampPicture picture, {required String id}) {
    final made = BrushStampImage.read(
      id: id,
      width: picture.width,
      height: picture.height,
      rgba: () {
        debugReadBack += 1;
        return picture.pixels();
      },
    );
    _of[made] = picture;
    return made;
  }
}

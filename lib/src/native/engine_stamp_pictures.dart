import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:gpu_engine/gpu_engine.dart';

import '../models/brush_stamp_image.dart';
import 'app_gpu_engine.dart';

/// The pictures of the stamps the engine lands, each on it once: a selection
/// moved lands the same one at each step of the drag. On the engine the
/// app has ([KeptOnTheAppsEngine]): once the app lets this one go, a stamp
/// is handed up again to the next — and one the engine made is made again
/// there, as it was made ([_makes]).
abstract final class EngineStampPictures {
  static final _pictures = KeptOnTheAppsEngine<Expando<GpuStampPicture>>();

  static Expando<GpuStampPicture> get _of => _pictures.of(Expando.new);

  /// What makes the picture of each stamp the engine made ([carried],
  /// [meshed]), on the engine the app has by then: of the stamp it was made
  /// of — whose bytes are here, or which the engine made in its turn — and
  /// the numbers it was made by.
  ///
  /// 🗣️gpu-canonical-store-Q11 (유저 2026-11-10): 「RAM 에 사본을 두고 앱을
  /// 유지한다」 — 「잃는 것은 그리던 획 정도다」. The bytes of a stamp the
  /// engine made never came here, so a float carried over a posed row, or
  /// warped, was lost with its device. Every such stamp is made of bytes
  /// that ARE here, so what is kept is the making, not a copy read back:
  /// nothing waits for a clock to be safe, and nothing is read from the GPU
  /// that nothing asked the bytes of.
  static final Expando<GpuStampPicture Function()> _makes = Expando();

  /// [stamp]'s picture: what the engine made it as ([carried], [meshed]),
  /// or its bytes handed over the first time it is asked for.
  static GpuStampPicture of(BrushStampImage stamp) =>
      _of[stamp] ??= _makes[stamp]?.call() ?? _handedUp(stamp);

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
  }) {
    final through = List<double>.unmodifiable(inverse);
    return _made(
      () => appGpuStampLanding.carried(
        of(stamp),
        inverse: through,
        radiusFloor: radiusFloor,
        sampling: sampling,
        width: width,
        height: height,
        window: window,
      ),
      id: id,
    );
  }

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
  }) {
    final rest = List<double>.unmodifiable(source);
    final dragged = List<double>.unmodifiable(destination);
    return _made(
      () => appGpuStampLanding.meshed(
        of(stamp),
        at: at,
        columns: columns,
        rows: rows,
        source: rest,
        destination: dragged,
        radiusFloor: radiusFloor,
        sampling: sampling,
        window: window,
      ),
      id: id,
    );
  }

  /// What [make] makes on the engine, as a stamp named [id] whose bytes are
  /// read from there the first time they are asked for — and which [make]
  /// makes again on the next engine ([_makes]): its numbers are its own
  /// from here, nothing writes them after.
  static BrushStampImage _made(
    GpuStampPicture Function() make, {
    required String id,
  }) {
    final picture = make();
    late final BrushStampImage made;
    made = BrushStampImage.read(
      id: id,
      width: picture.width,
      height: picture.height,
      rgba: () {
        debugReadBack += 1;
        return of(made).pixels();
      },
    );
    _of[made] = picture;
    _makes[made] = make;
    return made;
  }
}

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart' show Rect;
import 'package:gpu_engine/gpu_engine.dart' show GpuWaveView;

import '../../native/app_gpu_engine.dart';
import '../../native/engine_wave_peaks.dart';
import '../../services/audio/audio_peaks_extractor.dart';
import '../timeline/timeline_grid_screen.dart';
import '../timeline/timeline_grid_tile_picture.dart';

/// A sound's peaks and the views the waveform pass draws it by
/// ([engineWaveViewsOf]), in turn.
typedef EngineWaveDrawing = ({AudioPeaks peaks, List<GpuWaveView> views});

/// Sounds' bands baked on the engine into one picture and laid on the
/// grid's screen the slot painting them lays on ([TimelineGridScreenSlot]) —
/// how a band is drawn where no row's tile holds it: the viewer's face, the
/// offset strip. One picture: the screen's lay writes what it lays, it does
/// not draw it over what is there, so two bands laid over each other would
/// leave one.
///
/// Kept while what it was baked of stays the same, let go of with the
/// engine it was baked on, and by its owner ([letGo]).
final class EngineWaveBand {
  EngineWaveBand() {
    _onTheEngine.start();
  }

  late final StandsOnTheAppsEngine _onTheEngine = StandsOnTheAppsEngine(
    letGo: _drop,
  );

  TimelineGridTilePicture? _picture;
  List<Object>? _bakedOf;

  /// Lays [bands] baked into one picture onto [onto] of the painting slot,
  /// [devicePixelRatio] device pixels to a logical one — true where it laid
  /// them, false where no screen lays there or the engine makes no such
  /// picture: its painter draws them itself.
  bool layOn(
    Rect onto,
    List<EngineWaveDrawing> bands,
    double devicePixelRatio,
  ) {
    final laying = TimelineGridScreenSlot.laying;
    if (laying == null) {
      return false;
    }
    final width = (onto.width * devicePixelRatio).ceil();
    final height = (onto.height * devicePixelRatio).ceil();
    if (width <= 0 || height <= 0) {
      return true;
    }
    final bakedOf = <Object>[
      width,
      height,
      for (final (:peaks, :views) in bands) ...[peaks, ...views],
    ];
    var picture = _picture;
    if (picture == null || !listEquals(bakedOf, _bakedOf)) {
      final baked = _baked(width, height, bands);
      if (baked == null) {
        return false;
      }
      _drop();
      _picture = picture = baked;
      _bakedOf = bakedOf;
    }
    laying.lay((
      picture: picture,
      from: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      onto: Rect.fromLTWH(
        onto.left,
        onto.top,
        width / devicePixelRatio,
        height / devicePixelRatio,
      ),
    ));
    return true;
  }

  static TimelineGridTilePicture? _baked(
    int width,
    int height,
    List<EngineWaveDrawing> bands,
  ) {
    final batch = appGpuGridKernels.kept.batch;
    final picture = batch.picture(width, height);
    if (picture == null) {
      return null;
    }
    for (final (:peaks, :views) in bands) {
      for (final view in views) {
        batch.wave(picture, EngineWavePeaks.of(peaks), view);
      }
    }
    return TimelineGridTilePicture(picture);
  }

  void _drop() {
    _picture?.letGo();
    _picture = null;
    _bakedOf = null;
  }

  /// Lets go of what it keeps, and hears the engine no more.
  void letGo() {
    _onTheEngine.stop();
    _drop();
  }
}

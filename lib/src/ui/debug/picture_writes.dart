import 'measurement_mode.dart';

/// How a change of the frame shown went onto the screen: into the picture
/// shown where it is ([inPlace]), into a copy of it where another screen
/// shows it too ([copied] — every tile of it copied first), or the frame
/// laid whole on a view's own screen, no picture shown ([whole]).
enum PictureWrite { inPlace, copied, whole }

/// The writes of each [PictureWrite] counted so far.
typedef PictureWritesCounted = ({int inPlace, int copied, int whole});

/// 🔬HOW THE PICTURES OF THE FRAMES SHOWN TOOK THEIR CHANGES, counted
/// (`EngineFramePictureStore.patch`, `FramePictureView`'s screen of its
/// own) — what a stroke's first step and its landing did, read across
/// their frames (`StrokeSteps`). Nothing is counted while the frame
/// statistics are off.
///
/// 🗣️유저 2026-11-23 on a Galaxy Tab (card
/// the-start-of-every-stroke-stalls-on-the-galaxy-tab, H67): the start of
/// every stroke stalls, then draws — and the code has three ways to take a
/// step that cost a tile, a picture or a frame, none of them on the screen.
abstract final class PictureWrites {
  static final List<int> _counted = List<int>.filled(
    PictureWrite.values.length,
    0,
  );

  /// The writes counted so far, by how each went.
  static PictureWritesCounted get counted => (
    inPlace: _counted[PictureWrite.inPlace.index],
    copied: _counted[PictureWrite.copied.index],
    whole: _counted[PictureWrite.whole.index],
  );

  /// A change of a frame shown went onto the screen [how].
  static void wrote(PictureWrite how) {
    if (!MeasurementMode.frameStats.value) {
      return;
    }
    _counted[how.index] += 1;
  }
}

import 'dart:ui' as ui;

import '../../models/cut_id.dart';
import '../../models/rgba_image_bytes.dart';
import '../../services/playback/cut_frame_composite_signature.dart';
import '../../services/playback/frame_demand.dart';
import 'cut_frame_composite_cache.dart';

/// What a frame's picture is made of, where the screen that shows it looks
/// for it — asked by the one maker of playback's pictures, and through it by
/// a run that waits for one and the ruler's bar that counts them, so none of
/// them can mean a different picture from the one the screen draws
/// (playback-plays-the-screen-material).
abstract interface class PlaybackPictures {
  /// Whether [picture] is there to show.
  bool has(DemandedPicture picture);

  /// Whether making [picture] threw at the content it has now — it is not
  /// waited for, nor made again until that content changes ([noteFailure]).
  bool failed(DemandedPicture picture);

  /// Remembers that making [picture] threw at the content it has now.
  void noteFailure(DemandedPicture picture);

  /// The bytes making [picture] would add.
  int bytesToMake(DemandedPicture picture);

  /// The bytes [picture] holds that [seen] has not counted, which it adds to
  /// [seen]: a walk weighs the window it has passed over by this, each
  /// picture's parts counted once however many frames show them.
  int weighNew(DemandedPicture picture, Set<Object> seen);

  /// Makes [picture]: true when it landed, false when [shouldAbort] stood it
  /// down. Throws where its content cannot be read.
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
  });
}

/// The pictures the screen shows a frame from NOW — whichever [shown]
/// answers, asked afresh at every question, so the one maker follows the
/// screen as it changes (the camera view turned on, the film started). The
/// owner wakes the maker from the start when the answer changes: what it had
/// walked over was counted in the other pictures.
class ShownPictures implements PlaybackPictures {
  ShownPictures(this.shown);

  final PlaybackPictures Function() shown;

  @override
  bool has(DemandedPicture picture) => shown().has(picture);

  @override
  bool failed(DemandedPicture picture) => shown().failed(picture);

  @override
  void noteFailure(DemandedPicture picture) => shown().noteFailure(picture);

  @override
  int bytesToMake(DemandedPicture picture) => shown().bytesToMake(picture);

  @override
  int weighNew(DemandedPicture picture, Set<Object> seen) =>
      shown().weighNew(picture, seen);

  @override
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
  }) => shown().make(picture, shouldAbort: shouldAbort);
}

/// A cut's frame as ONE picture, the cut's own size ([CutFrameCompositeCache])
/// — what the track stack shows: the whole film.
class CompositePictures implements PlaybackPictures {
  CompositePictures(this.composites);

  final CutFrameCompositeCache composites;

  /// Frames whose composite threw, and the content signature they threw
  /// at — the warm's half of the layer stack's `_failedRevisions`.
  ///
  /// A throwing compose caches nothing, so the frame can never read as
  /// there; and the walk starts over shortly after every stroke. Without
  /// this, one unreachable cel is re-opened, re-thrown and re-reported once
  /// per walk, on every stroke, for the life of the session — a blocking
  /// file open each time, which is the hot loop the sibling record exists to
  /// stop. The signature comes from the composite cache so "has this frame
  /// changed" stays one rule rather than two.
  final Map<(CutId, int), CutFrameCompositeSignature> _failedSignatures = {};

  /// The store generation those records belong to. A project OPEN bumps
  /// it — the one moment a cel the filesystem refused can have become
  /// readable — and dropping the map there is also what stops it growing
  /// for the life of the session.
  int _failedSignaturesGeneration = 0;

  void _forgetStaleFailures() {
    final generation = composites.frameStore.celContentRevision.value;
    if (generation == _failedSignaturesGeneration) {
      return;
    }
    _failedSignaturesGeneration = generation;
    _failedSignatures.clear();
  }

  ui.Image? _imageOf(DemandedPicture picture) => composites
      .validCompositeOrNull(cut: picture.cut, frameIndex: picture.frameIndex);

  @override
  bool has(DemandedPicture picture) => _imageOf(picture) != null;

  @override
  bool failed(DemandedPicture picture) {
    _forgetStaleFailures();
    final failed = _failedSignatures[(picture.cut.id, picture.frameIndex)];
    return failed != null &&
        failed ==
            composites.signatureOf(
              cut: picture.cut,
              frameIndex: picture.frameIndex,
            );
  }

  @override
  void noteFailure(DemandedPicture picture) {
    _forgetStaleFailures();
    _failedSignatures[(picture.cut.id, picture.frameIndex)] = composites
        .signatureOf(cut: picture.cut, frameIndex: picture.frameIndex);
  }

  @override
  int bytesToMake(DemandedPicture picture) => estimatedImageBytes(
    picture.cut.canvasSize.width,
    picture.cut.canvasSize.height,
  );

  /// Held exposures share one composite, so they are one part.
  @override
  int weighNew(DemandedPicture picture, Set<Object> seen) {
    final shown = _imageOf(picture);
    if (shown == null || !seen.add(shown)) {
      return 0;
    }
    return estimatedImageBytes(shown.width, shown.height);
  }

  @override
  Future<bool> make(
    DemandedPicture picture, {
    required bool Function() shouldAbort,
  }) async =>
      await composites.prepareCompositeInterruptible(
        cut: picture.cut,
        frameIndex: picture.frameIndex,
        shouldAbort: shouldAbort,
      ) !=
      null;
}

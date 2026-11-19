import 'package:flutter/foundation.dart';

import '../../models/cut.dart' show Cut;
import '../../models/cut_id.dart';
import '../../models/onion_skin_settings.dart' show OnionSkinPlacement;
import '../../services/playback/frame_demand.dart'
    show DemandedPicture, standingPicturesOf;
import '../playback/frame_pictures.dart' show FramePictures;
import '../playback/moves_wait_for_their_pictures.dart';
import '../playback/playback_pictures.dart' show PictureState;

/// 🚨★★★A CANVAS THAT STANDS GOES TO A FRAME WITH ITS PICTURE — the law of
/// [MovesWaitForTheirPictures], its places the frames of the project's
/// cuts: a move of the playhead to a frame whose pictures are not there
/// leaves the session standing on the frame it shows — the playhead, the
/// timeline's current cell and the frame number with it — and lands, all
/// of it together, once they are. They are made at once, at the front of
/// the store's line ([FramePictures.makeShown]).
///
/// ↩️The playhead went at once and the canvas composed the frame as it
/// stood, at the canvas's own resolution, until its picture came: the same
/// frame composed twice, one after the other (🔬Surface Pro 11, S5_BA cut
/// 352: move → picture on screen p50 58 ms, 28 ms without, 11-18).
class StandsWithItsPicture extends MovesWaitForTheirPictures {
  StandsWithItsPicture({
    required FramePictures Function() pictures,
    required Cut? Function() cut,
    required Cut? Function(CutId) cutById,
    required int Function() frame,
    required OnionSkinPlacement Function() placement,
  }) : this._(
         _CanvasFrames(
           pictures: pictures,
           cut: cut,
           cutById: cutById,
           frame: frame,
           placement: placement,
         ),
       );

  StandsWithItsPicture._(_CanvasFrames frames)
    : _frames = frames,
      super(stood: frames.stood, isThere: frames.isThere, make: frames.make);

  final _CanvasFrames _frames;

  /// Moves the playhead to [frame] of [inCut] — of the cut stood in, where
  /// none is named: [land] now, where its pictures are there or nothing
  /// shows them; once they are, else. The move after replaces it.
  ///
  /// 🗣️Q3 = stand (유저 2026-11-18 13:43, 「컷도 앞 컷에 서 있는다」): a move
  /// into another cut waits as one within a cut does — the cut, its row
  /// and the frame stand where they are until the frame it goes to is
  /// made, and land together. ↩️A cut switch landed at once, and the canvas
  /// composed the new cut's frame as it stood until its picture came.
  void moveTo(int frame, VoidCallback land, {CutId? inCut}) {
    final stood = _frames.cut();
    final into = inCut == null || inCut == stood?.id
        ? stood
        : _frames.cutById(inCut);
    moveToPlace(into == null ? null : (scope: into.id, at: frame), land);
  }

  /// The cut a move that waits goes into, where it is not the one stood in:
  /// null while none waits, or one waits within the cut stood in.
  CutId? get cutWaitedFor => switch (waiting) {
    (:final from, :final to) when to.scope != from.scope => to.scope as CutId,
    _ => null,
  };
}

/// The canvas's places: a frame of a cut, its pictures the store's
/// ([FramePictures]).
final class _CanvasFrames {
  _CanvasFrames({
    required FramePictures Function() pictures,
    required this.cut,
    required this.cutById,
    required int Function() frame,
    required OnionSkinPlacement Function() placement,
  }) : _pictures = pictures,
       _frame = frame,
       _placement = placement;

  final FramePictures Function() _pictures;
  final Cut? Function() cut;

  /// The cut with an id, anywhere in the project — where a move goes.
  final Cut? Function(CutId) cutById;

  final int Function() _frame;
  final OnionSkinPlacement Function() _placement;

  /// The frame the session stands on, in the cut stood in.
  PicturePlace? stood() => switch (cut()) {
    final cut? => (scope: cut.id, at: _frame()),
    null => null,
  };

  /// Whether every picture a canvas standing on [place] shows is there, or
  /// will not come.
  bool isThere(PicturePlace place) {
    final cut = cutById(place.scope as CutId);
    if (cut == null) {
      return true;
    }
    final shown = standingPicturesOf(cut, place.at, _placement());
    final over = shown.over;
    return _isThere(shown.frame) && (over == null || _isThere(over));
  }

  bool _isThere(DemandedPicture picture) =>
      _pictures().standingOf(picture).state != PictureState.toCome;

  /// Makes [place]'s pictures at once.
  Future<void> make(
    PicturePlace place, {
    required bool Function() givenUp,
  }) async {
    final cut = cutById(place.scope as CutId);
    if (cut == null) {
      return;
    }
    final pictures = _pictures();
    final shown = standingPicturesOf(cut, place.at, _placement());
    await Future.wait([
      for (final picture in [shown.frame, ?shown.over])
        if (!_isThere(picture)) _madeNow(pictures, picture, givenUp),
    ]);
  }

  /// [picture] made now for a move — given up where its making threw, as
  /// a screen's own making gives up (`FramePictureView`).
  Future<void> _madeNow(
    FramePictures pictures,
    DemandedPicture picture,
    bool Function() givenUp,
  ) => pictures
      .makeShown(
        pictures.stackOf(picture),
        picture,
        shouldAbort: givenUp,
        // Kept as the canvas that goes to the frame keeps them where it
        // makes it itself (`FramePictureView`, a screen that draws live):
        // the pen's steps patch into them (🔬S5_BA cut 352, Surface Pro 11:
        // with the cels in hand p50 83–154 ms to the picture, 186 ms not
        // kept, 249 ms where the canvas made it itself, 11-18) — this the
        // canvas it moves stands as (`FramePictureView.standsAs`).
        canvas: this,
      )
      .then<void>(
        (_) {},
        onError: (Object error, StackTrace stack) {
          pictures.noteFailure(picture);
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'stands with its picture',
              context: ErrorDescription('making the frame a move waits for'),
            ),
          );
        },
      );
}

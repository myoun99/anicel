import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../models/canvas_viewport.dart';
import 'viewport_canvas_transform.dart';

/// The whole device pixels a picture drawn through [drawnFor] is moved by
/// to stand where the view [now] lays it, on a screen of [devicePixelRatio]
/// — null where the view has zoomed, turned or flipped since: the picture
/// stands as drawn till the next is up. Moved with the view there, it would
/// be shown stretched or turned by Flutter meanwhile.
///
/// On whole device pixels: a texel stays a device pixel.
(double, double)? panSince(
  CanvasViewport drawnFor,
  CanvasViewport now,
  double devicePixelRatio,
) {
  final snapped = renderSnappedViewport(now, devicePixelRatio);
  if (drawnFor.copyWith(panX: snapped.panX, panY: snapped.panY) != snapped) {
    return null;
  }
  return (
    ((snapped.panX - drawnFor.panX) * devicePixelRatio).roundToDouble(),
    ((snapped.panY - drawnFor.panY) * devicePixelRatio).roundToDouble(),
  );
}

/// The view a picture drawn through [drawnFor] stands at on the screen,
/// the view being [now] ([panSince]).
CanvasViewport viewStandingAt(
  CanvasViewport drawnFor,
  CanvasViewport now,
  double devicePixelRatio,
) {
  final pan = panSince(drawnFor, now, devicePixelRatio);
  if (pan == null) {
    return drawnFor;
  }
  final (x, y) = pan;
  return drawnFor.copyWith(
    panX: drawnFor.panX + x / devicePixelRatio,
    panY: drawnFor.panY + y / devicePixelRatio,
  );
}

/// A picture on the canvas: the view it stands at, the view being [now]
/// ([viewStandingAt] — the view as it is, where it shows none).
abstract interface class StandingPicture {
  CanvasViewport standingFor(CanvasViewport now);
}

/// 🚨★★★WHAT IS DRAWN OVER THE CANVAS IS DRAWN THROUGH THE VIEW ITS PICTURE
/// STANDS AT — one clock for the picture and everything on it.
///
/// 🗣️a-pan-moves-the-overlays-before-the-canvas-Q1 (유저 2026-11-15): 「(다)
/// 오버레이를 그림에 맞춰 늦춘다」. A frame is up once the GPU has finished
/// it ([ScreenTexture.present]), and through a zoom, a turn or a flip the
/// picture stands as drawn till then — so what is drawn over it waits for
/// it, and the two move as one body. 관제 (11-16): every one of the family
/// that stands on the canvas's coordinates keeps this clock — the stage's
/// planes, the guides, the camera's frame, the fade, the ants, the boxes —
/// and nothing that follows the hand does (the app's cursor, the pen's
/// mapping, a box carried by the pen: 11-12 「어긋나는거 ok」).
///
/// The picture is the one that carries the overlays
/// ([FramePictureView.carriesTheOverlays]); with none carrying them, the
/// view as it is.
final class PictureUpView extends ChangeNotifier {
  StandingPicture? _picture;

  /// The picture that carries the overlays, if one does.
  @visibleForTesting
  StandingPicture? get debugCarrier => _picture;

  /// The view what is drawn over the canvas is drawn through, the view
  /// being [now].
  CanvasViewport standing(CanvasViewport now) =>
      _picture?.standingFor(now) ?? now;

  /// [picture] carries the overlays from now on.
  void carriedBy(StandingPicture picture) => _picture = picture;

  /// [picture] carries them no more.
  void letGoOf(StandingPicture picture) {
    if (identical(_picture, picture)) {
      _picture = null;
    }
  }

  /// The picture stands at another view, the view as it was: a frame up.
  void moved() => notifyListeners();
}

/// 🚨★★★THE PICTURES OF ONE CANVAS GO UP TOGETHER: a frame the GPU has
/// finished goes up once every other frame of the canvas's pictures being
/// drawn meanwhile has finished too, or failed.
///
/// 🗣️관제 2026-11-16 (a-pan-moves-the-overlays-before-the-canvas (ㄱ)): 「덮는
/// 어니언 = 묶는다」 — the card's title is 「캔버스에 보이는 것은 한 몸으로」,
/// and the ghosts over the frame, on a texture of their own, are seen on
/// the canvas. Each picture is put up once the GPU has finished it
/// ([ScreenTexture.present]): two drawn for one view of a zoom came up a
/// frame apart where one finished later.
///
/// A frame drawn alone — a stroke's step, the ghosts standing — waits for
/// nothing; one drawn beside another waits for the slower.
/// ⛔Not one texture for the frame and its ghosts: the frame's every step
/// would composite the ghosts again, on the path a stroke takes.
final class PicturesUpTogether {
  /// The frames being drawn that have not gone up.
  int _drawing = 0;

  /// The frames finished, each waiting for the rest.
  final List<Completer<void>> _finished = [];

  /// [done] — a frame of one of the canvas's pictures, finishing on the
  /// GPU — as the frame goes up ([ScreenTexture.present]).
  Future<void> joined(Future<void> done) {
    _drawing += 1;
    final up = Completer<void>();
    unawaited(
      done.then(
        (_) {
          _finished.add(up);
          _letUp();
        },
        onError: (Object error, StackTrace stack) {
          _drawing -= 1;
          up.completeError(error, stack);
          _letUp();
        },
      ),
    );
    return up.future;
  }

  void _letUp() {
    if (_finished.length < _drawing) {
      return;
    }
    final finished = [..._finished];
    _finished.clear();
    _drawing -= finished.length;
    for (final up in finished) {
      up.complete();
    }
  }
}

/// Where the pictures of a canvas find its [PictureUpView], and go up
/// [together].
class PictureUpViewScope extends InheritedWidget {
  const PictureUpViewScope({
    super.key,
    required this.view,
    required this.together,
    required super.child,
  });

  final PictureUpView view;
  final PicturesUpTogether together;

  static PictureUpViewScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PictureUpViewScope>();

  static PictureUpView? maybeOf(BuildContext context) => _of(context)?.view;

  static PicturesUpTogether? togetherOf(BuildContext context) =>
      _of(context)?.together;

  @override
  bool updateShouldNotify(PictureUpViewScope oldWidget) =>
      !identical(view, oldWidget.view) ||
      !identical(together, oldWidget.together);
}

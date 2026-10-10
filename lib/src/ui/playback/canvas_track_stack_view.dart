import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/project.dart'
    show defaultProjectBackdropArgb, defaultProjectPasteboardArgb;
import '../../models/pasteboard_bounds.dart' show PasteboardBounds;
import '../../models/project_background.dart';
import '../../services/camera_projection_matrix.dart';
import '../../services/playback/playback_frame_mapping.dart';
import '../../services/se_name_tag_plan.dart';
import '../canvas/canvas_layer_stack_view.dart';
import '../canvas/outline_clipper.dart';
import '../canvas/paper_background.dart'
    show AlphaCheckerboardPainter, paintAlphaCheckerboard;
import 'camera_shot.dart';
import 'layer_frame_image_cache.dart';
import 'playback_frame_painter.dart';
import '../effective_device_pixel_ratio.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../repaint_props.dart';

/// The parked-state canvas content — the multitrack display path.
///
/// With NO active cut (a gap parking, UI-R9 #3) the canvas used to show a
/// paperless void even when the parked frame sits ON a cut (an SE-row
/// press parks in place, feedback #7). Now every track answers "which of
/// my cuts covers this global frame?" and the covered cuts stack in
/// CAMERA-FRAME space, each projected through its own cut's camera pose —
/// playback's camera view, one layer per track. Editing stays
/// single-active-cut; this path only displays ("draw on the canvas, watch
/// through the camera" — with nothing active, everything here is watched).
///
/// 🚨★★★A CUT IS DRAWN FROM ITS ROWS' IMAGES, AS THE CANVAS DRAWS IT
/// (playback-plays-the-screen-material, 2026-10-10; 유저 F-296-Q6
/// 「중복소재 안만들고 싶은것」, 10-10 「전체컷재생도 동일하게 합성본 안만들고
/// 통일하고싶고」): each covered cut is its composite tree
/// ([stackOf] — the V row's fx a group over it) on a [CanvasLayerStackView]
/// out of the canvas's own image cache, seen through the view the canvas
/// would see it through. ↩️Each covered cut was one composite per frame,
/// made and held here beside the very images the canvas holds — a second
/// picture of everything the film showed.
///
/// The bottom covered track is the STAGE: its paper and apron lie under its
/// picture, and its fade thins the whole unit, revealing the floor; the
/// tracks above composite transparently, their fades applied to their own
/// picture only — a full-frame wash there would blank the stage below
/// instead of revealing it.
///
/// No covered track at all keeps the void (the panel background shows
/// through) — the same gap semantics playback and the scrub preview
/// already have.
class CanvasTrackStackView extends StatelessWidget {
  const CanvasTrackStackView({
    super.key = const ValueKey<String>('canvas-track-stack-view'),
    required this.globalFrame,
    required this.positionsOf,
    required this.stackOf,
    required this.imageCache,
    required this.cameraFrameSize,
    required this.cameraPoseOf,
    this.cameraViewEnabled = true,
    this.seNameTagsOf,
    this.run,
    this.onBufferBytes,
    this.viewport,
    this.background = ProjectBackground.defaultBackground,
    this.backdropArgb = defaultProjectBackdropArgb,
    this.backdropNone = false,
    this.paintsFloor = true,
    this.pasteboardArgb = defaultProjectPasteboardArgb,
    this.pasteboardNone = false,
  });

  /// The parked global frame (the session's gap parking): moves per
  /// gesture move, null = no parking (the degenerate no-cut state) —
  /// nothing shows.
  final ValueListenable<int?> globalFrame;

  /// Live per-track resolution (resolveTrackStackContributions over the
  /// CURRENT project layout — never playlist snapshots, so edits made
  /// while parked show up on the next build). An O.L answers with BOTH
  /// cuts, the leaving one first.
  final List<TrackStackContribution> Function(int globalFrame) positionsOf;

  /// A covered cut's frame as a run shows it — its composite tree under the
  /// V row's fx ([EditingCanvas.playedStackAt]).
  final List<CompositeNode<CanvasStackRow>> Function(Cut cut, int frameIndex)
  stackOf;

  /// The canvas's own images, the ones every cut here is drawn from.
  final LayerFrameImageCache imageCache;

  /// Whether the CAMERA VIEW is on — the same view-mode flag the canvas
  /// takes, and the reason this stack no longer crops unconditionally.
  ///
  /// ★A ruler scrub parks per move in a gap (UI-R7 #9), so the parked stack
  /// is what the canvas shows while you drag through one (until I-57 ② it
  /// showed another cut's frames this way too). It used to be the one
  /// display path that ignored the toggle, which meant dragging the ruler
  /// reframed the canvas into the camera crop even with camera view off.
  /// The law is one line now: camera view decides the framing, wherever the
  /// picture comes from.
  final bool cameraViewEnabled;

  final CanvasSize cameraFrameSize;
  final CameraPose Function(Cut cut, int frameIndex) cameraPoseOf;

  /// The SE rows' on-canvas name tags (R5b): resolved PER CUT, so each
  /// covered track shows its own speakers rather than the selected
  /// track's.
  final List<ResolvedSeNameTag> Function(Cut cut, int frameIndex)?
  seNameTagsOf;

  /// Null where this view's cuts make what they lack themselves: a parked
  /// frame, an O.L partner — 「스크럽하던 뭐던 존재하는게 보여야함」 (F-206).
  ///
  /// Set where a run PLAYS through it: the warmer follows the run and is the
  /// one maker of its pictures, in the order the run wants them, so each cut
  /// here shows what has landed and changes frames whole
  /// ([CanvasLayerStackView.run]). ↩️It composed the frame under the
  /// playhead itself, beside a warmer that was baking the playlist from
  /// wherever play had been pressed — two makers, one picture between them
  /// at the worst moment.
  final StackRun? run;

  /// Told how many bytes each cut's display buffer holds, by cut, whenever
  /// that changes — 0 when it goes ([CanvasLayerStackView.onBufferBytes]).
  final void Function(Object cut, int bytes)? onBufferBytes;

  /// The panel's live pan/zoom; identity when null.
  final CanvasViewport? viewport;

  /// The project background: the paper of the bottom covered track.
  final ProjectBackground background;

  /// The BACKDROP (R3b): the panel-wide floor this stack sits on — what
  /// an uncovered frame shows (the old void) and what a translucent cut
  /// reveals. A fade lays its own screen instead (F-192).
  final int backdropArgb;

  /// The bottom covered track's stage apron (R3b): fills its camera frame
  /// under the paper, and fades with the cut unit.
  final int pasteboardArgb;

  /// Whether the backdrop and the pasteboard are ABSENT (F-114): on screen
  /// each is the checkerboard where it would be.
  final bool backdropNone;
  final bool pasteboardNone;

  /// Whether the stack stands on its own backdrop floor. False lays it OVER
  /// whatever is under it: the editing canvas's O.L partner (F-227) is
  /// painted over the LIVE cut, which is that partner's floor — the share
  /// the partner leaves is the live cut showing through, exactly the mix
  /// [sourceOverWeights] describes.
  final bool paintsFloor;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int?>(
    valueListenable: globalFrame,
    builder: (context, frame, _) => _frame(context, frame),
  );

  Widget _frame(BuildContext context, int? frame) {
    final positions = frame == null
        ? const <TrackStackContribution>[]
        : positionsOf(frame);
    final ratio = EffectiveDevicePixelRatio.of(context);
    final view = viewport ?? CanvasViewport();
    // The BACKDROP floor (R3b): the void is retired — an uncovered frame
    // shows the stage's floor, exactly what an opaque export bakes there.
    // An ABSENT backdrop (F-114) is the checkerboard, as on the editing
    // canvas. Seen through the camera, the floor past its frame is the
    // letterbox ([_CameraFloor]).
    final Widget? floor = !paintsFloor
        ? null
        : cameraViewEnabled
        ? CustomPaint(
            key: const ValueKey<String>('canvas-track-stack-floor'),
            painter: _CameraFloor(
              viewport: viewport,
              frameSize: cameraFrameSize,
              backdrop: Color(backdropArgb),
              backdropNone: backdropNone,
              devicePixelRatio: ratio,
            ),
            child: const SizedBox.expand(),
          )
        : backdropNone
        ? const CustomPaint(
            key: ValueKey<String>('canvas-track-stack-floor'),
            painter: AlphaCheckerboardPainter(),
            child: SizedBox.expand(),
          )
        : ColoredBox(
            key: const ValueKey<String>('canvas-track-stack-floor'),
            color: Color(backdropArgb),
          );
    if (positions.isEmpty) {
      return SizedBox.expand(
        key: const ValueKey<String>('canvas-track-stack-void'),
        child: floor,
      );
    }
    // The unit alpha of each contribution: its transition share. The
    // weights that follow turn those into source-over alphas — see
    // [sourceOverWeights] for why they are not the same number.
    final weights = trackGroupSourceOverWeights(positions, [
      for (final position in positions) position.opacity,
    ]);
    return Stack(
      key: const ValueKey<String>('canvas-track-stack-frames'),
      fit: StackFit.expand,
      children: [
        ?floor,
        for (final (i, position) in positions.indexed)
          _unit(position, weights[i], view: view, ratio: ratio),
      ],
    );
  }

  /// One covered cut's share of the frame: the stage's apron and paper under
  /// it when it is the stage, its rows' images cut to its canvas — and to the
  /// camera's frame through the camera — and its names and veils over it.
  Widget _unit(
    TrackStackContribution position,
    double weight, {
    required CanvasViewport view,
    required double ratio,
  }) {
    final cut = position.cut;
    final localFrame = position.localFrameIndex;
    final pose = cameraViewEnabled ? cameraPoseOf(cut, localFrame) : null;
    // The stage — paper, apron — belongs to the bottom covered TRACK, and
    // to EVERY contribution of it: a 場面転換 cross-fades the whole screen,
    // so the arriving cut brings its own paper and the weights mix the two.
    // Tracks above composite transparently over it.
    final isStage = position.isBottomTrack;
    final shot = pose == null
        ? null
        : (
            pose: pose,
            frameSize: cameraFrameSize,
            frameView: viewportAfter(
              view,
              cameraProjectionMatrix(pose, cameraFrameSize),
            ),
          );
    PlaybackFramePainter painter({required bool under}) => PlaybackFramePainter(
      image: null,
      canvasSize: cut.canvasSize,
      viewport: view,
      devicePixelRatio: ratio,
      cameraPose: pose,
      cameraFrameSize: pose == null ? null : cameraFrameSize,
      paperBackground: background,
      paintPaper: under && isStage,
      // The letterbox is the FLOOR's, laid once under every track
      // ([_CameraFloor]). ↩️Each stage contribution laid its own over
      // the whole screen, opaque, under its fade — so in an O.L the
      // arriving cut covered the leaving one and the dissolve went
      // through the letterbox (measured 10-10: two white papers met at
      // (99,102,104)), and a fade showed it where the backdrop is.
      paintLetterbox: false,
      // The apron rides the camera view: it is what the camera sees past
      // the paper.
      pasteboardColor: under && isStage && pose != null
          ? Color(pasteboardArgb)
          : null,
      // F-114: absent planes show the checkerboard here as on the editing
      // canvas — on screen only.
      pasteboardNone: pasteboardNone,
      checkersAbsentPlanes: true,
      seNameTags: under
          ? const []
          : seNameTagsOf?.call(cut, localFrame) ?? const [],
      // An upper track thins its names and veils with its picture.
      imageOpacity: isStage ? 1 : weight,
      veils: under ? const [] : position.veils,
    );
    final unit = Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: painter(under: true)),
        Opacity(
          opacity: isStage ? 1 : weight,
          child: ClipPath(
            clipper: OutlineClipper(
              pictureOutlineOnScreen(view, shot, cut.canvasSize, ratio),
            ),
            child: CanvasLayerStackView(
              nodes: stackOf(cut, localFrame),
              imageCache: imageCache,
              canvasSize: cut.canvasSize,
              viewport: shot?.frameView ?? view,
              // A drag parks one frame after another: a cut shows its last
              // whole frame until the next one is — a run's are whole anyway
              // ([CanvasLayerStackView.wholeFrames]).
              wholeFrames: true,
              run: run,
              onBufferBytes: onBufferBytes == null
                  ? null
                  : (bytes) => onBufferBytes!(cut.id, bytes),
            ),
          ),
        ),
        CustomPaint(painter: painter(under: false)),
      ],
    );
    // The FADE is transparency (R3b): the stage's whole contribution —
    // apron, paper, picture, names, veils — thins as one layer, revealing
    // whatever lies behind (the tracks below, then the backdrop).
    return Opacity(
      // The cut's own: what its stack holds — the last whole frame among it
      // — stays its own when another cut comes in beside it or leaves.
      key: ValueKey<Object>(('track-stack-unit', cut.id)),
      opacity: isStage ? weight : 1,
      child: unit,
    );
  }
}

/// The stage's floor seen through the camera (R3b): the letterbox past the
/// camera's frame, and in the frame the backdrop every track's unit lies
/// on — what a fade or a dissolve reveals. An ABSENT backdrop (F-114) is
/// the checkerboard there, as the apron's is.
///
/// ONE floor under every track: the letterbox is laid once, so no unit can
/// cover the one under it with it (see the frames' `paintLetterbox`).
class _CameraFloor extends CustomPainter with RepaintOnProps {
  const _CameraFloor({
    required this.viewport,
    required this.frameSize,
    required this.backdrop,
    required this.backdropNone,
    required this.devicePixelRatio,
  });

  /// The panel's pan/zoom; identity when null.
  final CanvasViewport? viewport;
  final CanvasSize frameSize;
  final Color backdrop;
  final bool backdropNone;

  /// The pan-phase snap's device grid — the frame lands where the frames
  /// over it clip to.
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = PlaybackFramePainter.letterboxColor,
    );
    if (viewport case final viewport?) {
      applyViewportTransform(
        canvas,
        viewport,
        devicePixelRatio: devicePixelRatio,
      );
    }
    if (backdropNone) {
      paintAlphaCheckerboard(canvas, frameSize.canvasRect);
    } else {
      canvas.drawRect(frameSize.canvasRect, Paint()..color = backdrop);
    }
    canvas.restore();
  }

  @override
  Object get props =>
      (viewport, frameSize, backdrop, backdropNone, devicePixelRatio);
}

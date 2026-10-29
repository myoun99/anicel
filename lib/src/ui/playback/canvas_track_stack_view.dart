import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/camera_pose.dart';
import '../../models/canvas_size.dart';
import '../../models/canvas_viewport.dart';
import '../../models/composite_tree.dart';
import '../../models/cut.dart';
import '../../models/project.dart'
    show defaultProjectBackdropArgb, defaultProjectPasteboardArgb;
import '../../models/pasteboard_bounds.dart'
    show PasteboardBounds, PasteboardReach;
import '../../models/project_background.dart';
import '../../services/camera_projection_matrix.dart';
import '../../services/playback/frame_demand.dart' show FrameGhosts;
import '../../services/playback/playback_frame_mapping.dart';
import '../../services/se_name_tag_plan.dart';
import '../canvas/canvas_layer_stack_view.dart' show CanvasStackRow;
import '../canvas/stage_planes_painter.dart';
import 'camera_shot.dart';
import 'frame_picture_view.dart';
import 'playback_frame_painter.dart';
import '../effective_device_pixel_ratio.dart';
import '../canvas/viewport_canvas_transform.dart';
import '../repaint_props.dart';

/// What the track stack takes from a RUN it shows: whether the run's frame
/// goes up when asked for — the question the run's clock counts the frames
/// it leaves by (`PlaybackRig.frameIsThere`).
typedef TrackStackRun = ({bool Function(int frame) frameIsThere});

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
/// 🚨★★★A CUT'S FRAME IS ITS ONE PICTURE, THE ONE THE CANVAS SHOWS OF IT
/// (one-picture-per-frame ②-2 · ②-3, D7-2-Q3=a; 유저 F-296-Q6 「중복소재
/// 안만들고 싶은것」, 10-10 「전체컷재생도 동일하게 합성본 안만들고
/// 통일하고싶고」): each covered cut is its composite tree ([stackOf] — the V
/// row's fx a group over it), signed, and the picture [pictures] keep of
/// it ([FramePictureView]), seen through the view the canvas would see it
/// through — parked or under a run. ↩️Each covered cut was one composite
/// per frame, made and held here beside the very images the canvas holds —
/// a second picture of everything the film showed; then, parked, its rows'
/// images stacked again (`CanvasLayerStackView`, 2026-10-10 → ②-3).
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
    required this.pictures,
    required this.cameraFrameSize,
    required this.cameraPoseOf,
    this.cameraViewEnabled = true,
    this.seNameTagsOf,
    this.run,
    this.viewport,
    this.background = ProjectBackground.defaultBackground,
    this.backdropArgb = defaultProjectBackdropArgb,
    this.backdropNone = false,
    this.paintsFloor = true,
    this.pasteboardArgb = defaultProjectPasteboardArgb,
    this.pasteboardNone = false,
    this.pasteboardReach = PasteboardReach.whole,
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

  /// The frames' pictures — the canvas's own, every cut here shows — and
  /// the signal that one landed.
  final StackRun pictures;

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

  /// Null where this view's cuts make what they lack themselves
  /// ([FramePictureView.laysWhatItMisses]): a parked frame, an O.L partner
  /// — 「스크럽하던 뭐던 존재하는게 보여야함」 (F-206).
  ///
  /// Set where a run PLAYS through it: the warmer follows the run and is the
  /// one maker of its pictures, in the order the run wants them, so each cut
  /// here shows what has landed ([FramePictureView]) and the film
  /// changes frames whole, across its cuts as within one
  /// ([_WholeFilmFrames]). ↩️It composed the frame under the playhead
  /// itself, beside a warmer that was baking the playlist from wherever
  /// play had been pressed — two makers, one picture between them at the
  /// worst moment.
  final TrackStackRun? run;

  /// The panel's live pan/zoom; identity when null.
  final CanvasViewport? viewport;

  /// The project background: the paper of the bottom covered track.
  final ProjectBackground background;

  /// The BACKDROP (R3b): the panel-wide floor this stack sits on — what
  /// an uncovered frame shows (the old void) and what a translucent cut
  /// reveals. A fade lays its own screen instead (F-192). The project's,
  /// alpha and all: the floor lays it over the panel's ground
  /// ([backdropOnScreen]).
  final int backdropArgb;

  /// The bottom covered track's stage apron (R3b): fills its camera frame
  /// under the paper, and fades with the cut unit.
  final int pasteboardArgb;

  /// Whether the backdrop and the pasteboard are ABSENT (F-114): on screen
  /// each is the checkerboard where it would be.
  final bool backdropNone;
  final bool pasteboardNone;

  /// How far the pasteboard reaches past each cut's paper (I-109) — the
  /// wall its pictures stand behind and its plane is laid to.
  final PasteboardReach pasteboardReach;

  /// Whether the stack stands on its own backdrop floor. False lays it OVER
  /// whatever is under it: the editing canvas's O.L partner (F-227) is
  /// painted over the LIVE cut, which is that partner's floor — the share
  /// the partner leaves is the live cut showing through, exactly the mix
  /// [sourceOverWeights] describes.
  final bool paintsFloor;

  @override
  Widget build(BuildContext context) => _WholeFilmFrames(
    globalFrame: globalFrame,
    landings: pictures.landings,
    run: run,
    builder: _frame,
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
    // letterbox ([_StageFloor]).
    //
    // As the SCREEN shows the backdrop ([backdropOnScreen]): the film lies
    // over the editing canvas's own planes, so its floor is the backdrop
    // over the panel's ground, once — opaque, where the editing canvas's
    // planes would show through it twice.
    final Widget? floor = !paintsFloor
        ? null
        : CustomPaint(
            key: const ValueKey<String>('canvas-track-stack-floor'),
            painter: _StageFloor(
              backdrop: backdropOnScreen((
                color: stageColorOnScreen(backdropArgb),
                none: backdropNone,
              ), stageGroundOf(context)),
              camera: cameraViewEnabled
                  ? (frameSize: cameraFrameSize, viewport: viewport)
                  : null,
              devicePixelRatio: ratio,
            ),
            child: const SizedBox.expand(),
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

  /// One covered cut's share of the frame: the stage's planes under it when
  /// it is the stage, its rows' images — cut to its canvas inside the
  /// camera's frame through the camera, and nowhere without one — and its
  /// names and veils over it.
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
      canvasSize: cut.canvasSize,
      pasteboardReach: pasteboardReach,
      viewport: view,
      devicePixelRatio: ratio,
      cameraPose: pose,
      cameraFrameSize: pose == null ? null : cameraFrameSize,
      paperBackground: background,
      // The paper is the canvas's own, drawn with its rows (as the camera's
      // shot leaves it). Here, through the camera, is only its plane where
      // it is ABSENT (F-114): the checkerboard in its place.
      // 🚨playback-picture-is-not-the-canvas-picture (유저 10-13 「끝에 흰
      // 선」): painted here under the rows, the paper filled the canvas
      // to its edge — under a level image whose last pixel the edge cuts
      // part-way, which the stack's own paper yields to (#15) — and showed
      // white through it.
      paintPaper: under && isStage && background.none,
      // The letterbox is the FLOOR's, laid once under every track
      // ([_StageFloor]). ↩️Each stage contribution laid its own over
      // the whole screen, opaque, under its fade — so in an O.L the
      // arriving cut covered the leaving one and the dissolve went
      // through the letterbox (measured 10-10: two white papers met at
      // (99,102,104)), and a fade showed it where the backdrop is.
      paintLetterbox: false,
      // The apron rides the camera view: it is what the camera sees past
      // the paper.
      pasteboardColor: under && isStage
          ? stageColorOnScreen(pasteboardArgb)
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
    // 🚨Seen through no camera the stage is the EDITING CANVAS's — its
    // pasteboard where its cut's pasteboard is, the checkerboard where the
    // paper is absent, laid by the painter the canvas lays them with — and
    // nothing of the picture is cut: a cut played whole shows what it shows
    // standing still (conte-playback-hides-the-pasteboard, 유저 10-13 「둘 다
    // 보인다(편집 캔버스처럼)」). ↩️The film cut every cut at its canvas's
    // edge on the floor while a cut's run on the canvas showed the
    // pasteboard. Through the camera, the planes are what the camera sees.
    final CustomPainter? planes = pose != null
        ? painter(under: true)
        : isStage
        ? StagePlanesPainter(
            pasteboard: (
              color: stageColorOnScreen(pasteboardArgb),
              none: pasteboardNone,
            ),
            pasteboardReach: pasteboardReach,
            paperNone: background.none,
            canvasSize: cut.canvasSize,
            viewport: view,
            devicePixelRatio: ratio,
          )
        : null;
    final unit = Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: planes),
        Opacity(
          opacity: isStage ? 1 : weight,
          child: ShotClip(
            outline: pictureOutlineOnScreen(view, shot, cut.canvasSize, ratio),
            child: FramePictureView(
              run: pictures,
              picture: (
                cut: cut,
                frameIndex: localFrame,
                paintPaper: isStage,
                ghosts: FrameGhosts.none,
              ),
              nodes: stackOf(cut, localFrame),
              viewport: shot?.frameView ?? view,
              // A run's frames are made ahead of it by its warmer; parked, a
              // cut makes what it lacks — and a drag parks one frame after
              // another, so a cut shows its last whole frame until the next
              // one is ([FramePictureView.wholeFrames]).
              laysWhatItMisses: run == null,
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

/// 🚨A FILM CHANGES FRAMES WHOLE, ACROSS ITS CUTS AS WITHIN ONE (유저
/// 2026-10-15, F-365-Q2: 「컷을 넘을 때도 직전 그림을 남기고, 건너뛴 프레임
/// 수를 재생 버튼 왼쪽에 빨갛게」). Under a run, the frame shown is the
/// run's — or, while its picture is not all there, the last one that was.
/// Each cut's view changes its own frames whole ([FramePictureView]),
/// but a cut coming in is a view of its own, with no frame of its own to
/// leave standing: it showed its paper until its rows landed.
///
/// ⚠️Past the frame a run is put on, only a clock that goes on without a
/// picture asks for a frame that is not whole — skipping frames — and every
/// frame it leaves so is counted dropped by the same question
/// (`CanvasPlaybackController.frameIsThere`), so what stands in for it is
/// never shown silently. A clock that waits
/// stands on the last whole frame itself (F-365-Q1, `playheadWay`):
/// ⛔holding the picture here while ITS playhead went on was turned down —
/// the playhead on one frame and the screen on another.
///
/// The first frame a clock asks for is shown whatever it holds — there is
/// no other to show — and parked, every frame is shown as it is asked for:
/// the cuts make what they lack themselves, and leave their own last whole
/// frame standing.
class _WholeFilmFrames extends StatefulWidget {
  const _WholeFilmFrames({
    required this.globalFrame,
    required this.landings,
    required this.run,
    required this.builder,
  });

  final ValueListenable<int?> globalFrame;

  /// That a frame's picture landed ([StackRun.landings]).
  final Listenable landings;
  final TrackStackRun? run;
  final Widget Function(BuildContext context, int? frame) builder;

  @override
  State<_WholeFilmFrames> createState() => _WholeFilmFramesState();
}

class _WholeFilmFramesState extends State<_WholeFilmFrames> {
  /// The frame on screen: the one asked for, or the last whole one.
  late int? _shown = widget.globalFrame.value;

  @override
  void initState() {
    super.initState();
    widget.globalFrame.addListener(_look);
    widget.landings.addListener(_look);
  }

  @override
  void didUpdateWidget(_WholeFilmFrames oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.globalFrame, widget.globalFrame)) {
      oldWidget.globalFrame.removeListener(_look);
      widget.globalFrame.addListener(_look);
    }
    if (!identical(oldWidget.landings, widget.landings)) {
      oldWidget.landings.removeListener(_look);
      widget.landings.addListener(_look);
    }
    // Another clock, another run: what stands, stands until what is asked
    // for now is whole.
    final asked = widget.globalFrame.value;
    if (_isWhole(asked)) {
      _shown = asked;
    }
  }

  @override
  void dispose() {
    widget.globalFrame.removeListener(_look);
    widget.landings.removeListener(_look);
    super.dispose();
  }

  bool _isWhole(int? frame) =>
      frame == null || (widget.run?.frameIsThere(frame) ?? true);

  /// The frame asked for, or a picture landed: the frame asked for goes up
  /// once it is whole.
  void _look() {
    final asked = widget.globalFrame.value;
    if (asked != _shown && _isWhole(asked)) {
      setState(() => _shown = asked);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _shown);
}

/// The stage's floor (R3b): the backdrop every track's unit lies on — what
/// an uncovered frame shows and a fade or a dissolve reveals — over the
/// box, or seen through the camera in the camera's frame with the
/// letterbox past it. An ABSENT backdrop (F-114) is the checkerboard there,
/// as the apron's is: one plane, laid the one way ([paintStagePlane]).
///
/// ONE floor under every track: the letterbox is laid once, so no unit can
/// cover the one under it with it (see the frames' `paintLetterbox`).
/// ↩️Seen through no camera the floor was a widget of its own — a colour,
/// or a checkerboard painter — spelling the plane's switch once more.
class _StageFloor extends CustomPainter with RepaintOnProps {
  const _StageFloor({
    required this.backdrop,
    required this.camera,
    required this.devicePixelRatio,
  });

  final StagePlane backdrop;

  /// Where the floor is seen through the camera: the camera's frame, laid
  /// through the panel's pan/zoom (identity when null). Null lays the
  /// floor over the whole box, which no view moves.
  final ({CanvasSize frameSize, CanvasViewport? viewport})? camera;

  /// The pan-phase snap's device grid — the frame lands where the frames
  /// over it clip to.
  final double devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final screen = canvas.getTransform();
    canvas.save();
    canvas.clipRect(box);
    var region = box;
    if (camera case (:final frameSize, :final viewport)?) {
      canvas.drawRect(
        box,
        Paint()..color = PlaybackFramePainter.letterboxColor,
      );
      if (viewport != null) {
        applyViewportTransform(
          canvas,
          viewport,
          devicePixelRatio: devicePixelRatio,
        );
      }
      region = frameSize.canvasRect;
    }
    paintStagePlane(canvas, region, backdrop, screen: screen);
    canvas.restore();
  }

  @override
  Object get props => (backdrop, camera, devicePixelRatio);
}

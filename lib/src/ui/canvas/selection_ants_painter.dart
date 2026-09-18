import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../models/canvas_point.dart';
import '../../models/canvas_viewport.dart';
import '../../services/canvas_selection.dart';
import '../../services/canvas_selection_region.dart';
import '../theme/app_theme.dart';
import '../repaint_props.dart';
import '../timeline/memo_token.dart';

/// The Ctrl+T box chrome in viewport space: the transformed box outline,
/// the scale handles and the rotate knob (null in QUAD mode — a free
/// quadrilateral has no rotation lever).
typedef SelectionTransformChrome = ({
  List<Offset> box,
  List<Offset> handles,
  Offset? knob,
});

/// Marching ants: dashed outlines whose dash phase rides the animation.
///
/// R28-S: extracted from the selection layer so the SAME ants can be
/// painted under every tool. The selection is a document fact, not a
/// selection-tool decoration — with the brush armed the user still has to
/// see where paint will land (R26 #18).
class SelectionAntsPainter extends CustomPainter with RepaintOnProps {
  SelectionAntsPainter({
    required Animation<double> repaint,
    required this.viewport,
    required this.committedRegion,
    this.startShape,
    required this.screenOffset,
    required this.marqueeShapes,
    required this.openTrail,
    this.closeTarget,
    this.closeTargetArmed = true,
    this.cursor,
    this.transformChrome,
    this.sessionHasChanges = false,
    this.outlineIsLive = false,
  }) : _phase = repaint,
       super(
         repaint: cursor == null
             ? repaint
             : Listenable.merge(<Listenable>[repaint, cursor]),
       );

  final Animation<double> _phase;
  final CanvasViewport viewport;

  /// The committed selection — its composite outline is the ants.
  final CanvasSelectionRegion? committedRegion;

  /// 🚨★★★**WHERE THE SESSION STARTED**, drawn while a transform is live and
  /// gone the moment it is confirmed (I-38).
  ///
  /// > 「변형 도구 사용시, 자유든 일반이든 뭐든 묻지말고 변형도구 사용시
  /// > **기존의 실루엣**(사각형 라인이나 메시워프든 **낡지 않을 구조로**)을
  /// > **초록색 선**(변형하지 않았다는 그 선 ui 그대로)으로 보여줌. 확정시
  /// > 사라짐. 즉 변형중에는 보이도록」 (유저 2026-09-16)
  ///
  /// ⛔**NOT A RECTANGLE, and that is the 「낡지 않을 구조로」**: it is the
  /// session's own [CanvasSelectionRegion], so a lasso starts as a lasso and
  /// a warped one starts as whatever it was. Nothing here knows the shapes
  /// apart, which is why nothing here can go stale when a new one arrives.
  ///
  /// The colour is the one the ants and the confirm button already speak —
  /// `selectionSession(changed: false)`, the 「hasn't been touched」 green —
  /// because that is precisely what this line means: here is the untouched
  /// thing, and the red chrome beside it is what you are doing to it.
  final CanvasSelectionRegion? startShape;
  final Offset screenOffset;

  /// The polygon being dragged right now (not yet folded into the region),
  /// with every copy a symmetry guide is making of it.
  ///
  /// A list because the preview has to show what will LAND: a mirrored drag
  /// commits every copy, so a preview that traced only the pointer's own
  /// rectangle would be a promise the commit breaks. Empty while no outline
  /// is being dragged.
  final List<CanvasSelectionShape> marqueeShapes;

  /// An outline still being drawn and not yet closable: the lasso's raw
  /// trail, or a polygon's vertices with the rubber band to the cursor on
  /// the end. Drawn open, because it IS open.
  final List<CanvasPoint> openTrail;

  /// Where tapping would END the outline — the polygon's first vertex, from
  /// the moment it is placed.
  ///
  /// TS6: it used to appear only once three vertices could actually close,
  /// on the grounds that the ring must not promise a tap that does nothing.
  /// The promise is wider than that now — a tap here closes when it can and
  /// abandons the trace when it cannot (유저: 불가능할땐 그냥 취소) — so it
  /// is honest from the first point, which is also the only feedback that
  /// the first point landed at all.
  final CanvasPoint? closeTarget;

  /// Whether that tap would CLOSE (three or more vertices) rather than
  /// abandon. Drawn hollow either way; the ring is one shape with two
  /// meanings, so it is drawn thinner while it can only abandon.
  final bool closeTargetArmed;

  /// The pointer, in this painter's own (viewport-local) coordinates — the
  /// far end of the rubber band from the last placed vertex. Null when the
  /// active shape lays no vertices.
  ///
  /// 유저: *"직선이 커서를 따라 이동하고 찍히면 고정이란 느낌 나야하는데 그게
  /// 없음."* ⚠️A listenable rather than a value: it is merged into this
  /// painter's repaint so the band follows the pointer without anyone
  /// rebuilding the layer above.
  final ValueListenable<Offset?>? cursor;
  final SelectionTransformChrome? transformChrome;

  /// R16-① TVP grammar: RED silhouette while the move session holds
  /// unconfirmed changes, GREEN when confirmed/untouched.
  final bool sessionHasChanges;

  /// Whether [committedRegion] is still MOVING — an open transform, warp or
  /// mesh session remaps it into a new region on every frame.
  ///
  /// 유저 (F-65): 「**라이브로 선택중일땐 선이 픽셀에 안착안된 벡터로 보여도
  /// 상관없는데**, 선택 커밋될떈 픽셀에 제대로 안착한 상태로」 — so a live
  /// outline traces the polygon and a settled one walks the pixels.
  ///
  /// ⚠️It is also what keeps the walk affordable. The pixel outline is
  /// memoised on the region, which is an exact key precisely because a
  /// region is immutable — and a session that builds a NEW region per frame
  /// would therefore miss that memo every frame and rasterise a mask over
  /// the whole selection to draw one line. ⛔The two reasons agree here, but
  /// the USER'S rule is the one this flag is named for: if they ever ask for
  /// pixel-exact ants mid-drag, the cost is the thing to solve, not this.
  final bool outlineIsLive;

  /// The colour the SESSION CHROME is drawn in — transform box, handles,
  /// rotate lever. ⛔Three separate constants lived here, and the box's was
  /// a fixed blue that never answered the question the other two did.
  ///
  /// ⚠️The ANTS left this in F-65 (see [_antColour]); R16-①'s red/green
  /// grammar still reads, because the parts that carry it are exactly the
  /// parts a move session puts on screen.
  Color get _sessionColor =>
      AppColors.selectionSession(changed: sessionHasChanges);

  /// 🚨★★★THE ANTS ARE BLACK — 유저 (F-65): 「선택툴의 개미행렬 색을 앱
  /// 강조색이아니라 **검정색으로. 그러니 흰색바탕에 검정 개미가 지나가도록.
  /// 앞으로 개미행렬은 이 공통 ui를 사용**」.
  ///
  /// ⚠️They read it as the app accent; it was actually
  /// `AppColors.selectionSession`'s green (red while a move session holds
  /// changes). Either way the instruction is the same, and the white
  /// under-stroke this pairs with was already there — 「흰색바탕에 검정
  /// 개미」 is that pair, now spelled the way they asked.
  ///
  /// ⛔A constant, not a theme token: it must not follow the accent, and
  /// following a THEME colour would be the same mistake one level up. The
  /// white beneath it is `Colors.white` for the same reason.
  static const Color _antColour = Color(0xFF000000);

  static const double _dashOn = 5;
  static const double _dashOff = 4;

  /// Screen pixels. The same number the layer hit-tests the close tap
  /// against, so what the ring says is aimable is what is aimable — and
  /// screen pixels rather than canvas ones, because a finger is the same
  /// size at every zoom.
  static const double closeTargetRadius = 9;

  Offset _map(CanvasPoint point) {
    final mapped = viewport.canvasToViewport(point);
    return Offset(mapped.x, mapped.y);
  }

  /// The committed region's pixel-edge outline, in SCREEN space.
  ///
  /// ⚠️No cache HERE. The expensive half — the mask and the boundary walk —
  /// is memoised on the region itself, which is immutable and therefore an
  /// exact key; what is left is mapping the points, which is what tracing
  /// the polygon cost all along. A cache in this class would either vanish
  /// every tick (the painter is rebuilt per frame) or be a global that the
  /// two painters on screen take turns evicting.
  Path _committedOutline(CanvasSelectionRegion region) =>
      region.pixelOutlineIn((point) => _map(point) + screenOffset);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    final phase = _phase.value * (_dashOn + _dashOff);

    // I-38: where this session started, UNDER everything else — it is what
    // the live outline is being compared against, so the live one is what
    // sits on top when they cross.
    //
    // ⚠️`pathIn`, like every other live outline here: it is on screen only
    // while a session is open, and 유저 already ruled that a live line need
    // not be settled onto pixels (F-65). Walking the pixels would rasterise
    // a whole-selection mask for one line that is about to move anyway.
    final start = startShape;
    if (start != null) {
      canvas.drawPath(
        start.pathIn((point) => _map(point) + screenOffset),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.selectionSession(changed: false),
      );
    }

    final committed = committedRegion;
    if (committed != null) {
      // 🚨THE COMMITTED OUTLINE WALKS THE PIXELS, not the polygon (F-65,
      // 유저: 「선택 커밋될떈 픽셀에 제대로 안착한 상태로. 지금은 **변형되는
      // 픽셀 범위와 개미행렬 위치가 다르다**」).
      //
      // ⛔`pathIn` traces where the DRAG went; membership is decided by
      // pixel CENTRE. Both were right about which pixels are in, and only
      // one of them was where the user was looking. The fold still decides
      // everything — unions merge and subtractions cut holes — the line has
      // simply moved onto the edges of the pixels that will actually move.
      //
      // ⚠️The LIVE outlines below keep `pathIn` on purpose — 「라이브로
      // 선택중일땐 선이 픽셀에 안착안된 벡터로 보여도 상관없는데」 — and that
      // is also what keeps a drag cheap: nothing rasterises while the
      // finger is down.
      final path = outlineIsLive
          ? committed.pathIn((point) => _map(point) + screenOffset)
          : _committedOutline(committed);
      _paintAnts(canvas, path, phase);
    }
    if (marqueeShapes.isNotEmpty) {
      // Copies UNION, the same way the committed fold does — two copies
      // that overlap trace one outline, not two crossing ones.
      var path = Path()
        ..fillType = PathFillType.evenOdd
        ..addPolygon([
          for (final point in marqueeShapes.first.points) _map(point),
        ], true);
      for (final marquee in marqueeShapes.skip(1)) {
        path = Path.combine(
          PathOperation.union,
          path,
          Path()
            ..fillType = PathFillType.evenOdd
            ..addPolygon([
              for (final point in marquee.points) _map(point),
            ], true),
        );
      }
      _paintAnts(canvas, path, phase);
    } else if (openTrail.isNotEmpty) {
      // Not closable yet: show the outline as far as it has been drawn,
      // plus the segment the next tap would lay (TS6). With one vertex the
      // band IS the whole drawing — which is the point, since a lone
      // vertex has no segment of its own to show.
      final band = cursor?.value;
      final path = Path()
        ..moveTo(_map(openTrail.first).dx, _map(openTrail.first).dy);
      for (final point in openTrail.skip(1)) {
        final mapped = _map(point);
        path.lineTo(mapped.dx, mapped.dy);
      }
      if (band != null) {
        path.lineTo(band.dx, band.dy);
      }
      if (openTrail.length >= 2 || band != null) {
        _paintAnts(canvas, path, phase);
      }
    }

    final close = closeTarget;
    if (close != null) {
      // The tap target that ends the outline. A ring, not a filled dot: it
      // has to read as somewhere to aim rather than as a vertex that is
      // already there — and the vertices themselves wear nothing (유저:
      // "꼭짓점 점 그리지말라고. 그냥 라이브로 보이면 찍은건지 알수있으니까"
      // — the band is that liveness).
      canvas.drawCircle(
        _map(close),
        closeTargetRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = closeTargetArmed ? 1.5 : 1.0
          ..color = _sessionColor,
      );
    }

    final chrome = transformChrome;
    if (chrome != null) {
      _paintTransformChrome(canvas, chrome);
    }
  }

  void _paintTransformChrome(Canvas canvas, SelectionTransformChrome chrome) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = _sessionColor;
    final fill = Paint()..color = _sessionColor;

    canvas.drawPath(Path()..addPolygon(chrome.box, true), stroke);
    for (final handle in chrome.handles) {
      canvas.drawRect(
        Rect.fromCenter(center: handle, width: 9, height: 9),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromCenter(center: handle, width: 9, height: 9),
        stroke,
      );
    }
    // The rotate lever: line from the top edge midpoint to the knob.
    // Quad mode carries no knob (R20-D2).
    final knob = chrome.knob;
    if (knob != null) {
      final topMid = Offset(
        (chrome.box[0].dx + chrome.box[1].dx) / 2,
        (chrome.box[0].dy + chrome.box[1].dy) / 2,
      );
      canvas.drawLine(topMid, knob, stroke);
      canvas.drawCircle(knob, 5, fill);
    }
  }

  /// White under-stroke + phase-offset dashes in [_antColour]. The white
  /// underneath is what keeps the black readable on dark artwork, and the
  /// black is what keeps the white readable on light — 「흰색바탕에 검정
  /// 개미가 지나가도록」 is the pair, not the dash alone.
  ///
  /// ★THIS is 「이 공통 ui」. Every marching outline in the app is painted
  /// here already (R28-S pulled it out of the selection layer so the same
  /// ants show under every tool), so 「앞으로 개미행렬은 이 공통 ui를 사용」
  /// is a rule about where the NEXT one goes rather than a change here.
  void _paintAnts(Canvas canvas, Path path, double phase) {
    final white = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white;
    final dashes = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _antColour;
    canvas.drawPath(path, white);
    canvas.drawPath(_dashPath(path, phase), dashes);
  }

  Path _dashPath(Path source, double phase) {
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var distance = -phase % (_dashOn + _dashOff);
      while (distance < metric.length) {
        final start = distance.clamp(0.0, metric.length);
        final end = (distance + _dashOn).clamp(0.0, metric.length);
        if (end > start) {
          dashed.addPath(metric.extractPath(start, end), Offset.zero);
        }
        distance += _dashOn + _dashOff;
      }
    }
    return dashed;
  }

  @override
  Object get props => (
    outlineIsLive,
    viewport,
    committedRegion,
    startShape,
    screenOffset,
    ByList(marqueeShapes),
    // The live trail is a fresh list per pointer sample, and it is compared
    // by identity for that reason — as a `List`'s own `==` already was.
    ByIdentity(openTrail),
    closeTarget,
    closeTargetArmed,
    ByIdentity(cursor),
    transformChrome,
    sessionHasChanges,
  );
}

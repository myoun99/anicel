part of '../storyboard_panel.dart';

/// A projection row's cut starts as a layer of its stack — over its paper,
/// under everything that answers ([StoryboardCutStartsPainter]).
class _StoryboardCutStarts extends StatelessWidget {
  const _StoryboardCutStarts({
    required this.paintKey,
    required this.starts,
    required this.geometry,
    required this.windowBucket,
  });

  final Key paintKey;
  final List<int> starts;
  final TimelineFrameGeometryHandle geometry;
  final ValueListenable<int> windowBucket;

  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: paintKey,
          painter: StoryboardCutStartsPainter(
            starts: starts,
            geometry: geometry,
            colorScheme: Theme.of(context).colorScheme,
            windowBucket: windowBucket,
          ),
        ),
      ),
    ),
  );
}

/// WHERE EACH CUT BEGINS ON A PROJECTION ROW — a dashed line at each cut's
/// place on the track, on the camera row, the conte row and every row
/// riding it. The drawn proposal: 「투영 행은 컷이 시작하는 자리마다 세로
/// 점선(2 3)」; 유저 2026-10-08: 「컷 클리핑하는거 사이 점선으로 만드는거
/// 좋네. 굉장히 알기쉬워」.
///
/// A projection row shows each cut's own layer side by side, and the line
/// says where one cut's ends and the next one's begins. Painted over the
/// panel's window alone, never pressed.
class StoryboardCutStartsPainter extends CustomPainter with RepaintOnProps {
  StoryboardCutStartsPainter({
    required this.starts,
    required this.geometry,
    required this.colorScheme,
    required this.windowBucket,
  }) : super(repaint: Listenable.merge([geometry, windowBucket]));

  /// Each cut's place on the track — its first frame, not where a のりしろ
  /// before it is drawn from.
  final List<int> starts;
  final TimelineFrameGeometryHandle geometry;
  final ColorScheme colorScheme;
  final ValueListenable<int> windowBucket;

  /// How far the view reaches along the frames — the live geometry's, so a
  /// widened view repaints the lines ([TimelineFrameGeometry.viewExtentPx]).
  double get viewportMainExtent => geometry.value.viewExtentPx;

  /// Two on, three off.
  static const DashPattern dashes = DashPattern(on: 2, off: 3);

  /// Where each cut begins inside the window, row-local x — THE probe
  /// surface, and what [paint] strokes. On the grid's own line, snapped as
  /// it is ([timelineGridLineSnap]) — the sheet leaves that line to the
  /// dash ([TimelineGridRows.dashes], F-347); ↩️stroked on the bare edge,
  /// it ran half a pixel beside the line it should have been.
  List<double> cutStarts() {
    final frames = geometry.value;
    if (frames.frameCellExtent <= 0) {
      return const [];
    }
    final window = visibleFrameWindowFor(
      bucket: windowBucket,
      viewportMainExtent: viewportMainExtent,
      cellExtent: frames.frameCellExtent,
      frameStartIndex: 0,
      frameEndIndexExclusive: 1 << 30,
    );
    return [
      for (final start in starts)
        if (start >= window.startIndex && start < window.endIndexExclusive)
          frames.edgeAt(start) + timelineGridLineSnap,
    ];
  }

  /// 🪶ONE LINE CUT, DRAWN AT EACH START (card frame-panels-build-in-one-
  /// frame, 2026-10-28): every line runs the row's height from its top, so
  /// its dashes stand where any other's do. Each start used to cut its own
  /// line into dashes and draw each dash on its own — on the storyboard,
  /// zoomed out to the whole film, every row of it again whenever the
  /// panel was shown (measured: ~1ms of the reopen frame).
  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final line = Path();
    for (final piece in dashesAlong(
      Path()
        ..moveTo(0, 0)
        ..lineTo(0, size.height),
      dashes,
    )) {
      line.addPath(piece, Offset.zero);
    }
    for (final x in cutStarts()) {
      canvas
        ..save()
        ..translate(x, 0)
        ..drawPath(line, dash)
        ..restore();
    }
  }

  @override
  // Geometry and the window are absent on purpose — they arrive through
  // `repaint`.
  Object get props => (ByList(starts), colorScheme);
}

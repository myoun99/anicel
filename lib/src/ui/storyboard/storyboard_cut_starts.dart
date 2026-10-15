part of '../storyboard_panel.dart';

/// A projection row's cut starts as a layer of its stack — over its paper,
/// under everything that answers ([StoryboardCutStartsPainter]).
class _StoryboardCutStarts extends StatelessWidget {
  const _StoryboardCutStarts({
    required this.paintKey,
    required this.starts,
    required this.geometry,
    required this.windowBucket,
    required this.viewportWidth,
  });

  final Key paintKey;
  final List<int> starts;
  final TimelineFrameGeometryHandle geometry;
  final ValueListenable<int> windowBucket;
  final double viewportWidth;

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
            viewportMainExtent: viewportWidth,
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
    required this.viewportMainExtent,
  }) : super(repaint: Listenable.merge([geometry, windowBucket]));

  /// Each cut's place on the track — its first frame, not where a のりしろ
  /// before it is drawn from.
  final List<int> starts;
  final TimelineFrameGeometryHandle geometry;
  final ColorScheme colorScheme;
  final ValueListenable<int> windowBucket;
  final double viewportMainExtent;

  /// Two on, three off.
  static const DashPattern dashes = DashPattern(on: 2, off: 3);

  /// Where each cut begins inside the window, row-local x — THE probe
  /// surface, and what [paint] strokes.
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
          frames.edgeAt(start),
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = colorScheme.outline
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final x in cutStarts()) {
      final edge = Path()
        ..moveTo(x, 0)
        ..lineTo(x, size.height);
      for (final piece in dashesAlong(edge, dashes)) {
        canvas.drawPath(piece, dash);
      }
    }
  }

  @override
  // Geometry and the window are absent on purpose — they arrive through
  // `repaint`.
  Object get props => (ByList(starts), colorScheme, viewportMainExtent);
}

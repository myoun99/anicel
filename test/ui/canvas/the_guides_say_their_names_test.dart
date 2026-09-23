import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/models/drawing_guide.dart';
import 'package:anicel/src/ui/canvas/guide_overlay.dart';

import '../../helpers/app_faces.dart';

/// 🚨★★★유저 (guide-sym): 「가이드툴 선택된 상태에선 캔버스에 표시되는 자에
/// **이름표시**. 대칭자같은건 **중앙포인트 위에 중앙정렬**로 해당 자의
/// 이름(대칭 2)표시. 퍼스자는 **퍼스자의 이름말고 소실점 이름**을 각 소실점 위
/// 중앙정렬로 표시. / 이름표시는 **가이드툴이 선택됬을때, 그리고 물론
/// 결과적으로 비지블 on**으로 했을때만 표시」.
///
/// ⚠️These RENDER the painter, and they read the DIFFERENCE between two
/// renders rather than counting ink inside a box.
///
/// 🧪The first draft counted ink above the point, and every case passed with
/// the names switched off — the window was catching the guide's own line and
/// the handle drawn there. Subtracting two renders that differ ONLY in the
/// name leaves the name and nothing else, so there is nothing else left to
/// mistake it for.
void main() {
  const size = ui.Size(300, 200);

  DrawingGuide symmetry({String name = '대칭 2', bool visible = true}) =>
      DrawingGuide(
        id: const GuideId('sym'),
        name: name,
        visible: visible,
        shape: SymmetryShape(
          axis: GuideAxis(
            origin: CanvasPoint(x: 150, y: 120),
            angleDegrees: 90,
          ),
        ),
      );

  // Far apart, so each name's cluster is unmistakably its own.
  DrawingGuide perspective() => DrawingGuide(
    id: const GuideId('per'),
    name: '퍼스 1',
    shape: PerspectiveShape(
      eyeLevel: GuideAxis(origin: CanvasPoint(x: 150, y: 120), angleDegrees: 0),
      vanishingPoints: [
        VanishingPointAt(CanvasPoint(x: 40, y: 120)),
        VanishingPointAt(CanvasPoint(x: 260, y: 120)),
      ],
    ),
  );

  GuideOverlayPainter painterFor(
    List<DrawingGuide> guides, {
    required bool emphasized,
    String label = 'VP',
    TextStyle face = const TextStyle(),
  }) => GuideOverlayPainter(
    guides: CutGuides(guides: guides),
    viewport: CanvasViewport(),
    canvasSize: const CanvasSize(width: 300, height: 200),
    emphasized: emphasized,
    color: const Color(0xFF00FF00),
    face: face,
    vanishingPointLabel: label,
  );

  Future<ByteData> render(
    WidgetTester tester,
    GuideOverlayPainter painter,
  ) async {
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    final picture = recorder.endRecording();
    // ⚠️`runAsync`: outside it the fake clock never lets the rasterizer
    // finish and the future simply never completes — a hang, not a failure.
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data;
    });
    picture.dispose();
    return bytes!;
  }

  /// Every pixel where the two renders disagree.
  List<({int x, int y})> differences(ByteData a, ByteData b) {
    final out = <({int x, int y})>[];
    final width = size.width.toInt();
    for (var y = 0; y < size.height.toInt(); y += 1) {
      for (var x = 0; x < width; x += 1) {
        final i = (y * width + x) * 4;
        if (a.getUint32(i) != b.getUint32(i)) {
          out.add((x: x, y: y));
        }
      }
    }
    return out;
  }

  testWidgets('a symmetry says ITS name, centred above its centre point', (
    tester,
  ) async {
    final named = await render(
      tester,
      painterFor([symmetry()], emphasized: true),
    );
    final blank = await render(
      tester,
      painterFor([symmetry(name: '')], emphasized: true),
    );
    final diff = differences(named, blank);

    // ★The premise: something WAS drawn. Everything below is about where.
    expect(diff, isNotEmpty, reason: 'the name reaches the canvas at all');

    final xs = diff.map((p) => p.x);
    final ys = diff.map((p) => p.y);
    final left = xs.reduce((a, b) => a < b ? a : b);
    final right = xs.reduce((a, b) => a > b ? a : b);
    final bottom = ys.reduce((a, b) => a > b ? a : b);

    expect(
      bottom,
      lessThan(120),
      reason: '「중앙포인트 위에」 — every pixel of it is above the point',
    );
    expect(
      (left + right) / 2,
      closeTo(150, 2),
      reason: '「중앙정렬」 — its middle is the point x',
    );
  });

  testWidgets('a perspective names each vanishing point, not itself', (
    tester,
  ) async {
    // ⛔Two LABELS rather than name-on/name-off: a vanishing point's name is
    // built from its index, so there is no way to blank it. What differs
    // between these renders is the words above each point, which is exactly
    // what is being asked about.
    final short = await render(
      tester,
      painterFor([perspective()], emphasized: true),
    );
    final long = await render(
      tester,
      painterFor([perspective()], emphasized: true, label: 'MMMMMM'),
    );
    final diff = differences(short, long);
    expect(diff, isNotEmpty);

    for (final x in [40, 260]) {
      expect(
        diff.any((p) => (p.x - x).abs() < 45 && p.y < 120),
        isTrue,
        reason: 'the point at $x has a name of its own, above it',
      );
    }
    expect(
      diff.every((p) => p.y < 120),
      isTrue,
      reason: 'and nothing was written below any of them',
    );
  });

  testWidgets('⛔a HIDDEN guide says nothing', (tester) async {
    final named = await render(
      tester,
      painterFor([symmetry(visible: false)], emphasized: true),
    );
    final blank = await render(
      tester,
      painterFor([symmetry(name: '', visible: false)], emphasized: true),
    );
    expect(
      differences(named, blank),
      isEmpty,
      reason: '「물론 결과적으로 비지블 on으로 했을때만 표시」',
    );
  });

  testWidgets('⛔and so does a guide whose tool is not in hand', (tester) async {
    final named = await render(
      tester,
      painterFor([symmetry()], emphasized: false),
    );
    final blank = await render(
      tester,
      painterFor([symmetry(name: '')], emphasized: false),
    );
    expect(
      differences(named, blank),
      isEmpty,
      reason: '「가이드툴이 선택됬을때」 — a quiet guide keeps its lines only',
    );
  });

  testWidgets('a name is set in the app\'s face, not the OS\'s (「앱은 한 글꼴」, '
      '08-28)', (tester) async {
    await loadTheAppFaces();
    const face = TextStyle(fontFamily: 'BIZ UDPGothic');
    double widthIn(TextStyle style) => (TextPainter(
      text: TextSpan(
        text: 'Sym 2',
        style: style.copyWith(fontSize: 11, height: 1.1),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).maxIntrinsicWidth;
    expect(
      widthIn(face),
      isNot(closeTo(widthIn(const TextStyle()), 0.5)),
      reason: 'the premise: the two faces set the name at different widths',
    );

    final painted = _PaintedWidths();
    painterFor(
      [symmetry(name: 'Sym 2')],
      emphasized: true,
      face: face,
    ).paint(painted, size);
    expect(painted.widths, hasLength(1));
    expect(painted.widths.single, closeTo(widthIn(face), 0.5));
  });
}

/// The natural width of every paragraph painted, in painting order.
class _PaintedWidths implements Canvas {
  final widths = <double>[];

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) =>
      widths.add(paragraph.maxIntrinsicWidth);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// STILL EDGE PROBE — is a region's still image the same pixels as the region
// drawn live, on THIS engine? (card dock-pixels-differ-between-runs-at-one-
// scroll-position-on-the-surface, Q2 b: 「원인을 재서 그림 가장자리를 라이브와
// 맞춘다」 — 🔬the Surface parted them by up to 25/255 at the edges, the main
// PC by about 1.)
//
//   flutter run -d windows --release -t tool/probe/still_edge_probe_main.dart \
//     --dart-define=EDGE_OUT=<dir>
//
// It stays open showing a table: a row per way of taking the image, a column
// per shape, and in each cell the shape drawn LIVE on the left and put back
// from an image on the right. It writes `layout.json` into EDGE_OUT — where
// each half stands, in device pixels from the magenta mark in the window's
// top-left corner. Take a screenshot of the screen at its own resolution
// (nothing over the window), then:
//
//   dart run tool/probe/still_edge_compare.dart <screenshot.png> \
//     <EDGE_OUT>/layout.json
//
// The image is taken and put back as `StillRaster` does: the shape's layer
// drawn by `Scene.toImageSync` on a transparent ground, put back 1:1 with
// `FilterQuality.none` (`RasterGridFit.blitPart`). The other rows each change
// ONE thing about that, so the row that agrees with the live half names the
// cause:
//
//   scene         the region's own way
//   opaque        the panel's ground drawn into the image under the shape —
//                 does compositing a premultiplied edge over the ground part
//                 from drawing it on the ground?
//   picture       `Picture.toImageSync` — the scene's layers or the picture?
//   twice         taken at twice the pixels and put back halved — does the
//                 offscreen target take fewer samples an edge than the screen?
//   layer         no image: the right half drawn live inside a `saveLayer` —
//                 does ANY offscreen target part from the screen?
//
// Below them, the APP'S OWN way: the right half is the region itself
// (`StillRaster`, as every dock region and row stands on one), round widgets
// a dock is made of — the shapes above as a `CustomPaint`, a rounded pill,
// blocks under a clip, a text widget, a pill under an opacity — the left
// half the same widgets live. Three times: on whole device pixels (`still`),
// and a third and a half of a device pixel over (`stl+1/3`, `stl+1/2`),
// where a 150% screen stands a logical third. Then the layers a dock adds
// round them (🔬the Surface, 11-07 22:31: the three rows above all agreed
// with the live half): a region inside the region a third of a device pixel
// in, as a dock's image holds its rows' (`nest`, `nst+1/2`), and the widget
// over and under a tick that is painted again at every frame — the same
// pixels each time — which the region draws live between its strata
// (`tick-o`, `tick-u`). Its layout is written once the regions have their
// images, and each such cell says how many bytes its image holds
// (`imageBytes`, 0 while it paints live — then it measured nothing), why it
// last painted (`standDown`) and, for a tick it could not draw live, why
// (`tickRefusals`).
//
// Measurement, not a feature: not wired into the app, no strings, no UI
// conventions apply.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:anicel/src/ui/widgets/still_raster.dart';
import 'package:anicel/src/ui/widgets/tick_layer.dart' show TickOverlay;

const _outDir = String.fromEnvironment('EDGE_OUT', defaultValue: '');

/// One cell's half, in device pixels.
const int _half = 72;

/// Room between the cells and round the table, in device pixels.
const int _gap = 12;

/// The mark the compare finds the window by: magenta, this many device
/// pixels a side, in the window's top-left corner.
const int _mark = 8;

/// The panel's ground the shapes stand on, and their inks — the dock's own
/// dark surface and accent, near enough.
const _ground = Color(0xFF26282C);
const _accent = Color(0xFF4F8DF5);
const _ink = Color(0xFFE6E8EB);

/// The ways an image is taken, in table order.
const _variants = ['scene', 'opaque', 'picture', 'twice', 'layer'];

/// A shape drawn in a cell [_half] device pixels a side, from its corner.
typedef _Shape = ({String name, void Function(Canvas canvas) draw});

final List<_Shape> _shapes = [
  (
    name: 'rrect-fill',
    draw: (canvas) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8.3, 10.6, 52.4, 30.2),
        const Radius.circular(6.5),
      ),
      Paint()..color = _accent,
    ),
  ),
  (
    name: 'rrect-line',
    draw: (canvas) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(8.5, 10.5, 52, 40),
        const Radius.circular(6),
      ),
      Paint()
        ..color = _ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    ),
  ),
  (
    name: 'circle',
    draw: (canvas) => canvas.drawCircle(
      const Offset(36.3, 35.7),
      22.4,
      Paint()..color = _accent,
    ),
  ),
  (
    name: 'diagonal',
    draw: (canvas) => canvas.drawLine(
      const Offset(6, 64),
      const Offset(66, 9),
      Paint()
        ..color = _ink
        ..strokeWidth = 1.5,
    ),
  ),
  (name: 'text', draw: _drawText),
  (
    name: 'half-alpha',
    draw: (canvas) => canvas.drawRect(
      const Rect.fromLTWH(10, 10, 52, 52),
      Paint()..color = _accent.withValues(alpha: 0.5),
    ),
  ),
  (name: 'image', draw: _drawSmallImage),
];

void _drawText(Canvas canvas) {
  final builder =
      ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 15))
        ..pushStyle(ui.TextStyle(color: _ink))
        ..addText('値速度\nAg 1-2');
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: _half - 8.0));
  canvas.drawParagraph(paragraph, const Offset(4.4, 8.2));
  paragraph.dispose();
}

/// A small image of its own with soft edges, drawn 1:1 on whole pixels —
/// the rows' tiles are images like it.
ui.Image? _small;

void _drawSmallImage(Canvas canvas) {
  final image = _small;
  if (image == null) {
    return;
  }
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    Rect.fromLTWH(10, 10, image.width.toDouble(), image.height.toDouble()),
    Paint()..filterQuality = FilterQuality.low,
  );
}

ui.Image _makeSmallImage() {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(2.5, 3.5, 44, 40),
      const Radius.circular(9),
    ),
    Paint()..color = const Color(0xFFF2A33A),
  );
  canvas.drawCircle(
    const Offset(25, 24),
    9.3,
    Paint()..color = const Color(0x8020C060),
  );
  final picture = recorder.endRecording();
  final image = picture.toImageSync(50, 48);
  picture.dispose();
  return image;
}

/// How a row of the app's own cells holds its widget in the right half.
enum _Hold {
  /// In the region.
  region,

  /// In a region a third of a device pixel inside the region — a dock's
  /// image holding its rows' images.
  nested,

  /// Over a tick that changes alone at every frame, which the region draws
  /// live between its strata: the widget is the stratum above it.
  overTick,

  /// Under that tick: the widget is the stratum below it.
  underTick,
}

/// The app's own way's rows: a name, how far over a whole device pixel
/// both halves stand, and how the right half holds the widget.
const _stillVariants = [
  ('still', 0.0, _Hold.region),
  ('stl+1/3', 1 / 3, _Hold.region),
  ('stl+1/2', 0.5, _Hold.region),
  ('nest', 0.0, _Hold.nested),
  ('nst+1/2', 0.5, _Hold.nested),
  ('tick-o', 1 / 3, _Hold.overTick),
  ('tick-u', 1 / 3, _Hold.underTick),
];

/// The most cells a line of the app's own rows holds; a row goes on to the
/// next line past it.
const int _stillColumns = 11;

/// [widget] as [hold] stands it in a half — [inRegion] for the right one,
/// which a region holds. The left half stands the same pixels live: the
/// nested region's inset, the tick's mark.
Widget _held(
  _Hold hold,
  double ratio,
  Widget widget, {
  required bool inRegion,
  required Listenable beat,
}) {
  switch (hold) {
    case _Hold.region:
      return widget;
    case _Hold.nested:
      return Padding(
        padding: EdgeInsets.only(left: 1 / 3 / ratio, top: 1 / 3 / ratio),
        child: inRegion
            ? StillRaster(debugLabel: 'probe-in', child: widget)
            : widget,
      );
    case _Hold.overTick || _Hold.underTick:
      // A 4-device-pixel mark in the corner no widget draws in, painted
      // again at every frame — the same pixels each time.
      final tick = TickOverlay(
        children: [
          Positioned(
            right: 3 / ratio,
            bottom: 3 / ratio,
            width: 4 / ratio,
            height: 4 / ratio,
            child: CustomPaint(painter: _TickMark(beat)),
          ),
        ],
      );
      return Stack(
        fit: StackFit.expand,
        children: hold == _Hold.overTick ? [tick, widget] : [widget, tick],
      );
  }
}

/// The tick's mark: the same square at every [beat].
class _TickMark extends CustomPainter {
  _TickMark(Listenable beat) : super(repaint: beat);

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawRect(Offset.zero & size, Paint()..color = _ink);

  @override
  bool shouldRepaint(_TickMark oldDelegate) => false;
}

/// A widget a cell holds, made at [ratio] device pixels a logical one, its
/// sizes given in device pixels from the cell's corner as the shapes are.
typedef _WidgetShape = ({String name, Widget Function(double ratio) build});

/// [left], [top], [width], [height] device pixels inside a cell.
Widget _at(
  double ratio,
  double left,
  double top,
  double width,
  double height,
  Widget child,
) => Positioned(
  left: left / ratio,
  top: top / ratio,
  width: width / ratio,
  height: height / ratio,
  child: child,
);

Widget _pill(double ratio) => Stack(
  children: [
    _at(
      ratio,
      8.3,
      10.6,
      52.4,
      30.2,
      DecoratedBox(
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(6.5 / ratio),
        ),
      ),
    ),
  ],
);

final List<_WidgetShape> _widgetShapes = [
  for (final shape in _shapes)
    (
      name: shape.name,
      build: (ratio) => CustomPaint(painter: _ShapePainter(shape, ratio)),
    ),
  (name: 'pill', build: _pill),
  (
    name: 'clip-blocks',
    build: (ratio) => Stack(
      children: [
        _at(
          ratio,
          6.4,
          9.7,
          58.1,
          50.2,
          ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _at(
                  ratio,
                  -10,
                  4.2,
                  40,
                  18.5,
                  const ColoredBox(color: _accent),
                ),
                _at(
                  ratio,
                  33.3,
                  26.6,
                  40,
                  18.5,
                  const ColoredBox(color: Color(0xFFF2A33A)),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
  (
    name: 'text-widget',
    build: (ratio) => Padding(
      padding: EdgeInsets.fromLTRB(4.4 / ratio, 8.2 / ratio, 0, 0),
      child: Text(
        '値速度\nAg 1-2',
        style: TextStyle(
          inherit: false,
          color: _ink,
          fontSize: 15 / ratio,
          height: 1.2,
        ),
      ),
    ),
  ),
  (
    name: 'opacity',
    build: (ratio) => Opacity(opacity: 0.5, child: _pill(ratio)),
  ),
];

/// [shape] painted in device pixels from a box's corner.
class _ShapePainter extends CustomPainter {
  _ShapePainter(this.shape, this.ratio);

  final _Shape shape;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(1 / ratio);
    shape.draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapePainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.ratio != ratio;
}

/// Where the app's own cell of variant [variant], shape [shape] stands —
/// `[x, y, side, side]` in device pixels from the window's corner — on the
/// lines below the table's.
({List<int> live, List<int> image}) _stillCellAt(int variant, int shape) {
  final lines = (_widgetShapes.length + _stillColumns - 1) ~/ _stillColumns;
  return _cellAt(
    _variants.length + variant * lines + shape ~/ _stillColumns,
    shape % _stillColumns,
  );
}

ui.Picture _pictureOf(_Shape shape, {Color? under, double scale = 1}) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (scale != 1) {
    canvas.scale(scale);
  }
  if (under != null) {
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _half + 0.0, _half + 0.0),
      Paint()..color = under,
    );
  }
  shape.draw(canvas);
  return recorder.endRecording();
}

/// [shape] taken as [variant] says, [_half] device pixels a side — null for
/// the variant that takes none.
ui.Image? _take(_Shape shape, String variant) {
  switch (variant) {
    case 'scene' || 'opaque' || 'twice':
      final twice = variant == 'twice';
      final picture = _pictureOf(
        shape,
        under: variant == 'opaque' ? _ground : null,
        scale: twice ? 2 : 1,
      );
      final builder = ui.SceneBuilder()
        ..pushOffset(0, 0)
        ..addPicture(Offset.zero, picture)
        ..pop();
      final scene = builder.build();
      final side = twice ? 2 * _half : _half;
      final image = scene.toImageSync(side, side);
      scene.dispose();
      picture.dispose();
      return image;
    case 'picture':
      final picture = _pictureOf(shape);
      final image = picture.toImageSync(_half, _half);
      picture.dispose();
      return image;
  }
  return null;
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _EdgeProbeApp());
}

class _EdgeProbeApp extends StatefulWidget {
  const _EdgeProbeApp();

  @override
  State<_EdgeProbeApp> createState() => _EdgeProbeAppState();
}

class _EdgeProbeAppState extends State<_EdgeProbeApp>
    with SingleTickerProviderStateMixin {
  /// Each cell's image, by variant then shape; null until taken.
  List<List<ui.Image?>>? _images;

  /// What the tick rows' marks are painted again at: every frame.
  final ValueNotifier<int> _beat = ValueNotifier(0);
  late final _ticker = createTicker((_) => _beat.value += 1);

  @override
  void dispose() {
    _ticker.dispose();
    _beat.dispose();
    super.dispose();
  }

  /// The app's own cells' regions, by variant then shape.
  final List<List<GlobalKey>> _regions = [
    for (final _ in _stillVariants)
      [for (final _ in _widgetShapes) GlobalKey()],
  ];

  RenderStillRaster? _regionOf(int variant, int shape) =>
      _regions[variant][shape].currentContext?.findRenderObject()
          as RenderStillRaster?;

  bool get _everyRegionIsAnImage => [
    for (var v = 0; v < _stillVariants.length; v += 1)
      for (var s = 0; s < _widgetShapes.length; s += 1) _regionOf(v, s),
  ].every((region) => (region?.rasterBytes ?? 0) > 0);

  @override
  void initState() {
    super.initState();
    _ticker.start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _takeAll());
  }

  Future<void> _takeAll() async {
    _small = _makeSmallImage();
    final images = [
      for (final variant in _variants)
        [for (final shape in _shapes) _take(shape, variant)],
    ];
    setState(() => _images = images);
    final view = View.of(context);
    // Once every region of the app's own rows holds its image — or ten
    // seconds on, and the cells that paint live say so.
    for (var tries = 0; tries < 40 && !_everyRegionIsAnImage; tries += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    await _writeLayout(view.devicePixelRatio);
  }

  /// Where each cell's two halves stand, in device pixels from the mark.
  Future<void> _writeLayout(double ratio) async {
    final cells = [
      for (var row = 0; row < _variants.length; row += 1)
        for (var column = 0; column < _shapes.length; column += 1)
          {
            'variant': _variants[row],
            'shape': _shapes[column].name,
            'live': _cellAt(row, column).live,
            'image': _cellAt(row, column).image,
          },
      for (final (variant, (name, _, _)) in _stillVariants.indexed)
        for (final (shape, widget) in _widgetShapes.indexed)
          {
            'variant': name,
            'shape': widget.name,
            'live': _stillCellAt(variant, shape).live,
            'image': _stillCellAt(variant, shape).image,
            'imageBytes': _regionOf(variant, shape)?.rasterBytes ?? 0,
            'standDown': _regionOf(variant, shape)?.standDown.name,
            // A tick row whose tick the region could not draw live between
            // its strata says why here — then it measured a baked tick.
            'tickRefusals': _regionOf(variant, shape)?.debugTickRefusals,
          },
    ];
    final out = Directory(_outDir.isEmpty ? 'still_edge_probe_out' : _outDir);
    await out.create(recursive: true);
    await File('${out.path}/layout.json').writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'devicePixelRatio': ratio,
        'half': _half,
        'mark': _mark,
        'cells': cells,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final ratio = View.of(context).devicePixelRatio;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ColoredBox(
        color: _ground,
        child: images == null
            ? const SizedBox.expand()
            : Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(painter: _TablePainter(images, ratio)),
                  ),
                  for (final (variant, (_, over, hold))
                      in _stillVariants.indexed)
                    for (final (shape, widget) in _widgetShapes.indexed) ...[
                      _cell(
                        _stillCellAt(variant, shape).live,
                        over,
                        ratio,
                        _held(
                          hold,
                          ratio,
                          widget.build(ratio),
                          inRegion: false,
                          beat: _beat,
                        ),
                      ),
                      _cell(
                        _stillCellAt(variant, shape).image,
                        over,
                        ratio,
                        StillRaster(
                          key: _regions[variant][shape],
                          debugLabel: 'probe',
                          child: _held(
                            hold,
                            ratio,
                            widget.build(ratio),
                            inRegion: true,
                            beat: _beat,
                          ),
                        ),
                      ),
                    ],
                ],
              ),
      ),
    );
  }
}

/// [child] in the cell [rect] of device pixels, [over] a device pixel
/// further right and down.
Widget _cell(List<int> rect, double over, double ratio, Widget child) =>
    Positioned(
      left: (rect[0] + over) / ratio,
      top: (rect[1] + over) / ratio,
      width: rect[2] / ratio,
      height: rect[3] / ratio,
      child: child,
    );

/// Where cell [row], [column]'s halves stand, `[x, y, side, side]` in device
/// pixels from the window's corner.
({List<int> live, List<int> image}) _cellAt(int row, int column) {
  final x = _gap + _mark + column * (2 * _half + 2 * _gap);
  final y = _gap + _mark + row * (_half + _gap);
  return (
    live: [x, y, _half, _half],
    image: [x + _half + _gap ~/ 2, y, _half, _half],
  );
}

class _TablePainter extends CustomPainter {
  _TablePainter(this.images, this.ratio);

  final List<List<ui.Image?>> images;
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything in device pixels, from the window's corner.
    canvas.scale(1 / ratio);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, _mark + 0.0, _mark + 0.0),
      Paint()..color = const Color(0xFFFF00FF),
    );
    for (var row = 0; row < _variants.length; row += 1) {
      for (var column = 0; column < _shapes.length; column += 1) {
        final (:live, :image) = _cellAt(row, column);
        final shape = _shapes[column];
        canvas
          ..save()
          ..translate(live[0] + 0.0, live[1] + 0.0);
        shape.draw(canvas);
        canvas
          ..restore()
          ..save()
          ..translate(image[0] + 0.0, image[1] + 0.0);
        final taken = images[row][column];
        if (taken == null) {
          // `layer`: the shape live, inside an offscreen layer.
          canvas.saveLayer(
            const Rect.fromLTWH(0, 0, _half + 0.0, _half + 0.0),
            Paint(),
          );
          shape.draw(canvas);
          canvas.restore();
        } else {
          final side = math.min(taken.width, 2 * _half).toDouble();
          canvas.drawImageRect(
            taken,
            Rect.fromLTWH(0, 0, side, side),
            const Rect.fromLTWH(0, 0, _half + 0.0, _half + 0.0),
            Paint()
              ..filterQuality = taken.width == _half
                  ? FilterQuality.none
                  : FilterQuality.medium,
          );
        }
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(_TablePainter oldDelegate) =>
      oldDelegate.images != images || oldDelegate.ratio != ratio;
}

// Renders every platform's app icon and the desktop launch splash from the
// one mark, so no picture of it is drawn twice by hand.
//
// I-106 (user, 2026-10-20): the teal stencil — app accent #4FA8A0 rounded
// square, a white bold A without a crossbar, a white dot where the bar
// would be, the ENLARGED dot at every size (「애초에 키운점을 기본으로하자」).
// I-106-Q3/Q4/Q5: the desktop launch splash is the A alone in teal (no
// square), the name below in WHITE (「통일감없는건 아쉽지만 이게 젤
// 이뻐」), on a transparent window, closed at the first Flutter frame, on
// every desktop. I-106-Q6: its height is half its monitor's short side
// (「짧은 변의 50%로하면 가로일땐 높이의 50%」) — the runners scale it.
//
// Run from the repo root (it writes the platform folders in place):
//   bash tool/run.sh test_queue flutter test tool/app_art/render_app_art_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The mark on its 120-unit grid.
const double kGrid = 120;
const Color kTeal = Color(0xFF4FA8A0);
const Color kWhite = Color(0xFFFFFFFF);
const double kCornerRadius = 27;
const List<Offset> kStroke = [Offset(30, 100), Offset(60, 24), Offset(90, 100)];
const double kStrokeWidth = 22;
const Offset kDotCenter = Offset(60, 90);
const double kDotRadius = 10;

/// The A's extent with its stroke, on the grid (round caps and joins).
const Rect kLetterBounds = Rect.fromLTRB(19, 13, 101, 111);

/// Apple's macOS icon template: the body is 824 of 1024, centred.
const double kMacBody = 824 / 1024;

/// The splash's layout, in its own units.
const double kSplashWidth = 240;
const double kSplashHeight = 232;

/// Where the runners write the launch stage (I-106, 2026-10-21): close
/// under the name, small and faint — 「Anicel 아래에 어느정도 붙고, 글자크기도
/// 좀 작게 … 있는듯 없는듯한 느낌으로」. Left empty here, its place kept in
/// the picture's own margin. The runners spell its middle and its type
/// size again, as shares of the picture's height: 210 / 232 and 8 / 232.
const double kSplashStageCenter = 210;
const double kSplashStageSize = 8;
const double kSplashLetterScale = 1.3;
const double kSplashNameSize = 34;
const double kSplashGap = 12;
const Color kShadow = Color(0x73000000);
const Offset kShadowOffset = Offset(0, 3);
const double kShadowSigma = 5;

/// The splash picture's height in pixels: half the short side of a 5K
/// monitor (2880), so the runners only ever scale it down.
const double kSplashPictureHeight = 1440;

Path letterPath() => Path()
  ..moveTo(kStroke[0].dx, kStroke[0].dy)
  ..lineTo(kStroke[1].dx, kStroke[1].dy)
  ..lineTo(kStroke[2].dx, kStroke[2].dy);

Paint strokePaint(Color color) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = kStrokeWidth
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

void paintLetter(Canvas canvas, Color color, {MaskFilter? blur}) {
  final stroke = strokePaint(color)..maskFilter = blur;
  final dot = Paint()
    ..color = color
    ..maskFilter = blur
    ..isAntiAlias = true;
  canvas
    ..drawPath(letterPath(), stroke)
    ..drawCircle(kDotCenter, kDotRadius, dot);
}

enum IconShape {
  /// The rounded square fills the canvas (Windows, Linux, Android legacy).
  rounded,

  /// The square fills edge to edge with no corners — iOS masks it itself
  /// and refuses transparency.
  fullBleed,

  /// The rounded square inside Apple's macOS template margin.
  macTemplate,
}

/// The icon at [size] pixels.
Future<Uint8List> renderIcon(int size, IconShape shape) {
  return renderPng(size, size, (canvas) {
    final px = size.toDouble();
    final body = shape == IconShape.macTemplate ? px * kMacBody : px;
    final inset = (px - body) / 2;
    canvas
      ..translate(inset, inset)
      ..scale(body / kGrid);
    final square = Paint()
      ..color = kTeal
      ..isAntiAlias = true;
    if (shape == IconShape.fullBleed) {
      canvas.drawRect(const Rect.fromLTWH(0, 0, kGrid, kGrid), square);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, kGrid, kGrid),
          const Radius.circular(kCornerRadius),
        ),
        square,
      );
    }
    paintLetter(canvas, kWhite);
  });
}

/// The launch splash at [scale] times its layout: the teal A, the white
/// name under it, a soft shadow under both, nothing else.
Future<Uint8List> renderSplash(double scale) {
  final width = (kSplashWidth * scale).round();
  final height = (kSplashHeight * scale).round();
  return renderPng(width, height, (canvas) {
    canvas.scale(scale);
    final letterWidth = kLetterBounds.width * kSplashLetterScale;
    final letterHeight = kLetterBounds.height * kSplashLetterScale;
    final name = TextPainter(
      text: const TextSpan(
        text: 'Anicel',
        style: TextStyle(
          fontFamily: 'BIZ UDPGothic',
          fontWeight: FontWeight.w700,
          fontSize: kSplashNameSize,
          color: kWhite,
          shadows: [
            Shadow(
              color: kShadow,
              offset: kShadowOffset,
              blurRadius: 8,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top =
        (kSplashHeight - letterHeight - kSplashGap - name.height) / 2;
    final left = (kSplashWidth - letterWidth) / 2;

    void placeLetter() => canvas
      ..translate(left, top)
      ..scale(kSplashLetterScale)
      ..translate(-kLetterBounds.left, -kLetterBounds.top);

    const blur = MaskFilter.blur(
      BlurStyle.normal,
      kShadowSigma / kSplashLetterScale,
    );
    canvas
      ..save()
      ..translate(kShadowOffset.dx, kShadowOffset.dy);
    placeLetter();
    paintLetter(canvas, kShadow, blur: blur);
    canvas
      ..restore()
      ..save();
    placeLetter();
    paintLetter(canvas, kTeal);
    canvas.restore();
    name.paint(
      canvas,
      Offset(
        (kSplashWidth - name.width) / 2,
        top + letterHeight + kSplashGap,
      ),
    );
  });
}

Future<Uint8List> renderPng(
  int width,
  int height,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  paint(Canvas(recorder));
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

/// [png] with its alpha channel dropped: App Store Connect refuses an iOS
/// app icon that has one, even fully opaque, and `dart:ui` always writes
/// RGBA.
Uint8List withoutAlpha(Uint8List png) =>
    img.encodePng(img.decodePng(png)!.convert(numChannels: 3));

/// A Windows .ico holding one PNG per size (Vista and later read them).
Uint8List icoOf(Map<int, Uint8List> pngs) {
  final sizes = pngs.keys.toList()..sort();
  final header = BytesBuilder()
    ..add(_le16(0))
    ..add(_le16(1))
    ..add(_le16(sizes.length));
  var offset = 6 + 16 * sizes.length;
  final body = BytesBuilder();
  for (final size in sizes) {
    final png = pngs[size]!;
    header
      ..addByte(size >= 256 ? 0 : size)
      ..addByte(size >= 256 ? 0 : size)
      ..addByte(0)
      ..addByte(0)
      ..add(_le16(1))
      ..add(_le16(32))
      ..add(_le32(png.length))
      ..add(_le32(offset));
    offset += png.length;
    body.add(png);
  }
  return (header..add(body.takeBytes())).takeBytes();
}

List<int> _le16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _le32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

String _n(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';

/// Android's adaptive foreground as a vector, from the same geometry. The
/// 108dp layer shows about 72dp through a launcher's mask, so the 120-unit
/// mark is laid at 0.6dp a unit around the centre.
String androidForeground({required String color}) {
  const scale = 72 / kGrid;
  const shift = (108 - kGrid * scale) / 2;
  const a = kStroke;
  const d = kDotCenter;
  const r = kDotRadius;
  return '''
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_art/render_app_art_test.dart — edit the mark there. -->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
  <group
      android:translateX="${_n(shift)}"
      android:translateY="${_n(shift)}"
      android:scaleX="${_n(scale)}"
      android:scaleY="${_n(scale)}">
    <path
        android:pathData="M${_n(a[0].dx)},${_n(a[0].dy)} L${_n(a[1].dx)},${_n(a[1].dy)} L${_n(a[2].dx)},${_n(a[2].dy)}"
        android:strokeColor="$color"
        android:strokeWidth="${_n(kStrokeWidth)}"
        android:strokeLineCap="round"
        android:strokeLineJoin="round" />
    <path
        android:pathData="M${_n(d.dx - r)},${_n(d.dy)} a${_n(r)},${_n(r)} 0 1,0 ${_n(2 * r)},0 a${_n(r)},${_n(r)} 0 1,0 ${_n(-2 * r)},0 Z"
        android:fillColor="$color" />
  </group>
</vector>
''';
}

const String kAndroidAdaptive = '''
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_art/render_app_art_test.dart. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background" />
  <foreground android:drawable="@drawable/ic_launcher_foreground" />
  <monochrome android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
''';

String androidBackground() {
  final hex = kTeal.toARGB32().toRadixString(16).substring(2).toUpperCase();
  return '''
<?xml version="1.0" encoding="utf-8"?>
<!-- Generated by tool/app_art/render_app_art_test.dart. -->
<resources>
  <color name="ic_launcher_background">#$hex</color>
</resources>
''';
}

void write(String path, List<int> bytes) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

void writeText(String path, String text) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsStringSync(text);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('render the app icons and the launch splash', () async {
    final font = FontLoader('BIZ UDPGothic')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File('assets/fonts/BIZUDPGothic-Bold.ttf').readAsBytesSync(),
          ),
        ),
      );
    await font.load();

    // Windows: one .ico, every size the shell asks for.
    final ico = <int, Uint8List>{};
    for (final size in const [16, 20, 24, 32, 40, 48, 64, 128, 256]) {
      ico[size] = await renderIcon(size, IconShape.rounded);
    }
    write('windows/runner/resources/app_icon.ico', icoOf(ico));

    // The Microsoft Store package's logos (store-distribution-plan-Q2,
    // 유저 10-30 「MS 스토어도 지금 시작」), named as windows/msix/AppxManifest.xml
    // names them; tool/msix_pack.sh indexes the qualifiers into resources.pri.
    // The unplated sizes are the taskbar's and Start's, drawn as the .ico is.
    const store = 'windows/msix/Assets';
    write('$store/Square150x150Logo.scale-200.png',
        await renderIcon(300, IconShape.rounded));
    write('$store/Square44x44Logo.scale-200.png',
        await renderIcon(88, IconShape.rounded));
    for (final size in const [16, 24, 32, 48, 256]) {
      write('$store/Square44x44Logo.targetsize-${size}_altform-unplated.png',
          await renderIcon(size, IconShape.rounded));
    }
    write('$store/StoreLogo.scale-200.png',
        await renderIcon(100, IconShape.rounded));

    // macOS: the template's sizes, named as Contents.json names them.
    for (final size in const [16, 32, 64, 128, 256, 512, 1024]) {
      write(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
        await renderIcon(size, IconShape.macTemplate),
      );
    }

    // iOS: every file the set already lists, sized from its name.
    final ios = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
    final iosName = RegExp(r'^Icon-App-([\d.]+)x[\d.]+@(\d)x\.png$');
    for (final file in ios.listSync().whereType<File>()) {
      final match = iosName.firstMatch(file.uri.pathSegments.last);
      if (match == null) continue;
      final size =
          (double.parse(match[1]!) * int.parse(match[2]!)).round();
      write(
        file.path,
        withoutAlpha(await renderIcon(size, IconShape.fullBleed)),
      );
    }

    // Android: the adaptive icon, and the legacy square for older launchers.
    const legacy = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    const res = 'android/app/src/main/res';
    for (final entry in legacy.entries) {
      write(
        '$res/mipmap-${entry.key}/ic_launcher.png',
        await renderIcon(entry.value, IconShape.rounded),
      );
    }
    writeText(
      '$res/drawable/ic_launcher_foreground.xml',
      androidForeground(color: '#FFFFFFFF'),
    );
    writeText('$res/mipmap-anydpi-v26/ic_launcher.xml', kAndroidAdaptive);
    writeText('$res/values/ic_launcher_background.xml', androidBackground());

    // Linux: the window icon.
    write('linux/runner/resources/app_icon.png',
        await renderIcon(256, IconShape.rounded));

    // The launch splash: one picture, scaled down by each runner to half
    // its monitor's short side (I-106-Q6).
    final splash = await renderSplash(kSplashPictureHeight / kSplashHeight);
    write('windows/runner/resources/launch_splash.png', splash);
    const splashSet = 'macos/Runner/Assets.xcassets/LaunchSplash.imageset';
    write('$splashSet/launch_splash.png', splash);
    writeText('$splashSet/Contents.json', '''
{
  "images" : [
    {
      "filename" : "launch_splash.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
''');
    write('linux/runner/resources/launch_splash.png', splash);
  });
}

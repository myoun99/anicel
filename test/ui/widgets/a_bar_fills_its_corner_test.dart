import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

/// 🗣️a-live-dock-frame-costs-a-whole-draw-Q10 (유저 2026-11-08, 2: 「그림 안의
/// 자르기를 『자르지 않고 그 모양으로 칠하는』 그리기로 다시 짠다」 — 「값 막대의
/// 값 칠은 축에 맞는 사각형으로 자르고(정확) 그 안에 초타원 채움」): a bar's fill
/// is the track's shape where it lies, never a rectangle clipped to the
/// corner — a clip parts an image of the bar from the bar on the screen.
void main() {
  const width = 120.0;
  const ground = Color(0xFF101010);
  const ink = Color(0xFF3355FF);

  Future<RenderBox> pumpBar(WidgetTester tester, double value) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Center(
          child: RepaintBoundary(
            child: ColoredBox(
              color: ground,
              child: SizedBox(
                width: width,
                child: FieldSlider(
                  value: value,
                  min: 0,
                  max: 1,
                  color: ink,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return tester.renderObject(find.byType(FieldSliderTrack));
  }

  RSuperellipse trackOf(RenderBox track) => BorderRadius.circular(
    FieldSlider.radiusFor(track.size.height),
  ).toRSuperellipse(Offset.zero & track.size);

  testWidgets('a full bar fills the track\'s shape itself, clipping no '
      'corner', (tester) async {
    final track = await pumpBar(tester, 1);
    final shape = trackOf(track);
    // Past the frame's own shapes, which come first.
    expect(
      track,
      paints..something(
        (method, arguments) =>
            method == #drawRSuperellipse &&
            arguments.first == shape &&
            isSameColorAs(ink).matches((arguments[1] as Paint).color, {}),
      ),
    );
    // A rectangle's clip is the writing's own (its inks), and exact.
    for (final clip in [#clipRSuperellipse, #clipPath, #clipRRect]) {
      expect(track, paintsExactlyCountTimes(clip, 0), reason: '$clip');
    }
  });

  testWidgets('a half bar is the track\'s shape cut where the fill ends — by '
      'a hard-edged rectangle', (tester) async {
    final track = await pumpBar(tester, 0.5);
    final half = Rect.fromLTWH(0, 0, width / 2, track.size.height);
    expect(
      track,
      paints
        ..clipRect(rect: half)
        ..rsuperellipse(rsuperellipse: trackOf(track), color: ink),
    );
    final spy = _Cuts();
    tester.widget<FieldSliderTrack>(find.byType(FieldSliderTrack)).fill.paint(
      spy,
      track.size,
    );
    expect(spy.cuts, [(rect: half, antiAliased: false)]);
  });

  testWidgets('nothing of a full bar is drawn past its corner', (
    tester,
  ) async {
    await pumpBar(tester, 1);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    final size = boundary.size;
    final track = tester.renderObject<RenderBox>(
      find.byType(FieldSliderTrack),
    );
    final origin = track.localToGlobal(Offset.zero, ancestor: boundary);
    final pixels = (await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
    /// How far the pixel at [point] is from the ground, in its bluest
    /// channel — the ink's.
    int fromGround(Offset point) {
      final i = (point.dy.floor() * size.width.round() + point.dx.floor()) * 4;
      return (pixels[i + 2] - (ground.b * 255).round()).abs();
    }

    // The corner pixel is the shape's rim — a sliver of it at most; a fill
    // laid as a rectangle would be the ink there whole.
    for (final corner in [
      origin,
      origin + Offset(track.size.width - 1, 0),
      origin + Offset(0, track.size.height - 1),
      origin + Offset(track.size.width - 1, track.size.height - 1),
    ]) {
      expect(fromGround(corner), lessThan(64), reason: 'at $corner');
    }
    expect(
      fromGround(origin + track.size.center(Offset.zero)),
      greaterThan(200),
      reason: 'fixture: the bar is drawn where it lies',
    );
  });
}

typedef _Cut = ({Rect rect, bool antiAliased});

/// The rectangles a fill was cut to, and whether each edge was smoothed.
class _Cuts implements Canvas {
  final cuts = <_Cut>[];

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => cuts.add((rect: rect, antiAliased: doAntiAlias));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

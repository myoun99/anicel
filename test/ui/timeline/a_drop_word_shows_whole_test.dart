import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_section_defaults.dart'
    show transitionLayerIdForTrack;
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/axis_turn.dart'
    show endAcross, endAlong, offsetAlong, partAcross, partAlong, startAcross,
        startAlong;
import 'package:anicel/src/ui/timeline/timeline_orientation.dart';
import 'package:anicel/src/ui/widgets/instant_tap_region.dart'
    show InstantTapRegion;

import '../../helpers/line_on_screen.dart';
import '../../helpers/named_finders.dart';

import '../../helpers/timeline_host.dart';

/// 🚨F-393 ② (검증 2026-11-16, 서피스 · 150%): the rider at the end of the
/// list, carried past it, let go of its base as it should — and its word
/// 「アタッチを解除」, centred across the line at the rail's last edge, showed
/// its upper half only: the rail's rows are cut off where they end, and
/// the word stood half past them. The law is the user's (F-423②, 10-20):
/// 「가로선 안에 다 보이도록」.
///
/// Read off the pixels, as a line's showing is
/// (`a_line_past_the_lanes_shows_test`): where the word stands says nothing
/// of what of it is seen. The sheet's word was hidden for another reason:
/// wider than a column, it ran under the columns painted after it.
///
/// ⚠️No conte rail here: carried past its end, a conte seat draws no line
/// at all (measured 11-16 — its seats move within the conte group), so no
/// word stands at its ends. Its lines and words take the same road
/// (`RailRowLines`), should one ever do.
void main() {
  final word = find.ancestor(
    of: find.text(AppText.strings.tlDropDetachAttach),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox && widget.decoration is ShapeDecoration,
    ),
  );

  testWidgets('the rail\'s last line says its word whole, standing on the '
      'last row', (tester) async {
    await pumpTimelineHost(
      tester,
      _film([
        _rider('under', AttachedPlacement.below),
        _layer('base'),
      ]),
      surface: const Size(790, 446),
    );
    final row = tester.getRect(find.named('timeline-layer-row-under'));

    final gesture = await _carry(
      tester,
      find.named('timeline-layer-name-under'),
      Axis.horizontal,
      row.bottom + 8,
    );
    final shown = await _wordOnScreen(tester, word, Axis.horizontal);
    final hidden = await _glyphSlicesHidden(tester, Axis.horizontal);
    final at = tester.getRect(word);
    await _letGo(tester, gesture);

    expect(shown, greaterThan(0.95));
    expect(hidden, 0);
    expect(
      at.bottom,
      row.bottom,
      reason: 'moved inside no further than it must',
    );
  });

  // 🔬F-393 ① (검증 2026-11-17, 서피스): this line stands at the top of the
  // carried row, which is selected — and the selection's band ran its edge
  // through the middle of the word.
  testWidgets('CONTROL: a line between two rows says its word centred '
      'across it, over the carried row\'s selection', (tester) async {
    await pumpTimelineHost(
      tester,
      _film([_layer('base'), _rider('over', AttachedPlacement.above)]),
      surface: const Size(790, 446),
    );
    final transition = transitionLayerIdForTrack(const TrackId('t')).value;
    final above = tester.getRect(find.named('timeline-layer-row-$transition'));

    final gesture = await _carry(
      tester,
      find.named('timeline-layer-name-over'),
      Axis.horizontal,
      above.top + above.height * 0.8,
    );
    final shown = await _wordOnScreen(tester, word, Axis.horizontal);
    final hidden = await _glyphSlicesHidden(tester, Axis.horizontal);
    final at = tester.getRect(word);
    final line = tester.getRect(
      find.byKey(const ValueKey<String>('timeline-row-caret-before-over')),
    );
    await _letGo(tester, gesture);

    expect(shown, greaterThan(0.95));
    expect(hidden, 0);
    expect(at.center.dy, line.center.dy);
  });

  testWidgets('the sheet\'s first line says its word whole', (tester) async {
    await pumpTimelineHost(
      tester,
      _film([
        _rider('under', AttachedPlacement.below),
        _layer('base'),
      ]),
      surface: const Size(1400, 900),
      orientation: TimelineOrientation.vertical,
    );
    final column = tester.getRect(find.named('xsheet-column-under-cells'));

    final gesture = await _carry(
      tester,
      find.named('xsheet-layer-name-under'),
      Axis.vertical,
      column.left - 8,
    );
    final shown = await _wordOnScreen(tester, word, Axis.vertical);
    final hidden = await _glyphSlicesHidden(tester, Axis.vertical);
    await _letGo(tester, gesture);

    expect(shown, greaterThan(0.95));
    expect(hidden, 0);
  });
}

Project _film(List<Layer> layers) => Project(
  id: const ProjectId('word'),
  name: 'Word',
  createdAt: DateTime.utc(2026, 11, 16),
  tracks: [
    Track(id: const TrackId('t'), name: 'V', cuts: [_cut(layers)]),
  ],
);

/// One cut of [layers] (model order, bottom → top) under a camera.
Cut _cut(List<Layer> layers) => Cut(
  id: const CutId('c'),
  name: 'C',
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  camera: CutCamera.empty(),
  layers: [
    ...layers,
    Layer(
      id: const LayerId('cam'),
      name: 'Camera',
      kind: LayerKind.camera,
      frames: const [],
    ),
  ],
);

Layer _layer(String id) =>
    Layer(id: LayerId(id), name: id.toUpperCase(), frames: const []);

/// [id], riding `base` on its [placement] side.
Layer _rider(String id, AttachedPlacement placement) => Layer(
  id: LayerId(id),
  name: id.toUpperCase(),
  frames: const [],
  attachedToLayerId: const LayerId('base'),
  attachedPlacement: placement,
  attachedMode: AttachedMode.free,
);

/// [grip]'s row, selected by a drag along the rows' [axis] and then
/// carried to [to] across them, held there.
Future<TestGesture> _carry(
  WidgetTester tester,
  Finder grip,
  Axis axis,
  double to,
) async {
  await tester.dragFrom(
    tester.getCenter(grip),
    offsetAlong(axis, along: InstantTapRegion.travelSlop + 2, across: 0),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pumpAndSettle();
  final start = tester.getCenter(grip);
  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(const Duration(milliseconds: 16));
  final from = partAcross(axis, start);
  for (var step = 1; step <= 4; step += 1) {
    await gesture.moveTo(
      offsetAlong(
        axis,
        along: partAlong(axis, start),
        across: from + (to - from) * step / 4,
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  return gesture;
}

Future<void> _letGo(WidgetTester tester, TestGesture gesture) async {
  await gesture.up();
  await tester.pumpAndSettle();
}

/// How much of [badge]'s extent across the rows' [axis] the screen shows
/// in the theme's primary colour, from 0 to 1.
Future<double> _wordOnScreen(
  WidgetTester tester,
  Finder badge,
  Axis axis,
) async {
  expect(badge, findsOneWidget, reason: '⛔전제: the drop says its word');
  final view = tester.binding.renderViews.first;
  final scale = view.configuration.devicePixelRatio;
  final colour = Theme.of(
    tester.element(badge),
  ).colorScheme.primary.toARGB32();
  final at = tester.getRect(badge);
  final width = (view.size.width * scale).round();
  final pixels = await screenPixels(tester);
  bool isWord(int along, int across) {
    final (x, y) = axis == Axis.horizontal
        ? (along, across)
        : (across, along);
    final byte = (y * width + x) * 4;
    return (pixels.getUint8(byte + 3) << 24 |
            pixels.getUint8(byte) << 16 |
            pixels.getUint8(byte + 1) << 8 |
            pixels.getUint8(byte + 2)) ==
        colour;
  }

  final alongFrom = (startAlong(axis, at) * scale).round();
  final alongTo = (endAlong(axis, at) * scale).round();
  final from = (startAcross(axis, at) * scale).round();
  final to = (endAcross(axis, at) * scale).round();
  var shown = 0;
  for (var across = from; across < to; across += 1) {
    for (var along = alongFrom; along < alongTo; along += 1) {
      if (isWord(along, across)) {
        shown += 1;
        break;
      }
    }
  }
  return shown / (to - from);
}

/// How many pixel slices across the rows' [axis] through the drop word's
/// glyphs show none of them — every pixel the theme's primary, a line's
/// colour drawn over the word. ⚠️[_wordOnScreen] cannot tell: it counts
/// that colour, the badge's and a line's alike (F-393 ①, 11-17).
///
/// The slices are the text's own box a pixel in from its edges across,
/// clear of its leading; along, the whole text, where the test font's
/// glyphs are solid.
Future<int> _glyphSlicesHidden(WidgetTester tester, Axis axis) async {
  final text = find.text(AppText.strings.tlDropDetachAttach);
  expect(text, findsOneWidget, reason: '⛔전제: the drop says its word');
  final view = tester.binding.renderViews.first;
  final scale = view.configuration.devicePixelRatio;
  final colour = Theme.of(
    tester.element(text),
  ).colorScheme.primary.toARGB32();
  final at = tester.getRect(text);
  final width = (view.size.width * scale).round();
  final pixels = await screenPixels(tester);
  bool isLine(int along, int across) {
    final (x, y) = axis == Axis.horizontal
        ? (along, across)
        : (across, along);
    final byte = (y * width + x) * 4;
    return (pixels.getUint8(byte + 3) << 24 |
            pixels.getUint8(byte) << 16 |
            pixels.getUint8(byte + 1) << 8 |
            pixels.getUint8(byte + 2)) ==
        colour;
  }

  final alongFrom = (startAlong(axis, at) * scale).ceil();
  final alongTo = (endAlong(axis, at) * scale).floor();
  final from = ((startAcross(axis, at) + 1) * scale).ceil();
  final to = ((endAcross(axis, at) - 1) * scale).floor();
  expect(to - from, greaterThan(4), reason: '⛔전제: slices to look at');
  var hidden = 0;
  for (var across = from; across < to; across += 1) {
    var all = true;
    for (var along = alongFrom; along < alongTo && all; along += 1) {
      all = isLine(along, across);
    }
    if (all) {
      hidden += 1;
    }
  }
  return hidden;
}

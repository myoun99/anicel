import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/ui/timeline/timeline_cel_content_source.dart';
import 'package:anicel/src/ui/timeline/timeline_frame_geometry.dart';
import 'package:anicel/src/ui/timeline/timeline_row_run_labels_painter.dart';

import 'timeline_frame_geometry_probe.dart';

/// 🔬frame-panels-build-in-one-frame (10-28) — a row built again over the
/// same blocks sets its numbers once for what they are drawn from
/// ([TimelineRowRunLabelsPainter.pictureKey]): the storyboard's conte rows
/// set every block's number of the film again at every reopening.
void main() {
  Layer row({int length = 6}) => Layer(
    id: const LayerId('row'),
    name: 'row',
    frames: const [],
    timeline: {
      for (var block = 0; block < 8; block += 1)
        block * length: TimelineExposure.drawing(
          const FrameId('f'),
          length: length,
        ),
    },
  );
  final blocks = row();
  const size = Size(48 * 24, 28);

  ValueNotifier<TimelineFrameGeometry> zoomed(
    double cell, {
    double view = 24 * 20,
  }) => testFrameGeometry(
    frameCellExtent: cell,
    frameEndIndexExclusive: 48,
    viewExtentPx: view,
  );

  /// A row built again: every handle it is handed is a new one — the axis,
  /// and the window it is scrolled to.
  TimelineRowRunLabelsPainter numbers({
    Layer? layer,
    ValueNotifier<TimelineFrameGeometry>? geometry,
    double crossAxisExtent = 28,
    bool showSeconds = false,
    int countingBase = 24,
    TextStyle baseTextStyle = const TextStyle(fontSize: 11),
    Axis axis = Axis.horizontal,
    ValueNotifier<int>? window,
    bool shown = true,
    TimelineCelContentSource? celContent,
    Color? paperGround,
  }) => TimelineRowRunLabelsPainter(
    layer: layer ?? blocks,
    geometry: geometry ?? zoomed(24),
    crossAxisExtent: crossAxisExtent,
    showSeconds: showSeconds,
    countingBase: countingBase,
    baseTextStyle: baseTextStyle,
    axis: axis,
    windowBucket: window ?? ValueNotifier(0),
    shown: shown,
    celContent: celContent,
    paperGround: paperGround,
  );

  /// How many times [painter] set its numbers in one paint.
  int setsOf(TimelineRowRunLabelsPainter painter) {
    final before = TimelineRowRunLabelsPainter.debugRowsSet;
    final recorder = ui.PictureRecorder();
    painter.paint(Canvas(recorder), size);
    recorder.endRecording().dispose();
    return TimelineRowRunLabelsPainter.debugRowsSet - before;
  }

  testWidgets('a row built again over the same blocks sets no number '
      'again', (tester) async {
    setsOf(numbers());
    expect(
      setsOf(numbers()),
      0,
      reason: '↩️every reopening of the storyboard set its conte rows\' '
          'numbers again',
    );
  });

  testWidgets('every input its numbers are drawn from sets them again', (
    tester,
  ) async {
    setsOf(numbers());
    final changed = {
      'its blocks': numbers(layer: row(length: 4)),
      'the seconds toggle': numbers(showSeconds: true),
      // With the seconds shown — the base counts nothing without them.
      'the counting base': numbers(showSeconds: true, countingBase: 30),
      'the face': numbers(
        baseTextStyle: const TextStyle(fontSize: 11, fontFamily: 'Other'),
      ),
      'the row\'s extent': numbers(crossAxisExtent: 40),
      'the axis': numbers(axis: Axis.vertical),
      'the window': numbers(window: ValueNotifier(1)),
      'the viewport': numbers(geometry: zoomed(24, view: 24 * 30)),
      'the eye': numbers(shown: false),
      'what its cels hold': numbers(
        celContent: TimelineCelContentSource(
          hasContent: (_, at) => at >= 6,
          cannotRead: (_, _) => false,
          revision: CelContentRevision.everyRow(ValueNotifier(0)),
        ),
      ),
      'what stands behind it': numbers(paperGround: const Color(0xFF202124)),
      'the zoom': numbers(geometry: zoomed(30)),
    };
    for (final MapEntry(key: input, value: painter) in changed.entries) {
      expect(setsOf(painter), 1, reason: input);
    }
  });

  testWidgets('a row sets its numbers again for what moves under it — a '
      'zoom, a scroll across a span, a cel turning empty', (tester) async {
    final geometry = zoomed(24);
    final window = ValueNotifier(0);
    final revision = ValueNotifier(0);
    final painter = numbers(
      geometry: geometry,
      window: window,
      celContent: TimelineCelContentSource(
        hasContent: (_, at) => at >= revision.value,
        cannotRead: (_, _) => false,
        revision: CelContentRevision.everyRow(revision),
      ),
    );
    setsOf(painter);
    expect(setsOf(painter), 0, reason: 'fixture: kept');
    geometry.value = zoomed(30).value;
    expect(setsOf(painter), 1, reason: 'the zoom');
    window.value = 1;
    expect(setsOf(painter), 1, reason: 'the scroll');
    revision.value = 6;
    expect(setsOf(painter), 1, reason: 'the cel (I-129)');
  });
}

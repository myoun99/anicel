import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_language.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/sheet/sheet_strata.dart';
import 'package:anicel/src/ui/theme/app_theme.dart' show AppTypography;
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';
import 'package:anicel/src/ui/timesheet/timesheet_notation.dart';

import '../../helpers/app_faces.dart';

/// 🚨THE TIMESHEET'S FORM COMPARES ITS SHAPE, AND ITS SHAPE IS ALL IT
/// PRINTS.
///
/// The form stratum does not re-record for a value typed on the sheet (유저
/// 2026-09-25: 「텍스트 바뀌거나 하는데 용지 리빌드하면 너무
/// 비효율적이잖아」) — so what it compares is a list written by hand of what
/// it reads. A list that missed something would keep printing the old form.
/// Asked of each change here, both ways: a change the form calls its own is
/// one it prints differently, and a change it calls not its own prints the
/// very same pixels.
void main() {
  // ⚠️In the app's own faces: the test font sets every glyph as one square,
  // so 「A」 and 「Z」 printed the same pixels and a renamed column looked
  // like no change at all.
  setUpAll(loadTheAppFaces);
  const fps = 24;

  Layer layer(String id, String name, Map<int, int> exposures) => Layer(
    id: LayerId(id),
    name: name,
    kind: LayerKind.animation,
    frames: [
      for (final start in exposures.keys)
        Frame(id: FrameId('$id-$start'), duration: 1, strokes: const []),
    ],
    timeline: {
      for (final entry in exposures.entries)
        entry.key: TimelineExposure.drawing(
          FrameId('$id-${entry.key}'),
          length: entry.value,
        ),
    },
  );

  final base = Cut(
    id: const CutId('c'),
    name: '12',
    duration: 48,
    canvasSize: const CanvasSize(width: 1920, height: 1080),
    layers: [
      layer('a', 'A', {0: 12, 12: 12}),
    ],
  );
  const info = TimesheetInfo(title: 'T');

  TimesheetDocumentPainter form(
    Cut cut, {
    TimesheetInfo info = info,
    int fps = fps,
    AppLanguage language = AppLanguage.ja,
  }) {
    final document = TimesheetDocument.fromCut(
      cut: cut,
      projectName: 'P',
      fps: fps,
      info: info,
    );
    return TimesheetDocumentPainter(
      document: document,
      layout: TimesheetDocumentLayout(document: document),
      face: const TextStyle(
        fontFamily: AppTypography.bundledFamily,
        fontFamilyFallback: AppTypography.bundledFallback,
      ),
      layers: SheetStratum.form.layers,
      notation: TimesheetNotation.of(language),
    );
  }

  Future<(Size, Uint8List)> printed(
    WidgetTester tester,
    TimesheetDocumentPainter painter,
  ) async {
    final size = painter.layout.documentSize;
    final recorder = ui.PictureRecorder();
    painter.paint(ui.Canvas(recorder), size);
    final picture = recorder.endRecording();
    final bytes = (await tester.runAsync(() async {
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    picture.dispose();
    return (size, bytes);
  }

  final before = form(base);

  // Values typed on the sheet or drawn into it — none of them the form's.
  final values = <String, TimesheetDocumentPainter>{
    'the cut renamed': form(base.copyWith(name: '12A')),
    'a memo written': form(
      base.copyWith(metadata: base.metadata.copyWith(note: 'O.L')),
    ),
    'the title retyped': form(base, info: info.copyWith(title: 'U')),
    'an exposure held longer': form(
      base.copyWith(
        layers: [
          layer('a', 'A', {0: 18, 18: 6}),
        ],
      ),
    ),
    'the bar threshold changed': form(
      base,
      info: info.copyWith(exposureBarThreshold: () => 3),
    ),
  };

  // The sheet's shape: its columns, its pages, its header boxes, its frame
  // rate and the language its words are printed in.
  final shapes = <String, TimesheetDocumentPainter>{
    'a column added': form(
      base.copyWith(
        layers: [
          ...base.layers,
          layer('b', 'B', {0: 48}),
        ],
      ),
    ),
    // The letter over a column is the layer's name.
    'a layer renamed': form(
      base.copyWith(
        layers: [
          layer('a', 'Z', {0: 12, 12: 12}),
        ],
      ),
    ),
    'the frame rate changed': form(base, fps: 30),
    'the cut grown past a page': form(base.copyWith(duration: 200)),
    'a header box hidden': form(
      base,
      info: info.copyWith(hiddenFields: {TimesheetHeaderField.scene}),
    ),
    'the notation language changed': form(base, language: AppLanguage.ko),
  };

  for (final MapEntry(key: name, value: after) in values.entries) {
    testWidgets('$name: the form does not re-record, and prints the same '
        'pixels', (tester) async {
      expect(after.shouldRepaint(before), isFalse);
      final (sizeBefore, pixelsBefore) = await printed(tester, before);
      final (sizeAfter, pixelsAfter) = await printed(tester, after);
      expect(sizeAfter, sizeBefore);
      expect(
        pixelsAfter,
        pixelsBefore,
        reason: 'the form printed differently for a change it did not '
            'call its own — its shape list misses what it reads',
      );
    });
  }

  for (final MapEntry(key: name, value: after) in shapes.entries) {
    testWidgets('$name: the form re-records, and prints differently', (
      tester,
    ) async {
      final (sizeBefore, pixelsBefore) = await printed(tester, before);
      final (sizeAfter, pixelsAfter) = await printed(tester, after);
      expect(
        sizeAfter != sizeBefore || !listEquals(pixelsAfter, pixelsBefore),
        isTrue,
        reason: 'fixture: the change reaches the printed form',
      );
      expect(after.shouldRepaint(before), isTrue);
    });
  }
}

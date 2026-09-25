import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/timesheet_document.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/conte/conte_page_painter.dart';
import 'package:anicel/src/ui/conte/conte_sheet_builder.dart';
import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/sheet_marks.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';
import 'package:anicel/src/ui/timesheet/timesheet_document_painter.dart';

/// F-88 (유저 2026-09-12): 「타임라인 엔드라인 조절할때 타임시트헤더의 초수랑
/// 페이지수같은것도 갱신. 콘티패널의 초수도 똑같이」.
///
/// What each sheet SAYS while a cut-length drag is in flight — the strings
/// the paint prints, read through the same calls it makes. The paper does
/// not re-flow mid-drag (the document is memoized against the committed
/// cut); the numbers on it do.
void main() {
  group('the timesheet header', () {
    const cutId = CutId('cut-1');
    TimesheetDocument documentOf({int duration = 24}) =>
        TimesheetDocument.fromCut(
          cut: Cut(
            id: cutId,
            name: '1',
            duration: duration,
            canvasSize: const CanvasSize(width: 1920, height: 1080),
            layers: const [],
          ),
          projectName: 'P',
          fps: 24,
        );

    TimesheetDocumentPainter painterOn(
      TimesheetDocument document,
      ValueNotifier<TimelineDragPreview?> channel,
    ) => TimesheetDocumentPainter(
      face: const TextStyle(),
      document: document,
      layout: TimesheetDocumentLayout(document: document),
      dragPreview: channel,
      cutId: cutId,
    );

    test('prints the committed length and sheet count with no drag', () {
      final channel = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(channel.dispose);
      final painter = painterOn(documentOf(), channel);

      expect(painter.headerValueFor(TimesheetHeaderField.time, 0), '1 + 0');
      expect(painter.headerValueFor(TimesheetHeaderField.sheet, 0), '1/1');
    });

    test('🚨prints the length the drag is holding, and the sheet count that '
        'length needs', () {
      final channel = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(channel.dispose);
      final document = documentOf();
      final painter = painterOn(document, channel);
      expect(
        document.pageFrameCount,
        144,
        reason: 'fixture premise: six seconds of rows to a sheet',
      );

      // 150 frames: past the first sheet, so the cut needs a second one.
      channel.value = CutTrimDragPreview(
        previewDurations: {cutId: 150},
      );
      expect(painter.headerValueFor(TimesheetHeaderField.time, 0), '6 + 6');
      expect(painter.headerValueFor(TimesheetHeaderField.sheet, 0), '1/2');
      expect(
        document.durationLabel,
        '1+0',
        reason: 'the document is memoized against the COMMITTED cut',
      );
    });

    test('a trim that stays on the sheet leaves the sheet count alone', () {
      final channel = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(channel.dispose);
      final painter = painterOn(documentOf(), channel);

      channel.value = CutTrimDragPreview(
        previewDurations: {cutId: 100},
      );
      expect(painter.headerValueFor(TimesheetHeaderField.time, 0), '4 + 4');
      expect(painter.headerValueFor(TimesheetHeaderField.sheet, 0), '1/1');
    });

    test('another cut\'s drag is not this sheet\'s business', () {
      final channel = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(channel.dispose);
      final painter = painterOn(documentOf(), channel);

      channel.value = CutTrimDragPreview(
        previewDurations: {const CutId('other'): 150},
      );
      expect(painter.headerValueFor(TimesheetHeaderField.time, 0), '1 + 0');
    });
  });

  group('the conte page', () {
    Project project() => Project(
      id: const ProjectId('conte-lengths'),
      name: 'Conte',
      cameraSize: const CanvasSize(width: 32, height: 18),
      createdAt: DateTime.utc(2026, 9, 16),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'Video',
          cuts: [
            for (var index = 0; index < 2; index += 1)
              Cut(
                id: CutId('c$index'),
                name: '${index + 1}',
                duration: 6,
                canvasSize: const CanvasSize(width: 64, height: 36),
                layers: [
                  Layer(
                    id: LayerId('c$index-sb'),
                    name: 'SB',
                    kind: LayerKind.storyboard,
                    frames: [
                      Frame(
                        id: FrameId('c$index-f'),
                        duration: 1,
                        strokes: const [],
                      ),
                    ],
                    timeline: {
                      0: TimelineExposure.drawing(
                        FrameId('c$index-f'),
                        length: 6,
                      ),
                    },
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    /// What the time column and the page's foot print, read off the marks
    /// the page prints — the words in the TIME column's body (its head
    /// prints 秒), top to bottom, and the running total under the table.
    ({List<String> times, String total}) printed(ContePagePainter painter) {
      final metrics = painter.metrics;
      final words = painter.marks().whereType<SheetWords>();
      return (
        times: [
          for (final word in words)
            if (word.slot.left >= metrics.timeLeft - 0.001 &&
                word.slot.top >= metrics.bodyTop - 0.001 &&
                word.slot.bottom <= metrics.bodyBottom + 0.001)
              word.text,
        ],
        total: words
            .firstWhere((word) => word.slot == metrics.pageTotalSlot)
            .text,
      );
    }

    test('🚨a cut\'s length and the page total follow the drag; with no drag '
        'they are the cuts\' own', () {
      final source = buildConteSheetSource(project());
      final page = layoutConteSheet(source).first;
      final channel = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(channel.dispose);
      final painter = ContePagePainter(
        page: page,
        source: source,
        dragPreview: channel,
      );
      expect(
        page.cutBands.every((band) => band.showsLength),
        isTrue,
        reason: 'fixture premise: both cuts end on this page',
      );

      // Two one-block cuts: each prints its total and no block length.
      expect(printed(painter).times, ['0+6', '0+6']);
      expect(printed(painter).total, '0+12');

      // The first cut is dragged out to thirty frames.
      channel.value = CutTrimDragPreview(
        previewDurations: {const CutId('c0'): 30},
      );
      expect(printed(painter).times, ['1+6', '0+6']);
      expect(
        printed(painter).total,
        '1+12',
        reason: 'the running total is the lengths ending here, read live',
      );
    });

    test('a page with no drag channel prints the cuts\' own lengths', () {
      final source = buildConteSheetSource(project());
      final page = layoutConteSheet(source).first;
      final painter = ContePagePainter(page: page, source: source);

      expect(printed(painter).times, ['0+6', '0+6']);
      expect(printed(painter).total, '0+12');
    });
  });
}

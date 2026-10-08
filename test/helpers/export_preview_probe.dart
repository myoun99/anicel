import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/export/export_preview_document.dart';
import 'package:anicel/src/ui/export/export_preview_panel.dart';
import 'package:anicel/src/ui/export/export_settings_modules.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/transport_bar.dart';

/// The export window's preview, read as it is DRAWN — the picture that is
/// up, the name on its plate, the transport under it.
extension ExportPreviewProbe on WidgetTester {
  Finder get _exportPreview => find.byType(ExportPreviewPanel);

  ExportPreviewPanelState get exportPreview =>
      state<ExportPreviewPanelState>(_exportPreview);

  /// The file under preview, as the window hands it to the panel.
  ExportPreviewDocument? get exportPreviewDocument =>
      widget<ExportPreviewPanel>(_exportPreview).document;

  /// Waits for the picture of the page stood on to land, and draws it.
  Future<void> settleExportPreview() async {
    await runAsync(exportPreview.debugSettle);
    await pump();
  }

  /// The picture that is up, or null while none is.
  ui.Image? get exportPreviewImage => exportPreview.debugPicture.image;

  /// Whether it stands on the transparency checker.
  bool get exportPreviewCheckered => exportPreview.debugPicture.checkered;

  BrushCanvasPanel get _exportPreviewCanvas => widget<BrushCanvasPanel>(
    find.descendant(of: _exportPreview, matching: find.byType(BrushCanvasPanel)),
  );

  /// The name on the preview's plate, or null where there is none.
  String? get exportPreviewName => _exportPreviewCanvas.documentName;

  /// Whether that name is one the run does not write.
  bool get exportPreviewNameAbsent => _exportPreviewCanvas.documentAbsent;

  /// The name on the plate, and where the page shown stands among the ones
  /// the preview turns through: `A1.png · 1 / 2`.
  String get exportPreviewLine {
    final panel = widget<ExportPreviewPanel>(_exportPreview);
    return '$exportPreviewName · ${panel.page + 1} / '
        '${panel.document?.pageCount ?? 0}';
  }

  /// The pixels the page shown is written at.
  Size get exportPreviewPageSize {
    final size = _exportPreviewCanvas.canvasSize;
    return Size(size.width.toDouble(), size.height.toDouble());
  }

  /// What the head of the tab's name module says: the first file its run
  /// writes — the module titled 이름 for a file a hand names, 이름 규칙
  /// for files a rule names.
  String get exportFirstFileName {
    final strings = AppText.strings;
    return widgetList<ExportAccordion>(find.byType(ExportAccordion))
        .singleWhere(
          (module) =>
              module.title == strings.commonNameField ||
              module.title == strings.exNaming,
        )
        .summary;
  }

  Finder get exportTransportBar =>
      find.descendant(of: _exportPreview, matching: find.byType(TransportBar));

  /// The transport under the preview — there on the tabs whose file runs.
  TransportBar get exportTransport => widget<TransportBar>(exportTransportBar);

  /// Seeks the preview's transport to [frame], as a hand on its track does.
  Future<void> seekExportPreview(int frame) async {
    exportTransport.onSeek(frame);
    await pump();
  }

  /// Types a one-based frame into the transport's IN or OUT readout, as a
  /// hand does: a press opens it, Enter commits.
  Future<void> typeExportRange({String? inFrame, String? outFrame}) async {
    for (final (end, typed) in [('in', inFrame), ('out', outFrame)]) {
      if (typed == null) {
        continue;
      }
      await tap(find.byKey(ValueKey<String>('export-transport-$end')));
      await pump();
      await enterText(
        find.byKey(ValueKey<String>('export-transport-$end-input')),
        typed,
      );
      await testTextInput.receiveAction(TextInputAction.done);
      await pump();
    }
  }
}



import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/empty_state_text.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/services/media/viewer_document.dart';
import 'package:anicel/src/services/pdf/pdf_render_service.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/media/media_viewer_tab_host.dart';
import 'package:anicel/src/ui/text/app_strings.dart';

/// 🚨★★★**「NO DECODER IN THIS BUILD」 IS A DIFFERENT SENTENCE FROM 「THIS
/// FILE COULD NOT BE READ」, AND THE VIEWER USED TO SAY THE FIRST FOR BOTH.**
///
/// `VideoViewerDocument.open` returned null for two unrelated things — no
/// engine at all, and an engine that refused this file. The viewer turns
/// null into 「No video decoder in this build — movies cannot be shown.」, so
/// opening an `.mkv` on an iPad, where the decoder is right there and
/// AVFoundation has simply never read Matroska, sent the user hunting for a
/// codec they already had.
///
/// ⚠️The comment two lines above that message already warned about this
/// exact failure on a different axis: 「⛔One message for all three would
/// send someone hunting for a codec they do not need.」
void main() {
  group('the truth table, apart from any engine', () {
    // 🧪Here rather than through a decoder on purpose: a widget test cannot
    // conjure a native library, and the table is what was wrong.
    test('no engine is not the same as a refusal', () {
      expect(
        viewerOpenOutcome(hasReader: false, opened: false),
        ViewerOpenOutcome.noReaderInThisBuild,
      );
      expect(
        viewerOpenOutcome(hasReader: true, opened: false),
        ViewerOpenOutcome.unreadable,
        reason:
            '🚨a reader that is PRESENT and failed is not「no reader」— this '
            'is the case that used to answer with the other sentence',
      );
      expect(
        viewerOpenOutcome(hasReader: true, opened: true),
        ViewerOpenOutcome.opened,
      );
    });

    test('the reason survives being thrown', () {
      const failure = ViewerDocumentException('no decoder for this codec');
      expect('$failure', 'no decoder for this codec');
    });
  });

  group('what the panel says', () {
    late EditorSessionManager session;
    late MediaViewerSlot slot;

    setUp(() {
      session = EditorSessionManager(initialProject: createDefaultProject());
      slot = MediaViewerSlot();
    });

    tearDown(() {
      PdfRenderService.debugResetForTests();
      slot.dispose();
      session.dispose();
    });

    Future<void> openRefusing(WidgetTester tester, Exception failure) async {
      PdfRenderService.debugOpenerOverride = (_) async => throw failure;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaViewerTabHost(
              viewerId: 'media-viewer',
              session: session,
              request: slot.request,
              position: 0,
            ),
          ),
        ),
      );
      await tester.pump();
      slot.request.value = const MediaViewerRequest(
        path: 'C:/work/reference.pdf',
        kind: MediaAssetKind.pdf,
        name: 'reference',
      );
      await tester.pumpAndSettle();
    }

    /// The message the panel is showing, whatever it is made of.
    String shownMessage(WidgetTester tester) => tester
        .widget<EmptyStateText>(
          find.byKey(const ValueKey<String>('media-viewer-message')),
        )
        .text;

    testWidgets('🚨a file the engine refused says WHY, in the engine\'s own '
        'words, under the sentence that says what', (tester) async {
      await openRefusing(
        tester,
        const ViewerDocumentException('this file has no readable video stream'),
      );
      final shown = shownMessage(tester);
      expect(
        shown,
        contains(AppText.strings.mediaViewerLoadFailed),
        reason: 'the localized sentence stays — the detail rides under it',
      );
      expect(
        shown,
        contains('this file has no readable video stream'),
        reason:
            '🚨the engines have always answered with a reason and nobody '
            'read it. A user who cannot quote the reason cannot report it.',
      );
      expect(
        shown,
        isNot(contains(AppText.strings.mediaViewerNoPdfRenderer)),
        reason:
            '⛔and NOT the missing-engine sentence: the engine is right '
            'here, refusing one file',
      );
    });
  });
}

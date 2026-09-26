import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/timesheet_info.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';

/// 🚨A PICTURE THAT LANDS REPAINTS THE SHEET. A sheet painter asks for the
/// logo, the cover picture or a 도장 SYNCHRONOUSLY; the first ask answers
/// null and the decode runs aside (`SheetImageCache`). Nothing the painter
/// compares changes when it lands — so unless the landing itself repaints
/// the page, the picture shows only after the next pan. ↩️That was the
/// case: the cache called the workspace back, the workspace rebuilt, and
/// the painters, seeing equal inputs, kept their old pixels.
///
/// Measured here as the painter asking again: a repaint asks, a kept
/// picture does not.
void main() {
  const logo = 'media/logo.png';

  EditorSessionManager sessionWithALogo() {
    final project = createDefaultProject();
    final session = EditorSessionManager(
      initialProject: project.copyWith(
        timesheetInfo: TimesheetInfo.empty.copyWith(
          logoAssetPath: () => logo,
        ),
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  Future<void> pumpHost(WidgetTester tester, Widget host) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: host)));
    await tester.pumpAndSettle();
  }

  for (final (name, build) in <(
    String,
    Widget Function(
      EditorSessionManager session,
      ui.Image? Function(String) imageFor,
      Listenable landed,
    ),
  )>[
    (
      'the conte',
      (session, imageFor, landed) => ConteTabHost(
        session: session,
        thumbnails: null,
        imageFor: imageFor,
        imageRepaint: landed,
      ),
    ),
    (
      'the envelope',
      (session, imageFor, landed) => CutEnvelopeTabHost(
        session: session,
        imageFor: imageFor,
        imageRepaint: landed,
      ),
    ),
  ]) {
    testWidgets('$name repaints when the logo it asked for lands', (
      tester,
    ) async {
      final session = sessionWithALogo();
      final landed = ValueNotifier<int>(0);
      addTearDown(landed.dispose);
      var asked = 0;
      await pumpHost(
        tester,
        build(session, (path) {
          if (path == logo) {
            asked += 1;
          }
          return null;
        }, landed),
      );
      expect(asked, greaterThan(0), reason: 'the page prints a logo');
      final before = asked;

      await tester.pump();
      expect(asked, before, reason: 'a frame with nothing new paints nothing');

      landed.value += 1;
      await tester.pump();

      expect(
        asked,
        greaterThan(before),
        reason: 'the landing repainted the page, which asked again',
      );
    });
  }
}

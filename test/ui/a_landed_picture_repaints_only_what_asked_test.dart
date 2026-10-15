import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderCustomPaint;
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/ui/conte/conte_tab_host.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_tab_host.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/sheet/sheet_image_cache.dart';
import 'package:anicel/src/ui/storyboard_cut_blocks_painter.dart';
import 'package:anicel/src/ui/storyboard_cut_thumbnail_store.dart';
import 'package:anicel/src/ui/storyboard_tab_host.dart';
import 'package:anicel/src/ui/timesheet_tab_host.dart';

/// A picture that LANDS repaints the painters that asked for it and
/// rebuilds nothing — in the workspace as it is wired, with its own store.
///
/// ↩️The store sat in the storyboard tab's and the conte tab's listenable
/// merge, so every landing rebuilt the whole panel: at I-22's ten-minute
/// zoom every cut on the film lands a picture, and the storyboard's ruler,
/// rows and chrome were rebuilt once for each.
void main() {
  Future<void> open(WidgetTester tester, String tab) async {
    await tester.tap(find.byKey(ValueKey<String>(tab)));
    await tester.pumpAndSettle();
  }

  Future<void> pumpHome(WidgetTester tester, {String? tab}) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    if (tab != null) {
      await open(tester, tab);
    }
  }

  // The store's own signal, as a render that lands sends it.
  void land(StoryboardThumbnails thumbnails) =>
      (thumbnails.landed as ChangeNotifier).notifyListeners();

  testWidgets('the storyboard: the blocks that asked repaint, and the panel '
      'is not rebuilt', (tester) async {
    await pumpHome(tester, tab: 'timeline-mode-storyboard-button');
    final blocks = find
        .byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter is StoryboardCutBlocksPainter,
        )
        .first;
    final painter =
        tester.widget<CustomPaint>(blocks).painter!
            as StoryboardCutBlocksPainter;
    final render = tester.renderObject<RenderCustomPaint>(blocks);
    final host = tester.widget<StoryboardTabHost>(
      find.byType(StoryboardTabHost),
    );
    expect(painter.thumbnails, isNotNull, reason: 'the premise: pictures');
    expect(render.debugNeedsPaint, isFalse, reason: 'the premise: settled');

    land(painter.thumbnails!);
    expect(render.debugNeedsPaint, isTrue, reason: 'the blocks heard it');
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(StoryboardTabHost)), host),
      isTrue,
      reason: 'nothing rebuilt the panel for a picture',
    );
  });

  testWidgets('the three sheets draw their media from ONE cache, and each '
      'hears what lands in it — the timesheet its photos (I-97)', (
    tester,
  ) async {
    await pumpHome(tester);
    // The sheet ships open in the right dock (R26 #31).
    final timesheet = tester.widget<TimesheetTabHost>(
      find.byType(TimesheetTabHost),
    );
    await open(tester, 'timeline-mode-conte-button');
    final conte = tester.widget<ConteTabHost>(find.byType(ConteTabHost));
    await open(tester, 'timeline-mode-envelope-button');
    final envelope = tester.widget<CutEnvelopeTabHost>(
      find.byType(CutEnvelopeTabHost),
    );
    final cache = conte.imageRepaint;
    if (cache is! SheetImageCache) {
      fail('the premise: the conte hears the workspace\'s image cache');
    }
    expect(conte.imageFor, cache.imageFor);

    for (final (name, imageFor, landed) in [
      ('envelope', envelope.imageFor, envelope.imageRepaint),
      ('timesheet', timesheet.imageFor, timesheet.imageRepaint),
    ]) {
      expect(identical(landed, cache), isTrue, reason: name);
      expect(imageFor, cache.imageFor, reason: name);
    }
  });

  testWidgets('the conte: the page repaints on its own, and the panel is '
      'not rebuilt', (tester) async {
    await pumpHome(tester, tab: 'timeline-mode-conte-button');
    final host = tester.widget<ConteTabHost>(find.byType(ConteTabHost));
    expect(host.thumbnails, isNotNull, reason: 'the premise: pictures');

    land(host.thumbnails!);
    await tester.pump();

    expect(
      identical(tester.widget(find.byType(ConteTabHost)), host),
      isTrue,
      reason: 'nothing rebuilt the sheet for a picture',
    );
  });
}

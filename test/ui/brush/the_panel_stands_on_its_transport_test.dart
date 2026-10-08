import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/widgets/app_scrollbar_lane.dart';

import '../../helpers/canvas_pill.dart';
import '../../helpers/device_viewport.dart';

/// 🗣️F-289 (유저 2026-10-06): 「왼쪽알약말고 제대로 뷰어패널의 가로스크롤바
/// 아래에 재생버튼같은거 일반적인 미디어플레이어같은거 만들고싶어」 — a canvas
/// panel whose document runs in time stands ON its transport: a docked
/// panel's lanes on a band, the floor's bar on a capsule, and nothing the
/// panel frames lies under either.
///
/// And the file's name: 「그냥 제안한대로 동영상뷰어던 뭐던 해당 위치 고정으로
/// 두자」 — the artwork's lower left, over the horizontal bar, whatever the
/// document is.
void main() {
  const panelSize = Size(900, 420);
  const bandHeight = 53.0;
  const lane = AppScrollbarLane.wide;

  /// What the shell keeps a floating control in from an edge — read off the
  /// pill, so the number is the shell's and not this file's.
  double marginOf(WidgetTester tester) =>
      rectOf(tester, 'canvas-view-pill').top -
      rectOf(tester, 'canvas-editor-panel-shell').top;

  Widget harness({
    required bool onFloor,
    bool transport = true,
    String? documentName,
    EdgeInsets cover = EdgeInsets.zero,
    double bottomOverlay = 0,
    ValueChanged<CanvasViewport>? onViewportChanged,
  }) {
    final panel = BrushCanvasPanel(
      coordinator: null,
      availableFrameKeys: const [],
      cacheInvalidationSink: BrushEditCacheInvalidationSink(),
      canvasSize: const CanvasSize(width: 300, height: 300),
      floorCover: cover,
      floorBottomOverlaySpan: bottomOverlay,
      onViewportChanged: onViewportChanged,
      transport: transport
          ? const CanvasTransportBand(
              height: bandHeight,
              child: SizedBox.expand(
                key: ValueKey<String>('probe-transport'),
              ),
            )
          : null,
      documentName: documentName,
      contentOverride: (context, viewport) => const SizedBox.expand(),
    );
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox.fromSize(
            size: panelSize,
            child: onFloor
                ? CanvasFloorInsets(
                    insets: cover,
                    bottomOverlaySpan: bottomOverlay,
                    child: panel,
                  )
                : panel,
          ),
        ),
      ),
    );
  }

  /// Mounts [widget] in a window with room round the panel.
  Future<void> mount(WidgetTester tester, Widget widget) async {
    await tester.binding.setSurfaceSize(const Size(1000, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(widget);
    await tester.pumpAndSettle();
  }

  /// Where the artwork's middle lands once Fit has framed it, in the
  /// panel's own coordinates.
  Future<Offset> fittedCentre(
    WidgetTester tester,
    Widget Function(ValueChanged<CanvasViewport> onChanged) build,
  ) async {
    CanvasViewport? fitted;
    await mount(tester, build((view) => fitted = view));
    await tester.tap(find.byKey(const ValueKey<String>('canvas-viewport-fit')));
    await tester.pumpAndSettle();
    final centre = renderOf(
      tester,
      fitted!,
    ).canvasToViewport(CanvasPoint(x: 150, y: 150));
    return Offset(centre.x, centre.y);
  }

  group('docked', () {
    testWidgets('the transport is a band along the bottom, ruled off, and '
        'the lanes stand on it', (tester) async {
      await mount(tester, harness(onFloor: false));
      final panel = rectOf(tester, 'canvas-editor-panel-shell');
      final band = rectOf(tester, 'canvas-transport');
      final probe = rectOf(tester, 'probe-transport');

      expect(band.left, panel.left);
      expect(band.right, panel.right);
      expect(band.bottom, panel.bottom);
      expect(probe.height, bandHeight, reason: 'the band\'s own height');
      expect(probe.bottom, panel.bottom);
      expect(band.top, probe.top - 1, reason: 'one rule over the rows');

      expect(
        rectOf(tester, 'canvas-panbar-horizontal'),
        Rect.fromLTRB(
          panel.left,
          band.top - lane,
          panel.right - lane,
          band.top,
        ),
        reason: 'the horizontal lane lies on the band',
      );
      expect(
        rectOf(tester, 'canvas-panbar-vertical'),
        Rect.fromLTRB(
          panel.right - lane,
          panel.top,
          panel.right,
          band.top - lane,
        ),
        reason: 'the vertical lane stops at the corner over it',
      );
      expect(
        rectOf(tester, 'canvas-panbar-corner'),
        Rect.fromLTRB(
          panel.right - lane,
          band.top - lane,
          panel.right,
          band.top,
        ),
      );
    });

    testWidgets('with no transport the lanes stand on the panel\'s own edge', (
      tester,
    ) async {
      await mount(tester, harness(onFloor: false, transport: false));
      final panel = rectOf(tester, 'canvas-editor-panel-shell');
      expect(
        find.byKey(const ValueKey<String>('canvas-transport')),
        findsNothing,
      );
      expect(rectOf(tester, 'canvas-panbar-horizontal').bottom, panel.bottom);
      expect(rectOf(tester, 'canvas-panbar-corner').bottom, panel.bottom);
    });

    testWidgets('Fit centres the artwork in what the pill, the lanes and the '
        'transport leave', (tester) async {
      final centre = await fittedCentre(
        tester,
        (onChanged) => harness(onFloor: false, onViewportChanged: onChanged),
      );
      final pill = pillBandOf(tester);
      const under = lane + bandHeight + 1;
      expect(centre.dx, closeTo((panelSize.width - lane) / 2, 0.5));
      expect(
        centre.dy,
        closeTo(pill + (panelSize.height - pill - under) / 2, 0.5),
        reason: 'nothing framed lies under the band',
      );
    });
  });

  group('on the floor', () {
    const cover = EdgeInsets.only(left: 100, right: 60, bottom: 80);
    const overlay = 20.0;

    testWidgets('the transport is a capsule under the horizontal bar, as '
        'wide as what the panels leave and clear of what lies on the edge', (
      tester,
    ) async {
      await mount(
        tester,
        harness(onFloor: true, cover: cover, bottomOverlay: overlay),
      );
      final panel = rectOf(tester, 'canvas-editor-panel-shell');
      final margin = marginOf(tester);
      final capsule = rectOf(tester, 'canvas-transport');
      final bar = rectOf(tester, 'canvas-panbar-horizontal');

      expect(
        capsule,
        Rect.fromLTRB(
          panel.left + cover.left + margin,
          panel.bottom - cover.bottom - overlay - margin - bandHeight,
          panel.right - cover.right - margin,
          panel.bottom - cover.bottom - overlay - margin,
        ),
      );
      expect(bar.bottom, capsule.top - margin, reason: 'the bar stands on it');
      expect(
        find.byKey(const ValueKey<String>('canvas-panbar-corner')),
        findsNothing,
        reason: 'the floor has no lanes',
      );
    });

    testWidgets('with no transport the bar keeps its place on the edge', (
      tester,
    ) async {
      await mount(
        tester,
        harness(
          onFloor: true,
          transport: false,
          cover: cover,
          bottomOverlay: overlay,
        ),
      );
      final panel = rectOf(tester, 'canvas-editor-panel-shell');
      expect(
        rectOf(tester, 'canvas-panbar-horizontal').bottom,
        panel.bottom - cover.bottom - overlay - marginOf(tester),
      );
    });

    testWidgets('Fit centres the artwork in what the panels, the pill and '
        'the capsule leave', (tester) async {
      final centre = await fittedCentre(
        tester,
        (onChanged) => harness(
          onFloor: true,
          cover: cover,
          bottomOverlay: overlay,
          onViewportChanged: onChanged,
        ),
      );
      final margin = marginOf(tester);
      final pill = pillBandOf(tester);
      // The capsule stands on what lies on the edge, so what it hides
      // reaches from there up past its own top margin.
      final under = cover.bottom + overlay + bandHeight + 2 * margin;
      expect(
        centre.dx,
        closeTo(cover.left + (panelSize.width - cover.horizontal) / 2, 0.5),
      );
      expect(
        centre.dy,
        closeTo(pill + (panelSize.height - pill - under) / 2, 0.5),
        reason: 'nothing framed lies under the capsule',
      );
    });
  });

  group('the file\'s name', () {
    const name = 'cut012_take3.mov';
    const plate = ValueKey<String>('canvas-document-name');

    testWidgets('stands at the artwork\'s lower left over the horizontal '
        'lane, and takes no pointer', (tester) async {
      for (final transport in [false, true]) {
        await mount(
          tester,
          harness(onFloor: false, transport: transport, documentName: name),
        );
        final panel = rectOf(tester, 'canvas-editor-panel-shell');
        final margin = marginOf(tester);
        final across = rectOf(tester, 'canvas-panbar-horizontal');
        final where = tester.getRect(find.byKey(plate));

        expect(find.text(name), findsOneWidget);
        expect(where.left, panel.left + margin);
        expect(where.bottom, across.top - margin, reason: 'over the lane');
        expect(
          tester
              .widget<IgnorePointer>(
                find
                    .ancestor(
                      of: find.byKey(plate),
                      matching: find.byType(IgnorePointer),
                    )
                    .first,
              )
              .ignoring,
          isTrue,
          reason: 'a plate, not a control: the press is the canvas\'s',
        );
      }
    });

    testWidgets('a name longer than the panel is cut short inside it', (
      tester,
    ) async {
      await mount(
        tester,
        harness(onFloor: false, documentName: 'a_very_long_file_name_' * 12),
      );
      final panel = rectOf(tester, 'canvas-editor-panel-shell');
      final margin = marginOf(tester);
      expect(tester.takeException(), isNull);
      expect(
        tester.getRect(find.byKey(plate)).right,
        lessThanOrEqualTo(panel.right - lane - margin),
      );
    });

    testWidgets('on the floor it stands over the bar\'s capsule, inside what '
        'the panels leave', (tester) async {
      const cover = EdgeInsets.only(left: 100, right: 60, bottom: 80);
      await mount(
        tester,
        harness(onFloor: true, cover: cover, documentName: name),
      );
      final panel = rectOf(tester, 'canvas-editor-panel-shell');
      final margin = marginOf(tester);
      final where = tester.getRect(find.byKey(plate));
      expect(where.left, panel.left + cover.left + margin);
      expect(
        where.bottom,
        rectOf(tester, 'canvas-panbar-horizontal').top - margin,
      );
    });

    testWidgets('a panel handed no name writes none', (tester) async {
      await mount(tester, harness(onFloor: false));
      expect(find.byKey(plate), findsNothing);
    });
  });
}

Rect rectOf(WidgetTester tester, String key) =>
    tester.getRect(find.byKey(ValueKey<String>(key)));

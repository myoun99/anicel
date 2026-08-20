import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/canvas_pill.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/canvas_viewport.dart';
import 'package:anicel/src/ui/brush/brush_canvas_defaults.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_cursor_overlay.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_input_settings.dart';
import 'package:anicel/src/ui/canvas/brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/widgets/app_icon_button.dart';
import 'package:anicel/src/ui/widgets/panel_flyout.dart';

import '../helpers/brush_canvas_fixture.dart';
import 'brush_canvas_test_helpers.dart';

/// Everything a floor pill shows that a rail pill folds away — in the order
/// it is laid out, which is also the reverse of the order it folds in.
///
/// Fit and the zoom readout are deliberately NOT here: they are on both
/// bars, and the tests below assert their own things about them.
const floorPillKeys = <String>[
  'probe-host-verb',
  'canvas-viewport-reset',
  'canvas-viewport-zoom-out',
  'canvas-viewport-zoom-in',
  'canvas-viewport-rotate-ccw',
  'canvas-viewport-rotation-label',
  'canvas-viewport-rotate-cw',
  'canvas-viewport-rotate-reset',
  'canvas-viewport-flip',
  'canvas-viewport-flip-vertical',
  'canvas-paper-color-button',
  'canvas-pasteboard-color-button',
  'canvas-backdrop-color-button',
];

/// The panel as the app mounts it, with [onFloor] deciding WHERE.
///
/// 🚨[CanvasFloorInsets] is what says "you are lying on the floor" — the
/// panel reads it out of the tree rather than being told, which is the
/// whole reason no host had to learn a new parameter. A test that wants the
/// floor's pill has to put the panel under one; `floorCover:` is a
/// different thing entirely (how much of the artwork is covered) and says
/// nothing about where the panel is.
Widget floorPillHarness({
  required double width,
  required bool onFloor,
  int leadingCount = 0,
}) {
  final frameKeys = BrushCanvasFixture.createFrameKeys();
  final panel = BrushCanvasPanel(
    coordinator: BrushCanvasFixture.createCoordinator(frameKeys: frameKeys),
    availableFrameKeys: frameKeys,
    cacheInvalidationSink: BrushEditCacheInvalidationSink(),
    floorCover: EdgeInsets.zero,
    canvasSize: const CanvasSize(width: 300, height: 300),
    paperColor: 0xFFFFFFFF,
    onPaperColorChanged: (_) {},
    pasteboardColor: 0xFF202020,
    onPasteboardColorChanged: (_) {},
    backdropArgb: 0xFF101010,
    onBackdropColorChanged: (_) {},
    bottomBarLeading: [
      for (var i = 0; i < leadingCount; i += 1)
        AppIconButton(
          keyValue: 'probe-leading-$i',
          tooltip: 'probe $i',
          icon: const Icon(Icons.circle),
          size: AppIconButtonSize.strip,
          onPressed: () {},
        ),
    ],
    // The media viewer's shape: a verb the host keeps in its settings,
    // which the floor unfolds into a button of its own.
    bottomBarSettings: [
      PanelFlyoutItem(
        keyValue: 'probe-host-verb',
        label: 'probe verb',
        icon: Icons.playlist_add_outlined,
        onSelected: () {},
      ),
    ],
    bottomBarHostToken: leadingCount,
  );
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          height: 420,
          child: onFloor
              ? CanvasFloorInsets(insets: EdgeInsets.zero, child: panel)
              : panel,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('renders embedded canvas without temporary debug controls', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-canvas-panel')),
      findsOneWidget,
    );
    expect(find.byType(InteractiveBrushEditCanvasView), findsOneWidget);
    expect(
      tester
          .widget<InteractiveBrushEditCanvasView>(
            find.byType(InteractiveBrushEditCanvasView),
          )
          .inputSettings,
      BrushEditCanvasInputSettings(size: 10),
    );
    expect(
      find.byKey(
        const ValueKey<String>('interactive-brush-edit-canvas-view-listener'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-frame-1-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-frame-2-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-frame-3-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-undo-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-redo-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-reset-button')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-active-frame-label')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-status-text')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-workspace-debug-reset-help')),
      findsNothing,
    );
    expect(find.text('Debug Reset Session'), findsNothing);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Redo'), findsNothing);
    expect(find.text('Black'), findsNothing);
    expect(find.text('Red'), findsNothing);
  });

  testWidgets('canvas panel does not expose editable brush settings', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('brush-tool-options-bar')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-size-slider')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('brush-tool-opacity-slider')),
      findsNothing,
    );
  });

  testWidgets('유저 R4 #4·#5: the pill and BOTH panbars sit the same distance '
      'from the edge they ride, at a floor width and at a rail width', (
    tester,
  ) async {
    // 그 패딩거리 다 통일되있는거맞나? 상단에 알약은 거리 짧은데 가로스크롤바는
    // 더 떨어진 느낌이거든?
    //
    // They come off ONE constant, so the answer is yes — and this is the
    // test that says so, because "they read off the same number" is not the
    // same claim as "they land in the same place". Each of the three is
    // positioned against a different edge through a different Stack, and two
    // of them are additionally offset by the floor's cover.
    //
    // The rail width is here for 유저 R4 #4 (타임시트나 콘티 패널의 알약이
    // 패널탭과의 거리가 너무 먼 것 같다): the sheet panels mount this exact
    // shell, so if their pill really sat lower it would have to be the shell
    // measuring differently at 260px. It does not — the gap is the same
    // number at both widths, and what changes is only how large that number
    // reads beside a 30px tab strip instead of a 48px one.
    const margin = 6.0;

    Future<Rect> gapsAt(Size size, String key) async {
      await tester.binding.setSurfaceSize(size);
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: BrushCanvasFixture.createCoordinator(
                frameKeys: frameKeys,
              ),
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              floorCover: EdgeInsets.zero,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getRect(find.byKey(ValueKey<String>(key)));
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));

    for (final size in const [Size(1400, 900), Size(260, 700)]) {
      final panel = size;
      final pill = await gapsAt(size, 'canvas-view-pill');
      expect(
        pill.top,
        closeTo(margin, 0.5),
        reason: 'the pill hangs off the TOP edge at ${size.width}px',
      );

      final hBar = await gapsAt(size, 'canvas-panbar-horizontal');
      expect(
        panel.height - hBar.bottom,
        closeTo(margin, 0.5),
        reason: 'the horizontal bar rides the BOTTOM edge at ${size.width}px',
      );

      final vBar = await gapsAt(size, 'canvas-panbar-vertical');
      expect(
        panel.width - vBar.right,
        closeTo(margin, 0.5),
        reason: 'the vertical bar rides the RIGHT edge at ${size.width}px',
      );
    }
  });

  testWidgets(
    'renders compact canvas editor panel shell and viewport controls',
    (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('canvas-editor-panel-shell')),
        findsOneWidget,
      );
      // R2 #12: no status strip, docked or floating. The project name and
      // the layer readout are gone from every canvas panel — the user asked
      // for the space back and will ask for a pill if they want them.
      expect(
        find.byKey(const ValueKey<String>('canvas-editor-panel-status-strip')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-status-capsule')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-editor-panel-content')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-panbar-vertical')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-view-pill')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-fit')),
        findsOneWidget,
      );
      // The pill shows the READOUT and Fit, and nothing else about the view
      // (유저 확정 2026-08-13). The − and + steps are gone — the readout is
      // already a drag and a tap to type — and 1:1 is one tap away, behind
      // the gear.
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-out')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-in')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-reset')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-settings')),
        findsOneWidget,
      );
      await openViewSettings(tester);
      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-reset')),
        findsOneWidget,
      );
    },
  );

  testWidgets('a narrow pill keeps Fit and the gear, and never overflows '
      '(the readout is what sheds)', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 300, height: 300),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The two that may never shed: Fit, because no gesture replaces it, and
    // the gear, because it is the only way to what is behind it.
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-settings')),
      findsOneWidget,
    );
    // …and everything the pill used to squeeze in beside them is one tap
    // away instead of fighting for the width.
    await openViewSettings(tester);
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-reset')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-settings-view-row')),
      findsOneWidget,
    );
    // Rotate and flip are IN the list at this width — they used to give up
    // their space instead of overflowing, and now there is no width where
    // they have to, because they never compete for the pill's.
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-rotate-ccw')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-flip')),
      findsOneWidget,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('Fit stays INSIDE the pill at every width the shed passes '
      'through — no band where it is clipped away', (tester) async {
    // The shedding ladder budgets the host's leading controls at every
    // threshold but one: `bare`, the gate on the leading controls
    // themselves, compared the raw width. That left a band — measured at
    // 206..250px — where the pill kept all of a paper panel's controls and
    // pushed Fit out past its own ClipPath: invisible and unhittable, in
    // exactly the narrow panel the code promises it to. It blinked back in
    // below 206, so the button flickered as a rail was dragged.
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final leading = <Widget>[
      for (var i = 0; i < 7; i += 1)
        SizedBox(key: ValueKey<String>('probe-leading-$i'), width: 26),
    ];

    for (final width in [160.0, 190.0, 206.0, 215.0, 230.0, 250.0, 300.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: BrushCanvasFixture.createCoordinator(
                  frameKeys: frameKeys,
                ),
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                floorCover: EdgeInsets.zero,
                allowViewRotation: false,
                bottomBarLeading: leading,
                bottomBarHostToken: width,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pill = tester.getRect(
        find.byKey(const ValueKey<String>('canvas-view-pill')),
      );
      final fit = tester.getRect(
        find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      );
      expect(
        fit.right,
        lessThanOrEqualTo(pill.right + 0.5),
        reason: 'Fit clipped off the pill at $width',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'the pill overflowed at $width',
      );
    }
  });

  testWidgets('the pill NEVER stands down — a panel too narrow for the zoom '
      'cluster still has Fit', (tester) async {
    // It used to disappear below 190px, on the reading that a capsule
    // around an empty row says nothing. With the docked bar gone (R2 #13)
    // the row is never empty, and the panel narrow enough to have lost the
    // pill is the one that needed it most — Fit is the only control here
    // with no gesture that replaces it.
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 300, height: 300),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 150,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('canvas-view-pill')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      findsOneWidget,
    );
    // …and everything that does not fit has left rather than overflowed.
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('nothing the pill shows escapes the capsule, at any width', (
    tester,
  ) async {
    // 🐛The pill sheds clusters at thresholds it computes from the width it
    // is given, and every one of those thresholds has to budget the host's
    // own controls too. A threshold that under-budgets does not overflow
    // loudly — the capsule CLIPS, so the button is still in the tree, still
    // found by `find.byKey`, and simply cannot be seen or pressed. That is
    // how Fit spent a release outside the clip in a 206..250px band.
    //
    // The gear inherited the hazard when it arrived (유저 확정 2026-08-13):
    // it never sheds, so a budget that does not count it promises room the
    // pill has already spent. This sweep is what turned `_essentialBudget`
    // from a number someone added up into a number someone measured — put
    // it back to its pre-gear 60 and the gear leaves the capsule in a
    // 152..172px band with three host controls, 228..248px with six.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 500));

    Future<void> pumpAt(double width, int leadingCount) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                height: 420,
                child: BrushCanvasPanel(
                  coordinator: BrushCanvasFixture.createCoordinator(
                    frameKeys: frameKeys,
                  ),
                  availableFrameKeys: frameKeys,
                  cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                  floorCover: EdgeInsets.zero,
                  paperColor: 0xFFFFFFFF,
                  onPaperColorChanged: (_) {},
                  // Six is what the media viewer asked for before ⑤ and ⑥
                  // took its register, swap and page controls off the pill.
                  bottomBarLeading: [
                    for (var i = 0; i < leadingCount; i += 1)
                      AppIconButton(
                        keyValue: 'probe-leading-$i',
                        tooltip: 'probe $i',
                        icon: const Icon(Icons.circle),
                        onPressed: () {},
                      ),
                  ],
                  bottomBarHostToken: leadingCount,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Mounted, but not fully inside the capsule that clips it.
    List<String> escapees(int leadingCount) {
      final capsule = find.byKey(const ValueKey<String>('canvas-view-pill'));
      // The pill never stands down, so its absence is itself a failure.
      expect(capsule, findsOneWidget);
      final box = tester.getRect(capsule);
      final out = <String>[];
      for (final key in <String>[
        'canvas-viewport-fit',
        'canvas-viewport-settings',
        'canvas-viewport-zoom-label',
        for (var i = 0; i < leadingCount; i += 1) 'probe-leading-$i',
      ]) {
        final finder = find.byKey(ValueKey<String>(key));
        if (finder.evaluate().isEmpty) {
          continue; // shed, which is the correct way to not fit
        }
        final rect = tester.getRect(finder);
        if (rect.left < box.left - 0.5 || rect.right > box.right + 0.5) {
          out.add(key);
        }
      }
      return out;
    }

    for (final leadingCount in <int>[0, 3, 6]) {
      final bad = <String>[];
      // 1px through the band where clusters actually shed — a coarser step
      // walked straight past a width that overflowed by 2px — and coarse
      // above it, where nothing sheds and only the arithmetic is on trial.
      for (var width = 120.0; width <= 620.0; width += width < 340 ? 1 : 8) {
        await pumpAt(width, leadingCount);
        for (final key in escapees(leadingCount)) {
          bad.add('${width.toInt()}px: $key');
        }
        final exception = tester.takeException();
        if (exception != null) {
          bad.add('${width.toInt()}px: $exception');
        }
      }
      expect(
        bad,
        isEmpty,
        reason:
            'with $leadingCount host controls, the pill pushed something '
            'outside its own clip',
      );
    }
  });

  testWidgets('nor on the FLOOR, where it holds everything at once', (
    tester,
  ) async {
    // The same sweep for the pill that starts unfolded. It carries twelve
    // more controls than the rail's, so it is the one whose arithmetic can
    // actually be wrong — and the failure mode is identical: the capsule
    // clips, so a mis-budgeted control is in the tree, found by find.byKey,
    // and cannot be seen or pressed.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 600));

    for (final leadingCount in <int>[0, 2]) {
      final bad = <String>[];
      for (var width = 120.0; width <= 900.0; width += width < 620 ? 1 : 8) {
        await tester.pumpWidget(
          floorPillHarness(
            width: width,
            onFloor: true,
            leadingCount: leadingCount,
          ),
        );
        await tester.pumpAndSettle();
        final capsule = find.byKey(const ValueKey<String>('canvas-view-pill'));
        expect(capsule, findsOneWidget);
        final box = tester.getRect(capsule);
        for (final key in <String>[
          'canvas-viewport-fit',
          'canvas-viewport-settings',
          'canvas-viewport-zoom-label',
          ...floorPillKeys,
          for (var i = 0; i < leadingCount; i += 1) 'probe-leading-$i',
        ]) {
          final finder = find.byKey(ValueKey<String>(key));
          if (finder.evaluate().isEmpty) {
            continue; // folded, which is the correct way to not fit
          }
          final rect = tester.getRect(finder);
          if (rect.left < box.left - 0.5 || rect.right > box.right + 0.5) {
            bad.add('${width.toInt()}px: $key');
          }
        }
        final exception = tester.takeException();
        if (exception != null) {
          bad.add('${width.toInt()}px: $exception');
        }
      }
      expect(
        bad,
        isEmpty,
        reason:
            'with $leadingCount host controls, the floor pill pushed '
            'something outside its own clip',
      );
    }
  });

  testWidgets('a wide floor pill lays everything out and has NO gear', (
    tester,
  ) async {
    // 유저 확정 2026-08-13: 「캔버스패널은 너무 설정에 다넣었어 … 설정에 있는거
    // 다 빼」. The gear stopped being a decision about which controls are
    // common and became the place the ones that did not fit went — so with
    // room for all of them there is nothing behind it and it is not drawn.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pumpWidget(floorPillHarness(width: 900, onFloor: true));
    await tester.pumpAndSettle();

    for (final key in floorPillKeys) {
      expect(
        find.byKey(ValueKey<String>(key)),
        findsOneWidget,
        reason: '$key belongs on a floor pill with room for it',
      );
    }
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-settings')),
      findsNothing,
      reason: 'nothing folded, so the gear has nothing to hold',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the SAME panel off the floor keeps its gear at that width', (
    tester,
  ) async {
    // 유저 확정: 「바닥 둘만」. A sub viewer dragged as wide as the floor is
    // still not the floor — the rule is about WHERE a panel is, not about
    // how much room it happens to have.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pumpWidget(floorPillHarness(width: 900, onFloor: false));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-settings')),
      findsOneWidget,
    );
    for (final key in floorPillKeys) {
      expect(
        find.byKey(ValueKey<String>(key)),
        findsNothing,
        reason: '$key stays folded off the floor, however wide the panel is',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a floor pill folds outside-in, and lands on the rail bar', (
    tester,
  ) async {
    // The fold ORDER the user gave: colours, rotate/flip, 1:1, the host's
    // own verbs, the zoom steps. Each width below is a step further down
    // that ladder, and the last one is the bar every other panel wears —
    // which is the whole point of 「최대로 버튼 사라지는건 지금 고치기 전
    // 상황되도록」: folding cannot cost more than the old bar already did.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 600));

    Future<Set<String>> shownAt(double width) async {
      await tester.pumpWidget(floorPillHarness(width: width, onFloor: true));
      await tester.pumpAndSettle();
      return <String>{
        for (final key in floorPillKeys)
          if (find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty) key,
      };
    }

    final wide = await shownAt(900);
    final medium = await shownAt(420);
    final narrow = await shownAt(300);
    final tiny = await shownAt(150);

    // Every step is a SUBSET of the one before it. A fold that brought
    // something back would be a control blinking in and out as a rail is
    // dragged, which is the defect this bar has had once already.
    expect(wide.containsAll(medium), isTrue, reason: '$wide -> $medium');
    expect(medium.containsAll(narrow), isTrue, reason: '$medium -> $narrow');
    expect(narrow.containsAll(tiny), isTrue, reason: '$narrow -> $tiny');
    expect(medium, isNot(equals(wide)));

    // The colours go first — a choice you make once a project.
    expect(medium.contains('canvas-paper-color-button'), isFalse);
    expect(medium.contains('canvas-viewport-zoom-in'), isTrue);

    // …and the end of the ladder is exactly the bar a rail panel wears.
    expect(tiny, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-fit')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-settings')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('what folded off the floor pill is IN the gear', (tester) async {
    // The promise the fold makes: nothing is cut off, it is one tap away.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pumpWidget(floorPillHarness(width: 420, onFloor: true));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('canvas-paper-color-button')),
      findsNothing,
    );
    await openViewSettings(tester);
    expect(
      find.byKey(const ValueKey<String>('canvas-paper-color-button')),
      findsOneWidget,
      reason: 'the colours folded, so the gear is where they went',
    );
  });

  testWidgets('the zoom steps exist ONLY where the floor put them', (
    tester,
  ) async {
    // ⛔They fold into the gear like everything else — but only on a panel
    // that had them. Listing them in a rail panel's gear would hand it two
    // controls it has never had at any width.
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1200, 600));
    await tester.pumpWidget(floorPillHarness(width: 150, onFloor: false));
    await tester.pumpAndSettle();

    await openViewSettings(tester);
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-zoom-in')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-viewport-reset')),
      findsOneWidget,
      reason: '1:1 is in every gear — it is the zoom steps that are not',
    );
  });

  testWidgets('keeps inner drawing canvas at Cut canvas size', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
          ),
        ),
      ),
    );

    // The view now fills the editor viewport and renders the Cut-sized
    // canvas inside the painter (viewport transform is in-picture); the
    // drawing area therefore comes from the session surface.
    final canvasView = tester.widget<BrushEditCanvasView>(
      find.byType(BrushEditCanvasView),
    );
    expect(
      canvasView.sessionState.canvasState.currentSurface.canvasSize,
      BrushCanvasDefaults.canvasSize,
    );
  });

  testWidgets('fit action uses the available editor viewport size', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 100, height: 50),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 100, height: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final viewportSize = tester.getSize(
      find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
    );

    await tester.tap(find.byKey(const ValueKey<String>('canvas-viewport-fit')));
    await tester.pump();

    final canvas = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    final expected = CanvasViewport.fitToView(
      canvasWidth: 100,
      canvasHeight: 50,
      viewportWidth: viewportSize.width,
      viewportHeight: viewportSize.height,
    );

    expect(canvas.viewport.zoom, expected.zoom);
    expect(canvas.viewport.panX, expected.panX);
    expect(canvas.viewport.panY, expected.panY);
  });

  testWidgets('reset action restores the identity viewport', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 100, height: 50),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 100, height: 50),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('canvas-viewport-fit')));
    await tester.pump();
    // 1:1 is a COMMAND in the settings list, so pressing it closes the list
    // — one tap to open, one to press, exactly like the browser's row menu.
    await tapInViewSettings(tester, 'canvas-viewport-reset');

    final canvas = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );

    // 1:1 means one artwork pixel per DEVICE pixel (유저 확정 2026-08-21),
    // so the render zoom it lands on is the inverse of the effective ratio
    // — ⛔NOT a bare `CanvasViewport()`, which is one artwork pixel per
    // LOGICAL pixel and drew at 300% on this 3× test view while the button
    // beside it said "1:1".
    expect(
      canvas.viewport.zoom,
      closeTo(1 / tester.view.devicePixelRatio, 1e-12),
    );
    expect(canvas.viewport.panX, CanvasViewport().panX);
    expect(canvas.viewport.panY, CanvasViewport().panY);
    expect(canvas.viewport.rotationDegrees, 0);
    expect(find.text('100%'), findsOneWidget);
  });

  group('zoom label inline percent entry', () {
    Future<void> pumpZoomPanel(WidgetTester tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 100, height: 50),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 100, height: 50),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    CanvasViewport viewportOf(WidgetTester tester) => tester
        .widget<InteractiveBrushEditCanvasView>(
          find.byType(InteractiveBrushEditCanvasView),
        )
        .viewport;

    /// R10: ONE tap opens the entry. It was a double tap, which held every
    /// tap on the readout for the double-tap window — ~300ms of nothing,
    /// which the user asked to be gone everywhere. Nothing was lost: the
    /// label had no single-tap action to collide with.
    Future<void> tapZoomLabel(WidgetTester tester) async {
      await tester.tap(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-label')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('tap, type, and submit set the zoom', (tester) async {
      await pumpZoomPanel(tester);

      await tapZoomLabel(tester);
      final input = find.byKey(
        const ValueKey<String>('canvas-viewport-zoom-input'),
      );
      expect(input, findsOneWidget);

      await tester.enterText(input, '250');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(input, findsNothing);
      // The typed number is a DEVICE-pixel percentage (유저 확정
      // 2026-08-21), so the render zoom it commits is that over the
      // effective ratio. On this 3× test view, 250% is a render 0.8333.
      expect(
        viewportOf(tester).zoom,
        closeTo(2.5 / tester.view.devicePixelRatio, 1e-12),
      );
      expect(find.text('250%'), findsOneWidget);
    });

    testWidgets('Escape cancels the entry without committing', (tester) async {
      await pumpZoomPanel(tester);

      await tapZoomLabel(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        '300',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        findsNothing,
      );
      // Untouched: the panel's own default is a render 1.0, which on this
      // 3× test view reads as 300%.
      expect(viewportOf(tester).zoom, 1.0);
      expect(find.text('300%'), findsOneWidget);
    });

    testWidgets('out-of-range entries clamp to the zoom bounds', (
      tester,
    ) async {
      await pumpZoomPanel(tester);

      await tapZoomLabel(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('canvas-viewport-zoom-input')),
        '5000',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // The readout's own bound is 1600% and it is a DISPLAY percentage
      // now, so the render zoom it lands on is 1600% over the effective
      // ratio. ⚠️`CanvasViewport`'s [minZoom]/[maxZoom] are a SECOND,
      // absolute bound on the render zoom, and the tighter of the two
      // wins: the reachable range in device terms is unchanged from before
      // this convention — only the number on the label moved.
      expect(
        viewportOf(tester).zoom,
        closeTo(16.0 / tester.view.devicePixelRatio, 1e-12),
      );
      expect(find.text('1600%'), findsOneWidget);
    });
  });

  testWidgets('passes custom initial input settings to canvas view', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );
    final settings = BrushEditCanvasInputSettings(
      color: 0xFFFF0000,
      size: 12,
      opacity: 0.75,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
            brushToolState: BrushToolState.clamped(
              color: settings.color,
              size: settings.size,
              opacity: settings.opacity,
            ),
          ),
        ),
      ),
    );

    final canvas = tester.widget<InteractiveBrushEditCanvasView>(
      find.byType(InteractiveBrushEditCanvasView),
    );
    expect(canvas.inputSettings, settings);
  });

  testWidgets('commits sampled source dabs into the brush frame store', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    final sink = BrushEditCacheInvalidationSink();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: sink,
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
            brushToolState: BrushToolState.clamped(size: 8),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(1, 1)),
      pointer: 1,
    );
    await gesture.moveTo(canvasGlobalOffset(tester, const Offset(7, 1)));
    await gesture.up();
    await tester.pump();

    // R19 P3b: the stroke lands as raster truth — the pixels are the
    // record (no command bookkeeping to inspect).
    expect(
      coordinator.frameStore.celHasRenderableContent(
        coordinator.activeFrameKey,
      ),
      isTrue,
    );
    // Commit materializes the stroke and invalidates the affected frame and
    // derived layer-tile caches so previews/playback refresh.
    expect(sink.brushFrames, hasLength(1));
    expect(sink.layerTiles, isNotEmpty);
  });

  testWidgets('prepares display cache after drawing', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BrushCanvasPanel(
            coordinator: coordinator,
            availableFrameKeys: frameKeys,
            cacheInvalidationSink: BrushEditCacheInvalidationSink(),
            // A canvas standing on its own IS the floor, and that is where the
            // view controls live (법: 뷰 컨트롤은 바닥에만).
            floorCover: EdgeInsets.zero,
            brushToolState: BrushToolState.clamped(size: 8),
            canvasSize: BrushCanvasFixture.canvasSize,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      canvasGlobalOffset(tester, const Offset(1, 1)),
      pointer: 1,
    );
    await gesture.moveTo(canvasGlobalOffset(tester, const Offset(7, 1)));

    // Mid-stroke the live pointer path never generates a preview cache.
    expect(
      coordinator.frameStore.displayCacheOrNull(coordinator.activeFrameKey),
      isNull,
    );

    await gesture.up();
    await tester.pump();

    // Pen-up DONATES the committed session surface as the display cache —
    // nothing is generated (the immutable surface is shared), and no later
    // consumer replays the stroke.
    final cache = coordinator.frameStore.displayCacheOrNull(
      coordinator.activeFrameKey,
    )!;
    expect(cache.isValid, isTrue);
    expect(
      identical(
        cache.previewSurface,
        coordinator.activeSessionState.canvasState.currentSurface,
      ),
      isTrue,
    );

    // The committed stroke is materialized into the session surface and
    // displayed from the bitmap (WYSIWYG), not as source-dab stamps.
    // R25-④: the commit landed in the previous frame's post-frame
    // phase, so the view widget rebuilds with the post-commit session
    // state one pump later.
    await tester.pump();
    final canvasView = tester.widget<BrushEditCanvasView>(
      find.byType(BrushEditCanvasView),
    );
    expect(
      canvasView.sessionState.canvasState.currentSurface.tiles,
      isNotEmpty,
    );
    expect(
      identical(
        coordinator.frameStore.bakedSurfaceOrNull(coordinator.activeFrameKey),
        cache.previewSurface,
      ),
      isTrue,
      reason: 'the donation is also the bake (raster truth)',
    );
  });

  testWidgets('canvas editor panel shell remains safe at very small heights', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 80,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey<String>('canvas-editor-panel-content')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-panbar-vertical')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('canvas-view-pill')),
      findsOneWidget,
    );
  });

  testWidgets('panbar drag syncs parent once at drag end', (tester) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 300, height: 300),
    );
    final syncedViewports = <CanvasViewport>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // Narrow enough that the zoomed canvas overflows the viewport
            // (the panel no longer insets itself 16px on each side).
            width: 560,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
              viewport: CanvasViewport(zoom: 2),
              onViewportChanged: syncedViewports.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(
          const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
        ),
      ),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(syncedViewports, isEmpty);

    await gesture.up();
    await tester.pump();

    expect(syncedViewports, hasLength(1));
    expect(syncedViewports.single.panX, isNot(0));
  });

  testWidgets('panbar drag cancel syncs parent once with final viewport', (
    tester,
  ) async {
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    final coordinator = BrushCanvasFixture.createCoordinator(
      frameKeys: frameKeys,
      canvasSize: const CanvasSize(width: 300, height: 300),
    );
    final syncedViewports = <CanvasViewport>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            // Narrow enough that the zoomed canvas overflows the viewport
            // (the panel no longer insets itself 16px on each side).
            width: 560,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: coordinator,
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
              viewport: CanvasViewport(zoom: 2),
              onViewportChanged: syncedViewports.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(
          const ValueKey<String>('canvas-viewport-horizontal-scrollbar'),
        ),
      ),
    );
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(syncedViewports, isEmpty);

    await gesture.cancel();
    await tester.pump();

    expect(syncedViewports, hasLength(1));
    expect(syncedViewports.single.panX, isNot(0));
  });

  group('viewport gestures (panel-level, frame-independent)', () {
    // The gesture layer lives on the panel, so navigation must work when the
    // viewport shows the blank paper (no editable frame) — coordinator null,
    // contentOverride only.
    Widget blankPanel({
      required ValueChanged<CanvasViewport> onViewportChanged,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 360,
            child: BrushCanvasPanel(
              coordinator: null,
              availableFrameKeys: const [],
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              canvasSize: const CanvasSize(width: 300, height: 300),
              onViewportChanged: onViewportChanged,
              contentOverride: (context, viewport) => const SizedBox.expand(),
            ),
          ),
        ),
      );
    }

    /// How far below the viewport's top edge these gestures start.
    ///
    /// The floor's view pill is pinned to the TOP-LEFT corner, so a gesture
    /// aimed at (30, 30) is aimed at the pill. Deltas between two of these
    /// points are unaffected — but anything that measures an ABSOLUTE focal
    /// has to count the same shift, so it is a named number rather than one
    /// buried in a helper.
    const clusterClearance = 60.0;

    Offset viewportPoint(WidgetTester tester, Offset offset) {
      return tester.getTopLeft(
            find.byKey(const ValueKey<String>('brush-canvas-editor-viewport')),
          ) +
          const Offset(0, clusterClearance) +
          offset;
    }

    testWidgets('scroll wheel alone zooms without an editable frame', (
      tester,
    ) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(viewportPoint(tester, const Offset(40, 40)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(1.1, 1e-9));

      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 120)));
      await tester.pump();

      expect(viewports.last.zoom, closeTo(1.0, 1e-9));
    });

    testWidgets('middle mouse drag pans without an editable frame', (
      tester,
    ) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.down(viewportPoint(tester, const Offset(30, 30)));
      await gesture.moveTo(viewportPoint(tester, const Offset(42, 51)));
      await gesture.up();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.panX, 12);
      expect(viewports.last.panY, 21);
    });

    testWidgets('trackpad two-finger pan pans the viewport', (tester) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      final start = viewportPoint(tester, const Offset(50, 50));
      await gesture.panZoomStart(start);
      await gesture.panZoomUpdate(start, pan: const Offset(14, -9));
      await gesture.panZoomEnd();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, 1.0);
      expect(viewports.last.panX, 14);
      expect(viewports.last.panY, -9);
    });

    testWidgets('trackpad pinch zooms the viewport', (tester) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      final start = viewportPoint(tester, const Offset(50, 50));
      await gesture.panZoomStart(start);
      await gesture.panZoomUpdate(start, scale: 2.0);
      await gesture.panZoomEnd();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(2.0, 1e-9));
    });

    testWidgets('two-finger touch pinch zooms and pans without a frame', (
      tester,
    ) async {
      final viewports = <CanvasViewport>[];
      await tester.pumpWidget(blankPanel(onViewportChanged: viewports.add));
      await tester.pump();

      final firstFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      final secondFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await firstFinger.down(viewportPoint(tester, const Offset(40, 50)));
      await secondFinger.down(viewportPoint(tester, const Offset(80, 50)));

      // Pinch out: distance 40 → 80 doubles the zoom around the start
      // focal (60,50); the new focal (80,50) drags the view 20px along x.
      await secondFinger.moveTo(viewportPoint(tester, const Offset(120, 50)));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(2.0, 1e-9));
      expect(viewports.last.panX, closeTo(-40, 1e-9));
      // The focal's ABSOLUTE y is what doubling reflects, so this counts
      // the clearance the gestures started below.
      expect(viewports.last.panY, closeTo(-(50 + clusterClearance), 1e-9));
    });

    testWidgets('two-finger touch navigation works over a stroke in progress', (
      tester,
    ) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 300, height: 300),
      );
      final viewports = <CanvasViewport>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: viewports.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Finger 1 starts what looks like a stroke; finger 2 turns the
      // interaction into navigation (the view cancels the stroke).
      final firstFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await firstFinger.down(viewportPoint(tester, const Offset(40, 40)));
      final secondFinger = await tester.createGesture(
        kind: PointerDeviceKind.touch,
      );
      await secondFinger.down(viewportPoint(tester, const Offset(80, 40)));
      // The view cancels the touch stroke synchronously; the panel's
      // strokeActive flag clears on the next frame — pump before moving.
      await tester.pump();

      await secondFinger.moveTo(viewportPoint(tester, const Offset(100, 40)));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pumpAndSettle();

      expect(viewports, isNotEmpty);
    });

    testWidgets('scroll wheel zooms with an editable frame too', (
      tester,
    ) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 300, height: 300),
      );
      final viewports = <CanvasViewport>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: viewports.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final pointer = TestPointer(7, PointerDeviceKind.mouse);
      pointer.hover(viewportPoint(tester, const Offset(60, 60)));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -120)));
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(1.1, 1e-9));
    });

    testWidgets('wheel zoom is suppressed while a stroke is active', (
      tester,
    ) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      final coordinator = BrushCanvasFixture.createCoordinator(
        frameKeys: frameKeys,
        canvasSize: const CanvasSize(width: 300, height: 300),
      );
      final viewports = <CanvasViewport>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 640,
              height: 360,
              child: BrushCanvasPanel(
                coordinator: coordinator,
                availableFrameKeys: frameKeys,
                cacheInvalidationSink: BrushEditCacheInvalidationSink(),
                // A canvas standing on its own IS the floor, and that is where the
                // view controls live (법: 뷰 컨트롤은 바닥에만).
                floorCover: EdgeInsets.zero,
                canvasSize: const CanvasSize(width: 300, height: 300),
                onViewportChanged: viewports.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Start a stroke with the primary button and keep it held.
      final strokeGesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
      );
      await strokeGesture.down(viewportPoint(tester, const Offset(50, 50)));
      await tester.pump();

      final wheelPointer = TestPointer(9, PointerDeviceKind.mouse);
      wheelPointer.hover(viewportPoint(tester, const Offset(60, 60)));
      await tester.sendEventToBinding(
        wheelPointer.scroll(const Offset(0, -120)),
      );
      await tester.pump();

      expect(viewports, isEmpty);

      await strokeGesture.up();
      await tester.pumpAndSettle();
      viewports.clear();

      await tester.sendEventToBinding(
        wheelPointer.scroll(const Offset(0, -120)),
      );
      await tester.pump();

      expect(viewports, isNotEmpty);
      expect(viewports.last.zoom, closeTo(1.1, 1e-9));
    });
  });

  group('brush cursor', () {
    Future<void> pumpWithTool(WidgetTester tester, CanvasTool tool) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: BrushCanvasFixture.createCoordinator(
                frameKeys: frameKeys,
              ),
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              brushToolState: BrushToolState.clamped(size: 40, tool: tool),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> hoverCanvas(WidgetTester tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(canvasGlobalOffset(tester, const Offset(4, 4)));
      await tester.pump();
    }

    testWidgets('the brush wears a tip outline once the pointer arrives', (
      tester,
    ) async {
      await pumpWithTool(tester, CanvasTool.brush);
      // Nothing is drawn before the pointer has been anywhere.
      expect(
        find.byKey(const ValueKey<String>('brush-cursor-overlay')),
        findsNothing,
      );

      await hoverCanvas(tester);

      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey<String>('brush-cursor-overlay')),
                  )
                  .painter
              as BrushCursorPainter;
      // A 40px brush at 100% is an outline, not the small-brush crosshair.
      expect(painter.shape, isNotNull);
      expect(painter.shape!.majorRadius, closeTo(20, 1e-9));
    });

    testWidgets('the eraser wears it too', (tester) async {
      await pumpWithTool(tester, CanvasTool.eraser);
      await hoverCanvas(tester);

      expect(
        find.byKey(const ValueKey<String>('brush-cursor-overlay')),
        findsOneWidget,
      );
    });

    testWidgets('a tiny brush falls back to the crosshair', (tester) async {
      final frameKeys = BrushCanvasFixture.createFrameKeys();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrushCanvasPanel(
              coordinator: BrushCanvasFixture.createCoordinator(
                frameKeys: frameKeys,
              ),
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              // A canvas standing on its own IS the floor, and that is where the
              // view controls live (법: 뷰 컨트롤은 바닥에만).
              floorCover: EdgeInsets.zero,
              brushToolState: BrushToolState.clamped(size: 1),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await hoverCanvas(tester);

      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey<String>('brush-cursor-overlay')),
                  )
                  .painter
              as BrushCursorPainter;
      expect(painter.shape, isNull);
    });

    testWidgets('the non-painting tools keep their own cursors', (
      tester,
    ) async {
      for (final tool in [
        CanvasTool.fill,
        CanvasTool.select,
        CanvasTool.move,
      ]) {
        await pumpWithTool(tester, tool);
        expect(
          find.byKey(const ValueKey<String>('brush-cursor-region')),
          findsNothing,
          reason: '$tool must not wear the brush outline',
        );
      }
    });
  });
}

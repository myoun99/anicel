import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨★★★**AN `Opacity` IS A REPAINT BOUNDARY, AND A BOUNDARY INSIDE A PANEL
/// COSTS THAT PANEL ITS BAKE.**
///
/// `RenderOpacity.isRepaintBoundary` is `alpha > 0` — **255 included**, so
/// `Opacity(opacity: 1)` is one too — and `RenderAnimatedOpacity`
/// (`AnimatedOpacity`, `FadeTransition`) is the same at any alpha above
/// zero. [StaticRaster] refuses to bake a subtree that holds a boundary
/// (it would freeze: `markNeedsPaint` stops at the first boundary and never
/// reaches the wrapper), so the panel around it pays its FULL raster price
/// on every frame the app produces — looking identical while it does.
///
/// 🔬2026-09-22, one afternoon, three of these, each a different widget and
/// none of them visible as a defect:
///  * a disabled `FieldSlider` dimmed itself with `Opacity(0.4)`;
///  * the pressure-curve well beside it did the same;
///  * Material's own `Switch` carries one at **opacity 1**, which is why a
///    panel with a switch in it can never bake at all (board
///    `a-panel-with-a-switch-can-never-bake`).
///
/// The panel sweep (`test/ui/panels/panel_static_raster_test.dart`) is what
/// found them, and it can only find what a mounted panel shows in the state
/// it is swept in — a drag proxy, a disabled pill or a collapsed row is
/// invisible to it. So this is the other half: **every compositing wrapper
/// in `lib/` is one somebody decided**, and a new one has to be written
/// down before it can land.
///
/// ⛔This is a LEDGER, not a ban. Half of these are correct — a drag proxy
/// that must fade, a HUD that animates out. What is refused is an
/// unexamined one.
void main() {
  /// Widgets whose render object composites — every one of them a repaint
  /// boundary that a bake cannot cross.
  final wrappers = RegExp(
    r'\b(Opacity|AnimatedOpacity|FadeTransition|ShaderMask|ColorFiltered|'
    r'BackdropFilter|ImageFiltered)\(',
  );

  /// What `lib/` is allowed to hold, and why each one is there.
  ///
  /// ⚠️The COUNT is part of the entry: a file that grows a second wrapper
  /// has to say so, and a file that loses one has to lose its line.
  const ledger = <String, ({int count, String why})>{
    'lib/src/ui/brush/brush_canvas_panel.dart': (
      count: 1,
      why: 'the cut-editing fade, and only while it is under 1.0 (the '
          'branch above returns the view unwrapped otherwise). The canvas '
          'panel is on `_knownToPaintThrough` anyway — it owns its own '
          'boundaries and must never be asked for a full-surface copy.',
    ),
    'lib/src/ui/brush/brush_preset_reorder_grid.dart': (
      count: 1,
      why: 'the DRAG PROXY under the finger while a preset is being moved. '
          'It exists for the length of a drag, and what it dims is the '
          'thing being dragged.',
    ),
    'lib/src/ui/canvas/flip_hud_overlay.dart': (
      count: 1,
      why: 'the flip HUD fading out, over the canvas — which does not bake '
          '(`panel:canvas-editor`), and the subtree is BORN when the axis '
          'locks (the comment beside it says why it is a tween and not an '
          '`AnimatedOpacity`).',
    ),
    'lib/src/ui/export/export_cel_layer_row.dart': (
      count: 1,
      why: 'a row in the export WINDOW. A dialog is not a baked panel.',
    ),
    'lib/src/ui/media/media_pool_panel.dart': (
      count: 1,
      why: '`childWhenDragging` — the hole a dragged row leaves behind, for '
          'the length of the drag.',
    ),
    'lib/src/ui/panels/editor_panel_tabs.dart': (
      count: 1,
      why: 'the tab ROW fading while a tab is dragged out of it. It sits '
          'beside the content bake (`panel:<tabId>`), not inside it, so it '
          'costs no panel its raster — and it is always mounted on purpose: '
          'mounting a wrapper conditionally swaps the element type at that '
          'slot and deactivates everything under it.',
    ),
    'lib/src/ui/timeline/collapsed_row_overlay.dart': (
      count: 1,
      why: 'an overlay over the timeline GRID, which is the one surface in '
          'the app deliberately left unbaked (it is the most genuinely live '
          'one there is).',
    ),
    'lib/src/ui/timeline/layer_row_drag.dart': (
      count: 1,
      why: 'the lifted row under the finger, for the length of the drag.',
    ),
    'lib/src/ui/widgets/command_pill.dart': (
      count: 1,
      why: '⚠️A DISABLED PILL, and the comment beside it is a decision: the '
          'law is 「the whole noun stands down」 and a per-child sweep kept '
          'getting the geometry wrong. It is the one entry here that costs '
          'something real — a disabled pill in a command bar denies its '
          'zone the bake — and changing it means changing what a disabled '
          'pill looks like. Filed rather than done: board '
          '`a-panel-with-a-switch-can-never-bake` is the same question for '
          'the same reason.',
    ),
    'lib/src/ui/widgets/cursor_notice.dart': (
      count: 1,
      why: 'the notice fading itself out — an animation over the canvas, '
          'alive only while it shows.',
    ),
  };

  test('🚨every compositing wrapper in lib/ is one somebody decided', () {
    final found = <String, int>{};
    for (final entity in dartFilesUnder('lib')) {
      final path = entity.path.replaceAll(r'\', '/');
      for (final line in entity.readAsLinesSync()) {
        final code = line.trim();
        // A wrapper NAMED in prose is not a wrapper in the tree — and this
        // file's own subject matter means the comments are full of them.
        if (code.startsWith('//') || code.startsWith('*')) {
          continue;
        }
        if (wrappers.hasMatch(code)) {
          found[path] = (found[path] ?? 0) + 1;
        }
      }
    }

    final unledgered = <String>[];
    for (final entry in found.entries) {
      final listed = ledger[entry.key];
      if (listed == null) {
        unledgered.add('${entry.key}: ${entry.value} — new, and nothing '
            'says why');
      } else if (listed.count != entry.value) {
        unledgered.add(
          '${entry.key}: ${entry.value}, ledger says ${listed.count}',
        );
      }
    }
    expect(
      unledgered,
      isEmpty,
      reason:
          'a compositing wrapper is a repaint boundary, and a boundary '
          'inside a panel costs that panel its bake on EVERY frame:\n'
          '${unledgered.join('\n')}\n'
          'Dim the colours instead where the pixels allow it '
          '(`disabled_ink.dart`, and a single run of glyphs is exactly the '
          'case where a layer and an alpha are the same pixels), or add the '
          'file to the ledger in this test WITH the reason.',
    );

    final gone = ledger.keys.where((path) => !found.containsKey(path));
    expect(
      gone,
      isEmpty,
      reason:
          'these are in the ledger and not in the tree any more — take the '
          'line out, so the ledger keeps saying something true: $gone',
    );
  });
}

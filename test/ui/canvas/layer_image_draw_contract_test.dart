import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../helpers/dart_sources.dart';

/// A4's other half — THE SAMPLING QUESTION CANNOT BE LEFT UNANSWERED.
///
/// `drawPosedLayerImage` now REQUIRES `filterQuality`, which blocks the
/// class of drift where a new route "just draws" and inherits a quality
/// nobody chose (T21 — the active layer rendered jagged next to its
/// neighbours — walked in through exactly that door). But a required
/// parameter only guards the routes that come through the door. This is
/// the fence around the building: the census of RAW `drawImage*` calls
/// in `lib/` is frozen, so a new image draw either goes through
/// `drawPosedLayerImage` or argues itself into the number below — in the
/// same commit, with the sampling stated explicitly on its own Paint.
///
/// The existing raw sites are legitimate and stay: tile blits and buffer
/// self-copies at 1:1 (`FilterQuality.none` — resampling a 1:1 blit is
/// how the patch path would drift), thumbnails and previews that own
/// their quality on their own Paint, and export/PDF writers in output
/// space. The point is not that raw draws are wrong; it is that NEW ones
/// answer the question in review instead of by default.
void main() {
  test('no new raw image draw escapes the one place', () {
    final offenders = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final path = file.path.replaceAll(r'\', '/');
      // The one place: the shared draw whose filterQuality is required.
      if (path.endsWith('lib/src/ui/canvas/layer_image_draw.dart')) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (_rawImageDraw.hasMatch(line)) {
          offenders.add('$path:${i + 1}  ${line.trim()}');
        }
      }
    }
    // A RATCHET, not a wall (app_shapes_coverage_test is the pattern).
    // There were 32 raw sites when the required parameter landed; the
    // number may only ever go DOWN. When it reaches the handful that are
    // structurally 1:1 blits, freeze those as named allowances and delete
    // the number.
    expect(
      offenders.length,
      lessThanOrEqualTo(_knownRawDraws),
      reason:
          'A raw image draw was added. Layer artwork goes through '
          'drawPosedLayerImage, where filterQuality is required. A raw '
          'drawImage/drawImageRect is for 1:1 blits and quality-owning '
          'leaves — if this site is genuinely one of those, set '
          'filterQuality explicitly on its Paint and raise _knownRawDraws '
          'with the reason in the same commit.\n${offenders.join('\n')}',
    );
    expect(
      offenders.length,
      greaterThanOrEqualTo(_knownRawDraws),
      reason:
          'Raw draws were converted — lower _knownRawDraws to '
          '${offenders.length} so the ratchet keeps its grip.',
    );
  });

  test('the door itself stays locked — filterQuality remains required', () {
    // "required" is a compile-time guarantee, which no runtime test can
    // watch: restore a default and every suite stays green while the
    // drift class reopens. So the contract reads the declaration.
    final source = File(
      'lib/src/ui/canvas/layer_image_draw.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('required ui.FilterQuality filterQuality'),
      reason: 'a default filterQuality on drawPosedLayerImage is how '
          'sampling drift comes back — T21 walked in through that door',
    );
  });

  test('🚨D14: the layer stack names NO filtering quality of its own — the '
      'zoom decides', () {
    // 유저 D14 답 1 (2026-08-25, re-affirmed 2026-09-10): 「축소일 때만 low
    // 로」, with the condition attached in the same breath — 「액티브레이어랑
    // 다른레이어랑 구분둬서 적용한다거나 그런거 너무 심하거든? 그림 자체에
    // 통일해서 적용」. That IS T21, and [filterQualityForDisplayScale] is
    // where it lives.
    //
    // ⛔THE RATCHET IS A SOURCE SCAN, not a rendered comparison, and the
    // reason is the one this repo keeps re-learning: a behaviour test
    // passes while two routes happen to agree, and says nothing about the
    // third one someone adds next week. What must not come back is a
    // filtering constant WRITTEN HERE.
    //
    // `none` is not filtering — it is the absence of it — and the 1:1
    // blits in this file (patch base, scroll carry, group image) state it
    // precisely because they resample nothing. `low`/`medium`/`high` are
    // the ones that mean "and here is how I sample", which is the
    // question this file no longer gets to answer.
    final source = File(
      'lib/src/ui/canvas/layer_stack/layer_stack_paint_pass.dart',
    ).readAsLinesSync();
    final found = <String>[];
    for (var i = 0; i < source.length; i += 1) {
      final line = source[i];
      if (line.trimLeft().startsWith('//') || line.trimLeft().startsWith('///')) {
        continue;
      }
      if (line.contains('FilterQuality.low') ||
          line.contains('FilterQuality.medium') ||
          line.contains('FilterQuality.high')) {
        found.add('${i + 1}: ${line.trim()}');
      }
    }
    expect(
      found,
      isEmpty,
      reason: 'the walk must read _displayQuality, not name a quality — a '
          'route that samples differently from the buffered one is T21 '
          'wearing a different hat',
    );
  });

  test('the sampling-hiding conveniences stay out', () {
    // `paintImage` and `DecorationImage` wrap the same engine draw behind
    // their OWN quality defaults, which is the exact drift the required
    // parameter exists to end — and their internal draw lives in the
    // framework, where the census regex cannot see it. `drawAtlas` /
    // `drawRawAtlas` sample images through a paint the same way.
    //
    // ⚠️Stripping the private `_paintImage` FIRST keeps the guard's
    // teeth without banning a local helper whose body the census already
    // reads.
    final found = <String>[];
    for (final file in dartFilesUnder('lib')) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i += 1) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        final probe = line.replaceAll('_paintImage', '');
        if (probe.contains('paintImage(') ||
            probe.contains('drawAtlas(') ||
            probe.contains('drawRawAtlas(') ||
            probe.contains('DecorationImage(')) {
          found.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(found, isEmpty);
  });
}

/// The census the required parameter arrived to. Only ever goes down.
/// **32** at A4 (2026-08-16): 5 bitmap_surface_painter (tile blits, none) ·
/// 3 provisional_tile_pictures · 2 each in export_frame_renderer,
/// conte_pdf_writer, cut_envelope_painter, conte_page_painter,
/// tiled_surface_compose, canvas_layer_stack_view (patch-base + backdrop
/// blit, both 1:1 self-copies), cut_piece_preview · 1 each in
/// static_raster, timeline_row_cells_painter, storyboard_cut_blocks_painter,
/// playback_frame_painter, layer_frame_image_cache, media_viewer_tab_host,
/// import_preview, static_composite_bake (backdrop raster blit, none),
/// selection_float_overlay, raster_cel_import.
/// **35** at ⓔ stage 4a: +3 in active_layer_flat_projection — the flat
/// assembly's 1:1 integer blits (build, patch base carry-over, coordinate
/// replacement), all FilterQuality.none/BlendMode.src by construction and
/// byte-parity-pinned against the walk. Exactly the quality-owning-leaf
/// class the allowlist describes — and the ratchet catching its own
/// author on the very next canvas PR is the mechanism working.
/// **36** at ⓔ stage 5a: +1 in canvas_layer_stack_view — the scaled
/// buffer's active-flat blit, on its own Paint, because under the scaled
/// recording the active layer must resample under the SAME filter as every
/// other layer's image — that uniformity is the T21 closure below the knee.
/// ✏️It said LOW **on purpose** until 2026-09-10 (D14). The requirement was
/// never the constant, it was the SAMENESS: all three draws in this file
/// now read `_LayerStackPaintPass._displayQuality`, so they still agree
/// with each other and they also agree with the buffered route, which had
/// been reading [filterQualityForDisplayScale] all along. A flat `low`
/// filtered a MAGNIFIED view, which is the half of T21 the walk was still
/// getting wrong (유저 확정: 「확대는 `none`」).
/// **37** at the open-staleness round: +1 in canvas_layer_stack_view —
/// the FIRST-ACTIVATION stand-in blit in the active slot, on its own Paint:
/// it is the very image the cached-image route drew one frame earlier at
/// the same rect, and the handoff into the stand-in must be byte-identical
/// (the same sampling the [_PaintImage] route states through
/// drawPosedLayerImage). ✏️Also LOW until D14, and still byte-identical
/// for the same reason: both ends read the one law.
/// **38** at the every-node-is-a-picture round: +1 in
/// canvas_layer_stack_view — a GROUP no longer composites through
/// `saveLayer`; it rasterises to a `ui.Image` and blits it. That blit is
/// 1:1 by construction (the image grid is the local space at the walk's
/// raster scale, snapped outward) so it owns `FilterQuality.none`, and
/// LOW only in the one case the buffer cap clamped the scale and the
/// blit became a magnification. It is a quality-owning leaf in the
/// strictest sense: it is the composite, not a layer inside one.
/// **39** at the order-is-free round: +1 in subtree_image_composite — the
/// step blit that carries a chain from one raster to the next when a colour
/// key sits under painted state. Src and dst are the same rect at the
/// identity, so it is a 1:1 blit and owns `FilterQuality.none` on its own
/// Paint. (The step's OTHER draw is a `drawRect` under a shader, which is
/// not an image draw at all.)
/// **40** at the carry round: +1 in canvas_layer_stack_view — the blit that
/// moves a display buffer to its new home when a pan slides the extent. The
/// buffer is canvas resolution, so one buffer pixel is one canvas pixel and
/// src and dst are the same size: a 1:1 blit that owns `FilterQuality.none`
/// and `isAntiAlias: false` on its own Paint, exactly like the patch path's
/// base blit beside it.
/// **39** since the conte page and the cut envelope stopped each drawing
/// their own ink window: `paintSheetInkWindow` is the one clipped draw for
/// both sheets, and it owns its medium filter.
/// **37** since the surface paint pass draws a tile through one call: its
/// three identical tile blits (replaced, held, live) are `_drawTileImage`,
/// one raw draw at `tileOriginOffset` with the same tile image paint.
/// **38** at the predecessor round (2026-09-11): +1 in
/// provisional_tile_pictures — `composePredecessorStandIn` draws the
/// predecessor tile's picture 1:1 onto the stand-in recorder under
/// `_tilePaint` (`FilterQuality.none`, `isAntiAlias: false`), the same class
/// as the seeder's base draw beside it. ⚠️It landed two commits before this
/// line: this file does not import what it scans, so `affected_tests` never
/// selected it — CLAUDE.md's source-scanning-contract rule, one more time.
/// **38** still, and a different 38 (2026-09-15): +1 in viewer_document —
/// `cropImageRgba` (7e22dfa5, the viewer's cut tool) copies a box of the
/// page 1:1 onto a picture its own size under `BlendMode.src` and
/// `FilterQuality.none`, the quality-owning-leaf class — and −1 in
/// import_preview, whose raw draw left with 00346e27's placement window. The
/// first landed with no line here and turned master red at 39; the second
/// brought the number back with none either. Both are named so the number
/// describes the tree it counts.
/// **33** on 2026-09-16 (the render round, 안 1 「선명」): −5, all of them
/// the knee's. Three in active_layer_flat_projection (the file went with
/// the knee), one in layer_stack_paint_pass (the knee's scaled-buffer blit),
/// one in layer_frame_image_cache (`_downscale`'s one-step reduction). Below
/// 100% the display is now fed from a LEVEL — the artwork halved exactly
/// (`displayLevelOf`) — and a level is made by an image SHADER over a rect
/// (`level_image.dart`), which owns its quality explicitly and is not a raw
/// image draw.
/// **27** at the one-door round (2026-09-17): -5. provisional_tile_pictures
/// went whole (its three seeder draws and the predecessor compose), and
/// the first-activation stand-in blit went with the stand-in - a tile
/// pictures itself inside the paint now, so nothing stands in for one.
const int _knownRawDraws = 27;

final RegExp _rawImageDraw = RegExp(
  r'\.drawImage\(|\.drawImageRect\(|\.drawImageNine\(',
);

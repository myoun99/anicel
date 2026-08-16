import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
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
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
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
/// buffer's active-flat blit, 1:1 src/dst at FilterQuality.low: LOW on
/// purpose and on its own Paint, because under the scaled recording the
/// active layer must resample under the SAME filter as every other
/// layer's image — that uniformity is the T21 closure below the knee.
/// **37** at the open-staleness round: +1 in canvas_layer_stack_view —
/// the FIRST-ACTIVATION stand-in blit in the active slot, LOW on its own
/// Paint on purpose: it is the very image the cached-image route drew one
/// frame earlier at the same rect, and the handoff into the stand-in must
/// be byte-identical (the same sampling the [_PaintImage] route states
/// through drawPosedLayerImage).
const int _knownRawDraws = 37;

final RegExp _rawImageDraw = RegExp(
  r'\.drawImage\(|\.drawImageRect\(|\.drawImageNine\(',
);

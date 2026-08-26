import 'dart:typed_data';

import '../../models/brush_frame_key.dart';
import '../brush_frame_editing_coordinator.dart';
import '../cache_invalidation_executor.dart';
import '../canvas_selection.dart' show SelectionMaskOptions;
import '../canvas_selection_region.dart';
import '../cel_pixel_overwrite.dart';
import '../cel_source_effect_pass.dart';
import '../cel_pixel_region.dart';
import '../command.dart';

/// One cel a pixel verb acts on, with the region ALREADY restated in that
/// cel's own artwork space.
///
/// 🚨The region is frozen here, at the moment the command is built, and
/// never re-read from the session. A command that asked the live selection
/// again on the way back would restore whatever happened to be selected at
/// undo time — recolour, deselect, draw a new marquee somewhere else, press
/// Ctrl+Z, and the wrong pixels come back.
class CelPixelTarget {
  const CelPixelTarget({required this.key, this.region});

  final BrushFrameKey key;

  /// Null = the whole drawing, pasteboard included.
  final CanvasSelectionRegion? region;
}

/// 색 변환 and 픽셀 비우기 as one undoable step across every cel the
/// scope ladder named.
///
/// ⛔RETAINS RECIPES, NOT SURFACES. Every other pixel command on the stack
/// keeps a pre-surface and a post-surface ([BrushStrokeHistoryCommand]),
/// which is right for a stroke — it changes a handful of tiles — and wrong
/// here: a pass over a frame-range selection touches every tile of every
/// cel it names, so snapshots would retain tens of megabytes and push the
/// rest of the session's history off the byte budget. See
/// [overwriteCelPixels] for what a recipe costs instead (three bytes for
/// line art).
///
/// Redo re-runs the forward pass rather than restoring a post-surface: the
/// pass is deterministic, so the second run produces the same pixels and
/// the same recipe as the first.
class CelPixelOverwriteCommand implements Command, RetainedBytesCommand {
  CelPixelOverwriteCommand({
    required this.coordinator,
    required this.targets,
    required this.channel,
    required Uint8List value,
    required this.description,
    this.selector,
    this.options = SelectionMaskOptions.none,
    this.cacheInvalidationSink,
  }) : _value = Uint8List.fromList(value) {
    assert(
      value.length == channel.byteCount,
      'value must carry exactly the channel bytes.',
    );
  }

  /// The ONE place a verb becomes a channel, a value and a selector.
  ///
  /// ⛔Four verbs, one translation. 색 삭제 and 픽셀 삭제 are both alpha
  /// writes of zero and differ only in which pixels they take, so anything
  /// deciding that per call site would be deciding it four times.
  ///
  /// [argb]'s alpha is deliberately dropped throughout — 색 변환 keeps the
  /// drawing's own shape (유저 확정: "RGB만 쓰는거 ok"), and the colour verbs
  /// COMPARE against RGB, where a swatch's own transparency means nothing.
  factory CelPixelOverwriteCommand.forVerb({
    required BrushFrameEditingCoordinator coordinator,
    required List<CelPixelTarget> targets,
    required CelPixelVerb verb,
    required int argb,
    SelectionMaskOptions options = SelectionMaskOptions.none,
    CacheInvalidationSink? cacheInvalidationSink,
  }) => CelPixelOverwriteCommand(
    coordinator: coordinator,
    targets: targets,
    channel: verb.channel,
    value: verb.channel == CelPixelChannel.colour
        ? Uint8List.fromList([
            (argb >> 16) & 0xFF,
            (argb >> 8) & 0xFF,
            argb & 0xFF,
          ])
        : Uint8List.fromList([0]),
    selector: verb.selectorFor(argb),
    description: switch (verb) {
      CelPixelVerb.replaceColour => 'Replace colour',
      CelPixelVerb.clearPixels => 'Clear pixels',
      CelPixelVerb.deleteColour => 'Delete colour',
      CelPixelVerb.keepColour => 'Keep colour',
    },
    options: options,
    cacheInvalidationSink: cacheInvalidationSink,
  );

  /// 색 변환 — [forVerb] with the verb spelled out, kept because the call
  /// sites read better and the tests aim at it.
  factory CelPixelOverwriteCommand.replaceColour({
    required BrushFrameEditingCoordinator coordinator,
    required List<CelPixelTarget> targets,
    required int argb,
    SelectionMaskOptions options = SelectionMaskOptions.none,
    CacheInvalidationSink? cacheInvalidationSink,
  }) => CelPixelOverwriteCommand.forVerb(
    coordinator: coordinator,
    targets: targets,
    verb: CelPixelVerb.replaceColour,
    argb: argb,
    options: options,
    cacheInvalidationSink: cacheInvalidationSink,
  );

  /// 픽셀 비우기: the cel keeps its exposure and its colour bytes, and
  /// loses its coverage.
  factory CelPixelOverwriteCommand.clearPixels({
    required BrushFrameEditingCoordinator coordinator,
    required List<CelPixelTarget> targets,
    SelectionMaskOptions options = SelectionMaskOptions.none,
    CacheInvalidationSink? cacheInvalidationSink,
  }) => CelPixelOverwriteCommand.forVerb(
    coordinator: coordinator,
    targets: targets,
    verb: CelPixelVerb.clearPixels,
    argb: 0,
    options: options,
    cacheInvalidationSink: cacheInvalidationSink,
  );

  final BrushFrameEditingCoordinator coordinator;
  final List<CelPixelTarget> targets;
  final CelPixelChannel channel;

  /// Which pixels the pass takes, beyond coverage — null takes them all.
  /// See [celPixelParticipates] for why a colour selector is safe on an
  /// alpha write and an alpha-reading one would not be.
  final CelColorKey? selector;
  final SelectionMaskOptions options;
  final CacheInvalidationSink? cacheInvalidationSink;
  final Uint8List _value;

  @override
  final String description;

  /// What the forward pass ACTUALLY did, in the order it did it: which row
  /// it went through, and what that cel's pixels were.
  ///
  /// 🚨Not a map keyed by cel. Undo has to replay the very target the
  /// forward pass used, because the region rides on the target: with two
  /// linked rows carrying different poses, walking `targets.reversed` would
  /// reach the OTHER row first and restore the recipe through a region it
  /// was never measured against.
  final List<({CelPixelTarget target, CelPixelRestore restore})> _applied = [];

  @override
  int get estimatedRetainedBytes {
    var total = 0;
    for (final entry in _applied) {
      total += entry.restore.estimatedRetainedBytes;
    }
    return total;
  }

  @override
  void execute() {
    // Cleared first: a redo measures the cels again rather than trusting
    // the values it happens to be holding. The pass is deterministic, so
    // the second reading equals the first — but only because it IS a
    // reading, and a stale recipe would quietly outlive a canvas resize.
    _applied.clear();
    final done = <BrushFrameKey>{};
    for (final target in targets) {
      final cel = coordinator.frameStore.canonicalKeyOf(target.key);
      if (!done.add(cel)) {
        // Already done through another row. The region of the FIRST row
        // that reached this cel is the one that applies; a linked pair with
        // different poses is the only way that can even be noticed, and
        // stack order is the tiebreak everywhere else too.
        continue;
      }
      final before = coordinator.currentSurfaceOf(target.key);
      final result = overwriteCelPixels(
        surface: before,
        channel: channel,
        walk: celPixelWalkFor(
          surface: before,
          region: target.region,
          options: options,
        ),
        value: _value,
        selector: selector,
      );
      final restore = result.restore;
      if (restore == null) {
        // Nothing under the region — an empty cel, or a selection that
        // missed this row's drawing entirely. 없는 곳엔 아무 동작 안 함.
        continue;
      }
      _applied.add((target: target, restore: restore));
      coordinator.restoreSurfaceSnapshot(
        target.key,
        result.surface,
        cacheInvalidationSink: cacheInvalidationSink,
      );
    }
  }

  @override
  void undo() {
    for (final entry in _applied.reversed) {
      final target = entry.target;
      final current = coordinator.currentSurfaceOf(target.key);
      final result = overwriteCelPixels(
        surface: current,
        channel: channel,
        walk: celPixelWalkFor(
          surface: current,
          region: target.region,
          options: options,
        ),
        restore: entry.restore,
        // The SAME selector: an alpha write preserves RGB, so it picks
        // exactly the pixels the forward pass picked and the recipe's
        // positional walk lines up.
        selector: selector,
      );
      coordinator.restoreSurfaceSnapshot(
        target.key,
        result.surface,
        cacheInvalidationSink: cacheInvalidationSink,
      );
    }
  }
}

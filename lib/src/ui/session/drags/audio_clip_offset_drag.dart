import 'package:flutter/foundation.dart';

import '../../../models/audio_clip.dart';
import '../../../models/layer.dart';
import '../../../models/layer_id.dart';
import '../../../models/layer_kind.dart';
import 'editor_drag_session.dart';

/// The audio lane's slide edit (comma-drag idiom, REPO-DIRECT): a live
/// slide of one clip's offset trim.
///
/// This family is the one legitimate repo-direct previewer — the
/// OpenToonz-shaped idiom the pro-tool survey confirmed (EditTool applies
/// values into the document on every drag event, with snapshots making the
/// commit one undo step). The drag writes the repository per pointer move so
/// every waveform view repaints from the model in real time; the commit then
/// reverts silently to the before-snapshot and applies the final list as ONE
/// ordinary clip command, whose own before-snapshot stays correct.
///
/// Its input is the dragged ABSOLUTE offset, not a cumulative delta — the
/// scalar's meaning is the family's, per [EditorDragSession].
class AudioClipOffsetDrag implements EditorDragSession {
  AudioClipOffsetDrag._({
    required List<AudioClip> before,
    required LayerId layerId,
    required int clipIndex,
    required Layer? Function(LayerId) layerById,
    required void Function({
      required LayerId layerId,
      required List<AudioClip> audioClips,
    })
    previewClips,
    required void Function({
      required LayerId layerId,
      required List<AudioClip> audioClips,
    })
    commitClips,
    required void Function() notify,
  }) : _before = before,
       _layerId = layerId,
       _clipIndex = clipIndex,
       _layerById = layerById,
       _previewClips = previewClips,
       _commitClips = commitClips,
       _notify = notify;

  /// Starts a live slide of [layerId]'s [clipIndex]th sound; null when the
  /// row is not an SE lane or the index names no clip — no object, no drag.
  static AudioClipOffsetDrag? begin({
    required LayerId layerId,
    required int clipIndex,
    required Layer? Function(LayerId) layerById,
    required void Function({
      required LayerId layerId,
      required List<AudioClip> audioClips,
    })
    previewClips,
    required void Function({
      required LayerId layerId,
      required List<AudioClip> audioClips,
    })
    commitClips,
    required void Function() notify,
  }) {
    final layer = layerById(layerId);
    if (layer == null ||
        layer.kind != LayerKind.se ||
        clipIndex < 0 ||
        clipIndex >= layer.audioClips.length) {
      return null;
    }
    return AudioClipOffsetDrag._(
      before: layer.audioClips,
      layerId: layerId,
      clipIndex: clipIndex,
      layerById: layerById,
      previewClips: previewClips,
      commitClips: commitClips,
      notify: notify,
    );
  }

  /// The clip list as it was when the grip went down — what cancel restores
  /// and what the commit's silent revert returns to.
  final List<AudioClip> _before;
  final LayerId _layerId;
  final int _clipIndex;

  /// Live lookup on purpose: the drag WRITES the repository, so the layer
  /// object is stale the moment update runs — every step re-reads it.
  final Layer? Function(LayerId) _layerById;

  /// The repository's direct writer (no history) — the live preview.
  final void Function({
    required LayerId layerId,
    required List<AudioClip> audioClips,
  })
  _previewClips;

  /// The coordinator's clip command ('Slide sound') — ONE undo step.
  final void Function({
    required LayerId layerId,
    required List<AudioClip> audioClips,
  })
  _commitClips;

  final void Function() _notify;

  /// Applies the dragged ABSOLUTE offset as a live preview (clamped ≥ 0);
  /// no-op while the value is unchanged.
  @override
  void update(int offsetFrames) {
    final layer = _layerById(_layerId);
    if (layer == null || _clipIndex >= layer.audioClips.length) {
      return;
    }
    final clamped = offsetFrames < 0 ? 0 : offsetFrames;
    if (layer.audioClips[_clipIndex].offsetFrames == clamped) {
      return;
    }
    final next = [...layer.audioClips];
    next[_clipIndex] = next[_clipIndex].copyWith(offsetFrames: clamped);
    _previewClips(layerId: _layerId, audioClips: next);
    _notify();
  }

  /// Commits the slide as a single undo step: the preview reverts
  /// silently, then the normal clip command applies the final list (its
  /// before-snapshot stays correct).
  @override
  void commit() {
    final layer = _layerById(_layerId);
    if (layer == null) {
      return;
    }
    final after = layer.audioClips;
    if (listEquals(after, _before)) {
      return;
    }
    _previewClips(layerId: _layerId, audioClips: _before);
    _commitClips(layerId: _layerId, audioClips: after);
    _notify();
  }

  /// Reverts an in-flight slide preview without touching history.
  @override
  void cancel() {
    final layer = _layerById(_layerId);
    if (layer == null || listEquals(layer.audioClips, _before)) {
      return;
    }
    _previewClips(layerId: _layerId, audioClips: _before);
    _notify();
  }
}

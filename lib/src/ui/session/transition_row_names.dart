import 'package:flutter/foundation.dart' show listEquals;

import '../../models/camera_instruction.dart';
import '../../models/layer.dart';
import '../../models/storyboard_timeline_layout.dart';
import '../../models/track.dart';
import '../../models/track_id.dart';
import '../../models/transition_names.dart';
import '../text/app_strings.dart';
import 'camera.dart';
import 'session_roles.dart';

/// A track's transition row the way its readers SHOW it — every span named
/// by the cuts it joins (F-229, [transitionRowNamedByItsCuts]).
///
/// Apart from `Transitions` because the two never meet: that one edits the
/// row, and ⛔nothing an edit reads is ever named here — a name written back
/// would be a stale copy of a derived word the moment a cut was renamed.
class TransitionRowNames {
  TransitionRowNames({
    required Camera camera,
    required SelectionAccess selection,
  }) : _camera = camera,
       _selection = selection;

  final Camera _camera;
  final SelectionAccess _selection;

  /// [row] — [track]'s transition row, or a drag's form of it — named in
  /// [olWord] (the program's word unless the reader prints in another
  /// language).
  ///
  /// For the track's own row, the same instance comes back while the row,
  /// the cuts under it, the vocabulary and the word are the same, so the
  /// identity-keyed row memos downstream hold (the cut view's display
  /// clone among them). A drag's form is new at every step and is named
  /// afresh — kept, it would push the committed row out of the one slot.
  Layer rowNamed(Track track, Layer row, {String? olWord}) {
    final word = olWord ?? AppText.strings.tlTransitionCutOl;
    final cuts = cutSpansOf(track).toList();
    final vocabulary = _camera.cameraInstructionSet;
    Layer name() => transitionRowNamedByItsCuts(
      row: row,
      cuts: cuts,
      vocabulary: vocabulary,
      olWord: word,
    );
    if (!identical(row, track.transitionLayer)) {
      return name();
    }
    final layout = [
      for (final placed in cuts)
        (placed.cut.name, placed.startFrame, placed.endFrame),
    ];
    final cached = _named[(track.id, word)];
    if (cached != null &&
        identical(cached.row, row) &&
        identical(cached.vocabulary, vocabulary) &&
        listEquals(cached.layout, layout)) {
      return cached.named;
    }
    final named = name();
    _named[(track.id, word)] = (
      row: row,
      vocabulary: vocabulary,
      layout: layout,
      named: named,
    );
    return named;
  }

  /// [event] as the active track's row would show it at [globalStart] —
  /// for the term window's preview, which follows a re-pick of the term
  /// before anything is written.
  InstructionEvent eventShownAt(int globalStart, InstructionEvent event) {
    final track = _selection.activeTrack;
    final alone = track.transitionLayer.copyWith(
      instructions: {globalStart: event},
    );
    return rowNamed(track, alone).instructions[globalStart]!;
  }

  final Map<
    (TrackId, String),
    ({
      Layer row,
      CameraInstructionSet vocabulary,
      List<(String, int, int)> layout,
      Layer named,
    })
  >
  _named = {};
}

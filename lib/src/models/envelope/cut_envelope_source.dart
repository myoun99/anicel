import '../production_staff.dart';
import '../project_frame_rate.dart';
import 'cut_envelope_counts.dart';

/// One CUT line of an envelope: the number as authored and its length.
///
/// A 겸용 envelope carries several — the WIT sheet prints three — so this
/// is a list rather than a single cut.
class CutEnvelopeCutLine {
  const CutEnvelopeCutLine({
    required this.name,
    required this.durationFrames,
    required this.fps,
  });

  /// The cut's name VERBATIM. No prefix, no zero padding: the form already
  /// prints `C`, and a cut called `20` prints as `20` (user, 2026-08-06).
  final String name;

  final int durationFrames;
  final int fps;

  int get seconds => durationFrames ~/ fps;
  int get frames => durationFrames % fps;

  /// The sheet's `초+コマ` reading, when a form wants it in one box.
  String get lengthLabel => secondsPlusFramesLabel(durationFrames, fps);
}

/// What a cut envelope reads, with no idea where anything will be drawn —
/// the conte sheet's contract, said of envelopes.
class CutEnvelopeSource {
  const CutEnvelopeSource({
    this.title = '',
    this.episode = '',
    this.note = '',
    this.cuts = const [],
    this.cels = const [],
    this.staff = const {},
    this.logoAssetPath,
    this.canvasWidth = 0,
    this.canvasHeight = 0,
    this.cameraWidth = 0,
    this.cameraHeight = 0,
  });

  final String title;
  final String episode;

  /// The cut's Direction memo — the same text the timesheet's memo band
  /// prints.
  final String note;

  /// This envelope's cuts: the active one plus its 겸용 siblings, which is
  /// why an envelope is one sheet even for a shared folder of cuts.
  final List<CutEnvelopeCutLine> cuts;

  /// The 担当 rows, top to bottom.
  final List<CutEnvelopeCelCount> cels;

  final Map<String, ProductionStaff> staff;
  final String? logoAssetPath;

  final int canvasWidth;
  final int canvasHeight;
  final int cameraWidth;
  final int cameraHeight;

  /// The 計 row, derived rather than stored.
  CutEnvelopeCelCount get total => cutEnvelopeCelTotal(cels);
}

final RegExp _token = RegExp(r'^\{([^}]*)\}$');
final RegExp _indexed = RegExp(r'^(\w+)\[(\d+)\]\.(\w+)$');

/// The TEXT a binding resolves to, or null when it addresses nothing —
/// an index past the last cut, a role nobody holds, a token this version
/// does not know. Null prints an empty box, never a literal `{…}`.
///
/// Grammar:
/// `{title}` `{episode}` `{note}`
/// `{cut[i].name|seconds|frames|length}`
/// `{cel[i].name|genga|douga}`
/// `{total.genga|douga}`
/// `{staff.<role>.name}`
/// `{canvas.width|height}` `{camera.width|height}`
String? resolveEnvelopeText(String binding, CutEnvelopeSource source) {
  final match = _token.firstMatch(binding.trim());
  if (match == null) {
    return null;
  }
  final path = match.group(1)!;

  final indexed = _indexed.firstMatch(path);
  if (indexed != null) {
    final collection = indexed.group(1)!;
    final index = int.parse(indexed.group(2)!);
    final field = indexed.group(3)!;
    switch (collection) {
      case 'cut':
        if (index >= source.cuts.length) {
          return null;
        }
        final cut = source.cuts[index];
        return switch (field) {
          'name' => cut.name,
          'seconds' => '${cut.seconds}',
          'frames' => '${cut.frames}',
          'length' => cut.lengthLabel,
          _ => null,
        };
      case 'cel':
        if (index >= source.cels.length) {
          return null;
        }
        final cel = source.cels[index];
        return switch (field) {
          'name' => cel.name,
          'genga' => '${cel.genga}',
          'douga' => '${cel.dougaEstimate}',
          _ => null,
        };
      default:
        return null;
    }
  }

  final parts = path.split('.');
  if (parts.length == 1) {
    return switch (parts.first) {
      'title' => source.title,
      'episode' => source.episode,
      'note' => source.note,
      _ => null,
    };
  }
  if (parts.length == 2) {
    return switch (parts) {
      ['total', 'genga'] => '${source.total.genga}',
      ['total', 'douga'] => '${source.total.dougaEstimate}',
      ['canvas', 'width'] => _size(source.canvasWidth),
      ['canvas', 'height'] => _size(source.canvasHeight),
      ['camera', 'width'] => _size(source.cameraWidth),
      ['camera', 'height'] => _size(source.cameraHeight),
      _ => null,
    };
  }
  if (parts.length == 3 && parts.first == 'staff' && parts.last == 'name') {
    final name = source.staff[parts[1]]?.name ?? '';
    return name.isEmpty ? null : name;
  }
  return null;
}

/// The media asset PATH an image binding resolves to: `{logo}` or
/// `{staff.<role>.stamp}`. Null leaves the box empty — which is also what
/// a hand-drawn stamp wants.
String? resolveEnvelopeImage(String binding, CutEnvelopeSource source) {
  final match = _token.firstMatch(binding.trim());
  if (match == null) {
    return null;
  }
  final path = match.group(1)!;
  if (path == 'logo') {
    return source.logoAssetPath;
  }
  final parts = path.split('.');
  if (parts.length == 3 && parts.first == 'staff' && parts.last == 'stamp') {
    return source.staff[parts[1]]?.stampAssetPath;
  }
  return null;
}

/// A zero size means "not measured yet" and prints nothing rather than 0.
String? _size(int value) => value <= 0 ? null : '$value';

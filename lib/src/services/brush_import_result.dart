import 'dart:typed_data';

import '../models/brush_preset.dart';
import '../models/import/import_warning.dart';

/// What a brush file came in as: a preset for each brush it could read, and
/// a note for each thing it could not carry over.
///
/// 🚨ONE RESULT FOR EVERY BRUSH READER (2026-11-14, card I-86): Photoshop's
/// and Clip Studio's readers each kept this same pair under a name of their
/// own, and TVPaint's panel export, the third, would have been a third.
class BrushImportResult {
  const BrushImportResult({required this.presets, required this.warnings});

  /// What a reader made of a brush file — or, where it made not one brush
  /// of it, the refusal [refusal] makes of [brushFileHoldsNothing].
  factory BrushImportResult.orRefused(
    List<BrushPreset> presets,
    List<String> warnings, {
    required ImportRefusal Function(ImportWarning reason) refusal,
  }) {
    if (presets.isEmpty) {
      throw refusal(brushFileHoldsNothing);
    }
    return BrushImportResult(presets: presets, warnings: warnings);
  }

  /// One preset per usable brush, ready for the preset library.
  final List<BrushPreset> presets;

  /// Human-readable notes about what could not be fully imported.
  final List<String> warnings;
}

/// Why a brush file is refused when its reader found not one brush in it to
/// carry — each reader raising it as its own `ImportRefusal`.
///
/// 🚨ONE WORD FOR EVERY BRUSH READER (2026-11-14, card I-86): Photoshop's
/// and Clip Studio's readers said it under keys of their own, and TVPaint's
/// would have been the third.
const brushFileHoldsNothing = ImportWarning(
  'brushNothingImportable',
  'The file contained no importable brushes.',
);

/// A brush file's reader: its [BrushImportResult], or an `ImportRefusal`
/// where the file is not one it reads at all.
typedef BrushFileReader =
    Future<BrushImportResult> Function(
      Uint8List bytes, {
      required String sourceName,
    });

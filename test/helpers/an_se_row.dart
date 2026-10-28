import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';

/// A bare, shown SE row — the row an SE span reads its look through
/// (`SeSpanVisual.layer`, I-129), for a span pumped alone.
Layer anSeRow() => Layer(
  id: const LayerId('se'),
  name: 'SE',
  kind: LayerKind.se,
  frames: const [],
);

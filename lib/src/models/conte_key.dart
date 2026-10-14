import 'string_id.dart';

/// Which row of its track's conte a row is (`Layer.conteKey`, F-343) — the
/// name a row of the track's conte structure (`TrackConte`) keeps in every
/// cut, where each cut's layer has an id of its own.
final class ConteKey extends StringId {
  const ConteKey(super.value);
}

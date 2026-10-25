/// A key that HASHES WHAT IT HOLDS ONCE — for a cache asked for the same
/// value again and again, whose hash walks a deep value (a text style, a
/// span and every child of it).
///
/// 🔬WHY (card frame-panels-build-in-one-frame, 2026-10-25): one use of an
/// `Lru` asks its key's hash twice — taken out, put back — and a record
/// hashes its fields afresh each time it is asked. A storyboard tab's reopen
/// asked the glyph cache for 1,173 glyphs and the baked words for 305, nearly
/// every one a hit.
///
/// ⛔THE VALUE STAYS A RECORD, so what is compared and hashed is every field
/// it holds — never a list written out by hand that the next field is missing
/// from (`the_values_are_listed_whole_test.dart` is that disease, twice).
final class HashedOnce<T> {
  HashedOnce(this.value);

  final T value;

  @override
  late final int hashCode = value.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HashedOnce<T> &&
          other.hashCode == hashCode &&
          other.value == value;
}

/// What a stand-in movie holds: the size of an MP4's first box and nothing
/// after it — a file that calls itself a movie and hands no decoder a
/// picture. A test whose decoding is faked needs only the file to be there;
/// one that reads a real movie writes it with `writeEncodedMovie`
/// (`encoded_movie.dart`).
///
/// 🚨ONE SPELLING (board test-fake-movie-files-are-three-copies,
/// 2026-10-29): twenty-five writes across fifteen tests each spelled these
/// four bytes out themselves — one meaning, agreed on by copy.
/// ⛔A test writes its stand-in movie with this;
/// `a_stand_in_movie_is_spelled_once_test` keeps it so.
const List<int> standInMovieBytes = [0, 0, 0, 24];

/// What a door brings in, brought at once — for a library pinned on its
/// own, with no door's wait window to stand it behind (`BringIn`).
Future<T> broughtAtOnce<T>(Future<T> Function() bring) => bring();

// Flutter-free side of the hooks of `b012_sqlflite_easy.dart` (the Flutter
// side is `flutter_hooks.dart`, chosen by a conditional import).

/// Prints a message about a failure (Flutter: `debugPrint`).
void b012Trace(String message) {
  // ignore: avoid_print
  print(message);
}

/// Makes sure the files saved by name are encrypted along with the
/// database (Flutter: instantiates `DiscData`, which registers its hooks).
/// Without Flutter there are no `DiscData` files.
void b012PrepareFiles() {}

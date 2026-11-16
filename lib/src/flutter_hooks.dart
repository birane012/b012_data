// Flutter side of the hooks of `b012_sqlflite_easy.dart` (see `hooks.dart`).
import 'package:flutter/foundation.dart' show debugPrint;

import '../b012_disc_data.dart';

/// Prints a message about a failure, through `debugPrint`.
void b012Trace(String message) => debugPrint(message);

/// Instantiates `DiscData`, which registers the hooks that encrypt the files
/// saved by name along with the database.
void b012PrepareFiles() => DiscData.instance;

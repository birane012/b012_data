import 'dart:io';
import 'dart:math';

final Random _random = Random.secure();

/// Writes [bytes] to [file] all at once: into a temporary file of its own
/// next to it, flushed to disk, then renamed over [file]. A reader sees the
/// old content or the new one, never half of it. Missing folders are
/// created.
///
/// The target is never deleted: if the rename keeps failing (a file locked
/// for a moment on Windows, for instance), the temporary file is removed and
/// the error is rethrown, leaving the previous content in place.
Future<void> writeAtomically(File file, List<int> bytes) async {
  await file.parent.create(recursive: true);
  final String suffix = _random.nextInt(1 << 32).toRadixString(36);
  final File temp = File('${file.path}.$suffix.b012tmp');
  final RandomAccessFile raf = await temp.open(mode: FileMode.write);
  try {
    await raf.writeFrom(bytes);
    await raf.flush();
  } finally {
    await raf.close();
  }
  for (int attempt = 0; ; attempt++) {
    try {
      await temp.rename(file.path);
      return;
    } on FileSystemException {
      if (attempt >= 6) {
        try {
          await temp.delete();
        } on FileSystemException {
          // Nothing more can be done; the previous content is untouched.
        }
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 25 * (attempt + 1)));
    }
  }
}

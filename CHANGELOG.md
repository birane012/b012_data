## 2.0.0

Major maintenance release. **The public API is kept backwards-compatible
with 1.x** — no method renames. Update your `pubspec.yaml` and you're done.

### Requirements
* Minimum SDK bumped to Dart `>=3.4.0` and Flutter `>=3.22.0`.

### Fixes
* `changeDB` was using the native `sqflite` backend on Windows instead of
  the FFI backend; the platform detection is now consistent with the rest
  of the library.
* `changeDB` no longer crashes when the database has never been opened.
* Linux now correctly uses the FFI backend (previously only Windows did).
* `getEntityColumnsName<T>` was always returning an empty list because a
  shadowed local variable prevented the result from escaping the
  transaction.
* `validatePath` now strips a single trailing separator instead of
  chopping off two characters.
* `deleteFile` now returns `true` when the file did not exist and `false`
  on failure, instead of always returning the post-deletion existence
  state.
* `getImageFromDisc` no longer throws when the image file cannot be read.
* `countElementsOf` tolerates `NULL` results from SQLite and returns `0`
  instead of throwing.
* Sanitization of WHERE clauses no longer matches identifiers that start
  with `true`/`false` (`\btrue\b` / `\bfalse\b` word boundaries).
* `cleanAllTablesData` now skips `sqlite_master` and internal tables.

### Improvements
* Dependencies updated to their latest stable versions:
  * `sqflite: ^2.4.2`
  * `sqflite_common_ffi: ^2.4.0`
  * `path_provider: ^2.1.5`
  * `flutter_lints: ^6.0.0`
* Package documentation rewritten in clearer English, with consistent
  examples.
* Stricter analyzer configuration (`strict-casts`, `strict-inference`,
  `strict-raw-types`, several extra lint rules).
* Uses `Random.secure()` for `newKey`.
* Internal code cleanup (removed dead commented code, tightened types
  where the public signature is not affected).

## 1.0.2
* This version supports ANDROID, IOS, LINUX, MACOS and WINDOWS but pub.dev
* shows only ANDROID, IOS, MACOS as compatible platforms.
* This is fixed in this version.

## 1.0.1+2
* This version supports ANDROID, IOS, LINUX, MACOS and WINDOWS but pub.dev
* shows only ANDROID, IOS, MACOS as compatible platforms.

## 1.0.1+1
* This version supports ANDROID, IOS, LINUX, MACOS and WINDOWS but pub.dev
* shows only ANDROID, IOS, MACOS as compatible platforms.

## 1.0.1
* Previous versions of the package supported only ANDROID, IOS and MACOS.
* This version supports ANDROID, IOS, LINUX, MACOS and WINDOWS.

## 1.0.0
* First null-safe version of the package.

## 0.0.10

## 0.0.1
* Initial release — SQLite persistence and file system helpers for Flutter.
* `DataAccess.instance` provides entity persistence in a SQLite database.
* `DiscData.instance` provides file system persistence.
* See the bundled example for usage.

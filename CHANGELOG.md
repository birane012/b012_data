## 2.0.2

* Documented the Spring Boot inspiration and the automatic CRUD generation
  at the top of `README.md`, so the core value proposition is visible at
  first glance.
* Rewrote the `pubspec.yaml` description to surface the package when
  developers search pub.dev for Spring Boot, SQLite CRUD or binary file
  manipulation (images, audio, video).
* Split the example into two self-contained, runnable files with their
  own `main`: `example/sqlite_example.dart` (SQLite CRUD walk-through
  around the `Person` entity) and `example/disc_example.dart` (binary
  file / file system walk-through around the `Images` entity).
  `example/main.dart` now orchestrates both demos in sequence and the
  `README.md` documents how to run each one in isolation.
* Aligned the `Person` entity with the numbered `Required` / `Optional`
  steps used in the `README.md`, so both sources tell the exact same
  story.
* Fixed the `Installation` section of `README.md`, which still pointed at
  an older version constraint.

## 2.0.1

* Broadened SDK constraint to `>=2.12.0 <4.0.0` (Flutter `>=2.0.0`) so the
  package installs on older null-safe Flutter projects.
* Loosened dependency ranges on `sqflite`, `sqflite_common_ffi` and
  `path_provider` to `>=2.0.0 <3.0.0`.
* Added an explicit `import 'package:sqflite/sqflite.dart';` so the package
  still resolves `Database`, `DatabaseFactory` and `databaseFactory` when
  the lowest allowed `sqflite_common_ffi` is selected (fixes pub.dev
  "dependency constraint lower bounds" downgrade analysis).
* Replaced `Enum.name` (Dart 2.15+) with `toString().split('.').last` so
  the library runs on Dart 2.12.

## 2.0.0

Major maintenance release. **The public API is kept backwards-compatible
with 1.x** — no method renames. Update your `pubspec.yaml` and you're done.

### Requirements
* Minimum SDK Dart `>=3.4.0` and Flutter `>=3.22.0` (lowered in 2.0.1).

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

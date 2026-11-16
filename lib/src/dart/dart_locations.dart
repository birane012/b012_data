import 'dart:io';

String? _directory;

/// Folder where the Flutter-free entry opens the application databases
/// (and keeps the name chosen by `changeDB`). Call it before the first
/// database access. Without it: the current directory. Ignored inside a
/// Flutter application, where the databases stay in the application's own
/// folder.
void setDatabasesDirectory(String path) => _directory = path;

/// The folder set by [setDatabasesDirectory], else the current directory.
String databasesDirectory() => _directory ?? Directory.current.path;

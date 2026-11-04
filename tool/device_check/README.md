# device_check

Checks b012_data inside a real application, on the platform it runs on: the
platform's own SQLite for plain bases (the sqflite plugin on Android, iOS and
macOS), SQLite3MultipleCiphers for encrypted ones, and the real application
folders. The unit tests of the package cannot see these: they run on the
host, without the plugin.

The platform folders are generated before a run and never kept:

```sh
cd tool/device_check
flutter create --platforms=macos --org dev.b012 --project-name device_check .
rm -rf test
flutter test integration_test -d macos
```

Replace `macos` by `ios`, `android`, `linux` or `windows`, and `-d macos` by
the device to use (`flutter devices`). On Linux, the desktop application
needs `clang cmake ninja-build pkg-config libgtk-3-dev`, and a display
(`xvfb-run -a flutter test ...` on a server).

The workflow `.github/workflows/platforms.yml` runs it on Linux, macOS and
an iOS simulator at every push.

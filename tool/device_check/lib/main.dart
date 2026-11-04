import 'package:flutter/material.dart';

/// The checks live in `integration_test/`; this application only hosts them.
void main() => runApp(
  const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Text('b012_data: run flutter test integration_test -d <device>'),
      ),
    ),
  ),
);

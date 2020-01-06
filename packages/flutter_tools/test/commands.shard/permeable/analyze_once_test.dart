// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:platform/platform.dart';

import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/commands/analyze.dart';
import 'package:flutter_tools/src/commands/create.dart';
import 'package:flutter_tools/src/dart/pub.dart';
import 'package:flutter_tools/src/runner/flutter_command.dart';
import 'package:flutter_tools/src/globals.dart' as globals;

import '../../src/common.dart';
import '../../src/context.dart';

final Generator _kNoColorTerminalPlatform = () => FakePlatform.fromPlatform(const LocalPlatform())..stdoutSupportsAnsi = false;
final Map<Type, Generator> noColorTerminalOverride = <Type, Generator>{
  Platform: _kNoColorTerminalPlatform,
};

void main() {
  final String analyzerSeparator = globals.platform.isWindows ? '-' : '•';

  group('analyze once', () {
    Directory tempDir;
    String projectPath;
    File libMain;

    setUpAll(() {
      Cache.disableLocking();
      tempDir = globals.fs.systemTempDirectory.createTempSync('flutter_analyze_once_test_1.').absolute;
      projectPath = globals.fs.path.join(tempDir.path, 'flutter_project');
      libMain = globals.fs.file(globals.fs.path.join(projectPath, 'lib', 'main.dart'));
    });

    tearDownAll(() {
      tryToDelete(tempDir);
    });

    // Create a project to be analyzed
    testUsingContext('flutter create', () async {
      await runCommand(
        command: CreateCommand(),
        arguments: <String>['--no-wrap', 'create', projectPath],
        statusTextContains: <String>[
          'All done!',
          'Your application code is in ${globals.fs.path.normalize(globals.fs.path.join(globals.fs.path.relative(projectPath), 'lib', 'main.dart'))}',
        ],
      );
      expect(libMain.existsSync(), isTrue);
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
    });

    // Analyze in the current directory - no arguments
    testUsingContext('working directory', () async {
      await runCommand(
        command: AnalyzeCommand(workingDirectory: globals.fs.directory(projectPath)),
        arguments: <String>['analyze'],
        statusTextContains: <String>['No issues found!'],
      );
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
    });

    // Analyze a specific file outside the current directory
    testUsingContext('passing one file throws', () async {
      await runCommand(
        command: AnalyzeCommand(),
        arguments: <String>['analyze', libMain.path],
        toolExit: true,
        exitMessageContains: 'is not a directory',
      );
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
    });

    // Analyze in the current directory - no arguments
    testUsingContext('working directory with errors', () async {
      // Break the code to produce the "The parameter 'onPressed' is required" hint
      // that is upgraded to a warning in package:flutter/analysis_options_user.yaml
      // to assert that we are using the default Flutter analysis options.
      // Also insert a statement that should not trigger a lint here
      // but will trigger a lint later on when an analysis_options.yaml is added.
      String source = await libMain.readAsString();
      source = source.replaceFirst(
        'onPressed: _incrementCounter,',
        '// onPressed: _incrementCounter,',
      );
      source = source.replaceFirst(
        '_counter++;',
        '_counter++; throw "an error message";',
      );
      await libMain.writeAsString(source);

      // Analyze in the current directory - no arguments
      await runCommand(
        command: AnalyzeCommand(workingDirectory: globals.fs.directory(projectPath)),
        arguments: <String>['analyze'],
        statusTextContains: <String>[
          'Analyzing',
          'warning $analyzerSeparator The parameter \'onPressed\' is required',
          'info $analyzerSeparator The declaration \'_incrementCounter\' isn\'t',
        ],
        exitMessageContains: '2 issues found.',
        toolExit: true,
      );
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
      ...noColorTerminalOverride,
    });

    // Analyze in the current directory - no arguments
    testUsingContext('working directory with local options', () async {
      // Insert an analysis_options.yaml file in the project
      // which will trigger a lint for broken code that was inserted earlier
      final File optionsFile = globals.fs.file(globals.fs.path.join(projectPath, 'analysis_options.yaml'));
      await optionsFile.writeAsString('''
  include: package:flutter/analysis_options_user.yaml
  linter:
    rules:
      - only_throw_errors
  ''');

      // Analyze in the current directory - no arguments
      await runCommand(
        command: AnalyzeCommand(workingDirectory: globals.fs.directory(projectPath)),
        arguments: <String>['analyze'],
        statusTextContains: <String>[
          'Analyzing',
          'warning $analyzerSeparator The parameter \'onPressed\' is required',
          'info $analyzerSeparator The declaration \'_incrementCounter\' isn\'t',
          'info $analyzerSeparator Only throw instances of classes extending either Exception or Error',
        ],
        exitMessageContains: '3 issues found.',
        toolExit: true,
      );
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
      ...noColorTerminalOverride
    });

    testUsingContext('no duplicate issues', () async {
      final Directory tempDir = globals.fs.systemTempDirectory.createTempSync('flutter_analyze_once_test_2.').absolute;

      try {
        final File foo = globals.fs.file(globals.fs.path.join(tempDir.path, 'foo.dart'));
        foo.writeAsStringSync('''
import 'bar.dart';

void foo() => bar();
''');

        final File bar = globals.fs.file(globals.fs.path.join(tempDir.path, 'bar.dart'));
        bar.writeAsStringSync('''
import 'dart:async'; // unused

void bar() {
}
''');

        // Analyze in the current directory - no arguments
        await runCommand(
          command: AnalyzeCommand(workingDirectory: tempDir),
          arguments: <String>['analyze'],
          statusTextContains: <String>[
            'Analyzing',
          ],
          exitMessageContains: '1 issue found.',
          toolExit: true,
        );
      } finally {
        tryToDelete(tempDir);
      }
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
      ...noColorTerminalOverride
    });

    testUsingContext('returns no issues when source is error-free', () async {
      const String contents = '''
StringBuffer bar = StringBuffer('baz');
''';
      final Directory tempDir = globals.fs.systemTempDirectory.createTempSync('flutter_analyze_once_test_3.');
      tempDir.childFile('main.dart').writeAsStringSync(contents);
      try {
        await runCommand(
          command: AnalyzeCommand(workingDirectory: globals.fs.directory(tempDir)),
          arguments: <String>['analyze'],
          statusTextContains: <String>['No issues found!'],
        );
      } finally {
        tryToDelete(tempDir);
      }
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
      ...noColorTerminalOverride
    });

    testUsingContext('returns no issues for todo comments', () async {
      const String contents = '''
// TODO(foobar):
StringBuffer bar = StringBuffer('baz');
''';
      final Directory tempDir = globals.fs.systemTempDirectory.createTempSync('flutter_analyze_once_test_4.');
      tempDir.childFile('main.dart').writeAsStringSync(contents);
      try {
        await runCommand(
          command: AnalyzeCommand(workingDirectory: globals.fs.directory(tempDir)),
          arguments: <String>['analyze'],
          statusTextContains: <String>['No issues found!'],
        );
      } finally {
        tryToDelete(tempDir);
      }
    }, overrides: <Type, Generator>{
      Pub: () => const Pub(),
      ...noColorTerminalOverride
    });
  });
}

void assertContains(String text, List<String> patterns) {
  if (patterns == null) {
    expect(text, isEmpty);
  } else {
    for (String pattern in patterns) {
      expect(text, contains(pattern));
    }
  }
}

Future<void> runCommand({
  FlutterCommand command,
  List<String> arguments,
  List<String> statusTextContains,
  List<String> errorTextContains,
  bool toolExit = false,
  String exitMessageContains,
}) async {
  try {
    arguments.insert(0, '--flutter-root=${Cache.flutterRoot}');
    await createTestCommandRunner(command).run(arguments);
    expect(toolExit, isFalse, reason: 'Expected ToolExit exception');
  } on ToolExit catch (e) {
    if (!toolExit) {
      testLogger.clear();
      rethrow;
    }
    if (exitMessageContains != null) {
      expect(e.message, contains(exitMessageContains));
    }
  }
  assertContains(testLogger.statusText, statusTextContains);
  assertContains(testLogger.errorText, errorTextContains);

  testLogger.clear();
}

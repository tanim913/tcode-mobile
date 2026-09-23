/// Every language the editor supports, and the rules for detecting them.
///
/// Grammars are imported one by one rather than through `re_highlight`'s
/// `all.dart`, which would pull all 197 into the bundle. These 27 are the set
/// the brief requires; adding another is one import plus one list entry.
library;

import 'package:pocket_code/services/language/language_definition.dart';
import 'package:re_highlight/languages/bash.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/languages/cpp.dart';
import 'package:re_highlight/languages/csharp.dart';
import 'package:re_highlight/languages/css.dart';
import 'package:re_highlight/languages/dart.dart';
import 'package:re_highlight/languages/dockerfile.dart';
import 'package:re_highlight/languages/go.dart';
import 'package:re_highlight/languages/ini.dart';
import 'package:re_highlight/languages/java.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/languages/kotlin.dart';
import 'package:re_highlight/languages/lua.dart';
import 'package:re_highlight/languages/makefile.dart';
import 'package:re_highlight/languages/markdown.dart';
import 'package:re_highlight/languages/php.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/languages/ruby.dart';
import 'package:re_highlight/languages/rust.dart';
import 'package:re_highlight/languages/scss.dart';
import 'package:re_highlight/languages/sql.dart';
import 'package:re_highlight/languages/swift.dart';
import 'package:re_highlight/languages/typescript.dart';
import 'package:re_highlight/languages/xml.dart';
import 'package:re_highlight/languages/yaml.dart';

abstract final class LanguageRegistry {
  /// Fallback for anything unrecognised. Opens as text with no highlighting,
  /// which is honest rather than guessing at a grammar.
  static const LanguageDefinition plainText = LanguageDefinition(
    id: 'plaintext',
    label: 'Plain text',
    mode: null,
  );

  static final List<LanguageDefinition> all = <LanguageDefinition>[
    LanguageDefinition(
      id: 'dart',
      label: 'Dart',
      mode: langDart,
      extensions: const <String>['dart'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'javascript',
      label: 'JavaScript',
      mode: langJavascript,
      // JSX is handled by the JavaScript grammar.
      extensions: const <String>['js', 'mjs', 'cjs', 'jsx'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'typescript',
      label: 'TypeScript',
      mode: langTypescript,
      // TSX likewise rides on the TypeScript grammar.
      extensions: const <String>['ts', 'mts', 'cts', 'tsx'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'json',
      label: 'JSON',
      mode: langJson,
      extensions: const <String>['json', 'jsonc', 'json5'],
      fileNames: const <String>['.eslintrc', '.babelrc'],
      // JSON has no comments, so Toggle Comment is correctly unavailable.
    ),
    LanguageDefinition(
      id: 'html',
      label: 'HTML',
      // highlight.js serves HTML from the XML grammar.
      mode: langXml,
      extensions: const <String>['html', 'htm', 'xhtml', 'vue', 'svelte'],
      blockComment: ('<!--', '-->'),
    ),
    LanguageDefinition(
      id: 'xml',
      label: 'XML',
      mode: langXml,
      extensions: const <String>['xml', 'svg', 'xsl', 'plist', 'xaml'],
      blockComment: ('<!--', '-->'),
    ),
    LanguageDefinition(
      id: 'css',
      label: 'CSS',
      mode: langCss,
      extensions: const <String>['css'],
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'scss',
      label: 'SCSS',
      mode: langScss,
      extensions: const <String>['scss', 'sass'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'python',
      label: 'Python',
      mode: langPython,
      extensions: const <String>['py', 'pyw', 'pyi'],
      shebangs: const <String>['python', 'python2', 'python3'],
      lineComment: '#',
    ),
    LanguageDefinition(
      id: 'java',
      label: 'Java',
      mode: langJava,
      extensions: const <String>['java'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'kotlin',
      label: 'Kotlin',
      mode: langKotlin,
      extensions: const <String>['kt', 'kts'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'swift',
      label: 'Swift',
      mode: langSwift,
      extensions: const <String>['swift'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'c',
      label: 'C',
      mode: langC,
      extensions: const <String>['c', 'h'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'cpp',
      label: 'C++',
      mode: langCpp,
      extensions: const <String>['cpp', 'cc', 'cxx', 'hpp', 'hh', 'hxx'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'csharp',
      label: 'C#',
      mode: langCsharp,
      extensions: const <String>['cs'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'go',
      label: 'Go',
      mode: langGo,
      extensions: const <String>['go'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'rust',
      label: 'Rust',
      mode: langRust,
      extensions: const <String>['rs'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'php',
      label: 'PHP',
      mode: langPhp,
      extensions: const <String>['php', 'phtml'],
      lineComment: '//',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'ruby',
      label: 'Ruby',
      mode: langRuby,
      extensions: const <String>['rb', 'rake', 'gemspec'],
      fileNames: const <String>['Gemfile', 'Rakefile'],
      shebangs: const <String>['ruby'],
      lineComment: '#',
    ),
    LanguageDefinition(
      id: 'bash',
      label: 'Shell',
      mode: langBash,
      extensions: const <String>['sh', 'bash', 'zsh', 'fish'],
      fileNames: const <String>['.bashrc', '.zshrc', '.profile', '.bash_profile'],
      shebangs: const <String>['sh', 'bash', 'zsh', 'dash'],
      lineComment: '#',
    ),
    LanguageDefinition(
      id: 'yaml',
      label: 'YAML',
      mode: langYaml,
      extensions: const <String>['yaml', 'yml'],
      fileNames: const <String>['pubspec.yaml', 'pubspec.lock', '.gitlab-ci.yml'],
      lineComment: '#',
    ),
    LanguageDefinition(
      id: 'toml',
      label: 'TOML',
      // highlight.js maps TOML onto the INI grammar.
      mode: langIni,
      extensions: const <String>['toml', 'ini', 'cfg', 'conf', 'editorconfig'],
      fileNames: const <String>['Cargo.toml', '.editorconfig'],
      lineComment: '#',
    ),
    LanguageDefinition(
      id: 'markdown',
      label: 'Markdown',
      mode: langMarkdown,
      extensions: const <String>['md', 'markdown', 'mdx'],
      blockComment: ('<!--', '-->'),
    ),
    LanguageDefinition(
      id: 'sql',
      label: 'SQL',
      mode: langSql,
      extensions: const <String>['sql'],
      lineComment: '--',
      blockComment: ('/*', '*/'),
    ),
    LanguageDefinition(
      id: 'lua',
      label: 'Lua',
      mode: langLua,
      extensions: const <String>['lua'],
      shebangs: const <String>['lua'],
      lineComment: '--',
      blockComment: ('--[[', ']]'),
    ),
    LanguageDefinition(
      id: 'dockerfile',
      label: 'Dockerfile',
      mode: langDockerfile,
      extensions: const <String>['dockerfile'],
      fileNames: const <String>['Dockerfile', 'Containerfile', 'dockerfile'],
      lineComment: '#',
    ),
    LanguageDefinition(
      id: 'makefile',
      label: 'Makefile',
      mode: langMakefile,
      extensions: const <String>['mk'],
      fileNames: const <String>['Makefile', 'makefile', 'GNUmakefile'],
      lineComment: '#',
    ),
    plainText,
  ];

  static LanguageDefinition? byId(String id) {
    for (final LanguageDefinition l in all) {
      if (l.id == id) {
        return l;
      }
    }
    return null;
  }
}

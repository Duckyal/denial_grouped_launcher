import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

@immutable
class LauncherGroup {
  const LauncherGroup({required this.id, required this.name});

  final String id;
  final String name;

  LauncherGroup copyWith({String? name}) =>
      LauncherGroup(id: id, name: name ?? this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LauncherGroup && other.id == id && other.name == name;

  @override
  int get hashCode => Object.hash(id, name);
}

@immutable
class GroupedLauncherData {
  const GroupedLauncherData({
    required this.groups,
    required this.assignments,
    required this.lastUsedGroup,
    this.execOverrides = const <String, String>{},
    this.autoNames = const <String, String>{},
    this.groupOrder = const <String>[],
    this.appOrder = const <String, List<String>>{},
    this.hiddenApps = const <String>{},
    this.managedFiles = const <String, String>{},
  });

  GroupedLauncherData.empty()
    : groups = const <LauncherGroup>[],
      assignments = const <String, String>{},
      lastUsedGroup = '',
      execOverrides = const <String, String>{},
      autoNames = const <String, String>{},
      groupOrder = const <String>[],
      appOrder = const <String, List<String>>{},
      hiddenApps = const <String>{},
      managedFiles = const <String, String>{};

  final List<LauncherGroup> groups;

  /// Application id -> group id. Unknown group ids read as ungrouped.
  final Map<String, String> assignments;

  /// Id of the group selected when the launcher last closed ('' = all).
  final String lastUsedGroup;

  /// Launcher id -> replacement desktop-entry Exec line.
  final Map<String, String> execOverrides;

  /// Auto category group id ('auto:…') -> user-renamed display label.
  final Map<String, String> autoNames;

  /// Unified ordering for all groups (user + auto). Missing entries append at end.
  final List<String> groupOrder;

  /// Group id -> ordered application ids. Apps absent from the list append
  /// at the end in their default (alphabetical) order.
  final Map<String, List<String>> appOrder;

  /// Launcher ids the user removed from the launcher. Desktop entries under
  /// the user's own `$XDG_DATA_HOME/applications` are deleted on disk;
  /// system-wide entries can only be hidden locally, so they are listed here
  /// and stay out of every view until restored.
  final Set<String> hiddenApps;

  /// Launcher id -> absolute path of the AppImage copy the plugin manages.
  /// Adding an AppImage copies it under `$XDG_DATA_HOME/denial/appimages`
  /// so the tile keeps working when the original file is moved or deleted;
  /// removing the tile deletes that copy again.
  final Map<String, String> managedFiles;

  GroupedLauncherData copyWith({
    List<LauncherGroup>? groups,
    Map<String, String>? assignments,
    String? lastUsedGroup,
    Map<String, String>? execOverrides,
    Map<String, String>? autoNames,
    List<String>? groupOrder,
    Map<String, List<String>>? appOrder,
    Set<String>? hiddenApps,
    Map<String, String>? managedFiles,
  }) {
    return GroupedLauncherData(
      groups: groups ?? this.groups,
      assignments: assignments ?? this.assignments,
      lastUsedGroup: lastUsedGroup ?? this.lastUsedGroup,
      execOverrides: execOverrides ?? this.execOverrides,
      autoNames: autoNames ?? this.autoNames,
      groupOrder: groupOrder ?? this.groupOrder,
      appOrder: appOrder ?? this.appOrder,
      hiddenApps: hiddenApps ?? this.hiddenApps,
      managedFiles: managedFiles ?? this.managedFiles,
    );
  }
}

/// User-owned grouping state persisted next to the shell's other desktop
/// preferences, in `$XDG_CONFIG_HOME/denial/grouped-launcher.json`.
class GroupedLauncherStore {
  GroupedLauncherStore({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final config = env['XDG_CONFIG_HOME'];
    final root = config != null && config.startsWith('/')
        ? config
        : '${env['HOME']}/.config';
    _document = File('$root/denial/grouped-launcher.json');
  }

  late final File _document;
  int _groupSerial = 0;

  String nextGroupId() {
    _groupSerial += 1;
    return 'g${DateTime.now().microsecondsSinceEpoch}-$_groupSerial';
  }

  static bool isValidGroupName(String name) =>
      name.runes.length <= 60 && !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name);

  /// Mirrors the launcher's desktop-entry category ids so persisted
  /// category renames are validated against the known set.
  static const _knownAutoGroupKeys = {
    'development',
    'internet',
    'office',
    'graphics',
    'audiovideo',
    'games',
    'education',
    'system',
  };

  static bool _isKnownAutoGroupId(String id) =>
      id.startsWith('auto:') &&
      _knownAutoGroupKeys.contains(id.substring('auto:'.length));

  static bool isValidCommand(String command) =>
      command.runes.length <= 4096 &&
      !RegExp(r'[\x00-\x1f\x7f]').hasMatch(command);

  Future<GroupedLauncherData> read() async {
    try {
      if (!await _document.exists()) return GroupedLauncherData.empty();
      if (await _document.length() > 262144) return GroupedLauncherData.empty();
      final value = jsonDecode(await _document.readAsString());
      if (value is! Map || value['schema'] != 1) {
        return GroupedLauncherData.empty();
      }
      final groups = <LauncherGroup>[];
      final seen = <String>{};
      final rawGroups = value['groups'];
      if (rawGroups is List) {
        for (final entry in rawGroups) {
          if (entry is! Map) continue;
          final id = entry['id'];
          final name = entry['name'];
          if (id is! String ||
              name is! String ||
              id.isEmpty ||
              id.runes.length > 80 ||
              !isValidGroupName(name) ||
              name.trim().isEmpty ||
              !seen.add(id)) {
            continue;
          }
          groups.add(LauncherGroup(id: id, name: name.trim()));
        }
      }
      final knownIds = <String>{for (final group in groups) group.id};
      final assignments = <String, String>{};
      final rawAssignments = value['assignments'];
      if (rawAssignments is Map) {
        rawAssignments.forEach((key, group) {
          if (key is String &&
              group is String &&
              key.isNotEmpty &&
              key.runes.length <= 512 &&
              // '' pins an app outside every group and 'auto:…' pins it to a
              // desktop-entry category group; both are valid without a
              // user-created group existing.
              (group.isEmpty ||
                  group.startsWith('auto:') ||
                  knownIds.contains(group))) {
            assignments[key] = group;
          }
        });
      }
      final execOverrides = <String, String>{};
      final rawOverrides = value['execOverrides'];
      if (rawOverrides is Map) {
        rawOverrides.forEach((key, command) {
          if (key is String &&
              command is String &&
              key.isNotEmpty &&
              key.runes.length <= 512 &&
              command.trim().isNotEmpty &&
              isValidCommand(command.trim())) {
            execOverrides[key] = command.trim();
          }
        });
      }
      final lastUsed = value['lastUsedGroup'];
      final autoNames = <String, String>{};
      final rawAutoNames = value['autoNames'];
      if (rawAutoNames is Map) {
        rawAutoNames.forEach((key, name) {
          if (key is String &&
              name is String &&
              _isKnownAutoGroupId(key) &&
              isValidGroupName(name) &&
              name.trim().isNotEmpty) {
            autoNames[key] = name.trim();
          }
        });
      }
      final groupOrder = <String>[];
      final rawGroupOrder = value['groupOrder'];
      if (rawGroupOrder is List) {
        for (final entry in rawGroupOrder) {
          if (entry is String &&
                  (entry.startsWith('auto:') && _isKnownAutoGroupId(entry)) ||
              (!entry.startsWith('auto:') && entry.isNotEmpty)) {
            groupOrder.add(entry);
          }
        }
      }
      final appOrder = <String, List<String>>{};
      final rawAppOrder = value['appOrder'];
      if (rawAppOrder is Map) {
        rawAppOrder.forEach((key, order) {
          if (key is! String || key.isEmpty || order is! List) return;
          final ids = <String>[];
          final seenIds = <String>{};
          for (final entry in order) {
            if (entry is String &&
                entry.isNotEmpty &&
                entry.runes.length <= 512 &&
                seenIds.add(entry)) {
              ids.add(entry);
            }
          }
          if (ids.isNotEmpty) appOrder[key] = ids;
        });
      }
      final hiddenApps = <String>{};
      final rawHidden = value['hiddenApps'];
      if (rawHidden is List) {
        for (final entry in rawHidden) {
          if (entry is String &&
              entry.isNotEmpty &&
              entry.runes.length <= 512) {
            hiddenApps.add(entry);
          }
        }
      }
      final managedFiles = <String, String>{};
      final rawManaged = value['managedFiles'];
      if (rawManaged is Map) {
        rawManaged.forEach((key, path) {
          if (key is String &&
              path is String &&
              key.isNotEmpty &&
              key.runes.length <= 512 &&
              path.startsWith('/') &&
              path.runes.length <= 4096 &&
              !RegExp(r'[\x00-\x1f\x7f]').hasMatch(path)) {
            managedFiles[key] = path;
          }
        });
      }
      return GroupedLauncherData(
        groups: groups,
        assignments: assignments,
        lastUsedGroup:
            lastUsed is String &&
                (knownIds.contains(lastUsed) || lastUsed.startsWith('auto:'))
            ? lastUsed
            : '',
        execOverrides: execOverrides,
        autoNames: autoNames,
        groupOrder: groupOrder,
        appOrder: appOrder,
        hiddenApps: hiddenApps,
        managedFiles: managedFiles,
      );
    } on FormatException {
      return GroupedLauncherData.empty();
    } on Object {
      return GroupedLauncherData.empty();
    }
  }

  Future<void> write(GroupedLauncherData data) async {
    try {
      await _document.parent.create(recursive: true);
      final temporary = File('${_document.path}.$pid.tmp');
      try {
        await temporary.writeAsString(
          jsonEncode(<String, Object>{
            'schema': 1,
            'groups': <Object>[
              for (final group in data.groups)
                {'id': group.id, 'name': group.name},
            ],
            'assignments': data.assignments,
            'lastUsedGroup': data.lastUsedGroup,
            'execOverrides': data.execOverrides,
            'autoNames': data.autoNames,
            'groupOrder': data.groupOrder,
            'appOrder': data.appOrder,
            'hiddenApps': <String>[...data.hiddenApps]..sort(),
            'managedFiles': data.managedFiles,
          }),
          flush: true,
        );
        await temporary.rename(_document.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
    } on Object {
      // Grouping is cosmetic state; a failed write must not break the
      // launcher session, only skip persistence.
    }
  }
}

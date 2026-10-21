import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dbus/dbus.dart';
import 'package:denial_flutter_sdk/applications.dart' show DesktopApp;
import 'package:denial_flutter_sdk/environment.dart'
    show startupEnvironmentProvider;
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:denial_flutter_sdk/service_backends.dart'
    show LogindAction, LogindCapability;
import 'package:denial_flutter_sdk/state.dart'
    show
        denialBridgeProvider,
        SessionPowerAction,
        SessionPowerState,
        sessionPowerProvider;
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'group_store.dart';

part 'app_categories.dart';
part 'grouped_launcher_components.dart';
part 'power_backend.dart';

const _allViewKey = '';
const _ungroupedViewKey = '\u0000ungrouped';
const _hiddenViewKey = '\u0000hidden';

class GroupedApplicationLauncher extends ConsumerStatefulWidget {
  const GroupedApplicationLauncher({
    super.key,
    required this.launcher,
    required this.desktopAppsById,
    required this.onLaunchDesktopApp,
  });

  final LauncherContext launcher;

  /// Launcher application id -> desktop entry, used for default category
  /// grouping and Exec overrides. Local Flutter apps have no entry here.
  final Map<String, DesktopApp> desktopAppsById;

  /// Launches a desktop entry whose Exec the user rewrote, going through the
  /// shell's native launcher bridge.
  final ValueChanged<DesktopApp> onLaunchDesktopApp;

  @override
  _GroupedApplicationLauncherState createState() =>
      _GroupedApplicationLauncherState();
}

enum _MenuMode {
  tile,
  group,
  newGroup,
  renameGroup,
  editExec,
  power,
  autoGroup,
}

@immutable
class _MenuState {
  const _MenuState({
    required this.mode,
    required this.position,
    this.appId,
    this.groupId,
  });

  final _MenuMode mode;
  final Offset position;
  final String? appId;
  final String? groupId;
}

class _GroupedApplicationLauncherState
    extends ConsumerState<GroupedApplicationLauncher> {
  static const double _tileExtent = 112;
  static const double _suggestedTileExtent = 96;
  static const double _tileSpacing = 8;
  static const double _gridCardPadding = 12;

  /// Recent apps always fill one row of this many tiles, independent of the
  /// all-apps grid column count.
  static const int _suggestionColumns = 4;
  static const double _sidebarWidth = 184;
  static const double _menuWidth = 244;

  final GroupedLauncherStore _store = GroupedLauncherStore();
  late final TextEditingController _searchController;
  final ScrollController _gridController = ScrollController();
  final GlobalKey _panelKey = GlobalKey(debugLabel: 'grouped-launcher-panel');

  GroupedLauncherData _data = GroupedLauncherData.empty();
  bool _dataLoaded = false;
  String _selectedView = _allViewKey;

  String _profileDisplayName = '';
  String _profileAvatarPath = '';
  String _accountName = '';

  String _lastSearchText = '';
  int _columnCount = 1;
  Size _panelSize = const Size(640, 480);
  int _selectedIndex = -1;

  _MenuState? _menu;
  TextEditingController? _inputController;
  FocusNode? _inputFocus;

  /// Application awaiting the second-click confirmation in the tile menu's
  /// "remove from launcher" step. Reset whenever the menu closes.
  String? _pendingRemoveAppId;

  /// logind verbs the launcher runs itself, so one unsupported verb cannot
  /// disable the whole power menu. Created on first use to keep the D-Bus
  /// connection off the launcher's hot path.
  _LauncherPowerBackend? _power;
  LogindAction? _pendingPowerAction;
  bool _powerBusy = false;
  bool _powerFailed = false;

  List<LauncherApplication>? _cachedSource;
  List<LauncherApplication>? _cachedSortedApps;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()
      ..addListener(_handleQueryChanged);
    unawaited(_load());
    _loadProfile();
  }

  @override
  void dispose() {
    _disposeMenuInput();
    unawaited(_power?.dispose());
    _searchController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    _gridController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await _store.read();
    if (!mounted) {
      return;
    }
    setState(() {
      _data = data;
      _dataLoaded = true;
      final lastUsed = data.lastUsedGroup;
      if (lastUsed.isNotEmpty &&
          (data.groups.any((group) => group.id == lastUsed) ||
              _isKnownAutoGroup(lastUsed))) {
        _selectedView = lastUsed;
      }
    });
  }

  /// Mirrors the reference desktop's own profile store so the header shows
  /// the same name and avatar the user set in Settings.
  void _loadProfile() {
    final environment = ref.read(startupEnvironmentProvider);
    final account = environment['USER'] ?? environment['LOGNAME'];
    if (account != null && account.trim().isNotEmpty) {
      _accountName = account.trim();
    }
    final configured = environment['XDG_CONFIG_HOME']?.trim();
    final home = environment['HOME']?.trim();
    final root = configured != null && configured.startsWith('/')
        ? configured
        : home != null && home.startsWith('/')
        ? '$home/.config'
        : '';
    if (root.isEmpty) return;
    final directory = Directory('$root/denial/plugins/denial_desktop/profile');
    unawaited(() async {
      try {
        final document = File('${directory.path}/profile.json');
        if (!await document.exists() || await document.length() > 65536) {
          return;
        }
        final value = jsonDecode(await document.readAsString());
        if (value is! Map || value['schema'] != 1) return;
        final name = value['displayName'];
        final avatar = value['avatar'];
        var avatarPath = '';
        if (avatar is String &&
            RegExp(r'^avatar-[0-9]+-[0-9]+\.png$').hasMatch(avatar)) {
          final file = File('${directory.path}/$avatar');
          if (await file.exists()) avatarPath = file.path;
        }
        if (!mounted) return;
        setState(() {
          if (name is String &&
              name.runes.length <= 200 &&
              !RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
            _profileDisplayName = name.trim();
          }
          _profileAvatarPath = avatarPath;
        });
      } on Object {
        // The header falls back to the account name; a missing profile is
        // normal on a fresh session.
      }
    }());
  }

  void _persist() => unawaited(_store.write(_data));

  void _handleQueryChanged() {
    final searchText = _searchController.text;
    if (searchText == _lastSearchText) {
      return;
    }
    _lastSearchText = searchText;
    setState(() => _selectedIndex = -1);
    _resetGridScroll();
  }

  @override
  void didUpdateWidget(covariant GroupedApplicationLauncher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.launcher.visible && widget.launcher.visible) {
      _handleVisibilityChanged();
    }
  }

  void _handleVisibilityChanged() {
    // Prepare a clean launcher before the first frame of the next opening;
    // resetting on close would flash the full catalog during the fade-out.
    _selectedIndex = -1;
    _closeMenu();
    _resetGridScroll();
    if (_searchController.text.isNotEmpty) {
      _searchController.clear();
    }
  }

  void _clearSearch() {
    _searchController.clear();
    widget.launcher.searchFocusNode.requestFocus();
  }

  void _openSettings() {
    _closeMenu();
    widget.launcher.onDismiss();
    ref.read(denialBridgeProvider).launchApplication(<String>[
      'denial-settings',
    ]);
  }

  void _launch(LauncherApplication entry) {
    _closeMenu();
    final desktopApp = widget.desktopAppsById[entry.id];
    final override = _data.execOverrides[entry.id];
    if (desktopApp != null && override != null) {
      widget.launcher.onDismiss();
      widget.onLaunchDesktopApp(_withExec(desktopApp, override));
    } else {
      widget.launcher.onLaunch(entry.id);
    }
  }

  DesktopApp _withExec(DesktopApp app, String exec) => DesktopApp(
    id: app.id,
    name: app.name,
    exec: exec,
    desktopPath: app.desktopPath,
    categories: app.categories,
    keywords: app.keywords,
    icon: app.icon,
    iconPath: app.iconPath,
    startupWmClass: app.startupWmClass,
  );

  void _selectView(String viewKey) {
    if (_selectedView == viewKey) {
      return;
    }
    if (viewKey != _allViewKey && _searchController.text.isNotEmpty) {
      // The search field only exists in the "All" view; a stale query must
      // not keep filtering the other views.
      _searchController.clear();
    }
    setState(() {
      _selectedView = viewKey;
      _selectedIndex = -1;
      _data = _data.copyWith(
        lastUsedGroup:
            viewKey == _ungroupedViewKey || viewKey == _hiddenViewKey
            ? ''
            : viewKey,
      );
    });
    _resetGridScroll();
    _persist();
  }

  void _resetGridScroll() {
    if (!_gridController.hasClients) {
      return;
    }
    final position = _gridController.position;
    if (position.pixels != position.minScrollExtent) {
      _gridController.jumpTo(position.minScrollExtent);
    }
  }

  List<LauncherApplication> _sortedApps() {
    final source = widget.launcher.applications;
    final cached = _cachedSortedApps;
    if (identical(source, _cachedSource) && cached != null) return cached;
    _cachedSource = source;
    final apps = source.toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    _cachedSortedApps = apps;
    return apps;
  }

  List<String>? _categoriesOf(String appId) =>
      widget.desktopAppsById[appId]?.categories;

  /// The group an application is currently shown in. Manual assignments win
  /// over the desktop-entry default; an empty assignment explicitly pins the
  /// application to "ungrouped" even when its categories would group it.
  String? _effectiveGroup(String appId) {
    final assigned = _data.assignments[appId];
    if (assigned != null) {
      if (assigned.isEmpty) return null;
      if (assigned.startsWith(_autoGroupPrefix)) {
        return _isKnownAutoGroup(assigned)
            ? assigned
            : _autoGroupIdFor(_categoriesOf(appId));
      }
      if (_data.groups.any((group) => group.id == assigned)) {
        return assigned;
      }
    }
    return _autoGroupIdFor(_categoriesOf(appId));
  }

  List<LauncherApplication> _visibleApps(List<LauncherApplication> all) {
    final query = _selectedView == _allViewKey
        ? _lastSearchText.trim().toLowerCase()
        : '';
    if (query.isNotEmpty) {
      return all
          .where((app) => app.searchableText.contains(query))
          .toList(growable: false);
    }
    if (_selectedView == _allViewKey) return all;
    if (_selectedView == _ungroupedViewKey) {
      return _applyAppOrder(
        all
            .where((app) => _effectiveGroup(app.id) == null)
            .toList(growable: false),
      );
    }
    return _applyAppOrder(
      all
          .where((app) => _effectiveGroup(app.id) == _selectedView)
          .toList(growable: false),
    );
  }

  /// Reorders a group's applications by the user's persisted drag order.
  /// Apps absent from the stored list keep their alphabetical position at
  /// the end, so newly installed applications are never hidden.
  List<LauncherApplication> _applyAppOrder(List<LauncherApplication> apps) {
    final order = _data.appOrder[_selectedView];
    if (order == null || order.isEmpty || apps.length < 2) return apps;
    final byId = <String, LauncherApplication>{
      for (final app in apps) app.id: app,
    };
    final result = <LauncherApplication>[];
    for (final id in order) {
      final app = byId.remove(id);
      if (app != null) result.add(app);
    }
    // `apps` is already alphabetical; the leftovers keep that order.
    for (final app in apps) {
      if (byId.containsKey(app.id)) result.add(app);
    }
    return result;
  }

  List<LauncherApplication> _suggestedApps(
    List<LauncherApplication> all,
    bool queryActive,
  ) {
    if (_selectedView != _allViewKey || queryActive) {
      return const <LauncherApplication>[];
    }
    final appsById = <String, LauncherApplication>{
      for (final app in all) app.id: app,
    };
    final suggested = <LauncherApplication>[];
    for (final id in widget.launcher.recentApplicationIds) {
      final app = appsById[id];
      if (app == null) continue;
      suggested.add(app);
      if (suggested.length >= _suggestionColumns) break;
    }
    return suggested;
  }

  Map<String, int> _groupCounts(List<LauncherApplication> all) {
    final counts = <String, int>{};
    for (final app in all) {
      final groupId = _effectiveGroup(app.id);
      if (groupId != null) counts[groupId] = (counts[groupId] ?? 0) + 1;
    }
    return counts;
  }

  List<_AutoGroupView> _autoGroupViews(Map<String, int> counts, bool zh) {
    final present = <_AutoGroupView>[
      for (final group in _categoryGroups)
        if ((counts[group.id] ?? 0) > 0)
          _AutoGroupView(
            id: group.id,
            label: _autoGroupLabel(group.id, zh),
            icon: group.icon,
          ),
    ];
    final order = _data.groupOrder;
    if (order.isEmpty) return present;
    final byId = {for (final v in present) v.id: v};
    final result = <_AutoGroupView>[];
    for (final id in order) {
      if (id.startsWith(_autoGroupPrefix)) {
        final view = byId.remove(id);
        if (view != null) result.add(view);
      }
    }
    result.addAll(byId.values);
    return result;
  }

  /// Display label of a desktop-entry category, honoring the user's rename.
  String _autoGroupLabel(String id, bool zh) {
    final override = _data.autoNames[id];
    if (override != null && override.isNotEmpty) return override;
    final group = _categoryGroupById(id);
    if (group == null) return id;
    return zh ? group.zh : group.en;
  }

  // --- Group mutations -------------------------------------------------

  void _moveApp(String appId, String? groupId) {
    setState(() {
      final assignments = Map<String, String>.of(_data.assignments);
      // '' pins the application outside every group, including its
      // desktop-entry default.
      assignments[appId] = groupId ?? '';
      _data = _data.copyWith(assignments: assignments);
    });
    _closeMenu();
    _persist();
  }

  void _createGroup(String rawName) {
    final pendingAppId = _menu?.appId;
    final name = rawName.trim();
    if (!GroupedLauncherStore.isValidGroupName(name) || name.isEmpty) {
      _closeMenu();
      return;
    }
    final group = LauncherGroup(id: _store.nextGroupId(), name: name);
    setState(() {
      final assignments = Map<String, String>.of(_data.assignments);
      if (pendingAppId != null) assignments[pendingAppId] = group.id;
      _data = _data.copyWith(
        groups: <LauncherGroup>[..._data.groups, group],
        assignments: assignments,
        lastUsedGroup: group.id,
      );
      _selectedView = group.id;
      _selectedIndex = -1;
    });
    _closeMenu();
    _persist();
  }

  void _renameGroup(String rawName) {
    final groupId = _menu?.groupId;
    final name = rawName.trim();
    if (groupId == null ||
        !GroupedLauncherStore.isValidGroupName(name) ||
        name.isEmpty) {
      _closeMenu();
      return;
    }
    setState(() {
      if (groupId.startsWith(_autoGroupPrefix)) {
        final autoNames = Map<String, String>.of(_data.autoNames)
          ..[groupId] = name;
        _data = _data.copyWith(autoNames: autoNames);
        return;
      }
      _data = _data.copyWith(
        groups: [
          for (final group in _data.groups)
            if (group.id == groupId) group.copyWith(name: name) else group,
        ],
      );
    });
    _closeMenu();
    _persist();
  }

  void _resetAutoGroupName(String groupId) {
    setState(() {
      final autoNames = Map<String, String>.of(_data.autoNames)
        ..remove(groupId);
      _data = _data.copyWith(autoNames: autoNames);
    });
    _closeMenu();
    _persist();
  }

  void _deleteGroup(String groupId) {
    setState(() {
      final groups = _data.groups
          .where((group) => group.id != groupId)
          .toList(growable: false);
      final assignments = Map<String, String>.of(_data.assignments)
        ..removeWhere((_, value) => value == groupId);
      var next = _data.copyWith(groups: groups, assignments: assignments);
      if (_selectedView == groupId) _selectedView = _allViewKey;
      if (next.lastUsedGroup == groupId) {
        next = next.copyWith(lastUsedGroup: '');
      }
      _data = next;
    });
    _closeMenu();
    _persist();
  }

  void _reorderGroup(int oldIndex, int newIndex, Map<String, int> counts) {
    if (oldIndex == newIndex) return;
    final present = <String>{
      for (final g in _data.groups) g.id,
      for (final g in _autoGroupViews(counts, false)) g.id,
    };
    final order = <String>[];
    for (final id in _data.groupOrder) {
      if (present.remove(id)) order.add(id);
    }
    order.addAll(present);
    if (oldIndex < 0 ||
        oldIndex >= order.length ||
        newIndex < 0 ||
        newIndex > order.length) {
      return;
    }
    setState(() {
      final item = order.removeAt(oldIndex);
      order.insert(newIndex.clamp(0, order.length), item);
      _data = _data.copyWith(groupOrder: order);
    });
    _persist();
  }

  /// Moves a dragged application before or after `targetAppId` within the
  /// selected group. Dropping on the last tile's trailing half reaches the
  /// very end. Disabled in the "all" view, where the grid is alphabetical.
  void _reorderApp(String draggedAppId, String targetAppId, bool after) {
    if (_selectedView == _allViewKey) return;
    if (draggedAppId == targetAppId) return;
    final current = _visibleApps(_sortedApps())
        .map((app) => app.id)
        .toList(growable: true);
    final from = current.indexOf(draggedAppId);
    final to = current.indexOf(targetAppId);
    if (from < 0 || to < 0) return;
    setState(() {
      current.removeAt(from);
      // After removing the dragged entry, a forward drag shifts the target
      // one slot left; `after` then places it on the target's far side.
      var insert = to - (from < to ? 1 : 0) + (after ? 1 : 0);
      insert = insert.clamp(0, current.length);
      current.insert(insert, draggedAppId);
      final orders = Map<String, List<String>>.of(_data.appOrder)
        ..[_selectedView] = current;
      _data = _data.copyWith(appOrder: orders);
    });
    _persist();
  }

  // --- Launch command overrides ----------------------------------------

  void _saveExec(String rawCommand) {
    final appId = _menu?.appId;
    final command = rawCommand.trim();
    if (appId == null ||
        widget.desktopAppsById[appId] == null ||
        command.isEmpty ||
        !GroupedLauncherStore.isValidCommand(command)) {
      _closeMenu();
      return;
    }
    setState(() {
      final overrides = Map<String, String>.of(_data.execOverrides)
        ..[appId] = command;
      _data = _data.copyWith(execOverrides: overrides);
    });
    _closeMenu();
    _persist();
  }

  void _resetExec(String appId) {
    setState(() {
      final overrides = Map<String, String>.of(_data.execOverrides)
        ..remove(appId);
      _data = _data.copyWith(execOverrides: overrides);
    });
    _closeMenu();
    _persist();
  }

  // --- Remove from launcher --------------------------------------------

  /// Whether removing [appId] can also delete its desktop entry. Only files
  /// under the user's own `$XDG_DATA_HOME/applications` (or `~/.local/share`)
  /// are deleted; system-wide entries are read-only for a normal user and are
  /// hidden locally instead.
  bool _isUserOwnedDesktopEntry(String desktopPath) {
    final environment = ref.read(startupEnvironmentProvider);
    final dataHome = environment['XDG_DATA_HOME']?.trim();
    final home = environment['HOME']?.trim();
    final roots = <String>[
      if (dataHome != null && dataHome.startsWith('/'))
        '${dataHome.replaceAll(RegExp(r'/+$'), '')}/applications',
      if (home != null && home.startsWith('/'))
        '${home.replaceAll(RegExp(r'/+$'), '')}/.local/share/applications',
    ];
    return roots.any((root) => desktopPath.startsWith('$root/'));
  }

  /// First tap arms the confirmation; the menu then shows "confirm remove".
  void _requestRemoveApp(String appId) {
    if (_pendingRemoveAppId == appId) {
      unawaited(_removeApp(appId));
      return;
    }
    setState(() => _pendingRemoveAppId = appId);
  }

  Future<void> _removeApp(String appId) async {
    final desktopApp = widget.desktopAppsById[appId];
    final desktopPath = desktopApp?.desktopPath;
    var deletedOnDisk = false;
    if (desktopPath != null && _isUserOwnedDesktopEntry(desktopPath)) {
      try {
        final file = File(desktopPath);
        if (await file.exists()) {
          await file.delete();
          // The host watches this directory and re-scans; the entry is gone
          // from the catalog on its own, so no local hide is needed.
          deletedOnDisk = true;
        }
      } on Object {
        // A failed delete (permissions, race with a package manager) must not
        // break the launcher; fall through to the local hide so the tile
        // still disappears from this user's view.
      }
    }
    if (!mounted) return;
    setState(() {
      final hidden = Set<String>.of(_data.hiddenApps);
      final assignments = Map<String, String>.of(_data.assignments)
        ..remove(appId);
      final overrides = Map<String, String>.of(_data.execOverrides)
        ..remove(appId);
      if (!deletedOnDisk) hidden.add(appId);
      _data = _data.copyWith(
        hiddenApps: hidden,
        assignments: assignments,
        execOverrides: overrides,
      );
      _pendingRemoveAppId = null;
      _menu = null;
    });
    _persist();
  }

  void _restoreApp(String appId) {
    setState(() {
      final hidden = Set<String>.of(_data.hiddenApps)..remove(appId);
      _data = _data.copyWith(hiddenApps: hidden);
      _menu = null;
    });
    _persist();
  }

  // --- Context menu ----------------------------------------------------

  void _openMenu(_MenuState menu) {
    setState(() {
      _closeMenuInternal();
      _menu = menu;
      if (menu.mode == _MenuMode.power) {
        _power ??= _LauncherPowerBackend();
        _pendingPowerAction = null;
        _powerBusy = false;
        _powerFailed = false;
      }
      if (menu.mode == _MenuMode.newGroup ||
          menu.mode == _MenuMode.renameGroup ||
          menu.mode == _MenuMode.editExec) {
        String initial = '';
        if (menu.mode == _MenuMode.renameGroup) {
          final groupId = menu.groupId ?? '';
          if (groupId.startsWith(_autoGroupPrefix)) {
            initial = _autoGroupLabel(groupId, false);
          } else {
            for (final group in _data.groups) {
              if (group.id == groupId) initial = group.name;
            }
          }
        } else if (menu.mode == _MenuMode.editExec) {
          final appId = menu.appId;
          initial =
              _data.execOverrides[appId] ??
              widget.desktopAppsById[appId]?.exec ??
              '';
        }
        _inputController = TextEditingController(text: initial);
        _inputFocus = FocusNode(debugLabel: 'grouped-launcher-group-name');
      }
    });
    if (menu.mode == _MenuMode.power) {
      final power = _power;
      if (power != null) {
        unawaited(
          power.refresh().then((_) {
            if (mounted) setState(() {});
          }),
        );
      }
    }
    if (_inputFocus != null) {
      final focus = _inputFocus!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && focus.canRequestFocus) focus.requestFocus();
      });
    }
  }

  Future<void> _performSystemAction(LogindAction action) async {
    final power = _power;
    if (power == null || _powerBusy) {
      return;
    }
    setState(() {
      _powerBusy = true;
      _powerFailed = false;
    });
    try {
      await power.perform(action);
    } on Object {
      if (!mounted) {
        return;
      }
      setState(() {
        _powerBusy = false;
        _pendingPowerAction = null;
        _powerFailed = true;
      });
    }
  }

  void _openTileMenu(String appId, Offset globalPosition) {
    _openMenu(
      _MenuState(mode: _MenuMode.tile, position: globalPosition, appId: appId),
    );
  }

  /// Converts the menu's global anchor to a clamped offset inside the panel.
  Offset _menuLocalOffset(_MenuState menu, int autoGroupCount) {
    final box = _panelKey.currentContext?.findRenderObject();
    var position = menu.position;
    if (box is RenderBox) {
      position = box.globalToLocal(menu.position);
    }
    final height = _estimatedMenuHeight(menu, autoGroupCount);
    return Offset(
      position.dx
          .clamp(8.0, math.max(8.0, _panelSize.width - _menuWidth - 8.0))
          .toDouble(),
      position.dy
          .clamp(8.0, math.max(8.0, _panelSize.height - height - 8.0))
          .toDouble(),
    );
  }

  double _estimatedMenuHeight(_MenuState menu, int autoGroupCount) {
    if (menu.mode == _MenuMode.group) return 2 * 34 + 12;
    if (menu.mode == _MenuMode.autoGroup) return 46 + 2 * 34 + 12;
    if (menu.mode == _MenuMode.power) return 46 + 7 * 34 + 3 * 11 + 24;
    if (menu.mode != _MenuMode.tile) return 140;
    if (_selectedView == _hiddenViewKey) return 46 + 34 + 8;
    final desktopApp = widget.desktopAppsById[menu.appId];
    final overrideItems = desktopApp == null
        ? 0
        : 11 + 34 + (_data.execOverrides[menu.appId!] != null ? 34 : 0);
    // The trailing "remove" divider + item, present in every tile menu.
    return (46 +
            (_data.groups.length + autoGroupCount + 2) * 34 +
            44 +
            overrideItems +
            45)
        .toDouble();
  }

  void _disposeMenuInput() {
    _inputController?.dispose();
    _inputFocus?.dispose();
    _inputController = null;
    _inputFocus = null;
  }

  void _closeMenuInternal() {
    _disposeMenuInput();
    _menu = null;
    _pendingRemoveAppId = null;
  }

  void _closeMenu() {
    if (_menu == null) {
      _disposeMenuInput();
      return;
    }
    setState(_closeMenuInternal);
  }

  void _moveSelection(List<LauncherApplication> apps, int delta) {
    if (apps.isEmpty || delta == 0) {
      return;
    }
    final current = _selectedIndex < 0 ? (delta > 0 ? -1 : 0) : _selectedIndex;
    var next = (current + delta) % apps.length;
    if (next < 0) next += apps.length;
    setState(() => _selectedIndex = next);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.launcher.strings;
    final strings = _Strings(
      Localizations.localeOf(context).languageCode == 'zh',
    );
    final theme = ShellTheme.of(context);
    final session = ref.watch(sessionPowerProvider);
    final catalogApps = _sortedApps();
    final hiddenIds = _data.hiddenApps;
    final allApps = hiddenIds.isEmpty
        ? catalogApps
        : catalogApps
              .where((app) => !hiddenIds.contains(app.id))
              .toList(growable: false);
    final hiddenCount = catalogApps.length - allApps.length;
    final counts = _groupCounts(allApps);
    final autoGroups = _autoGroupViews(counts, strings.zh);
    final queryActive = _lastSearchText.trim().isNotEmpty;
    final apps = _selectedView == _hiddenViewKey
        ? catalogApps
              .where((app) => hiddenIds.contains(app.id))
              .toList(growable: false)
        : _visibleApps(allApps);
    final suggestedApps = _suggestedApps(allApps, queryActive);
    if (_selectedIndex >= apps.length) {
      _selectedIndex = apps.isEmpty ? -1 : apps.length - 1;
    }
    return _LauncherScope(
      launcher: widget.launcher,
      strings: strings,
      child: MouseRegion(
        onEnter: (_) => widget.launcher.onEnter(),
        onExit: (_) => widget.launcher.onExit(),
        child: CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_menu != null) {
                _closeMenu();
              } else {
                widget.launcher.onDismiss();
              }
            },
            const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                _moveSelection(apps, 1),
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                _moveSelection(apps, -1),
            const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                _moveSelection(apps, _columnCount),
            const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                _moveSelection(apps, -_columnCount),
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              _panelSize = constraints.biggest;
              _columnCount =
                  ((constraints.maxWidth - _sidebarWidth - 12 - _tileSpacing) /
                          (_tileExtent + _tileSpacing))
                      .floor()
                      .clamp(1, 32)
                      .toInt();
              return Overlay.wrap(
                clipBehavior: Clip.none,
                child: Stack(
                  children: [
                    DecoratedBox(
                      key: _panelKey,
                      decoration: BoxDecoration(
                        color: theme.panelColor(
                          context.shellColors.panelBackground,
                        ),
                        borderRadius: BorderRadius.circular(theme.panelRadius),
                        border: Border.all(color: context.shellColors.hairline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _UserPowerHeader(
                              displayName: _profileDisplayName.isNotEmpty
                                  ? _profileDisplayName
                                  : _accountName.isNotEmpty
                                  ? _accountName
                                  : strings.userFallback,
                              avatarPath: _profileAvatarPath,
                              busy: session.busy,
                              onOpenSettings: _openSettings,
                              onPowerMenu: (globalPosition) => _openMenu(
                                _MenuState(
                                  mode: _MenuMode.power,
                                  position: globalPosition,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _Sidebar(
                                    width: _sidebarWidth,
                                    data: _data,
                                    selectedView: _selectedView,
                                    counts: counts,
                                    autoGroups: autoGroups,
                                    strings: strings,
                                    visibleAllCount: allApps.length,
                                    hiddenCount: hiddenCount,
                                    onSelect: _selectView,
                                    onNewGroup: (globalPosition) => _openMenu(
                                      _MenuState(
                                        mode: _MenuMode.newGroup,
                                        position: globalPosition,
                                      ),
                                    ),
                                    onGroupContextMenu: (groupId, position) =>
                                        _openMenu(
                                          _MenuState(
                                            mode: _MenuMode.group,
                                            position: position,
                                            groupId: groupId,
                                          ),
                                        ),
                                    onRenameGroup: (groupId, position) =>
                                        _openMenu(
                                          _MenuState(
                                            mode: _MenuMode.renameGroup,
                                            position: position,
                                            groupId: groupId,
                                          ),
                                        ),
                                    onAutoGroupContextMenu:
                                        (groupId, position) => _openMenu(
                                          _MenuState(
                                            mode: _MenuMode.autoGroup,
                                            position: position,
                                            groupId: groupId,
                                          ),
                                        ),
                                    onAutoGroupRename: (groupId, position) =>
                                        _openMenu(
                                          _MenuState(
                                            mode: _MenuMode.renameGroup,
                                            position: position,
                                            groupId: groupId,
                                          ),
                                        ),
                                    onReorderGroup: (oldIndex, newIndex) =>
                                        _reorderGroup(oldIndex, newIndex, counts),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (_selectedView == _allViewKey) ...[
                                          _SearchField(
                                            controller: _searchController,
                                            focusNode:
                                                widget.launcher.searchFocusNode,
                                            onClear: _clearSearch,
                                            onSubmit: () {
                                              if (apps.isNotEmpty) {
                                                _launch(
                                                  apps[_selectedIndex < 0
                                                      ? 0
                                                      : _selectedIndex],
                                                );
                                              }
                                            },
                                          ),
                                          const SizedBox(height: 10),
                                          if (suggestedApps.isNotEmpty) ...[
                                            _BlockCard(
                                              padding: const EdgeInsets.all(
                                                _gridCardPadding,
                                              ),
                                              child: _SuggestionsRow(
                                                apps: suggestedApps,
                                                tileExtent:
                                                    _suggestedTileExtent,
                                                onLaunch: _launch,
                                                onContextMenu: _openTileMenu,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                          ],
                                        ],
                                        Expanded(
                                          child: _BlockCard(
                                            padding: const EdgeInsets.all(
                                              _gridCardPadding,
                                            ),
                                            child: _AppGrid(
                                              controller: _gridController,
                                              apps: apps,
                                              loading:
                                                  !_dataLoaded &&
                                                  widget
                                                      .launcher
                                                      .applications
                                                      .isEmpty,
                                              loadingLabel:
                                                  l10n.loadingApplications,
                                              emptyLabel: _selectedView ==
                                                      _hiddenViewKey
                                                  ? strings.hiddenHint
                                                  : queryActive
                                                  ? l10n.noApplicationsFound
                                                  : strings.emptyGroup,
                                              showSearchEmptyIcon: queryActive,
                                              selectedIndex: _selectedIndex,
                                              draggable:
                                                  _selectedView !=
                                                      _allViewKey &&
                                                  _selectedView !=
                                                      _hiddenViewKey,
                                              onReorder: _reorderApp,
                                              onTap: _launch,
                                              onSecondaryTap: _openTileMenu,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_menu != null)
                      ..._menuOverlay(autoGroups, strings, session),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  List<Widget> _menuOverlay(
    List<_AutoGroupView> autoGroups,
    _Strings strings,
    SessionPowerState session,
  ) {
    final menu = _menu!;
    final offset = _menuLocalOffset(menu, autoGroups.length);
    return <Widget>[
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeMenu,
          onSecondaryTap: _closeMenu,
        ),
      ),
      Positioned(
        left: offset.dx,
        top: offset.dy,
        child: _buildMenu(menu, autoGroups, strings, session),
      ),
    ];
  }

  Widget _buildMenu(
    _MenuState menu,
    List<_AutoGroupView> autoGroups,
    _Strings strings,
    SessionPowerState session,
  ) {
    final controller = _inputController;
    final focus = _inputFocus;
    return _MenuCard(
      width: _menuWidth,
      opacity: menu.mode == _MenuMode.power ? 1.0 : null,
      children: switch (menu.mode) {
        _MenuMode.tile => _tileMenuItems(menu, autoGroups, strings),
        _MenuMode.group => _groupMenuItems(menu, strings),
        _MenuMode.autoGroup => _autoGroupMenuItems(menu, strings),
        _MenuMode.power => _powerMenuItems(session, strings),
        _MenuMode.newGroup ||
        _MenuMode.renameGroup ||
        _MenuMode.editExec => _inputItems(
          mode: menu.mode,
          controller: controller,
          focus: focus,
          strings: strings,
        ),
      },
    );
  }

  List<_MenuItemData> _tileMenuItems(
    _MenuState menu,
    List<_AutoGroupView> autoGroups,
    _Strings strings,
  ) {
    final appId = menu.appId!;
    final LauncherApplication? app;
    {
      LauncherApplication? found;
      for (final entry in widget.launcher.applications) {
        if (entry.id == appId) found = entry;
      }
      app = found;
    }
    if (app == null) return <_MenuItemData>[];
    if (_selectedView == _hiddenViewKey) {
      // Removed entries only offer to come back; grouping or editing a tile
      // the user cannot launch from here would be confusing.
      return <_MenuItemData>[
        _MenuItemData.header(app.name),
        _MenuItemData.action(
          label: strings.restoreApp,
          icon: Icons.restore_rounded,
          onTap: () => _restoreApp(appId),
        ),
      ];
    }
    final currentGroupId = _effectiveGroup(appId);
    return <_MenuItemData>[
      _MenuItemData.header(app.name),
      _MenuItemData.label(strings.moveToGroup),
      for (final group in _data.groups)
        _MenuItemData.action(
          label: group.name,
          checked: group.id == currentGroupId,
          onTap: () => _moveApp(appId, group.id),
        ),
      for (final group in autoGroups)
        _MenuItemData.action(
          label:
              '${_autoGroupLabel(group.id, strings.zh)} · ${strings.autoGroupSuffix}',
          checked: group.id == currentGroupId,
          onTap: () => _moveApp(appId, group.id),
        ),
      _MenuItemData.action(
        label: strings.ungrouped,
        checked: currentGroupId == null,
        onTap: () => _moveApp(appId, null),
      ),
      _MenuItemData.divider(),
      _MenuItemData.action(
        label: strings.newGroupAndMove,
        icon: Icons.create_new_folder_rounded,
        onTap: () => _openMenu(
          _MenuState(
            mode: _MenuMode.newGroup,
            position: menu.position,
            appId: appId,
          ),
        ),
      ),
      if (widget.desktopAppsById[appId] != null) ...[
        _MenuItemData.divider(),
        _MenuItemData.action(
          label: strings.editExec,
          icon: Icons.terminal_rounded,
          onTap: () => _openMenu(
            _MenuState(
              mode: _MenuMode.editExec,
              position: menu.position,
              appId: appId,
            ),
          ),
        ),
        if (_data.execOverrides[appId] != null)
          _MenuItemData.action(
            label: strings.resetExec,
            icon: Icons.restore_rounded,
            onTap: () => _resetExec(appId),
          ),
      ],
      _MenuItemData.divider(),
      _pendingRemoveAppId == appId
          ? _MenuItemData.action(
              label: strings.confirmRemove,
              icon: Icons.check_rounded,
              destructive: true,
              dangerColor: const Color(0xFFEF5350),
              onTap: () => unawaited(_removeApp(appId)),
            )
          : _MenuItemData.action(
              label: strings.removeApp(
                _isUserOwnedDesktopEntry(
                  widget.desktopAppsById[appId]?.desktopPath ?? '',
                ),
              ),
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onTap: () => _requestRemoveApp(appId),
            ),
    ];
  }

  List<_MenuItemData> _groupMenuItems(_MenuState menu, _Strings strings) {
    final groupId = menu.groupId!;
    return <_MenuItemData>[
      _MenuItemData.action(
        label: strings.rename,
        icon: Icons.drive_file_rename_outline_rounded,
        onTap: () => _openMenu(
          _MenuState(
            mode: _MenuMode.renameGroup,
            position: menu.position,
            groupId: groupId,
          ),
        ),
      ),
      _MenuItemData.action(
        label: strings.deleteGroup,
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onTap: () => _deleteGroup(groupId),
      ),
    ];
  }

  List<_MenuItemData> _autoGroupMenuItems(_MenuState menu, _Strings strings) {
    final groupId = menu.groupId!;
    final overridden = _data.autoNames[groupId] != null;
    return <_MenuItemData>[
      _MenuItemData.header(_autoGroupLabel(groupId, strings.zh)),
      _MenuItemData.action(
        label: strings.rename,
        icon: Icons.drive_file_rename_outline_rounded,
        onTap: () => _openMenu(
          _MenuState(
            mode: _MenuMode.renameGroup,
            position: menu.position,
            groupId: groupId,
          ),
        ),
      ),
      if (overridden)
        _MenuItemData.action(
          label: strings.resetName,
          icon: Icons.restore_rounded,
          onTap: () => _resetAutoGroupName(groupId),
        ),
    ];
  }

  List<_MenuItemData> _powerMenuItems(
    SessionPowerState session,
    _Strings strings,
  ) {
    final controller = ref.read(sessionPowerProvider.notifier);
    final pending = session.confirmationAction;
    if (pending != null) {
      return <_MenuItemData>[
        _MenuItemData.header(
          strings.powerConfirm(_powerActionLabel(pending, strings)),
        ),
        _MenuItemData.action(
          label: strings.confirm,
          icon: Icons.check_rounded,
          destructive: _powerIsDestructive(pending),
          dangerColor:
              _powerIsDestructive(pending) ? const Color(0xFFEF5350) : null,
          onTap: () => unawaited(controller.confirm()),
        ),
        _MenuItemData.action(
          label: strings.cancel,
          onTap: () => controller.cancelConfirmation(),
        ),
      ];
    }
    final systemPending = _pendingPowerAction;
    if (systemPending != null) {
      return <_MenuItemData>[
        _MenuItemData.header(
          strings.powerConfirm(_systemActionLabel(systemPending, strings)),
        ),
        if (_powerFailed) _MenuItemData.label(strings.powerFailed),
        _MenuItemData.action(
          label: strings.confirm,
          icon: Icons.check_rounded,
          destructive: true,
          dangerColor: const Color(0xFFEF5350),
          disabled: _powerBusy,
          checked: _powerBusy,
          onTap: () => unawaited(_performSystemAction(systemPending)),
        ),
        _MenuItemData.action(
          label: strings.cancel,
          onTap: () => setState(() => _pendingPowerAction = null),
        ),
      ];
    }

    _MenuItemData systemItem(LogindAction action, String label, IconData icon) {
      final capability = _power?.capabilityFor(action);
      final enabled = !_powerBusy && (capability?.canRequest ?? true);
      final destructive =
          action == LogindAction.powerOff || action == LogindAction.reboot;
      return _MenuItemData.action(
        label: label,
        icon: icon,
        destructive: destructive,
        dangerColor: destructive ? const Color(0xFFEF5350) : null,
        disabled: !enabled,
        onTap: enabled
            ? () => setState(() {
                _pendingPowerAction = action;
                _powerFailed = false;
              })
            : null,
      );
    }

    _MenuItemData actionItem(
      SessionPowerAction action,
      IconData icon,
      VoidCallback? onTap,
    ) {
      final enabled = !session.busy && session.availabilityFor(action).enabled;
      return _MenuItemData.action(
        label: _powerActionLabel(action, strings),
        icon: icon,
        destructive: _powerIsDestructive(action),
        dangerColor:
            _powerIsDestructive(action) ? const Color(0xFFEF5350) : null,
        disabled: !enabled,
        checked: session.busyAction == action,
        onTap: enabled ? onTap : null,
      );
    }

    return <_MenuItemData>[
      _MenuItemData.header(
        _powerFailed ? strings.powerFailed : strings.powerMenu,
      ),
      systemItem(
        LogindAction.powerOff,
        strings.shutdown,
        Icons.power_settings_new,
      ),
      systemItem(
        LogindAction.reboot,
        strings.reboot,
        Icons.restart_alt_rounded,
      ),
      _MenuItemData.divider(),
      systemItem(
        LogindAction.hibernate,
        strings.hibernate,
        Icons.bedtime_rounded,
      ),
      systemItem(LogindAction.suspend, strings.suspend, Icons.pause_rounded),
      _MenuItemData.divider(),
      actionItem(SessionPowerAction.lock, Icons.lock_outline_rounded, () {
        _closeMenu();
        controller.request(SessionPowerAction.lock);
      }),
      _MenuItemData.action(
        label: strings.screenOff,
        icon: Icons.contrast_rounded,
        disabled: session.busy,
        // Compositor-owned DPMS: the SDK's screen-power service writes to a
        // powerd control socket that this host does not run, and swallows the
        // failed connect. Any physical input wakes the outputs again.
        onTap: () {
          _closeMenu();
          ref.read(denialBridgeProvider).requestDpmsOff();
        },
      ),
      _MenuItemData.divider(),
      actionItem(
        SessionPowerAction.logout,
        Icons.logout_rounded,
        () => unawaited(controller.request(SessionPowerAction.logout)),
      ),
    ];
  }

  String _systemActionLabel(LogindAction action, _Strings strings) {
    return switch (action) {
      LogindAction.powerOff => strings.shutdown,
      LogindAction.reboot => strings.reboot,
      LogindAction.hibernate => strings.hibernate,
      LogindAction.suspend => strings.suspend,
    };
  }

  String _powerActionLabel(SessionPowerAction action, _Strings strings) {
    return switch (action) {
      SessionPowerAction.powerOff => strings.shutdown,
      SessionPowerAction.reboot => strings.reboot,
      SessionPowerAction.hibernate => strings.hibernate,
      SessionPowerAction.suspend => strings.suspend,
      SessionPowerAction.lock => strings.lock,
      SessionPowerAction.logout => strings.logout,
    };
  }

  bool _powerIsDestructive(SessionPowerAction action) =>
      action == SessionPowerAction.powerOff ||
      action == SessionPowerAction.reboot ||
      action == SessionPowerAction.logout;

  List<_MenuItemData> _inputItems({
    required _MenuMode mode,
    required TextEditingController? controller,
    required FocusNode? focus,
    required _Strings strings,
  }) {
    if (controller == null || focus == null) {
      return <_MenuItemData>[];
    }
    final (
      String header,
      String hint,
      void Function(String) onSubmit,
    ) = switch (mode) {
      _MenuMode.renameGroup => (
        strings.rename,
        strings.groupNameHint,
        _renameGroup,
      ),
      _MenuMode.editExec => (strings.editExec, strings.execHint, _saveExec),
      _ => (strings.newGroup, strings.groupNameHint, _createGroup),
    };
    return <_MenuItemData>[
      _MenuItemData.header(header),
      _MenuItemData.input(
        controller: controller,
        focusNode: focus,
        hint: hint,
        onSubmit: () => onSubmit(controller.text),
      ),
      _MenuItemData.action(
        label: strings.save,
        icon: Icons.check_rounded,
        onTap: () => onSubmit(controller.text),
      ),
      _MenuItemData.action(
        label: strings.cancel,
        icon: Icons.close_rounded,
        onTap: _closeMenu,
      ),
    ];
  }
}

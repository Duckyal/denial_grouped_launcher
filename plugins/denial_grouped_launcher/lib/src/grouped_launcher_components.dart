part of 'grouped_launcher.dart';

class _LauncherScope extends InheritedWidget {
  const _LauncherScope({
    required this.launcher,
    required this.strings,
    required super.child,
  });

  final LauncherContext launcher;
  final _Strings strings;

  static _LauncherScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LauncherScope>()!;

  @override
  bool updateShouldNotify(_LauncherScope oldWidget) =>
      !identical(launcher, oldWidget.launcher);
}

class _Strings {
  const _Strings(this.zh);

  final bool zh;

  String get all => zh ? '全部' : 'All';
  String get ungrouped => zh ? '未分组' : 'Ungrouped';
  String get autoGroupSuffix => zh ? '分类' : 'category';
  String get newGroup => zh ? '新建分组' : 'New group';
  String get moveToGroup => zh ? '移动到分组' : 'Move to group';
  String get newGroupAndMove => zh ? '新建分组并移入' : 'New group and move';
  String get rename => zh ? '重命名分组' : 'Rename group';
  String get resetName => zh ? '恢复默认名称' : 'Reset name';
  String get deleteGroup => zh ? '删除分组' : 'Delete group';
  String get editExec => zh ? '编辑启动命令' : 'Edit launch command';
  String get resetExec => zh ? '恢复默认命令' : 'Reset command';
  String get execHint => zh ? '完整启动命令，回车保存' : 'Full command, Enter to save';
  String get cancel => zh ? '取消' : 'Cancel';
  String get save => zh ? '保存' : 'Save';
  String get groupNameHint => zh ? '分组名称，回车创建' : 'Group name, Enter to save';
  String get emptyGroup => zh ? '此分组暂无应用，右键应用可移入' : 'No apps in this group yet';
  String get powerMenu => zh ? '电源' : 'Power';
  String get settings => zh ? '设置' : 'Settings';
  String get shutdown => zh ? '关机' : 'Shut down';
  String get reboot => zh ? '重启' : 'Restart';
  String get hibernate => zh ? '休眠' : 'Hibernate';
  String get suspend => zh ? '挂起' : 'Suspend';
  String get lock => zh ? '锁定' : 'Lock';
  String get screenOff => zh ? '熄屏' : 'Screen off';
  String get logout => zh ? '注销' : 'Log out';
  String get confirm => zh ? '确认' : 'Confirm';
  String get powerFailed => zh ? '此操作当前无法执行' : 'This action could not run';
  String get userFallback => zh ? '用户' : 'User';
  String powerConfirm(String action) => zh ? '确认$action吗？' : 'Confirm $action?';
  String get hiddenApps => zh ? '已移除' : 'Removed';
  String get confirmRemove => zh ? '再次点击确认移除' : 'Tap again to confirm';
  String get restoreApp => zh ? '恢复到启动器' : 'Restore to launcher';
  String get hiddenHint =>
      zh ? '此分组暂无应用' : 'No removed apps';
  String get addApp => zh ? '添加应用' : 'Add application';
  String get addAppHint => zh
      ? '输入 AppImage 或 .desktop 文件路径，回车添加'
      : 'Path to an AppImage or .desktop file, Enter to add';
  String get addAppEmpty => zh ? '请输入文件路径' : 'Enter a file path';
  String get addAppNotFound => zh ? '文件不存在' : 'File not found';
  String get addAppInvalidDesktop => zh
      ? '无效的 desktop 文件（缺少 [Desktop Entry] 或 Exec）'
      : 'Invalid desktop entry (no [Desktop Entry] or Exec)';
  String get addAppAlready =>
      zh ? '该文件已在应用目录中' : 'Already in the applications directory';
  String get addAppType =>
      zh ? '仅支持 .AppImage 或 .desktop 文件' : 'Only .AppImage and .desktop files are supported';
  String get addAppFailed => zh ? '添加失败' : 'Could not add';
  /// [deletesFile] distinguishes a real desktop-entry delete (user-owned
  /// entry) from hiding a system-wide entry that only this launcher hides.
  String removeApp(bool deletesFile) => deletesFile
      ? (zh ? '移除并删除 desktop 文件' : 'Remove and delete entry')
      : (zh ? '从启动器移除' : 'Remove from launcher');
}

// --- Sidebar -----------------------------------------------------------

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.width,
    required this.data,
    required this.selectedView,
    required this.counts,
    required this.autoGroups,
    required this.strings,
    required this.visibleAllCount,
    required this.hiddenCount,
    required this.onSelect,
    required this.onNewGroup,
    required this.onGroupContextMenu,
    required this.onRenameGroup,
    required this.onAutoGroupContextMenu,
    required this.onAutoGroupRename,
    required this.onReorderGroup,
  });

  final double width;
  final GroupedLauncherData data;
  final String selectedView;
  final Map<String, int> counts;
  final List<_AutoGroupView> autoGroups;
  final _Strings strings;

  /// Apps shown in "All" (the catalog minus locally hidden entries).
  final int visibleAllCount;

  /// Entries the user removed; > 0 reveals the "Removed" view.
  final int hiddenCount;
  final ValueChanged<String> onSelect;
  final ValueChanged<Offset> onNewGroup;
  final void Function(String groupId, Offset globalPosition) onGroupContextMenu;
  final void Function(String groupId, Offset globalPosition) onRenameGroup;
  final void Function(String groupId, Offset globalPosition)
  onAutoGroupContextMenu;
  final void Function(String groupId, Offset globalPosition) onAutoGroupRename;
  final void Function(int oldIndex, int newIndex) onReorderGroup;

  @override
  Widget build(BuildContext context) {
    final groupedTotal = counts.values.fold<int>(0, (a, b) => a + b);
    final userGroups = data.groups;
    final byId = <String, _SidebarGroupEntry>{
      for (final g in userGroups)
        g.id: _SidebarGroupEntry(
          id: g.id,
          isAuto: false,
          icon: Icons.folder_rounded,
          label: g.name,
          count: counts[g.id] ?? 0,
        ),
      for (final g in autoGroups)
        g.id: _SidebarGroupEntry(
          id: g.id,
          isAuto: true,
          icon: g.icon,
          label: g.label,
          count: counts[g.id] ?? 0,
        ),
    };
    final allGroups = <_SidebarGroupEntry>[];
    for (final id in data.groupOrder) {
      final entry = byId.remove(id);
      if (entry != null) allGroups.add(entry);
    }
    allGroups.addAll(byId.values);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              primary: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _SideEntry(
                    icon: Icons.apps_rounded,
                    label: strings.all,
                    count: null,
                    selected: selectedView == _allViewKey,
                    onTap: () => onSelect(_allViewKey),
                  ),
                  if (allGroups.isNotEmpty) const _SidebarDivider(),
                  if (allGroups.isNotEmpty)
                    ReorderableListView(
                      shrinkWrap: true,
                      primary: false,
                      physics: const NeverScrollableScrollPhysics(),
                      buildDefaultDragHandles: false,
                      proxyDecorator: (child, index, animation) => child,
                      onReorderItem: onReorderGroup,
                      children: [
                        for (var i = 0; i < allGroups.length; i++)
                          _SideEntry(
                            key: ValueKey<String>(allGroups[i].id),
                            icon: allGroups[i].icon,
                            label: allGroups[i].label,
                            count: allGroups[i].count,
                            selected: selectedView == allGroups[i].id,
                            reorderIndex: i,
                            dragHandle: const Icon(Icons.drag_handle_rounded),
                            onTap: () => onSelect(allGroups[i].id),
                            onSecondaryTap: (position) => allGroups[i].isAuto
                                ? onAutoGroupContextMenu(allGroups[i].id, position)
                                : onGroupContextMenu(allGroups[i].id, position),
                            onEditTap: (position) => allGroups[i].isAuto
                                ? onAutoGroupRename(allGroups[i].id, position)
                                : onRenameGroup(allGroups[i].id, position),
                          ),
                      ],
                    ),
                  if (visibleAllCount - groupedTotal > 0)
                    _SideEntry(
                      icon: Icons.category_rounded,
                      label: strings.ungrouped,
                      count: visibleAllCount - groupedTotal,
                      selected: selectedView == _ungroupedViewKey,
                      onTap: () => onSelect(_ungroupedViewKey),
                    ),
                  if (hiddenCount > 0)
                    _SideEntry(
                      icon: Icons.visibility_off_rounded,
                      label: strings.hiddenApps,
                      count: hiddenCount,
                      selected: selectedView == _hiddenViewKey,
                      onTap: () => onSelect(_hiddenViewKey),
                    ),
                ],
              ),
            ),
          ),
          const _SidebarDivider(),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _SideEntry(
              icon: Icons.create_new_folder_rounded,
              label: strings.newGroup,
              count: null,
              selected: false,
              onTap: () {},
              onTapPositioned: onNewGroup,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarGroupEntry {
  const _SidebarGroupEntry({
    required this.id,
    required this.isAuto,
    required this.icon,
    required this.label,
    required this.count,
  });
  final String id;
  final bool isAuto;
  final IconData icon;
  final String label;
  final int count;
}

class _SidebarDivider extends StatelessWidget {
  const _SidebarDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: context.shellColors.hairlineSoft,
    );
  }
}

class _SideEntry extends StatefulWidget {
  const _SideEntry({
    super.key,
    required this.icon,
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onTapPositioned,
    this.onSecondaryTap,
    this.onEditTap,
    this.dragHandle,
    this.reorderIndex,
  });

  final IconData icon;
  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onTapPositioned;
  final ValueChanged<Offset>? onSecondaryTap;
  final ValueChanged<Offset>? onEditTap;
  final Widget? dragHandle;
  final int? reorderIndex;

  @override
  State<_SideEntry> createState() => _SideEntryState();
}

class _SideEntryState extends State<_SideEntry> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scope = _LauncherScope.of(context);
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final highlighted = widget.selected || _hovered;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: MouseRegion(
        cursor: scope.launcher.linkCursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.onTapPositioned == null
              ? null
              : (event) => widget.onTapPositioned!(event.globalPosition),
          onTap: widget.onTapPositioned == null ? widget.onTap : null,
          onSecondaryTapUp: widget.onSecondaryTap == null
              ? null
              : (event) => widget.onSecondaryTap!(event.globalPosition),
          child: AnimatedContainer(
            duration: Motion.tile,
            curve: Motion.standard,
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: highlighted
                  ? theme.cardColor(accent.container)
                  : accent.container.withValues(alpha: 0),
              borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
            ),
            child: Row(
              children: [
                if (widget.dragHandle != null &&
                    widget.reorderIndex != null &&
                    (_hovered || widget.selected))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: ReorderableDragStartListener(
                      index: widget.reorderIndex!,
                      child: IconTheme(
                        data: IconThemeData(
                          size: 14,
                          color: widget.selected
                              ? accent.onContainer
                              : context.shellColors.textTertiary,
                        ),
                        child: widget.dragHandle!,
                      ),
                    ),
                  ),
                Icon(
                  widget.icon,
                  size: 17,
                  color: widget.selected
                      ? accent.onContainer
                      : context.shellColors.textSecondary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.shellTheme.text.base.copyWith(
                      fontSize: 13,
                      color: widget.selected
                          ? accent.onContainer
                          : context.shellColors.textPrimary,
                    ),
                  ),
                ),
                if (widget.onEditTap != null && (_hovered || widget.selected))
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Semantics(
                      button: true,
                      label: scope.strings.rename,
                      child: MouseRegion(
                        cursor: scope.launcher.linkCursor,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: (event) =>
                              widget.onEditTap!(event.globalPosition),
                          child: SizedBox.square(
                            dimension: 20,
                            child: Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: widget.selected
                                  ? accent.onContainer
                                  : context.shellColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.count != null)
                  Text(
                    '${widget.count}',
                    style: context.shellTheme.text.base.copyWith(
                      fontSize: 11,
                      color: context.shellColors.textTertiary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Search ------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onClear,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final VoidCallback onSubmit;

  static final List<TextInputFormatter> _inputFormatters =
      List<TextInputFormatter>.unmodifiable(<TextInputFormatter>[
        FilteringTextInputFormatter.deny(RegExp(r'[\u0000-\u001F\u007F]')),
      ]);

  @override
  Widget build(BuildContext context) {
    final hasQuery = controller.text.isNotEmpty;
    final scope = _LauncherScope.of(context);
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final l10n = scope.launcher.strings;
    return Semantics(
      textField: true,
      label: l10n.searchApplications,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.cardColor(context.shellColors.surfaceContainerHigh),
          borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
        ),
        child: Stack(
          children: <Widget>[
            SizedBox(
              height: 42,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 19,
                      color: context.shellColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          if (!hasQuery)
                            IgnorePointer(
                              child: Text(
                                l10n.searchApplications,
                                style: TextStyle(
                                  color: context.shellColors.textTertiary,
                                  fontSize: 14,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          EditableText(
                            controller: controller,
                            focusNode: focusNode,
                            mouseCursor: scope.launcher.textCursor,
                            autofocus: true,
                            maxLines: 1,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.search,
                            onEditingComplete: () {},
                            onSubmitted: (_) => onSubmit(),
                            style: context.shellTheme.text.base,
                            cursorColor: accent.primary,
                            backgroundCursorColor:
                                context.shellColors.textSecondary,
                            selectionColor: accent.selection,
                            // Raw shortcuts and text input are separate
                            // channels. Deny control characters in case an IME
                            // commits one.
                            inputFormatters: _inputFormatters,
                          ),
                        ],
                      ),
                    ),
                    if (hasQuery) ...[
                      const SizedBox(width: 8),
                      Semantics(
                        button: true,
                        label: l10n.clearSearch,
                        child: MouseRegion(
                          cursor: scope.launcher.linkCursor,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onClear,
                            child: SizedBox.square(
                              dimension: 26,
                              child: Icon(
                                Icons.close_rounded,
                                size: 17,
                                color: context.shellColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: ListenableBuilder(
                  listenable: focusNode,
                  builder: (context, child) => DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: context.shellTheme.borderRadius(
                        ShellRadii.chip,
                      ),
                      border: Border.all(
                        color: focusNode.hasFocus
                            ? accent.primary
                            : context.shellColors.hairline,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Content blocks -----------------------------------------------------

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.cardColor(context.shellColors.surfaceContainerLow),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.shellColors.hairlineSoft),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _UserPowerHeader extends StatefulWidget {
  const _UserPowerHeader({
    required this.displayName,
    required this.avatarPath,
    required this.busy,
    required this.onOpenSettings,
    required this.onPowerMenu,
  });

  final String displayName;
  final String avatarPath;
  final bool busy;
  final VoidCallback onOpenSettings;
  final ValueChanged<Offset> onPowerMenu;

  @override
  State<_UserPowerHeader> createState() => _UserPowerHeaderState();
}

class _UserPowerHeaderState extends State<_UserPowerHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final strings = _LauncherScope.of(context).strings;
    return SizedBox(
      height: 40,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: widget.avatarPath.isNotEmpty
                      ? Image.file(
                          File(widget.avatarPath),
                          width: 30,
                          height: 30,
                          fit: BoxFit.cover,
                          cacheWidth: 120,
                          errorBuilder: (context, error, stackTrace) =>
                              _avatarFallback(accent, context.shellColors),
                        )
                      : _avatarFallback(accent, context.shellColors),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.shellTheme.text.base.copyWith(
                      fontSize: 14,
                      color: context.shellColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderIconButton(
                  label: strings.settings,
                  icon: Icons.settings_rounded,
                  onTap: widget.onOpenSettings,
                ),
                const SizedBox(width: 4),
                Semantics(
                  button: true,
                  label: strings.powerMenu,
                  child: MouseRegion(
                    cursor: _LauncherScope.of(context).launcher.linkCursor,
                    onEnter: (_) => setState(() => _hovered = true),
                    onExit: (_) => setState(() => _hovered = false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) =>
                          widget.onPowerMenu(details.globalPosition),
                      child: AnimatedContainer(
                        duration: Motion.tile,
                        curve: Motion.standard,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _hovered
                              ? theme.cardColor(accent.container)
                              : accent.container.withValues(alpha: 0),
                          borderRadius: context.shellTheme.borderRadius(
                            ShellRadii.chip,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              widget.busy
                                  ? Icons.pending_rounded
                                  : Icons.power_settings_new,
                              size: 17,
                              color: context.shellColors.textSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              strings.powerMenu,
                              style: context.shellTheme.text.base.copyWith(
                                fontSize: 13,
                                color: context.shellColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 18,
                              color: context.shellColors.textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(ShellAccentPalette accent, ShellColorScheme colors) {
    return Container(
      width: 30,
      height: 30,
      color: accent.container,
      child: Icon(
        Icons.account_circle_rounded,
        size: 26,
        color: colors.textSecondary,
      ),
    );
  }
}

class _HeaderIconButton extends StatefulWidget {
  const _HeaderIconButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_HeaderIconButton> createState() => _HeaderIconButtonState();
}

class _HeaderIconButtonState extends State<_HeaderIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        cursor: _LauncherScope.of(context).launcher.linkCursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.tile,
            curve: Motion.standard,
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _hovered
                  ? theme.cardColor(accent.container)
                  : accent.container.withValues(alpha: 0),
              borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
            ),
            child: Icon(
              widget.icon,
              size: 17,
              color: context.shellColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// --- App tiles -----------------------------------------------------------

class _SuggestionsRow extends StatelessWidget {
  const _SuggestionsRow({
    required this.apps,
    required this.tileExtent,
    required this.onLaunch,
    required this.onContextMenu,
  });

  final List<LauncherApplication> apps;
  final double tileExtent;
  final ValueChanged<LauncherApplication> onLaunch;
  final void Function(String appId, Offset globalPosition) onContextMenu;

  @override
  Widget build(BuildContext context) {
    final l10n = _LauncherScope.of(context).launcher.strings;
    return Semantics(
      container: true,
      label: l10n.suggestionsTitle,
      child: SizedBox(
        height: tileExtent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < apps.length; index++) ...[
              if (index > 0)
                const SizedBox(
                  width: _GroupedApplicationLauncherState._tileSpacing,
                ),
              Expanded(
                child: _AppTile(
                  key: ValueKey<String>('suggested-${apps[index].id}'),
                  app: apps[index],
                  selected: false,
                  singleLineName: true,
                  compact: true,
                  onTap: () => onLaunch(apps[index]),
                  onSecondaryTap: (position) =>
                      onContextMenu(apps[index].id, position),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppGrid extends StatelessWidget {
  const _AppGrid({
    required this.controller,
    required this.apps,
    required this.loading,
    required this.loadingLabel,
    required this.emptyLabel,
    required this.showSearchEmptyIcon,
    required this.selectedIndex,
    required this.onTap,
    required this.onSecondaryTap,
    this.onBackgroundContextMenu,
    this.draggable = false,
    this.onReorder,
  });

  final ScrollController controller;
  final List<LauncherApplication> apps;
  final bool loading;
  final String loadingLabel;
  final String emptyLabel;
  final bool showSearchEmptyIcon;
  final int selectedIndex;
  final ValueChanged<LauncherApplication> onTap;
  final void Function(String appId, Offset globalPosition) onSecondaryTap;

  /// Right-click on the grid's empty area (below/around the tiles). Tiles
  /// keep their own handler; the inner gesture wins for presses on a tile.
  final ValueChanged<Offset>? onBackgroundContextMenu;
  final bool draggable;
  final void Function(String draggedAppId, String targetAppId, bool after)?
  onReorder;

  @override
  Widget build(BuildContext context) {
    final Widget content;
    if (loading) {
      content = Center(
        child: Text(
          loadingLabel,
          style: context.shellTheme.text.base.copyWith(
            color: context.shellColors.textSecondary,
          ),
        ),
      );
    } else if (apps.isEmpty) {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              showSearchEmptyIcon
                  ? Icons.search_off_rounded
                  : Icons.folder_open_rounded,
              size: 34,
              color: context.shellColors.textTertiary,
            ),
            const SizedBox(height: 10),
            Text(
              emptyLabel,
              style: context.shellTheme.text.cardTitle.copyWith(
                color: context.shellColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    } else {
      content = GridView.builder(
        controller: controller,
        padding: const EdgeInsets.all(2),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: _GroupedApplicationLauncherState._tileExtent,
          mainAxisExtent: _GroupedApplicationLauncherState._tileExtent,
          crossAxisSpacing: _GroupedApplicationLauncherState._tileSpacing,
          mainAxisSpacing: _GroupedApplicationLauncherState._tileSpacing,
        ),
        itemCount: apps.length,
        itemBuilder: (context, index) => _tile(context, index),
      );
    }
    final onBackground = onBackgroundContextMenu;
    if (onBackground == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapUp: (event) => onBackground(event.globalPosition),
      child: content,
    );
  }

  Widget _tile(BuildContext context, int index) {
    final app = apps[index];
    final tile = _AppTile(
      key: ValueKey<String>('app-${app.id}'),
      app: app,
      selected: index == selectedIndex,
      compact: false,
      onTap: () => onTap(app),
      onSecondaryTap: (position) => onSecondaryTap(app.id, position),
    );
    if (!draggable || onReorder == null) return tile;
    return _DropSlotTile(
      appId: app.id,
      extent: _GroupedApplicationLauncherState._tileExtent,
      onReorder: onReorder!,
      tile: tile,
    );
  }
}

/// Payload carried by a tile drag so drop handlers know the source app.
@immutable
class _AppDrag {
  const _AppDrag(this.appId);

  final String appId;
}

enum _DropSide { none, before, after }

/// A grid cell that tracks the live drag pointer and paints a vertical slot
/// line on its leading or trailing edge, so the drop lands before or after
/// this tile (a line on the trailing edge of the last tile reaches the end).
class _DropSlotTile extends StatefulWidget {
  const _DropSlotTile({
    required this.appId,
    required this.extent,
    required this.onReorder,
    required this.tile,
  });

  final String appId;
  final double extent;
  final void Function(String draggedAppId, String targetAppId, bool after)
  onReorder;
  final Widget tile;

  @override
  State<_DropSlotTile> createState() => _DropSlotTileState();
}

class _DropSlotTileState extends State<_DropSlotTile> {
  _DropSide _side = _DropSide.none;
  RenderBox? _box;

  _DropSide _sideFor(Offset global) {
    final box = _box;
    if (box == null) return _DropSide.none;
    final local = box.globalToLocal(global);
    return local.dx > box.size.width / 2
        ? _DropSide.after
        : _DropSide.before;
  }

  @override
  Widget build(BuildContext context) {
    final accent = ShellTheme.of(context).accentPalette;
    return DragTarget<_AppDrag>(
      onMove: (details) {
        final side = details.data.appId == widget.appId
            ? _DropSide.none
            : _sideFor(details.offset);
        if (side != _side) setState(() => _side = side);
      },
      onLeave: (_) {
        if (_side != _DropSide.none) setState(() => _side = _DropSide.none);
      },
      onAcceptWithDetails: (details) {
        final drag = details.data;
        final after = _side == _DropSide.after;
        if (_side != _DropSide.none) setState(() => _side = _DropSide.none);
        if (drag.appId != widget.appId) {
          widget.onReorder(drag.appId, widget.appId, after);
        }
      },
      builder: (context, candidates, _) {
        final box = context.findRenderObject();
        if (box is RenderBox) _box = box;
        final source = Draggable<_AppDrag>(
          data: _AppDrag(widget.appId),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: widget.extent,
              height: widget.extent,
              child: Opacity(opacity: 0.9, child: widget.tile),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: widget.tile),
          child: widget.tile,
        );
        if (_side == _DropSide.none) return source;
        final leading = _side == _DropSide.before;
        return Stack(
          fit: StackFit.expand,
          children: [
            source,
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: leading ? 0 : 6,
                    right: leading ? 6 : 0,
                  ),
                  child: Align(
                    alignment: leading
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: accent.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AppTile extends StatefulWidget {
  const _AppTile({
    super.key,
    required this.app,
    required this.selected,
    required this.compact,
    this.singleLineName = false,
    required this.onTap,
    required this.onSecondaryTap,
  });

  final LauncherApplication app;
  final bool selected;
  final bool compact;
  final bool singleLineName;
  final VoidCallback onTap;
  final ValueChanged<Offset> onSecondaryTap;

  @override
  State<_AppTile> createState() => _AppTileState();
}

class _AppTileState extends State<_AppTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scope = _LauncherScope.of(context);
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final l10n = scope.launcher.strings;
    final highlighted = widget.selected || _hovered;
    final iconExtent = widget.compact ? 46.0 : 54.0;
    final name = Text(
      widget.app.name,
      maxLines: widget.singleLineName ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: context.shellTheme.text.cardTitle.copyWith(
        color: highlighted
            ? accent.onContainer
            : context.shellColors.textPrimary,
        fontSize: 11,
      ),
    );
    return Semantics(
      button: true,
      selected: widget.selected,
      label: l10n.launchApplication(widget.app.name),
      child: MouseRegion(
        cursor: scope.launcher.linkCursor,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapUp: (event) =>
              widget.onSecondaryTap(event.globalPosition),
          child: AnimatedContainer(
            duration: Motion.tile,
            curve: Motion.standard,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              // Keep the idle endpoint in the accent hue so the implicit
              // alpha transition never flashes through neutral grey.
              color: highlighted
                  ? theme.cardColor(accent.container)
                  : accent.container.withValues(alpha: 0),
              borderRadius: context.shellTheme.borderRadius(18),
              border: widget.selected
                  ? Border.all(color: accent.primary)
                  : null,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: iconExtent,
                  height: iconExtent,
                  child: scope.launcher.buildIcon(context, widget.app.id),
                ),
                const SizedBox(height: 8),
                if (widget.singleLineName) name else Expanded(child: name),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Context menu --------------------------------------------------------

enum _MenuItemKind { header, label, action, divider, input }

@immutable
class _MenuItemData {
  const _MenuItemData._({
    required this.kind,
    this.label = '',
    this.icon,
    this.checked = false,
    this.destructive = false,
    this.disabled = false,
    this.onTap,
    this.controller,
    this.focusNode,
    this.hint = '',
    this.onSubmit,
    this.dangerColor,
  });

  factory _MenuItemData.header(String label) =>
      _MenuItemData._(kind: _MenuItemKind.header, label: label);

  factory _MenuItemData.label(String label) =>
      _MenuItemData._(kind: _MenuItemKind.label, label: label);

  factory _MenuItemData.action({
    required String label,
    IconData? icon,
    bool checked = false,
    bool destructive = false,
    bool disabled = false,
    VoidCallback? onTap,
    Color? dangerColor,
  }) => _MenuItemData._(
    kind: _MenuItemKind.action,
    label: label,
    icon: icon,
    checked: checked,
    destructive: destructive,
    disabled: disabled,
    onTap: onTap,
    dangerColor: dangerColor,
  );

  factory _MenuItemData.divider() =>
      const _MenuItemData._(kind: _MenuItemKind.divider);

  factory _MenuItemData.input({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required VoidCallback onSubmit,
  }) => _MenuItemData._(
    kind: _MenuItemKind.input,
    controller: controller,
    focusNode: focusNode,
    hint: hint,
    onSubmit: onSubmit,
  );

  final _MenuItemKind kind;
  final String label;
  final IconData? icon;
  final bool checked;
  final bool destructive;
  final bool disabled;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final VoidCallback? onSubmit;
  final Color? dangerColor;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.width, required this.children, this.opacity});

  final double width;
  final List<_MenuItemData> children;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final baseColor = theme.cardColor(context.shellColors.surfaceContainerHigh);
    final color = opacity != null
        ? baseColor.withValues(alpha: opacity)
        : baseColor;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: MouseRegion(
        cursor: _LauncherScope.of(context).launcher.linkCursor,
        child: SizedBox(
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.shellColors.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [for (final item in children) _MenuRow(item: item)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item});

  final _MenuItemData item;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    switch (item.kind) {
      case _MenuItemKind.header:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
          child: Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.shellTheme.text.cardTitle.copyWith(
              fontSize: 13,
              color: context.shellColors.textPrimary,
            ),
          ),
        );
      case _MenuItemKind.label:
        return Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
          child: Text(
            item.label,
            style: context.shellTheme.text.base.copyWith(
              fontSize: 11,
              color: context.shellColors.textTertiary,
            ),
          ),
        );
      case _MenuItemKind.divider:
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 5),
          color: context.shellColors.hairlineSoft,
        );
      case _MenuItemKind.input:
        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.cardColor(accent.container),
              borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
              border: Border.all(color: accent.primary),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 15,
                    color: context.shellColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        IgnorePointer(
                          child: Text(
                            item.hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.shellColors.textTertiary,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                        EditableText(
                          controller: item.controller!,
                          focusNode: item.focusNode!,
                          mouseCursor: _LauncherScope.of(context)
                              .launcher
                              .textCursor,
                          maxLines: 1,
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => item.onSubmit!(),
                          style: context.shellTheme.text.base.copyWith(
                            fontSize: 13,
                            color: context.shellColors.textPrimary,
                          ),
                          cursorColor: accent.primary,
                          backgroundCursorColor:
                              context.shellColors.textSecondary,
                          selectionColor: accent.selection,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case _MenuItemKind.action:
        return _MenuActionRow(item: item);
    }
  }
}

class _MenuActionRow extends StatefulWidget {
  const _MenuActionRow({required this.item});

  final _MenuItemData item;

  @override
  State<_MenuActionRow> createState() => _MenuActionRowState();
}

class _MenuActionRowState extends State<_MenuActionRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShellTheme.of(context);
    final accent = theme.accentPalette;
    final item = widget.item;
    final danger = item.destructive;
    final disabled = item.disabled;
    final dangerColor = item.dangerColor ?? context.shellColors.performanceBad;
    final iconColor = disabled
        ? context.shellColors.textTertiary
        : danger
        ? dangerColor
        : context.shellColors.textSecondary;
    final labelColor = disabled
        ? context.shellColors.textTertiary
        : danger
        ? dangerColor
        : context.shellColors.textPrimary;
    return Semantics(
      button: true,
      enabled: !disabled,
      label: item.label,
      child: MouseRegion(
        cursor: disabled
            ? MouseCursor.defer
            : _LauncherScope.of(context).launcher.linkCursor,
        onEnter: disabled ? null : (_) => setState(() => _hovered = true),
        onExit: disabled ? null : (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: disabled ? null : item.onTap,
          child: AnimatedContainer(
            duration: Motion.tile,
            curve: Motion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _hovered && !disabled
                  ? danger
                      ? dangerColor.withValues(alpha: 0.12)
                      : theme.cardColor(accent.container)
                  : danger && !disabled
                      ? dangerColor.withValues(alpha: 0.06)
                      : accent.container.withValues(alpha: 0),
              borderRadius: context.shellTheme.borderRadius(ShellRadii.chip),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: item.checked
                      ? Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: accent.primary,
                        )
                      : item.icon == null
                      ? null
                      : Icon(
                          item.icon,
                          size: 15,
                          color: iconColor,
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.shellTheme.text.base.copyWith(
                      fontSize: 13,
                      color: labelColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

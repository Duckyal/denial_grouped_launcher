@Plugin()
library;

import 'dart:async';

import 'package:denial_sdk/composition.dart';
import 'package:denial_flutter_sdk/actions.dart';
import 'package:denial_flutter_sdk/applications.dart';
import 'package:denial_flutter_sdk/launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import 'src/grouped_launcher.dart';

@Provides(ShellLauncher)
final class GroupedLauncherPlugin implements ShellLauncher {
  const GroupedLauncherPlugin();

  @override
  Widget build(BuildContext context, {required LauncherContext launcher}) =>
      _DesktopCatalogScope(launcher: launcher);
}

/// Supplies each launcher entry with its desktop entry so the launcher can
/// derive default groups from `Categories=` and relaunch with custom commands.
/// The catalog ids come from the same slots the host wrapper uses, keeping the
/// id bridge exact.
final class _DesktopCatalogScope extends ConsumerWidget {
  const _DesktopCatalogScope({required this.launcher});

  final LauncherContext launcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = ref.watch(
      homeGridControllerProvider.select(
        (AsyncValue<HomeGridState> state) => state.asData?.value.slots,
      ),
    );
    final desktopApps = <String, DesktopApp>{};
    for (final item
        in slots?.whereType<HomeGridItem>() ?? const <HomeGridItem>[]) {
      final app = item.app;
      if (app != null) {
        desktopApps[desktopApplicationRecentId(app.id)] = app;
      }
    }
    return GroupedApplicationLauncher(
      launcher: launcher,
      desktopAppsById: desktopApps,
      onLaunchDesktopApp: (target) {
        // Mirror the host's launch flow for commands the user rewrote:
        // record the recent entry, then launch through the native bridge.
        ref
            .read(applicationRecentsProvider.notifier)
            .record(desktopApplicationRecentId(target.id));
        unawaited(ref.read(appLauncherProvider).launch(target));
      },
    );
  }
}

/// The launcher supplies the action; Rust only routes its stable identity.
@Provides(ShellAction)
final class OpenGroupedApplicationsAction implements ShellAction {
  const OpenGroupedApplicationsAction();
  @override
  String get id => 'denial_grouped_launcher.openApplications';
  @override
  String get provider => 'Grouped Launcher';
  @override
  String label(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'zh'
      ? '打开应用列表（分组）'
      : 'Open applications (grouped)';
  @override
  String description(BuildContext context) => '';
  @override
  void invoke(ShellActionContext context) => context.services.toggleLauncher();
}

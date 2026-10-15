part of 'grouped_launcher.dart';

/// Default groups derived from the freedesktop `Categories=` field of each
/// desktop entry, like the "All Applications" menus in KDE and GNOME.
/// Manual assignments in [GroupedLauncherData.assignments] override these.
const _autoGroupPrefix = 'auto:';

@immutable
class _CategoryGroup {
  const _CategoryGroup({
    required this.key,
    required this.zh,
    required this.en,
    required this.icon,
    required this.categories,
  });

  final String key;
  final String zh;
  final String en;
  final IconData icon;

  /// Lowercased desktop-entry category tokens accepted by this group.
  final Set<String> categories;

  String get id => '$_autoGroupPrefix$key';
}

/// Ordered by precedence: an application joins the first group matching any
/// of its categories, so more specific groups must come before broader ones.
const _categoryGroups = <_CategoryGroup>[
  _CategoryGroup(
    key: 'development',
    zh: '开发',
    en: 'Development',
    icon: Icons.code_rounded,
    categories: {
      'development',
      'ide',
      'versioncontrol',
      'debuggers',
      'buildsystem',
      'projectmanagement',
      'texteditor',
    },
  ),
  _CategoryGroup(
    key: 'internet',
    zh: '互联网',
    en: 'Internet',
    icon: Icons.language_rounded,
    categories: {
      'network',
      'webbrowser',
      'email',
      'chat',
      'instantmessaging',
      'filetransfer',
      'feed',
      'news',
      'telephony',
    },
  ),
  _CategoryGroup(
    key: 'office',
    zh: '办公',
    en: 'Office',
    icon: Icons.assignment_rounded,
    categories: {
      'office',
      'wordprocessor',
      'spreadsheet',
      'presentation',
      'finance',
      'calendar',
      'dti',
    },
  ),
  _CategoryGroup(
    key: 'graphics',
    zh: '图形',
    en: 'Graphics',
    icon: Icons.palette_rounded,
    categories: {
      'graphics',
      'photography',
      '3dgraphics',
      'vectorgraphics',
      'rastergraphics',
      'viewers',
      'publishing',
      'scancamera',
    },
  ),
  _CategoryGroup(
    key: 'audiovideo',
    zh: '影音',
    en: 'Audio & Video',
    icon: Icons.play_circle_outline_rounded,
    categories: {
      'audiovideo',
      'audio',
      'video',
      'player',
      'recording',
      'mixing',
      'sequencer',
      'synth',
      'tvtuner',
      'amfm',
      'musicplayer' /* deprecated but common */,
      'audiocd' /* deprecated but common */,
    },
  ),
  _CategoryGroup(
    key: 'games',
    zh: '游戏',
    en: 'Games',
    icon: Icons.sports_esports_rounded,
    categories: {
      'game',
      'games',
      'actiongame',
      'adventuregame',
      'arcadegame',
      'boardgame',
      'cardgame',
      'puzzlegame',
      'strategygame',
      'simulation',
    },
  ),
  _CategoryGroup(
    key: 'education',
    zh: '教育',
    en: 'Education',
    icon: Icons.school_rounded,
    categories: {
      'education',
      'art',
      'grammar',
      'history',
      'languages',
      'math',
      'numericy',
      'science',
      'education-other',
    },
  ),
  _CategoryGroup(
    key: 'system',
    zh: '系统工具',
    en: 'System Tools',
    icon: Icons.settings_applications_rounded,
    categories: {
      'system',
      'utility',
      'settings',
      'systemsettings',
      'monitor',
      'filemanager',
      'archiver',
      'terminaltools',
      'coresetting',
      'desktopenvironment',
      'x-dde-daemon' /* DDE daemon entries */,
    },
  ),
];

/// The category group an application belongs to by default, if any.
String? _autoGroupIdFor(List<String>? categories) {
  if (categories == null || categories.isEmpty) {
    return null;
  }
  final normalized = categories
      .map((category) => category.trim().toLowerCase())
      .where((category) => category.isNotEmpty)
      .toSet();
  for (final group in _categoryGroups) {
    if (normalized.intersection(group.categories).isNotEmpty) {
      return group.id;
    }
  }
  return null;
}

_CategoryGroup? _categoryGroupById(String id) {
  if (!id.startsWith(_autoGroupPrefix)) {
    return null;
  }
  final key = id.substring(_autoGroupPrefix.length);
  for (final group in _categoryGroups) {
    if (group.key == key) return group;
  }
  return null;
}

bool _isKnownAutoGroup(String id) => _categoryGroupById(id) != null;

/// A category group currently worth showing: localized label plus icon.
@immutable
class _AutoGroupView {
  const _AutoGroupView({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id;
  final String label;
  final IconData icon;
}

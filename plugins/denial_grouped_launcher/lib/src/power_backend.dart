part of 'grouped_launcher.dart';

/// logind access for 关机/重启/休眠/挂起, read one verb at a time.
///
/// The SDK's shared session-power backend asks every `Can*` in a single
/// `Future.wait`, so a host that replies to one verb with a D-Bus error (this
/// machine: `CanHibernate` -> FileNotFound, hibernate not configured) fails the
/// whole read and marks all four verbs unavailable. Per-verb reads keep the
/// verbs the system does support callable.
class _LauncherPowerBackend {
  static const String _service = 'org.freedesktop.login1';
  static const String _managerPath = '/org/freedesktop/login1';
  static const String _managerInterface = 'org.freedesktop.login1.Manager';
  static const Duration _readTimeout = Duration(seconds: 4);
  static const Duration _actionTimeout = Duration(seconds: 30);

  final DBusClient _client = DBusClient.system();
  late final DBusRemoteObject _manager = DBusRemoteObject(
    _client,
    name: _service,
    path: DBusObjectPath(_managerPath),
  );

  /// Null means the verb has not been read yet; callers treat that as
  /// permitted and let logind refuse the request itself.
  final Map<LogindAction, LogindCapability> _capabilities = {};

  LogindCapability? capabilityFor(LogindAction action) => _capabilities[action];

  Future<void> refresh() async {
    for (final action in LogindAction.values) {
      _capabilities[action] = await _readCapability(action);
    }
  }

  Future<LogindCapability> _readCapability(LogindAction action) async {
    try {
      final reply = await _manager
          .callMethod(
            _managerInterface,
            'Can${action.method}',
            const <DBusValue>[],
            replySignature: DBusSignature('s'),
          )
          .timeout(_readTimeout);
      final values = reply.returnValues;
      if (values.length != 1) {
        return LogindCapability.unavailable;
      }
      return switch (values.single.asString()) {
        'yes' => LogindCapability.available,
        'challenge' => LogindCapability.authenticationRequired,
        'no' => LogindCapability.denied,
        'na' => LogindCapability.unsupported,
        _ => LogindCapability.unavailable,
      };
    } on DBusMethodResponseException {
      return LogindCapability.unsupported;
    } on Object {
      return LogindCapability.unavailable;
    }
  }

  Future<void> perform(LogindAction action) async {
    await _manager
        .callMethod(_managerInterface, action.method, const <DBusValue>[
          DBusBoolean(true),
        ], replySignature: DBusSignature(''))
        .timeout(_actionTimeout);
  }

  Future<void> dispose() async {
    try {
      await _client.close();
    } on Object {
      // The launcher is going away; a closed socket is enough.
    }
  }
}

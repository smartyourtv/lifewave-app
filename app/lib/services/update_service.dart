import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// M5 updater (standing rule + PRE-BUILD-AUDIT §4 contract).
///
/// Checks `version.json` in the public GitHub repo
/// `smartyourtv/lifewave-app`, compares the remote Android
/// `versionCode` (integer compare — never string compare) to this
/// app's own version code, and if newer shows ONE subtle notification
/// for that version (a dismissible banner on Home + a row in
/// Settings). Dismissing records that versionCode as seen and it never
/// nags again for that version. The Update button opens the stable
/// GitHub release asset in the browser — the user taps to install.
/// Never forced, never auto-downloads, never auto-installs.
///
/// The app's own version code comes from [AppInfo.buildNumber], the
/// generated constant kept in sync with `pubspec.yaml`
/// (`version: 1.0.0+1`). package_info_plus was NOT added: AppInfo is
/// already the app's single version source (see theme.dart) and adding
/// a platform plugin for one integer on the pinned Flutter 3.24.5
/// toolchain adds risk with no benefit.
///
/// All network access goes through an injectable [VersionFetcher] —
/// unit tests pass fakes and never touch the real network.
class RemoteAppVersion {
  final int versionCode;
  final String versionName;
  final String releaseTag;
  final String asset;
  const RemoteAppVersion({
    required this.versionCode,
    required this.versionName,
    this.releaseTag = '',
    this.asset = UpdateService.androidAssetName,
  });

  /// Parses the PRE-BUILD-AUDIT §4 shape:
  /// `{ "android": { "versionCode": 1, "versionName": "1.0.0",
  ///    "releaseTag": "v1.0.0", "asset": "Lifewave-latest.apk" }, ... }`
  /// Throws [FormatException] on a malformed/missing payload.
  factory RemoteAppVersion.fromVersionJson(Map<String, dynamic> json) {
    final android = json['android'];
    if (android is! Map) {
      throw const FormatException('version.json has no "android" object');
    }
    final code = android['versionCode'];
    if (code is! int) {
      throw const FormatException('version.json android.versionCode '
          'is missing or not an integer');
    }
    final name = android['versionName'];
    return RemoteAppVersion(
      versionCode: code,
      versionName: name is String ? name : '',
      releaseTag: android['releaseTag'] is String
          ? android['releaseTag'] as String
          : '',
      asset: android['asset'] is String
          ? android['asset'] as String
          : UpdateService.androidAssetName,
    );
  }
}

enum UpdateCheckStatus {
  notChecked,
  upToDate,
  updateAvailable,
  couldNotCheck,
  throttled,
}

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final RemoteAppVersion? remote;
  final DateTime? checkedAt;
  const UpdateCheckResult(this.status, {this.remote, this.checkedAt});

  bool get isUpdateAvailable => status == UpdateCheckStatus.updateAvailable;

  /// Honest plain-language label for Diagnostics / Settings.
  String get diagnosticsLabel {
    switch (status) {
      case UpdateCheckStatus.notChecked:
        return 'Not checked yet';
      case UpdateCheckStatus.upToDate:
        return 'Up to date';
      case UpdateCheckStatus.updateAvailable:
        return 'Update available: version ${remote?.versionName ?? ''}';
      case UpdateCheckStatus.couldNotCheck:
        return "Couldn't check for updates (offline or the check failed)";
      case UpdateCheckStatus.throttled:
        return 'Checked recently — will check again later';
    }
  }
}

/// Fetches the raw version.json body. Throws on any failure.
typedef VersionFetcher = Future<String> Function(Uri url);

/// Persistence seam for the updater's small state (last check time,
/// dismissed version, last result). Real app: SharedPreferences.
/// Tests: [MemoryUpdatePrefs].
abstract class UpdatePrefs {
  int? get lastCheckMillis;
  set lastCheckMillis(int? v);
  int? get dismissedVersionCode;
  set dismissedVersionCode(int? v);
  String? get lastStatusName;
  set lastStatusName(String? v);
  int? get lastRemoteVersionCode;
  set lastRemoteVersionCode(int? v);
  String? get lastRemoteVersionName;
  set lastRemoteVersionName(String? v);
  Future<void> save();
}

class MemoryUpdatePrefs implements UpdatePrefs {
  @override
  int? lastCheckMillis;
  @override
  int? dismissedVersionCode;
  @override
  String? lastStatusName;
  @override
  int? lastRemoteVersionCode;
  @override
  String? lastRemoteVersionName;
  @override
  Future<void> save() async {}
}

class SharedPreferencesUpdatePrefs implements UpdatePrefs {
  static const _kLastCheck = 'update_last_check_millis';
  static const _kDismissed = 'update_dismissed_version_code';
  static const _kStatus = 'update_last_status';
  static const _kRemoteCode = 'update_last_remote_code';
  static const _kRemoteName = 'update_last_remote_name';

  final SharedPreferences _prefs;
  SharedPreferencesUpdatePrefs(this._prefs);

  static Future<SharedPreferencesUpdatePrefs> load() async =>
      SharedPreferencesUpdatePrefs(await SharedPreferences.getInstance());

  @override
  int? get lastCheckMillis => _prefs.getInt(_kLastCheck);
  @override
  set lastCheckMillis(int? v) =>
      v == null ? _prefs.remove(_kLastCheck) : _prefs.setInt(_kLastCheck, v);
  @override
  int? get dismissedVersionCode => _prefs.getInt(_kDismissed);
  @override
  set dismissedVersionCode(int? v) =>
      v == null ? _prefs.remove(_kDismissed) : _prefs.setInt(_kDismissed, v);
  @override
  String? get lastStatusName => _prefs.getString(_kStatus);
  @override
  set lastStatusName(String? v) =>
      v == null ? _prefs.remove(_kStatus) : _prefs.setString(_kStatus, v);
  @override
  int? get lastRemoteVersionCode => _prefs.getInt(_kRemoteCode);
  @override
  set lastRemoteVersionCode(int? v) => v == null
      ? _prefs.remove(_kRemoteCode)
      : _prefs.setInt(_kRemoteCode, v);
  @override
  String? get lastRemoteVersionName => _prefs.getString(_kRemoteName);
  @override
  set lastRemoteVersionName(String? v) => v == null
      ? _prefs.remove(_kRemoteName)
      : _prefs.setString(_kRemoteName, v);
  @override
  Future<void> save() async {}
}

class UpdateService {
  static const String repoSlug = 'smartyourtv/lifewave-app';
  static const String androidAssetName = 'Lifewave-latest.apk';
  static const String windowsAssetName = 'Lifewave-Setup.exe';
  static final Uri versionJsonUri = Uri.parse(
      'https://raw.githubusercontent.com/$repoSlug/main/version.json');
  static final Uri downloadUri = Uri.parse(
      'https://github.com/$repoSlug/releases/latest/download/$androidAssetName');
  static const Duration checkInterval = Duration(hours: 24);

  final VersionFetcher fetcher;
  final UpdatePrefs prefs;
  final int currentVersionCode;
  final DateTime Function() _now;

  UpdateCheckResult _lastResult =
      const UpdateCheckResult(UpdateCheckStatus.notChecked);
  UpdateCheckResult get lastResult => _lastResult;

  UpdateService({
    required this.fetcher,
    required this.prefs,
    this.currentVersionCode = AppInfo.buildNumber,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    // Restore the last known result for honest Diagnostics display
    // before the first check of this session completes.
    final name = prefs.lastStatusName;
    if (name != null) {
      UpdateCheckStatus? status;
      for (final s in UpdateCheckStatus.values) {
        if (s.name == name) status = s;
      }
      if (status != null) {
        final code = prefs.lastRemoteVersionCode;
        _lastResult = UpdateCheckResult(
          status,
          remote: code == null
              ? null
              : RemoteAppVersion(
                  versionCode: code,
                  versionName: prefs.lastRemoteVersionName ?? '',
                ),
          checkedAt: prefs.lastCheckMillis == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(prefs.lastCheckMillis!),
        );
      }
    }
  }

  /// Production fetcher: a real HTTP GET with a timeout.
  static VersionFetcher httpFetcher({http.Client? client}) {
    return (Uri url) async {
      final c = client ?? http.Client();
      try {
        final resp = await c
            .get(url)
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode != 200) {
          throw Exception('version check HTTP ${resp.statusCode}');
        }
        return resp.body;
      } finally {
        if (client == null) c.close();
      }
    };
  }

  /// True when a check is due (never checked, or interval elapsed).
  bool get isCheckDue {
    final last = prefs.lastCheckMillis;
    if (last == null) return true;
    return _now().millisecondsSinceEpoch - last >=
        checkInterval.inMilliseconds;
  }

  /// Runs a check unless throttled (pass [force] to bypass the
  /// throttle, e.g. a manual "Check now" tap). Failures are silent in
  /// the UI and honest in Diagnostics: status becomes couldNotCheck.
  Future<UpdateCheckResult> check({bool force = false}) async {
    if (!force && !isCheckDue) {
      // Keep the restored/last result; just report throttling if we
      // have never had a real result this session.
      if (_lastResult.status == UpdateCheckStatus.notChecked) {
        _lastResult = UpdateCheckResult(UpdateCheckStatus.throttled,
            checkedAt: _lastResult.checkedAt);
      }
      return _lastResult;
    }
    try {
      final body = await fetcher(versionJsonUri);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('version.json is not an object');
      }
      final remote = RemoteAppVersion.fromVersionJson(decoded);
      final status = remote.versionCode > currentVersionCode
          ? UpdateCheckStatus.updateAvailable
          : UpdateCheckStatus.upToDate;
      _lastResult = UpdateCheckResult(status, remote: remote, checkedAt: _now());
    } catch (_) {
      _lastResult = UpdateCheckResult(UpdateCheckStatus.couldNotCheck,
          checkedAt: _now());
    }
    prefs.lastCheckMillis = _now().millisecondsSinceEpoch;
    prefs.lastStatusName = _lastResult.status.name;
    prefs.lastRemoteVersionCode = _lastResult.remote?.versionCode;
    prefs.lastRemoteVersionName = _lastResult.remote?.versionName;
    await prefs.save();
    return _lastResult;
  }

  /// Whether the one subtle notification surface should show: an
  /// update is available AND this versionCode was not dismissed.
  bool get shouldNotify {
    final r = _lastResult;
    if (r.status != UpdateCheckStatus.updateAvailable || r.remote == null) {
      return false;
    }
    final dismissed = prefs.dismissedVersionCode;
    return dismissed == null || dismissed < r.remote!.versionCode;
  }

  /// Records the available version as seen — it never nags again for
  /// that version (the next version may notify once).
  Future<void> dismissCurrent() async {
    final code = _lastResult.remote?.versionCode;
    if (code == null) return;
    prefs.dismissedVersionCode = code;
    await prefs.save();
  }
}

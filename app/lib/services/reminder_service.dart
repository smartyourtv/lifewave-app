import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'social_store.dart';

/// OS reminders via flutter_local_notifications.
///
/// Audit rules obeyed (PRE-BUILD-AUDIT §§1/3):
///  - INEXACT alarms only (`AndroidScheduleMode.inexactAllowWhileIdle`)
///    — post reminders are nudges, so the app never requests
///    SCHEDULE_EXACT_ALARM. Copy says "around" the chosen time.
///  - POST_NOTIFICATIONS is requested at first scheduling, in context.
///  - Failure degrades honestly: [available] goes false, the queue +
///    Today card stay the source of truth, nothing crashes.
class LocalNotificationsReminderScheduler implements ReminderScheduler {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _available = false;
  String _stateLabel = 'Not set up yet';

  @override
  bool get available => _available;

  @override
  String get stateLabel => _stateLabel;

  @override
  Future<void> initialize({void Function(String postId)? onTapPost}) async {
    if (_initialized) return;
    _initialized = true;
    try {
      tzdata.initializeTimeZones();
      try {
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name));
      } catch (e) {
        // Without the device zone, tz.local stays UTC and times would
        // drift — say so via stateLabel rather than failing silently.
        debugPrint('Reminder timezone lookup failed: $e');
        _stateLabel = 'Reminders may show at the wrong time on this '
            'device (time zone could not be read). The in-app queue '
            'times are correct.';
      }
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      final ok = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty && onTapPost != null) {
            onTapPost(payload);
          }
        },
      );
      _available = ok ?? false;
      if (_available && _stateLabel == 'Not set up yet') {
        _stateLabel = 'On — reminders use approximate (inexact) times';
      }
      if (!_available) {
        _stateLabel = 'Not available on this device — the app queue and '
            'Today card still track everything';
      }
    } catch (e) {
      // MissingPluginException on platforms without an implementation
      // (e.g. Windows in this plugin version) lands here.
      debugPrint('Reminder init failed: $e');
      _available = false;
      _stateLabel = 'Not available on this device — the app queue and '
          'Today card still track everything';
    }
  }

  /// Requests the Android 13+ notification permission, in context, the
  /// first time a reminder is actually set.
  Future<bool> _ensurePermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return _available;
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Reminder permission request failed: $e');
      return false;
    }
  }

  @override
  Future<bool> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payloadPostId,
  }) async {
    if (!_initialized) await initialize();
    if (!_available) return false;
    if (!await _ensurePermission()) {
      _stateLabel = 'Notification permission not given — reminders show '
          'in the app instead';
      return false;
    }
    try {
      final scheduled = tz.TZDateTime.from(when, tz.local);
      if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) {
        // A past inexact reminder would fire immediately or never,
        // depending on the OS — the due-post list in the app covers it.
        return false;
      }
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'post_reminders',
            'Post reminders',
            channelDescription:
                'Reminds you when a queued curiosity post is due to share',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        // INEXACT by design (audit §3) — no exact-alarm permission.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payloadPostId,
      );
      return true;
    } catch (e) {
      debugPrint('Reminder schedule failed: $e');
      return false;
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (_) {
      // Cancelling a reminder that never existed is fine.
    }
  }
}

/// Test/preview scheduler: records calls, always "succeeds".
class FakeReminderScheduler implements ReminderScheduler {
  final Map<int, DateTime> scheduled = {};
  final List<int> cancelled = [];
  bool succeed = true;

  @override
  bool get available => true;

  @override
  String get stateLabel => 'Fake scheduler (tests)';

  @override
  Future<void> initialize({void Function(String postId)? onTapPost}) async {}

  @override
  Future<bool> schedule({
    required int id,
    required DateTime when,
    required String title,
    required String body,
    required String payloadPostId,
  }) async {
    if (succeed) scheduled[id] = when;
    return succeed;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
  }
}

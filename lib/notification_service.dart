import 'package:expired/database_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Manages scheduling local notifications for product expiry alerts.
///
/// Instead of a fixed daily alarm, one digest notification is scheduled for
/// each upcoming day on which a product hits a reminder point (7 days before,
/// 1 day before, and on the expiry day). Days with nothing to report get no
/// notification. Call [rescheduleAll] whenever the inventory changes.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'expiry_alerts';
  static const _channelName = 'Expiry Alerts';
  static const _channelDesc = 'Alerts for products that are about to expire';

  /// Days before expiry on which a reminder is shown.
  static const reminderOffsets = [7, 1, 0];

  /// Local hour of day at which reminders are shown.
  static const reminderHour = 9;

  /// How many days ahead to schedule; refreshed every time the app opens.
  static const _scheduleWindowDays = 60;
  static const _baseId = 2000;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Call once from [main] before [runApp].
  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      tz.initializeTimeZones();
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(initSettings);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Request the POST_NOTIFICATIONS permission (Android 13+).
  Future<bool> requestPermission() async {
    if (!_ready) return false;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Cancels all pending reminders and schedules fresh ones from the DB.
  Future<void> rescheduleAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      final rows = await AppDatabase.instance.getUpcomingExpiries();
      final now = DateTime.now();
      final digests = buildDigests(rows, now);

      for (final entry in digests.entries) {
        final day = entry.key;
        final fireAt = DateTime(day.year, day.month, day.day, reminderHour);
        if (!fireAt.isAfter(now)) continue;
        final dayIndex = DateTime.utc(
          day.year,
          day.month,
          day.day,
        ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
        await _plugin.zonedSchedule(
          _baseId + dayIndex,
          entry.value.title,
          entry.value.body,
          // Convert the local wall-clock time to an absolute instant.
          tz.TZDateTime.from(fireAt, tz.UTC),
          _notificationDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      // Notifications are best-effort; never break the main flow.
    }
  }

  /// Groups expiry rows (`name`, `expiryDate`) into one digest per reminder
  /// day within the schedule window, keyed by local date.
  @visibleForTesting
  static Map<DateTime, ({String title, String body})> buildDigests(
    List<Map<String, dynamic>> rows,
    DateTime now,
  ) {
    final today = DateTime(now.year, now.month, now.day);
    final byDay = <DateTime, List<({String name, int daysLeft})>>{};

    for (final row in rows) {
      final expiry = DateTime.tryParse(row['expiryDate'] as String? ?? '');
      if (expiry == null) continue;
      final expiryDay = DateTime(expiry.year, expiry.month, expiry.day);
      for (final offset in reminderOffsets) {
        final day = DateTime(
          expiryDay.year,
          expiryDay.month,
          expiryDay.day - offset,
        );
        if (day.isBefore(today)) continue;
        if (day.difference(today).inDays > _scheduleWindowDays) continue;
        byDay.putIfAbsent(day, () => []).add((
          name: row['name'] as String,
          daysLeft: offset,
        ));
      }
    }

    return byDay.map((day, items) {
      items.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
      final first = items.first;
      final when = switch (first.daysLeft) {
        0 => 'expires today',
        1 => 'expires tomorrow',
        final d => 'expires in $d days',
      };
      final more = items.length > 1 ? ' (+${items.length - 1} more)' : '';
      final title = items.length == 1
          ? '⚠️ Expiry alert'
          : '⚠️ ${items.length} products expiring soon';
      return MapEntry(day, (title: title, body: '${first.name} $when$more'));
    });
  }

  NotificationDetails _notificationDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    ),
  );
}

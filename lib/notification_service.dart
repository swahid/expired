import 'package:expired/database_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Manages scheduling and showing local notifications for product expiry alerts.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _channelId = 'expiry_alerts';
  static const _channelName = 'Expiry Alerts';
  static const _channelDesc =
      'Daily alerts for products expiring within 7 days';

  // Notification IDs — one per schedule slot so they do not overwrite each other
  static const _morningId = 1001;
  static const _eveningId = 1002;

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Call once from [main] before [runApp].
  Future<void> init() async {
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(initSettings);
  }

  /// Request the POST_NOTIFICATIONS permission (Android 13+).
  Future<bool> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Schedule the two daily checks (7 AM & 8 PM) and cancel any previous ones.
  Future<void> scheduleDailyChecks() async {
    await _plugin.cancel(_morningId);
    await _plugin.cancel(_eveningId);

    await _scheduleDailyAt(id: _morningId, hour: 7, minute: 0);
    await _scheduleDailyAt(id: _eveningId, hour: 20, minute: 0);
  }

  /// Immediately check the database and show a notification if products are
  /// expiring within 7 days. Called by the scheduled alarms.
  Future<void> checkAndNotify() async {
    final expiring = await AppDatabase.instance.getExpiringItems(withinDays: 7);
    if (expiring.isEmpty) return;

    final count = expiring.length;
    final body = 'You have $count product${count == 1 ? '' : 's'} '
        'about to expire, please check your inventory.';

    await _showNow(
      id: _morningId,
      title: '⚠️ Expiry Alert',
      body: body,
    );
  }

  // ─── private helpers ──────────────────────────────────────────────────────

  Future<void> _scheduleDailyAt({
    required int id,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the time has already passed today, start from tomorrow
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      '⚠️ Expiry Alert',
      'Checking your inventory for expiring products…',
      scheduled,
      _notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  Future<void> _showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await _plugin.show(id, title, body, _notificationDetails());
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

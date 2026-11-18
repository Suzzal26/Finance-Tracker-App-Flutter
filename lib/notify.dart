import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'core.dart';

// All notification work lives here. Nothing is sent over the internet:
// the phone itself shows these at the scheduled time.
class Notifier {
  static final FlutterLocalNotificationsPlugin _p = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await _p.initialize(
          settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
      _ready = true;
    } catch (_) {}
  }

  // Asked only when the user first turns on a feature that needs it.
  static Future<bool> askPermission() async {
    if (kIsWeb) return false;
    await init();
    try {
      final android = _p.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final ok = await android?.requestNotificationsPermission();
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  static NotificationDetails _details(String id, String name, String desc) => NotificationDetails(
      android: AndroidNotificationDetails(id, name,
          channelDescription: desc, importance: Importance.defaultImportance, priority: Priority.defaultPriority));

  static Future<void> _at(int id, DateTime when, String title, String body, NotificationDetails d) async {
    if (!when.isAfter(DateTime.now())) return;
    await _p.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(when, tz.UTC),
        notificationDetails: d,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
  }

  // The longer the user stays away, the more the message changes.
  static (String, String) _nightMessage(int gap) {
    final String body;
    final String e;
    if (gap <= 1) {
      body = t("Did you log today's expenses? It only takes 10 seconds", 'आजको खर्च लेख्नुभयो? १० सेकेन्ड मात्र लाग्छ',
          'Aajako kharcha lekhnu bhayo? 10 second matra lagchha');
      e = '✍️';
    } else if (gap <= 3) {
      body = t('A few days with no entries. Your wallet is wondering where the money went',
          'केही दिन भयो हिसाब लेखेको छैन। खल्तीले सोध्दैछ — पैसा कता गयो?',
          'Kehi din bhayo hisab lekheko chhaina. Khalti le sodhdai chha, paisa kata gayo?');
      e = '👀';
    } else if (gap <= 6) {
      body = t('Your notebook is getting lonely. Add what you remember', 'तपाईंको कापी एक्लो भयो। सम्झेजति लेखिदिनुस् है',
          'Hisab ko kapi eklo bhayo. Samjheko jati lekhdeu na');
      e = '📒';
    } else if (gap <= 13) {
      body = t('A whole week! Rough numbers are fine, just write them', 'एक हप्ता नै भयो! अदाजी रकम भए पनि लेखिदिनुस्',
          'Pura ek hapta bhayo! Andaji rakam bhaye pani lekhdeu');
      e = '🙏';
    } else if (gap <= 29) {
      body = t('Two weeks of mystery spending. Let us catch up, it is easier than you think',
          'दुई हप्ताको खर्च रहस्य बन्यो। सँगै मिलाऔं, सजिलो छ', 'Duita hapta ko kharcha mystery bhayo. Sangai milaau, sajilo chha');
      e = '💪';
    } else {
      body = t('It has been a month. We miss you! Start fresh today, your old records are safe',
          'एक महिना भयो। हामीलाई तपाईंको याद आयो! आजैदेखि फेरि सुरु गरौं, पुरानो हिसाब सुरक्षित छ',
          'Ek mahina bhayo. Hamilai timro yaad aayo! Aajai bata naya shuru garau, purano hisab surakshit chha');
      e = '🌱';
    }
    return (appName, emojiOn('msgs') ? '$body $e' : body);
  }

  // Re-plans every notification. Called whenever something relevant changes.
  static Future<void> reschedule() async {
    if (kIsWeb) return;
    await init();
    if (!_ready) return;
    try {
      await _p.cancelAll();
      final now = DateTime.now();
      final st = app.st;

      if (st.reminders) {
        final last = st.lastEntry == null ? null : dateOnly(st.lastEntry!);
        final today = dateOnly(now);
        final night = _details('night', t('Daily reminder', 'दैनिक सम्झना', 'Daily reminder'), t('Reminds you to log your expenses', 'खर्च लेख्न सम्झाउँछ', 'Kharcha lekhna yaad dilaunchha'));
        for (var i = 0; i < 30; i++) {
          final day = DateTime(today.year, today.month, today.day + i);
          final gap = last == null ? 30 : daysBetween(last, day);
          if (gap <= 0) continue; // already wrote something that day: no reminder
          final msg = _nightMessage(gap);
          await _at(1 + i, DateTime(day.year, day.month, day.day, st.remHour, st.remMin), msg.$1, msg.$2, night);
        }
      }

      final ud = _details('udharo', t('Loan due dates', 'उधारोको म्याद', 'Udharo ko miti'), t('Tells you when a loan is due', 'उधारोको म्याद आएपछि सम्झाउँछ', 'Udharo ko miti aayepachhi yaad dilaunchha'));
      for (final u in app.udharo) {
        if (u.status != 'open' || u.due == null || !u.remind) continue;
        final d = u.due!;
        final when = DateTime(d.year, d.month, d.day, 9, 0);
        final body = u.iGave
            ? t('${u.person} should pay you ${rs(u.left)} today', '${u.person} ले आज तपाईंलाई ${rs(u.left)} तिर्नुपर्ने हो', '${u.person} le aaja timilai ${rs(u.left)} tirnu parne ho')
            : t('You should pay ${u.person} ${rs(u.left)} today', 'आज तपाईंले ${u.person} लाई ${rs(u.left)} तिर्नुपर्ने हो', 'Aaja timile ${u.person} lai ${rs(u.left)} tirnu parne ho');
        await _at(1000 + u.id, when, t('Loan due today', 'आज उधारोको म्याद', 'Aaja udharo ko miti'), body, ud);
      }
    } catch (_) {}
  }
}

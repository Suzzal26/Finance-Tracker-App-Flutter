import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nepali_utils/nepali_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notify.dart';

const appNameEn = 'Kharcha Sarcha Hisab Kitab (K.S.H.K)';
const appNameNe = 'खर्चा सर्चा हिसाब किताब (K.S.H.K)';
const appVersion = '2.1.0';
const redDark = Color(0xFF3B1212);
const redStrong = Color(0xFF7A1717);

// ================= Language =================
String curLang = 'rom'; // 'rom' = Roman Nepali mix (default), 'en' = English, 'ne' = Devanagari
bool nepDigits = true; // show १२३ instead of 123 when Devanagari
bool forceEn = false; // temporarily true while making PDF/CSV
bool get ne => curLang == 'ne' && !forceEn;
bool get isRom => curLang == 'rom' && !forceEn;
String t(String en, String nep, [String? rom]) => ne ? nep : (isRom ? (rom ?? en) : en);
String get appName => ne ? appNameNe : appNameEn;

String nd(String s) {
  if (!(ne && nepDigits)) return s;
  const d = '०१२३४५६७८९';
  return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => d[int.parse(m[0]!)]);
}

const bsMonthsEn = ['Baisakh', 'Jestha', 'Asar', 'Shrawan', 'Bhadra', 'Asoj',
  'Kartik', 'Mangsir', 'Poush', 'Magh', 'Falgun', 'Chaitra'];
const bsMonthsNe = ['बैशाख', 'जेठ', 'असार', 'साउन', 'भदौ', 'असोज',
  'कात्तिक', 'मंसिर', 'पुस', 'माघ', 'फागुन', 'चैत'];
const adShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
  'Sep', 'Oct', 'Nov', 'Dec'];
const adFull = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
  'August', 'September', 'October', 'November', 'December'];
const adNe = ['जनवरी', 'फेब्रुअरी', 'मार्च', 'अप्रिल', 'मे', 'जुन', 'जुलाई',
  'अगस्ट', 'सेप्टेम्बर', 'अक्टोबर', 'नोभेम्बर', 'डिसेम्बर'];
const weekdaysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday',
  'Saturday', 'Sunday'];
const weekdaysNe = ['सोमबार', 'मंगलबार', 'बुधबार', 'बिहीबार', 'शुक्रबार',
  'शनिबार', 'आइतबार'];

// ================= Date / time helpers =================
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String bsText(DateTime d) {
  final n = NepaliDateTime.fromDateTime(d);
  final m = ne ? bsMonthsNe[n.month - 1] : bsMonthsEn[n.month - 1];
  return nd('$m ${n.day}, ${n.year}');
}

String adText(DateTime d) => ne
    ? nd('${adNe[d.month - 1]} ${d.day}, ${d.year}')
    : '${adShort[d.month - 1]} ${d.day}, ${d.year}';

String dayName(DateTime d) => ne ? weekdaysNe[d.weekday - 1] : weekdaysEn[d.weekday - 1];

bool useBs(Settings s) => s.dateMode == DateMode.bs || (s.dateMode == DateMode.both && s.bsFirst);

String dayTitle(DateTime d, Settings s) {
  switch (s.dateMode) {
    case DateMode.bs:
      return '${bsText(d)}, ${dayName(d)}';
    case DateMode.ad:
      return '${adText(d)}, ${dayName(d)}';
    case DateMode.both:
      return s.bsFirst
          ? '${bsText(d)} (${adText(d)}), ${dayName(d)}'
          : '${adText(d)} (${bsText(d)}), ${dayName(d)}';
  }
}

// one short date, following the user's date setting
String dateLabel(DateTime d) {
  final s = app.st;
  if (s.dateMode == DateMode.bs) return bsText(d);
  if (s.dateMode == DateMode.ad) return adText(d);
  return s.bsFirst ? bsText(d) : adText(d);
}

(int, String) monthOf(DateTime d, bool bs) {
  if (bs) {
    final n = NepaliDateTime.fromDateTime(d);
    final m = ne ? bsMonthsNe[n.month - 1] : bsMonthsEn[n.month - 1];
    return (n.year * 100 + n.month, nd('$m ${n.year}'));
  }
  final m = ne ? adNe[d.month - 1] : adFull[d.month - 1];
  return (d.year * 100 + d.month, nd('$m ${d.year}'));
}

String monthTitleEn(DateTime d, bool bs) {
  forceEn = true;
  try {
    return monthOf(d, bs).$2;
  } finally {
    forceEn = false;
  }
}

DateTime monthFirstDay(DateTime ref, bool bs) {
  var d = dateOnly(ref);
  final k = monthOf(d, bs).$1;
  for (var i = 0; i < 40; i++) {
    final p = DateTime(d.year, d.month, d.day - 1);
    if (monthOf(p, bs).$1 != k) break;
    d = p;
  }
  return d;
}

// everything searchable about a date, in both languages and both calendars
String dayText(DateTime d) {
  final n = NepaliDateTime.fromDateTime(d);
  return [
    bsMonthsEn[n.month - 1], bsMonthsNe[n.month - 1], '${n.day}', '${n.year}',
    adFull[d.month - 1], adShort[d.month - 1], adNe[d.month - 1], '${d.day}', '${d.year}',
    weekdaysEn[d.weekday - 1], weekdaysNe[d.weekday - 1],
  ].join(' ').toLowerCase();
}

String fmtTime(int mins, bool h24) {
  final h = mins ~/ 60, m = mins % 60;
  final mm = m.toString().padLeft(2, '0');
  if (h24) return nd('${h.toString().padLeft(2, '0')}:$mm');
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return nd('$h12:$mm ${h < 12 ? 'AM' : 'PM'}');
}

int nowMins() {
  final n = DateTime.now();
  return n.hour * 60 + n.minute;
}

String fmt(double v) {
  final neg = v < 0;
  v = v.abs();
  final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  final parts = s.split('.');
  parts[0] = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return nd((neg ? '-' : '') + parts.join('.'));
}

String rs(double v) => '${t('Rs', 'रु.')} ${fmt(v)}/-';
String plainAmount(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

String stamp(DateTime x) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${x.year}${two(x.month)}${two(x.day)}_${two(x.hour)}${two(x.minute)}';
}

String tzText() {
  final o = DateTime.now().timeZoneOffset;
  final a = o.abs();
  return 'UTC${o.isNegative ? '-' : '+'}${a.inHours.toString().padLeft(2, '0')}:${(a.inMinutes % 60).toString().padLeft(2, '0')}';
}

// ================= Settings =================
enum DateMode { both, bs, ad }

class Settings {
  DateMode dateMode = DateMode.both;
  bool bsFirst = true;
  bool hour24 = false;
  double? limit;
  bool autoBackup = true;
  DateTime? lastBackup;
  String? bgPath;
  double bgDim = 0.65;
  String lang = 'rom';
  String theme = 'teal';
  bool emojiAll = true;
  bool emojiEntries = true;
  bool emojiCats = true;
  bool emojiMsgs = true;
  int quickVer = 0;
  int catVer = 0;
  bool langChosen = false;
  bool nepDigits = true;
  bool reminders = false;
  int remHour = 21;
  int remMin = 0;
  bool askedReminder = false;
  DateTime? lastEntry;
  int? lastPromptKey;
  int nextId = 1;

  static Future<Settings> load() async {
    final p = await SharedPreferences.getInstance();
    final s = Settings();
    s.bsFirst = p.getBool('bs') ?? true; // same key as the first versions
    final raw = p.getString('settings');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        s.dateMode = DateMode.values.firstWhere((m) => m.name == j['dateMode'], orElse: () => DateMode.both);
        s.hour24 = j['hour24'] ?? false;
        s.limit = (j['limit'] as num?)?.toDouble();
        s.autoBackup = j['autoBackup'] ?? true;
        s.lastBackup = j['lastBackup'] == null ? null : DateTime.tryParse(j['lastBackup']);
        s.bgPath = j['bgPath'];
        s.bgDim = (j['bgDim'] as num?)?.toDouble() ?? 0.65;
        s.lang = j['lang'] ?? 'rom';
        s.theme = j['theme'] ?? 'teal';
        s.emojiAll = j['emojiAll'] ?? true;
        s.emojiEntries = j['emojiEntries'] ?? true;
        s.emojiCats = j['emojiCats'] ?? true;
        s.emojiMsgs = j['emojiMsgs'] ?? true;
        s.quickVer = j['quickVer'] ?? 0;
        s.catVer = j['catVer'] ?? 0;
        s.langChosen = j['langChosen'] ?? false;
        s.nepDigits = j['nepDigits'] ?? true;
        s.reminders = j['reminders'] ?? false;
        s.remHour = j['remHour'] ?? 21;
        s.remMin = j['remMin'] ?? 0;
        s.askedReminder = j['askedReminder'] ?? false;
        s.lastEntry = j['lastEntry'] == null ? null : DateTime.tryParse(j['lastEntry']);
        s.lastPromptKey = j['lastPromptKey'];
        s.nextId = j['nextId'] ?? 1;
      } catch (_) {}
    }
    return s;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('bs', bsFirst);
    await p.setString(
        'settings',
        jsonEncode({
          'dateMode': dateMode.name,
          'hour24': hour24,
          'limit': limit,
          'autoBackup': autoBackup,
          'lastBackup': lastBackup?.toIso8601String(),
          'bgPath': bgPath,
          'bgDim': bgDim,
          'lang': lang,
          'theme': theme,
          'emojiAll': emojiAll,
          'emojiEntries': emojiEntries,
          'emojiCats': emojiCats,
          'emojiMsgs': emojiMsgs,
          'quickVer': quickVer,
          'catVer': catVer,
          'langChosen': langChosen,
          'nepDigits': nepDigits,
          'reminders': reminders,
          'remHour': remHour,
          'remMin': remMin,
          'askedReminder': askedReminder,
          'lastEntry': lastEntry?.toIso8601String(),
          'lastPromptKey': lastPromptKey,
          'nextId': nextId,
        }));
  }
}

// ================= Themes =================
class AppTheme {
  final String id, en, nep, rom;
  final Color seed, bg, card;
  const AppTheme(this.id, this.en, this.nep, this.rom, this.seed, this.bg, this.card);
  String get name => ne ? nep : (isRom ? rom : en);
}

// The first one is the classic look and the default.
const appThemes = <AppTheme>[
  AppTheme('teal', 'Teal (classic)', 'टिल (सुरुको)', 'Teal (classic)', Colors.teal, Color(0xFF0E1311), Color(0xFF18201D)),
  AppTheme('orange', 'Sunset orange', 'सूर्यास्त सुन्तला', 'Sunset orange', Colors.deepOrange, Color(0xFF14100D), Color(0xFF211A15)),
  AppTheme('blue', 'Ocean blue', 'समुद्री नीलो', 'Ocean blue', Colors.blue, Color(0xFF0B1119), Color(0xFF141C27)),
  AppTheme('purple', 'Royal purple', 'बैजनी', 'Royal purple', Colors.deepPurple, Color(0xFF110E17), Color(0xFF1B1724)),
  AppTheme('green', 'Forest green', 'हरियो', 'Forest green', Colors.green, Color(0xFF0C130D), Color(0xFF152017)),
  AppTheme('rose', 'Rose pink', 'गुलाबी', 'Rose pink', Colors.pink, Color(0xFF160D11), Color(0xFF231920)),
  AppTheme('amoled', 'AMOLED black', 'पूरै कालो', 'AMOLED black', Colors.teal, Color(0xFF000000), Color(0xFF121212)),
];

AppTheme get curTheme => appThemes.firstWhere((x) => x.id == app.st.theme, orElse: () => appThemes.first);

// ================= Emoji switches =================
// part: 'entries' (on each line), 'cats' (categories, buttons, reports), 'msgs' (messages, reminders)
bool emojiOn(String part) {
  final s = app.st;
  if (!s.emojiAll) return false;
  if (part == 'entries') return s.emojiEntries;
  if (part == 'cats') return s.emojiCats;
  return s.emojiMsgs;
}

String withEmoji(String emoji, String text, [String part = 'cats']) => emojiOn(part) ? '$emoji $text' : text;
String catLabel(Cat c, [String part = 'cats']) => withEmoji(c.emoji, c.name, part);

// ================= Words -> category hints =================
// Built-in guesses. The app also LEARNS from what you pick (see AppState.learn).
const _kwCats = <String, List<String>>{
  'fuel': ['petrol', 'diesel', 'fuel', 'indhan', 'charging'],
  'food': ['khaja', 'chiya', 'tea', 'coffee', 'momo', 'chowmein', 'chau', 'dudh', 'milk', 'dahi', 'tarkari', 'sabji', 'masu',
    'chicken', 'egg', 'anda', 'rice', 'chamal', 'dal', 'oil', 'tel', 'fruit', 'phal', 'lunch', 'dinner', 'breakfast', 'khana',
    'snack', 'snacks', 'samosa', 'pizza', 'burger', 'juice', 'restaurant', 'cafe', 'biscuit', 'roti', 'paneer', 'mithai',
    'sweets', 'bakery', 'capsicum', 'dhaniya', 'kashmiri', 'gai'],
  'transport': ['bus', 'taxi', 'pathao', 'indrive', 'tempo', 'micro', 'ticket', 'rickshaw', 'flight', 'parking', 'toll',
    'vehicle', 'gadi', 'bike', 'scooter'],
  'home': ['rent', 'ghar', 'bijuli', 'electricity', 'nea', 'water', 'paani', 'khanepani', 'bill', 'tax', 'kar', 'gas', 'lpg',
    'cylinder', 'maintenance', 'repair', 'furniture', 'cleaning'],
  'shop': ['shopping', 'kapda', 'cloth', 'clothes', 'shoes', 'jutta', 'mart', 'bigmart', 'bhatbhateni', 'daraz', 'gift',
    'sabun', 'soap', 'shampoo', 'grocery'],
  'health': ['medicine', 'aushadi', 'doctor', 'hospital', 'pharmacy', 'clinic', 'lab', 'dental', 'tablet', 'pill'],
  'edu': ['school', 'college', 'fee', 'fees', 'books', 'kitab', 'copy', 'pen', 'tuition', 'course', 'exam', 'class', 'stationery'],
  'phone': ['recharge', 'ntc', 'ncell', 'data', 'internet', 'wifi', 'worldlink', 'vianet', 'sim', 'topup', 'dish', 'netflix'],
  'fun': ['movie', 'cinema', 'party', 'game', 'trip', 'picnic', 'concert'],
  'loan': ['emi', 'loan', 'kisti', 'kista', 'installment', 'interest'],
};

Map<String, String>? _kwCache;
Map<String, String> get _kw {
  if (_kwCache == null) {
    final m = <String, String>{};
    _kwCats.forEach((c, ws) {
      for (final w in ws) {
        m.putIfAbsent(w, () => c);
      }
    });
    _kwCache = m;
  }
  return _kwCache!;
}

const _stopWords = {'the', 'for', 'and', 'with', 'from', 'lai', 'bata', 'sanga', 'gareko', 'bhayo'};

// ================= Models =================
class Line {
  bool isLess;
  double amount;
  String note;
  int? time; // minutes since midnight, local wall-clock
  String? cat; // category id
  String? photo; // receipt photo file name
  bool auto; // made by a repeating entry
  Line(this.isLess, this.amount, this.note, {this.time, this.cat, this.photo, this.auto = false});
  Map<String, dynamic> toJson() =>
      {'less': isLess, 'amt': amount, 'note': note, 'time': time, 'cat': cat, 'photo': photo, 'auto': auto};
  factory Line.fromJson(Map<String, dynamic> j) => Line(j['less'], (j['amt'] as num).toDouble(), j['note'] ?? '',
      time: j['time'] as int?, cat: j['cat'] as String?, photo: j['photo'] as String?, auto: j['auto'] ?? false);
}

class Day {
  DateTime date;
  List<Line> lines;
  Day(this.date, [List<Line>? lines]) : lines = lines ?? [];
  double get less => lines.where((l) => l.isLess).fold(0.0, (a, l) => a + l.amount);
  double get add => lines.where((l) => !l.isLess).fold(0.0, (a, l) => a + l.amount);
  String get totalText => add == 0
      ? '${t('Total', 'जम्मा', 'Jamma')}: ${rs(less)}'
      : '${t('Spent', 'खर्च', 'Kharcha')}: ${rs(less)}   ${t('Received', 'आम्दानी', 'Aamdani')}: ${rs(add)}   ${t('Net', 'बचत', 'Bachat')}: ${rs(add - less)}';
  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'lines': lines.map((l) => l.toJson()).toList()};
  factory Day.fromJson(Map<String, dynamic> j) => Day(DateTime.parse(j['date']),
      (j['lines'] as List).map((e) => Line.fromJson(Map<String, dynamic>.from(e as Map))).toList());
}

class Cat {
  String id, en, nep, emoji;
  String? rom;
  double? limit;
  Cat(this.id, this.en, this.nep, this.emoji, {this.rom, this.limit});
  String get name => ne ? nep : (isRom ? (rom ?? en) : en);
  Map<String, dynamic> toJson() => {'id': id, 'en': en, 'ne': nep, 'rom': rom, 'emoji': emoji, 'limit': limit};
  factory Cat.fromJson(Map<String, dynamic> j) => Cat(j['id'], j['en'], j['ne'], j['emoji'],
      rom: j['rom'] as String?, limit: (j['limit'] as num?)?.toDouble());
}

class QuickItem {
  String id, en, nep;
  String? rom;
  String? cat;
  double? amt;
  bool less;
  QuickItem(this.id, this.en, this.nep, {this.rom, this.cat, this.amt, this.less = true});
  String get name => ne ? nep : (isRom ? (rom ?? en) : en);
  Map<String, dynamic> toJson() => {'id': id, 'en': en, 'ne': nep, 'rom': rom, 'cat': cat, 'amt': amt, 'less': less};
  factory QuickItem.fromJson(Map<String, dynamic> j) => QuickItem(j['id'], j['en'], j['ne'],
      rom: j['rom'] as String?, cat: j['cat'] as String?, amt: (j['amt'] as num?)?.toDouble(), less: j['less'] ?? true);
}

class Payment {
  DateTime date;
  double amount;
  Payment(this.date, this.amount);
  Map<String, dynamic> toJson() => {'date': date.toIso8601String(), 'amt': amount};
  factory Payment.fromJson(Map<String, dynamic> j) =>
      Payment(DateTime.parse(j['date']), (j['amt'] as num).toDouble());
}

class Udharo {
  int id;
  String person;
  double amount;
  bool iGave; // true = they owe me, false = I owe them
  String note;
  DateTime created;
  DateTime? due;
  bool remind;
  String status; // open, done, cancelled
  List<Payment> payments;
  Udharo(
      {required this.id,
      required this.person,
      required this.amount,
      required this.iGave,
      this.note = '',
      DateTime? created,
      this.due,
      this.remind = true,
      this.status = 'open',
      List<Payment>? payments})
      : created = created ?? DateTime.now(),
        payments = payments ?? [];
  double get paid => payments.fold(0.0, (a, p) => a + p.amount);
  double get left {
    final v = amount - paid;
    return v < 0 ? 0.0 : v;
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'person': person, 'amount': amount, 'iGave': iGave, 'note': note,
        'created': created.toIso8601String(), 'due': due?.toIso8601String(), 'remind': remind,
        'status': status, 'payments': payments.map((p) => p.toJson()).toList(),
      };
  factory Udharo.fromJson(Map<String, dynamic> j) => Udharo(
        id: j['id'], person: j['person'], amount: (j['amount'] as num).toDouble(), iGave: j['iGave'],
        note: j['note'] ?? '', created: DateTime.tryParse(j['created'] ?? ''),
        due: j['due'] == null ? null : DateTime.tryParse(j['due']),
        remind: j['remind'] ?? true, status: j['status'] ?? 'open',
        payments: ((j['payments'] ?? []) as List).map((e) => Payment.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

class Recurring {
  int id;
  bool isLess;
  double amount;
  String note;
  String? cat;
  String freq; // daily, weekly, monthly
  int weekday; // 1..7 (Monday = 1)
  int monthDay; // 1..28
  bool bs; // monthly day counted in BS (true) or AD (false)
  DateTime? lastApplied;
  Recurring(
      {required this.id,
      required this.isLess,
      required this.amount,
      this.note = '',
      this.cat,
      this.freq = 'monthly',
      this.weekday = 1,
      this.monthDay = 1,
      this.bs = true,
      this.lastApplied});

  bool matches(DateTime d) {
    if (freq == 'daily') return true;
    if (freq == 'weekly') return d.weekday == weekday;
    final day = bs ? NepaliDateTime.fromDateTime(d).day : d.day;
    return day == monthDay;
  }

  String get describe {
    if (freq == 'daily') return t('Every day', 'हरेक दिन', 'Roj ko roj');
    if (freq == 'weekly') return t('Every ${weekdaysEn[weekday - 1]}', 'हरेक ${weekdaysNe[weekday - 1]}', 'Har ${weekdaysEn[weekday - 1]}');
    return nd(t('Every month on day $monthDay (${bs ? 'BS' : 'AD'})', 'हरेक महिना $monthDay गते (${bs ? 'वि.सं.' : 'ई.सं.'})'));
  }

  Map<String, dynamic> toJson() => {
        'id': id, 'less': isLess, 'amt': amount, 'note': note, 'cat': cat, 'freq': freq,
        'weekday': weekday, 'monthDay': monthDay, 'bs': bs, 'last': lastApplied?.toIso8601String(),
      };
  factory Recurring.fromJson(Map<String, dynamic> j) => Recurring(
        id: j['id'], isLess: j['less'], amount: (j['amt'] as num).toDouble(), note: j['note'] ?? '',
        cat: j['cat'] as String?, freq: j['freq'] ?? 'monthly', weekday: j['weekday'] ?? 1,
        monthDay: j['monthDay'] ?? 1, bs: j['bs'] ?? true,
        lastApplied: j['last'] == null ? null : DateTime.tryParse(j['last']),
      );
}

List<Cat> defaultCats() => [
      Cat('food', 'Food', 'खाना', '🍜', rom: 'Khana'),
      Cat('fuel', 'Fuel', 'इन्धन', '⛽', rom: 'Petrol / Indhan'),
      Cat('transport', 'Transport', 'यातायात', '🚌', rom: 'Yatayat'),
      Cat('home', 'Rent & Bills', 'भाडा र बिल', '🏠', rom: 'Bhada ra Bill'),
      Cat('shop', 'Shopping', 'किनमेल', '🛒', rom: 'Kinmel'),
      Cat('health', 'Health', 'स्वास्थ्य', '💊', rom: 'Swasthya'),
      Cat('edu', 'Education', 'शिक्षा', '📚', rom: 'Padhai'),
      Cat('phone', 'Phone & Internet', 'फोन र इन्टरनेट', '📱', rom: 'Phone ra Net'),
      Cat('loan', 'EMI & Loans', 'किस्ता र ऋण', '🏦', rom: 'EMI / Karja'),
      Cat('fun', 'Fun', 'रमाइलो', '🎉', rom: 'Ramailo'),
      Cat('other', 'Other', 'अन्य', '📦', rom: 'Aru'),
    ];

List<QuickItem> defaultQuick() => [
      QuickItem('petrol', 'Petrol', 'पेट्रोल', rom: 'Petrol', cat: 'fuel'),
      QuickItem('khaja', 'Snacks', 'खाजा', rom: 'Khaja', cat: 'food'),
      QuickItem('chiya', 'Tea', 'चिया', rom: 'Chiya', cat: 'food'),
      QuickItem('momo', 'Momo', 'मोमो', rom: 'Momo', cat: 'food'),
      QuickItem('dudh', 'Milk', 'दूध', rom: 'Dudh', cat: 'food'),
      QuickItem('tarkari', 'Vegetables', 'तरकारी', rom: 'Tarkari', cat: 'food'),
      QuickItem('bus', 'Bus fare', 'बस भाडा', rom: 'Bus Bhada', cat: 'transport'),
      QuickItem('gadi', 'Vehicle fare', 'गाडी भाडा', rom: 'Gadi Bhada', cat: 'transport'),
      QuickItem('ghar', 'House rent', 'घर भाडा', rom: 'Ghar Bhada', cat: 'home'),
      QuickItem('bijuli', 'Electricity', 'बिजुली', rom: 'Bijuli', cat: 'home'),
      QuickItem('recharge', 'Mobile recharge', 'मोबाइल रिचार्ज', rom: 'Recharge', cat: 'phone'),
      QuickItem('internet', 'Internet', 'इन्टरनेट', rom: 'Internet', cat: 'phone'),
      QuickItem('emi', 'EMI', 'किस्ता (EMI)', rom: 'EMI', cat: 'loan'),
      QuickItem('medicine', 'Medicine', 'औषधि', rom: 'Aushadi', cat: 'health'),
    ];

// ================= Backup =================
class BackupData {
  List<Day> days;
  List<Cat>? cats;
  List<QuickItem>? quick;
  List<Udharo>? udharo;
  List<Recurring>? rec;
  double? limit;
  Map<String, String>? learned;
  BackupData(this.days, {this.cats, this.quick, this.udharo, this.rec, this.limit, this.learned});
}

class Backup {
  static String encode() => jsonEncode({
        'app': 'kshk',
        'version': 4,
        'created': DateTime.now().toIso8601String(),
        'limit': app.st.limit,
        'days': app.days.map((d) => d.toJson()).toList(),
        'cats': app.cats.map((d) => d.toJson()).toList(),
        'quick': app.quick.map((d) => d.toJson()).toList(),
        'udharo': app.udharo.map((d) => d.toJson()).toList(),
        'recurring': app.rec.map((d) => d.toJson()).toList(),
        'learned': app.learned,
      });

  static List<T>? _list<T>(dynamic v, T Function(Map<String, dynamic>) f) {
    if (v is! List) return null;
    return v.map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
  }

  static BackupData? decode(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map || j['days'] is! List) return null;
      return BackupData(_list(j['days'], Day.fromJson)!,
          cats: _list(j['cats'], Cat.fromJson),
          quick: _list(j['quick'], QuickItem.fromJson),
          udharo: _list(j['udharo'], Udharo.fromJson),
          rec: _list(j['recurring'], Recurring.fromJson),
          limit: (j['limit'] as num?)?.toDouble(),
          learned: j['learned'] is Map ? Map<String, String>.from(j['learned']) : null);
    } catch (_) {
      return null;
    }
  }

  static Future<Directory> dir() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/backups');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static Future<List<File>> list() async {
    final d = await dir();
    final files = d.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  static Future<File> write({String tag = 'auto'}) async {
    final d = await dir();
    final f = File('${d.path}/kshk_${tag}_${stamp(DateTime.now())}.json');
    await f.writeAsString(encode());
    final files = await list();
    if (files.length > 10) {
      for (final old in files.skip(10)) {
        try {
          await old.delete();
        } catch (_) {}
      }
    }
    return f;
  }

  static Future<bool> saveCopy() async {
    final bytes = Uint8List.fromList(utf8.encode(encode()));
    final uri = await FilePicker.saveFile(
        dialogTitle: 'Save backup copy', fileName: 'KSHK_backup_${stamp(DateTime.now())}.json', bytes: bytes);
    return uri != null;
  }
}

// ================= App state (one shared object) =================
final AppState app = AppState();

class AppState extends ChangeNotifier {
  List<Day> days = [];
  Settings st = Settings();
  List<Cat> cats = [];
  List<QuickItem> quick = [];
  List<Udharo> udharo = [];
  List<Recurring> rec = [];
  String docDir = '';
  Map<String, String> learned = {};

  bool get bs => useBs(st);

  void applyLang() {
    curLang = st.lang;
    nepDigits = st.nepDigits;
  }

  void refresh() => notifyListeners();

  List<T>? _read<T>(SharedPreferences p, String key, T Function(Map<String, dynamic>) f) {
    final s = p.getString(key);
    if (s == null) return null;
    try {
      return (jsonDecode(s) as List).map((e) => f(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    days = _read(p, 'days', Day.fromJson) ?? [];
    days.sort((a, b) => b.date.compareTo(a.date));
    st = await Settings.load();
    cats = _read(p, 'cats', Cat.fromJson) ?? defaultCats();
    quick = _read(p, 'quick', QuickItem.fromJson) ?? defaultQuick();
    udharo = _read(p, 'udharo', Udharo.fromJson) ?? [];
    rec = _read(p, 'recurring', Recurring.fromJson) ?? [];
    final lj = p.getString('learned');
    if (lj != null) {
      try {
        learned = Map<String, String>.from(jsonDecode(lj) as Map);
      } catch (_) {}
    }
    // one-time refresh of the built-in items (your own custom items are kept)
    if (st.quickVer < 2) {
      final custom = quick.where((q) => RegExp(r'^q\d+$').hasMatch(q.id)).toList();
      quick = [...defaultQuick(), ...custom];
      st.quickVer = 2;
      await saveQuick();
      await st.save();
    }
    if (st.catVer < 2) {
      final old = {for (final c in cats) c.id: c};
      final fresh = defaultCats();
      for (final d in fresh) {
        d.limit = old[d.id]?.limit;
      }
      final custom = cats.where((c) => RegExp(r'^c\d+$').hasMatch(c.id)).toList();
      cats = [...fresh, ...custom];
      st.catVer = 2;
      await saveCats();
      await st.save();
    }
    applyLang();
    if (!kIsWeb) {
      try {
        docDir = (await getApplicationDocumentsDirectory()).path;
      } catch (_) {}
    }
  }

  Future<void> _write(String key, List<dynamic> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(key, jsonEncode(items.map((e) => e.toJson()).toList()));
  }

  Future<void> saveDays() => _write('days', days);
  Future<void> saveCats() => _write('cats', cats);
  Future<void> saveQuick() => _write('quick', quick);
  Future<void> saveUdharo() => _write('udharo', udharo);
  Future<void> saveRec() => _write('recurring', rec);
  Future<void> saveSettings() => st.save();

  int newId() {
    final i = st.nextId++;
    st.save();
    return i;
  }

  String receiptPath(String name) => '$docDir/receipts/$name';

  // ---- word -> category learning ----
  Future<void> saveLearned() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('learned', jsonEncode(learned));
  }

  List<String> _tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9\u0900-\u097F]+'))
      .where((w) => w.length >= 2 && !RegExp(r'^[0-9]+$').hasMatch(w))
      .toList();

  // What category does this note probably belong to? null = uncategorized.
  String? guessCat(String text) {
    final toks = _tokens(text);
    if (toks.isEmpty) return null;
    for (final w in toks) {
      final v = learned[w];
      if (v != null) return (v.isNotEmpty && catById(v) != null) ? v : null;
    }
    final whole = text.trim().toLowerCase();
    for (final q in quick) {
      if (q.cat != null &&
          catById(q.cat) != null &&
          (q.en.toLowerCase() == whole || q.nep == whole || (q.rom ?? '').toLowerCase() == whole)) {
        return q.cat;
      }
    }
    for (final w in toks) {
      final k = _kw[w];
      if (k != null && catById(k) != null) return k;
    }
    return null;
  }

  // Remember which category the user chose for the words in this note.
  void learn(String note, String? cat, {bool explicitNone = false}) {
    if (cat == null && !explicitNone) return;
    for (final w in _tokens(note)) {
      if (w.length < 3 || _stopWords.contains(w)) continue;
      learned.remove(w);
      learned[w] = cat ?? '';
    }
    while (learned.length > 600) {
      learned.remove(learned.keys.first);
    }
    saveLearned();
  }

  Cat? catById(String? id) {
    if (id == null) return null;
    for (final c in cats) {
      if (c.id == id) return c;
    }
    return null;
  }

  Day dayFor(DateTime date) {
    final d = dateOnly(date);
    for (final x in days) {
      if (x.date == d) return x;
    }
    final day = Day(d);
    days.add(day);
    days.sort((a, b) => b.date.compareTo(a.date));
    return day;
  }

  // call after any change to entries; entry = true when the user added something
  Future<void> commitDays({bool entry = false}) async {
    notifyListeners();
    await saveDays();
    if (entry) {
      final today = dateOnly(DateTime.now());
      final le = st.lastEntry;
      if (le == null || dateOnly(le) != today) {
        st.lastEntry = today;
        await st.save();
        Notifier.reschedule();
      }
    }
  }

  Future<void> addEntry(DateTime date, Line line) async {
    dayFor(date).lines.add(line);
    await commitDays(entry: true);
  }

  double monthLess(DateTime ref, {String? cat}) {
    final k = monthOf(ref, bs).$1;
    var sum = 0.0;
    for (final d in days) {
      if (monthOf(d.date, bs).$1 != k) continue;
      for (final l in d.lines) {
        if (l.isLess && (cat == null || l.cat == cat)) sum += l.amount;
      }
    }
    return sum;
  }

  List<Udharo> dueUdharo() {
    final today = dateOnly(DateTime.now());
    return udharo.where((u) => u.status == 'open' && u.due != null && !dateOnly(u.due!).isAfter(today)).toList();
  }

  Future<void> udharoChanged() async {
    notifyListeners();
    await saveUdharo();
    Notifier.reschedule();
  }

  // adds today's repeating entries (and any missed days since the app was last opened)
  Future<int> applyRecurring() async {
    final today = dateOnly(DateTime.now());
    var added = 0;
    for (final r in rec) {
      final last = r.lastApplied ?? DateTime(today.year, today.month, today.day - 1);
      var d = DateTime(last.year, last.month, last.day + 1);
      var guard = 0;
      while (!d.isAfter(today) && guard++ < 400) {
        if (r.matches(d)) {
          dayFor(d).lines.add(Line(r.isLess, r.amount, r.note, cat: r.cat, auto: true));
          added++;
        }
        d = DateTime(d.year, d.month, d.day + 1);
      }
      r.lastApplied = today;
    }
    await saveRec();
    if (added > 0) await commitDays();
    return added;
  }

  Future<void> restoreAll(BackupData b) async {
    days = b.days..sort((a, c) => c.date.compareTo(a.date));
    if (b.cats != null) cats = b.cats!;
    if (b.quick != null) quick = b.quick!;
    if (b.udharo != null) udharo = b.udharo!;
    if (b.rec != null) rec = b.rec!;
    if (b.limit != null) st.limit = b.limit;
    if (b.learned != null) {
      learned = b.learned!;
      await saveLearned();
    }
    notifyListeners();
    await saveDays();
    await saveCats();
    await saveQuick();
    await saveUdharo();
    await saveRec();
    await st.save();
    Notifier.reschedule();
  }
}

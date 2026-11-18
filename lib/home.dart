import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'core.dart';
import 'notify.dart';

// ================= Shared helpers =================
bool hasBg(Settings s) => !kIsWeb && s.bgPath != null && File(s.bgPath!).existsSync();

Color cardColor(bool over) =>
    over ? redDark : (hasBg(app.st) ? curTheme.card.withAlpha(0xD9) : curTheme.card);

void showSnack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

class AppBg extends StatelessWidget {
  final Widget child;
  const AppBg({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final st = app.st;
    if (!hasBg(st)) return child;
    return Stack(fit: StackFit.expand, children: [
      Image.file(File(st.bgPath!),
          fit: BoxFit.cover, cacheWidth: 1080, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
      Container(color: Color.fromRGBO(0, 0, 0, st.bgDim)),
      child,
    ]);
  }
}

// A page that sits inside the bottom-bar shell
Widget panel({required String title, required Widget body, Widget? fab, List<Widget>? actions, Color? barColor}) {
  final bg = hasBg(app.st);
  return Scaffold(
    backgroundColor: bg ? Colors.transparent : null,
    appBar: AppBar(
        backgroundColor: barColor ?? (bg ? Colors.transparent : null),
        title: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(title,
                maxLines: 1,
                style: title.length > 22 ? const TextStyle(fontSize: 15, fontWeight: FontWeight.w600) : null)),
        actions: actions),
    floatingActionButton: fab,
    body: body,
  );
}

// A page opened on top (with its own back button)
Widget subPage({required String title, required Widget body, Widget? fab, List<Widget>? actions}) =>
    AppBg(child: panel(title: title, body: body, fab: fab, actions: actions));

Widget lineWidget(Line l) {
  final c = app.catById(l.cat);
  return Text.rich(TextSpan(children: [
    if (c != null && emojiOn('entries')) TextSpan(text: '${c.emoji} '),
    TextSpan(
        text: l.isLess ? '${t('Spent', 'खर्च', 'Kharcha')}: ' : '${t('Received', 'आम्दानी', 'Aamdani')}: ',
        style: TextStyle(fontWeight: FontWeight.w600, color: l.isLess ? Colors.redAccent : Colors.greenAccent)),
    TextSpan(text: rs(l.amount)),
    if (l.note.isNotEmpty) TextSpan(text: '  (${l.note})', style: const TextStyle(color: Colors.white60)),
    if (l.time != null)
      TextSpan(text: '  ${fmtTime(l.time!, app.st.hour24)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
    if (l.photo != null)
      const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.attach_file, size: 14, color: Colors.white54))),
    if (l.auto)
      const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.autorenew, size: 14, color: Colors.white54))),
  ]));
}

Future<void> showLimitDialog(BuildContext context) async {
  final st = app.st;
  final c = TextEditingController(text: st.limit == null ? '' : plainAmount(st.limit!));
  final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
            title: Text(t('Monthly limit', 'मासिक सीमा', 'Mahina ko limit')),
            content: TextField(
              controller: c,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  prefixText: '${t('Rs', 'रु.')} ', hintText: t('e.g. 20000', 'जस्तै: २००००', 'jastai: 20000')),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, '__clear'), child: Text(t('Remove limit', 'सीमा हटाउनुहोस्', 'Limit hataunu'))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'रद्द'))),
              TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
            ],
          ));
  if (res == null) return;
  if (res == '__clear') {
    st.limit = null;
  } else {
    final v = double.tryParse(res.trim());
    if (v == null || v <= 0) return;
    st.limit = v;
  }
  await st.save();
  app.refresh();
}

// ================= Home panel (the middle tab) =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String query = '';
  final searchCtl = TextEditingController();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _open(Day day) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DayScreen(day: day)));
    if (mounted) setState(() {});
  }

  Future<void> _newDay() async {
    final picked = await showDatePicker(
        context: context, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2090));
    if (picked == null) return;
    final day = app.dayFor(picked);
    await app.saveDays();
    app.refresh();
    _open(day);
  }

  Future<void> _delete(Day day) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(t('Delete this day?', 'यो दिन मेट्ने?', 'Yo din delete garne?')),
              content: Text(dayTitle(day.date, app.st)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Cancel', 'रद्द'))),
                TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('Delete', 'मेट्नुहोस्'))),
              ],
            ));
    if (ok == true) {
      app.days.remove(day);
      app.refresh();
      await app.saveDays();
    }
  }

  bool _matches(Day d, List<String> toks) {
    final dt = dayText(d.date);
    return toks.every((tk) =>
        dt.contains(tk) ||
        d.lines.any((l) =>
            l.note.toLowerCase().contains(tk) ||
            plainAmount(l.amount).contains(tk) ||
            (app.catById(l.cat)?.en.toLowerCase().contains(tk) ?? false) ||
            (app.catById(l.cat)?.nep.contains(tk) ?? false)));
  }

  String _summary(List<Day> shown, List<String> toks) {
    final all = shown.expand((d) => d.lines).toList();
    final hits = all.where((l) => toks.any((tk) => l.note.toLowerCase().contains(tk))).toList();
    final src = hits.isNotEmpty ? hits : all;
    final less = src.where((l) => l.isLess).fold(0.0, (a, l) => a + l.amount);
    final add = src.where((l) => !l.isLess).fold(0.0, (a, l) => a + l.amount);
    final label = hits.isNotEmpty
        ? nd(t('${hits.length} matching entries', '${hits.length} मिल्ने हिसाब', '${hits.length} milne hisab'))
        : nd(t('${shown.length} days', '${shown.length} दिन', '${shown.length} din'));
    return '$label  •  ${t('Spent', 'खर्च', 'Kharcha')} ${rs(less)}${add > 0 ? "  •  ${t('Received', 'आम्दानी', 'Aamdani')} ${rs(add)}" : ""}';
  }

  Widget _limitBanner(double spent) {
    final lim = app.st.limit!;
    final over = spent > lim;
    final pct = (spent / lim).clamp(0.0, 1.0).toDouble();
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        color: over ? redStrong : Color.alphaBlend(const Color(0x14FFFFFF), curTheme.card),
        borderRadius: BorderRadius.circular(12),
        border: over ? Border.all(color: Colors.redAccent) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (over)
            const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18)),
          Expanded(
            child: Text(
                over
                    ? t('Limit exceeded! ${rs(spent)} of ${rs(lim)}  (over by ${rs(spent - lim)})', 'सीमा नाघ्यो! ${rs(lim)} मा ${rs(spent)} खर्च  (${rs(spent - lim)} बढी)', 'Limit naghyo! ${rs(lim)} ma ${rs(spent)} kharcha  (${rs(spent - lim)} badhi)')
                    : t('This month: ${rs(spent)} of ${rs(lim)}  •  ${rs(lim - spent)} left', 'यो महिना: ${rs(lim)} मध्ये ${rs(spent)} खर्च  •  ${rs(lim - spent)} बाँकी', 'Yo mahina: ${rs(lim)} bata ${rs(spent)} gayo  •  ${rs(lim - spent)} baki'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit_outlined, size: 18),
              onPressed: () => showLimitDialog(context)),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: LinearProgressIndicator(
              value: pct,
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
              color: over ? Colors.white : (pct >= 0.8 ? Colors.orange : primary),
              backgroundColor: Colors.white12),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (c, _) => _build(c));

  Widget _build(BuildContext context) {
    final st = app.st;
    final bs = app.bs;
    final days = app.days;
    final now = DateTime.now();
    final toks = query.toLowerCase().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final shown = toks.isEmpty ? days : days.where((d) => _matches(d, toks)).toList();
    final primary = Theme.of(context).colorScheme.primary;

    final monthTotals = <int, double>{};
    for (final d in days) {
      final k = monthOf(d.date, bs).$1;
      monthTotals[k] = (monthTotals[k] ?? 0) + d.less;
    }
    bool overKey(int k) => toks.isEmpty && st.limit != null && (monthTotals[k] ?? 0) > st.limit!;
    final spentNow = monthTotals[monthOf(now, bs).$1] ?? 0;
    final overNow = st.limit != null && spentNow > st.limit!;

    final groups = <int, List<Day>>{};
    final titles = <int, String>{};
    for (final d in shown) {
      final m = monthOf(d.date, bs);
      groups.putIfAbsent(m.$1, () => []).add(d);
      titles[m.$1] = m.$2;
    }
    final items = <Object>[];
    groups.forEach((k, list) {
      items.add(_MonthHeader(k, titles[k]!, list.fold(0.0, (a, d) => a + d.less), list.fold(0.0, (a, d) => a + d.add)));
      items.addAll(list);
    });

    return panel(
      title: appName,
      barColor: overNow ? redDark : null,
      fab: FloatingActionButton.extended(heroTag: null, 
          onPressed: _newDay, icon: const Icon(Icons.add), label: Text(t('New day', 'नयाँ दिन', 'Naya din'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 8, 4),
          child: Row(children: [
            Expanded(
              child: Text('${dayTitle(now, st)}  •  ${fmtTime(now.hour * 60 + now.minute, st.hour24)}',
                  style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
            ),
            if (st.limit == null)
              TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => showLimitDialog(context),
                  icon: const Icon(Icons.speed, size: 16),
                  label: Text(t('Set limit', 'सीमा तोक्नुहोस्', 'Limit rakha'), style: const TextStyle(fontSize: 12))),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: searchCtl,
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  hintText: t('Search: month, item, day…', 'खोज्नुहोस्: महिना, सामान, बार…', 'Khoj: mahina, saman, bar…'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            searchCtl.clear();
                            setState(() => query = '');
                          }),
                  filled: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            if (st.dateMode == DateMode.both) ...[
              const SizedBox(width: 8),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(value: true, label: Text(t('BS', 'वि.सं.'))),
                  ButtonSegment(value: false, label: Text(t('AD', 'ई.सं.'))),
                ],
                selected: {st.bsFirst},
                onSelectionChanged: (s) {
                  st.bsFirst = s.first;
                  st.save();
                  app.refresh();
                },
              ),
            ],
          ]),
        ),
        if (st.limit != null && toks.isEmpty) _limitBanner(spentNow),
        if (toks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_summary(shown, toks), style: TextStyle(color: primary, fontWeight: FontWeight.w600)),
          ),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(days.isEmpty
                      ? t('No entries yet. Tap "New day".', 'अहिले केही छैन। "नयाँ दिन" थिच्नुहोस्।', 'Khali chha! "Naya din" thichera hisab suru gara.')
                      : t('No results', 'केही भेटिएन', 'Kei bhetiyena')))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final it = items[i];
                    if (it is _MonthHeader) {
                      final over = overKey(it.k);
                      return Container(
                        margin: const EdgeInsets.fromLTRB(0, 14, 0, 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: over ? redStrong : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Flexible(
                            child: Text(it.title,
                                style: TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.bold, color: over ? Colors.white : primary)),
                          ),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Text(
                                '${t('Spent', 'खर्च', 'Kharcha')} ${rs(it.less)}${it.add > 0 ? "  ${t('Received', 'आम्दानी', 'Aamdani')} ${rs(it.add)}" : ""}',
                                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                            if (over)
                              Text(
                                  t('Over limit by ${rs((monthTotals[it.k] ?? 0) - st.limit!)}', '${rs((monthTotals[it.k] ?? 0) - st.limit!)} सीमा भन्दा बढी', 'Limit bhanda ${rs((monthTotals[it.k] ?? 0) - st.limit!)} badhi'),
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ]),
                        ]),
                      );
                    }
                    final d = it as Day;
                    final over = overKey(monthOf(d.date, bs).$1);
                    return Card(
                      color: cardColor(over),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: over ? const BorderSide(color: Color(0x88FF5252)) : BorderSide.none),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _open(d),
                        onLongPress: () => _delete(d),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(dayTitle(d.date, st), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 6),
                            for (final l in d.lines) lineWidget(l),
                            const Divider(),
                            Text(d.totalText, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _MonthHeader {
  final int k;
  final String title;
  final double less, add;
  _MonthHeader(this.k, this.title, this.less, this.add);
}

// ================= Day screen =================
class DayScreen extends StatefulWidget {
  final Day day;
  const DayScreen({super.key, required this.day});
  @override
  State<DayScreen> createState() => _DayScreenState();
}

class _DayScreenState extends State<DayScreen> {
  bool isLess = true;
  int? pickedTime; // null = "now" when the line is added
  String? cat; // null = uncategorized
  bool catManual = false; // true once the user picked a category by hand
  final amountCtl = TextEditingController();
  final noteCtl = TextEditingController();

  @override
  void dispose() {
    amountCtl.dispose();
    noteCtl.dispose();
    super.dispose();
  }

  // The category follows the words you type, unless you picked one by hand.
  void _onNoteChanged(String text) {
    if (catManual) return;
    final g = text.trim().isEmpty ? null : app.guessCat(text);
    if (g != cat) setState(() => cat = g);
  }

  Future<void> _pickTime() async {
    final cur = pickedTime ?? nowMins();
    final r = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur ~/ 60, minute: cur % 60),
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: app.st.hour24), child: child!),
    );
    if (r != null) setState(() => pickedTime = r.hour * 60 + r.minute);
  }

  void _useQuick(QuickItem q) {
    setState(() {
      noteCtl.text = q.name;
      noteCtl.selection = TextSelection.collapsed(offset: noteCtl.text.length);
      catManual = false;
      cat = (q.cat != null && app.catById(q.cat) != null) ? q.cat : app.guessCat(q.name);
      isLess = q.less;
      if (q.amt != null && amountCtl.text.isEmpty) amountCtl.text = plainAmount(q.amt!);
    });
  }

  void _addLine() {
    final amt = double.tryParse(amountCtl.text.trim());
    if (amt == null || amt <= 0) return;
    final date = widget.day.date;
    final c = cat;
    final note = noteCtl.text.trim();
    final wasLess = isLess;
    final beforeAll = app.monthLess(date);
    final beforeCat = c == null ? 0.0 : app.monthLess(date, cat: c);
    widget.day.lines.add(Line(isLess, amt, note, time: pickedTime ?? nowMins(), cat: c));
    app.learn(note, c, explicitNone: catManual && c == null);
    amountCtl.clear();
    noteCtl.clear();
    setState(() {
      pickedTime = null;
      cat = null;
      catManual = false;
    });
    app.commitDays(entry: true);
    var alerted = false;
    if (wasLess) alerted = _checkLimits(beforeAll, beforeCat, c);
    if (!alerted) _maybeAskReminder();
  }

  bool _checkLimits(double beforeAll, double beforeCat, String? c) {
    final date = widget.day.date;
    final lim = app.st.limit;
    if (lim != null) {
      final after = app.monthLess(date);
      if (after > lim) {
        if (beforeAll <= lim) {
          _alert(t('Monthly limit exceeded', 'मासिक सीमा नाघ्यो', 'Mahina ko limit naghyo!'),
              t('Your limit is ${rs(lim)}.\nThis month you have spent ${rs(after)}, which is ${rs(after - lim)} over.',
                  'तपाईंको सीमा ${rs(lim)} हो।\nयो महिना ${rs(after)} खर्च भयो, जुन ${rs(after - lim)} बढी हो।',
                  'Timro limit ${rs(lim)} ho.\nYo mahina ${rs(after)} kharcha bhayo, ${rs(after - lim)} badhi!'));
          return true;
        }
        showSnack(context, t('Still over the limit by ${rs(after - lim)}', 'अझै सीमा भन्दा ${rs(after - lim)} बढी छ',
            'Limit bhanda ${rs(after - lim)} badhi nai chha'));
        return false;
      }
      if (beforeAll < lim * 0.8 && after >= lim * 0.8) {
        showSnack(context, t('Heads up: 80% of your monthly limit is used', 'ध्यान दिनुहोस्: मासिक सीमाको ८०% सकियो',
            'Hoshiyar! Limit ko 80% sakiyo'));
      }
    }
    final cc = app.catById(c);
    if (cc != null && cc.limit != null) {
      final afterCat = app.monthLess(date, cat: c);
      if (afterCat > cc.limit! && beforeCat <= cc.limit!) {
        _alert(t('${cc.name} limit exceeded', '${cc.name} को सीमा नाघ्यो', '${cc.name} ko limit naghyo'),
            t('Limit ${rs(cc.limit!)}, spent ${rs(afterCat)} this month.',
                'सीमा ${rs(cc.limit!)}, यो महिना ${rs(afterCat)} खर्च भयो।',
                'Limit ${rs(cc.limit!)}, yo mahina ${rs(afterCat)} kharcha.'));
        return true;
      }
    }
    return false;
  }

  void _alert(String title, String body) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
              backgroundColor: redDark,
              icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 40),
              title: Text(title),
              content: Text(body),
              actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
            ));
  }

  // Asked once, right after the first entry, so the permission makes sense to the user
  Future<void> _maybeAskReminder() async {
    final st = app.st;
    if (kIsWeb || st.askedReminder || st.reminders) return;
    st.askedReminder = true;
    await st.save();
    if (!mounted) return;
    final yes = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
              title: Text(t('Nightly reminder?', 'रातको सम्झना चाहिन्छ?', 'Raat ko reminder chahiyo?'), style: const TextStyle(fontSize: 17)),
              content: Text(t(
                  'Get a gentle reminder at 9 PM only if you forgot to log your expenses. You can change this in Settings.',
                  'खर्च लेख्न बिर्सनुभयो भने मात्र राति ९ बजे सम्झाउँछौं। सेटिङमा परिवर्तन गर्न सकिन्छ।',
                  'Kharcha lekhna birsiyo bhane matra rati 9 baje yaad dilaunchhau. Settings bata badalna sakinchha.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('Not now', 'अहिले होइन', 'Pachi'))),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('Yes, remind me', 'हुन्छ', 'Hunchha, yaad dilau'))),
              ],
            ));
    if (yes == true) {
      final ok = await Notifier.askPermission();
      if (ok) {
        st.reminders = true;
        await st.save();
        app.refresh();
        Notifier.reschedule();
      } else if (mounted) {
        showSnack(context, t('Notifications are blocked for this app in phone settings.', 'फोन सेटिङमा यो एपको नोटिफिकेसन बन्द छ।',
            'Phone settings ma yo app ko notification band chha.'));
      }
    }
  }

  // ---- delete (with Undo) ----
  void _deleteLine(int i) {
    final l = widget.day.lines[i];
    setState(() => widget.day.lines.removeAt(i));
    app.commitDays();
    final sm = ScaffoldMessenger.of(context);
    sm.hideCurrentSnackBar();
    sm
        .showSnackBar(SnackBar(
          content: Text(t('Entry deleted', 'हिसाब मेटियो', 'Hisab delete bhayo')),
          action: SnackBarAction(
              label: t('Undo', 'फिर्ता', 'Undo'),
              onPressed: () {
                final idx = i > widget.day.lines.length ? widget.day.lines.length : i;
                widget.day.lines.insert(idx, l);
                if (mounted) setState(() {});
                app.commitDays();
              }),
        ))
        .closed
        .then((reason) {
      if (reason != SnackBarClosedReason.action) _deletePhotoFile(l.photo);
    });
  }

  // ---- long-press menu: photo / delete ----
  Future<void> _lineMenu(int i) async {
    final l = widget.day.lines[i];
    final act = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
              child: Wrap(children: [
                ListTile(leading: const Icon(Icons.camera_alt_outlined), title: Text(t('Take a photo (receipt)', 'फोटो खिच्नुहोस् (रसिद)', 'Photo khicha (receipt)')), onTap: () => Navigator.pop(c, 'cam')),
                ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(t('Choose from gallery', 'ग्यालरीबाट छान्नुहोस्', 'Gallery bata chhana')), onTap: () => Navigator.pop(c, 'gal')),
                if (l.photo != null) ...[
                  ListTile(leading: const Icon(Icons.image_outlined), title: Text(t('View photo', 'फोटो हेर्नुहोस्', 'Photo herna')), onTap: () => Navigator.pop(c, 'view')),
                  ListTile(leading: const Icon(Icons.hide_image_outlined), title: Text(t('Remove photo', 'फोटो हटाउनुहोस्', 'Photo hatau')), onTap: () => Navigator.pop(c, 'rm')),
                ],
                ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    title: Text(t('Delete this entry', 'यो हिसाब मेट्नुहोस्', 'Yo hisab delete gara'), style: const TextStyle(color: Colors.redAccent)),
                    onTap: () => Navigator.pop(c, 'del')),
              ]),
            ));
    if (act == null || !mounted) return;
    if (act == 'cam') await _setPhoto(l, ImageSource.camera);
    if (act == 'gal') await _setPhoto(l, ImageSource.gallery);
    if (act == 'view') await _viewPhoto(l);
    if (act == 'rm') {
      _deletePhotoFile(l.photo);
      setState(() => l.photo = null);
      app.commitDays();
    }
    if (act == 'del') _deleteLine(i);
  }

  void _deletePhotoFile(String? name) {
    if (name == null || kIsWeb) return;
    try {
      File(app.receiptPath(name)).delete();
    } catch (_) {}
  }

  // No permission pop-up here: the phone's own camera / photo picker is used.
  Future<void> _setPhoto(Line l, ImageSource src) async {
    if (kIsWeb) return showSnack(context, t('Photos work on the phone only', 'फोटो फोनमा मात्र चल्छ', 'Photo phone ma matra chalchha'));
    try {
      final x = await ImagePicker().pickImage(source: src, maxWidth: 1280, imageQuality: 70);
      if (x == null) return;
      final dir = Directory('${app.docDir}/receipts');
      if (!await dir.exists()) await dir.create(recursive: true);
      final name = 'r_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(x.path).copy('${dir.path}/$name');
      _deletePhotoFile(l.photo);
      setState(() => l.photo = name);
      app.commitDays();
    } catch (e) {
      if (mounted) showSnack(context, t('Could not add photo: $e', 'फोटो थप्न सकिएन: $e', 'Photo thapna sakiyena: $e'));
    }
  }

  Future<void> _viewPhoto(Line l) async {
    if (l.photo == null || kIsWeb) return;
    final f = File(app.receiptPath(l.photo!));
    if (!f.existsSync()) return showSnack(context, t('Photo file not found', 'फोटो भेटिएन', 'Photo bhetiyena'));
    await showDialog(context: context, builder: (c) => Dialog(child: InteractiveViewer(child: Image.file(f))));
  }

  // ---- edit (can also delete) ----
  Future<void> _editLine(int i) async {
    final l = widget.day.lines[i];
    final a = TextEditingController(text: plainAmount(l.amount));
    final n = TextEditingController(text: l.note);
    var c = (l.cat != null && app.catById(l.cat) != null) ? l.cat! : '';
    var less = l.isLess;
    final res = await showDialog<String>(
        context: context,
        builder: (dc) => StatefulBuilder(
              builder: (dc, setS) => AlertDialog(
                title: Text(t('Edit', 'सच्याउनुहोस्', 'Edit')),
                content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: true, label: Text(t('Spent', 'खर्च', 'Kharcha'))),
                        ButtonSegment(value: false, label: Text(t('Received', 'आम्दानी', 'Aamdani'))),
                      ],
                      selected: {less},
                      onSelectionChanged: (s) => setS(() => less = s.first),
                    ),
                    TextField(
                        controller: a,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(labelText: t('Rs', 'रु.', 'Rs'))),
                    TextField(controller: n, decoration: InputDecoration(labelText: t('For what?', 'केको लागि?', 'Ke ko lagi?'))),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: c,
                      items: [
                        DropdownMenuItem(value: '', child: Text(withEmoji('🏷️', t('Uncategorized', 'वर्ग नतोकिएको', 'Uncategorized')))),
                        for (final cc in app.cats) DropdownMenuItem(value: cc.id, child: Text(catLabel(cc))),
                      ],
                      onChanged: (v) => setS(() => c = v ?? ''),
                    ),
                  ]),
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dc, 'delete'),
                      child: Text(t('Delete', 'मेट्नुहोस्', 'Delete'), style: const TextStyle(color: Colors.redAccent))),
                  TextButton(onPressed: () => Navigator.pop(dc, 'cancel'), child: Text(t('Cancel', 'रद्द', 'Cancel'))),
                  TextButton(onPressed: () => Navigator.pop(dc, 'save'), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
                ],
              ),
            ));
    if (res == 'delete') {
      _deleteLine(i);
      return;
    }
    if (res != 'save') return;
    final v = double.tryParse(a.text.trim());
    if (v == null || v <= 0) return;
    setState(() {
      l.isLess = less;
      l.amount = v;
      l.note = n.text.trim();
      l.cat = c.isEmpty ? null : c;
    });
    app.learn(l.note, l.cat);
    app.commitDays();
  }

  Widget _catChip() {
    final primary = Theme.of(context).colorScheme.primary;
    final co = app.catById(cat);
    final label = co == null
        ? withEmoji('🏷️', t('Uncategorized', 'वर्ग नतोकिएको', 'Uncategorized'))
        : catLabel(co);
    return PopupMenuButton<String>(
      tooltip: t('Category', 'वर्ग', 'Category'),
      onSelected: (v) {
        setState(() {
          if (v == '__auto') {
            catManual = false;
            cat = noteCtl.text.trim().isEmpty ? null : app.guessCat(noteCtl.text);
          } else if (v == '__none') {
            catManual = true;
            cat = null;
          } else {
            catManual = true;
            cat = v;
          }
        });
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: '__auto', child: Text(t('Auto-detect from my words', 'लेखेको शब्दबाट आफैं छान्ने', 'Lekheko shabda bata aafai chhana'))),
        PopupMenuItem(value: '__none', child: Text(t('Uncategorized', 'वर्ग नतोकिएको', 'Uncategorized'))),
        for (final c in app.cats) PopupMenuItem(value: c.id, child: Text(catLabel(c))),
      ],
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: co == null ? Colors.white24 : primary),
          borderRadius: BorderRadius.circular(8),
          color: co == null ? null : primary.withAlpha(40),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = app.st;
    final d = widget.day;
    final lim = st.limit;
    final ml = app.monthLess(d.date);
    final over = lim != null && ml > lim;
    final quick = app.quick.where((q) => q.less == isLess).toList();

    return AppBg(
      child: panel(
        title: dayTitle(d.date, st),
        barColor: over ? redDark : null,
        body: Column(children: [
          Expanded(
            child: d.lines.isEmpty
                ? Center(child: Text(t('Add your first line below', 'तल पहिलो हिसाब लेख्नुहोस्', 'Tala pahilo hisab lekha')))
                : ListView.builder(
                    itemCount: d.lines.length,
                    itemBuilder: (_, i) => ListTile(
                      dense: true,
                      title: lineWidget(d.lines[i]),
                      onLongPress: () => _lineMenu(i),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _editLine(i),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
                alignment: Alignment.centerLeft,
                child: Text(t('Tip: press and hold a line for photo / delete', 'सुझाव: फोटो / मेट्न लाइनमा थिचिराख्नुहोस्', 'Tip: photo / delete ko lagi hisab ma thichera rakha'),
                    style: const TextStyle(fontSize: 11, color: Colors.white38))),
          ),
          Container(
            width: double.infinity,
            color: over ? redStrong : Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.totalText, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (lim != null)
                Text(
                    t('Month: ${rs(ml)} of ${rs(lim)}${over ? "  —  over by ${rs(ml - lim)}" : ""}', 'यो महिना: ${rs(lim)} मध्ये ${rs(ml)}${over ? "  —  ${rs(ml - lim)} बढी" : ""}', 'Yo mahina: ${rs(lim)} bata ${rs(ml)}${over ? "  —  ${rs(ml - lim)} badhi" : ""}'),
                    style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                SizedBox(
                  height: 40,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    _catChip(),
                    for (final q in quick)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                            label: Text((emojiOn('cats') && app.catById(q.cat) != null) ? '${app.catById(q.cat)!.emoji} ${q.name}' : q.name),
                            onPressed: () => _useQuick(q)),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(t('Spent', 'खर्च', 'Kharcha'))),
                      ButtonSegment(value: false, label: Text(t('Received', 'आम्दानी', 'Aamdani'))),
                    ],
                    selected: {isLess},
                    onSelectionChanged: (s) => setState(() => isLess = s.first),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.access_time, size: 16),
                    label: Text(fmtTime(pickedTime ?? nowMins(), st.hour24)),
                    onPressed: _pickTime,
                  ),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: amountCtl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: t('Rs', 'रु.'), border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: noteCtl,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: _onNoteChanged,
                      onSubmitted: (_) => _addLine(),
                      decoration: InputDecoration(labelText: t('For what?', 'केको लागि?', 'Ke ko lagi?'), border: const OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(onPressed: _addLine, icon: const Icon(Icons.add)),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

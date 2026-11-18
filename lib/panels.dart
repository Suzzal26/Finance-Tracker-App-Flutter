import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'core.dart';
import 'export.dart';
import 'home.dart';
import 'notify.dart';

Widget _card(Widget child, {bool over = false}) => Card(
      color: cardColor(over),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );

Widget _header(BuildContext c, String text, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 12, 4),
      child: Row(children: [
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: Theme.of(c).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
        ),
        if (trailing != null) trailing,
      ]),
    );

// =====================================================================
//  REPORTS
// =====================================================================
class ReportsScreen extends StatefulWidget {
  final bool active;
  const ReportsScreen({super.key, required this.active});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  int idx = 0; // 0 = newest month that has entries

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return ListenableBuilder(listenable: app, builder: (c, _) => _build(c));
  }

  Future<void> _export(bool pdf, List<Day> ds, String titleEn) async {
    try {
      final sorted = [...ds]..sort((a, b) => a.date.compareTo(b.date));
      final ok = pdf ? await Exporter.pdf(sorted, titleEn) : await Exporter.csv(sorted, titleEn);
      if (mounted) showSnack(context, ok ? t('Saved', 'सुरक्षित भयो', 'Save bhayo') : t('Cancelled', 'रद्द भयो', 'Cancel bhayo'));
    } catch (e) {
      if (mounted) showSnack(context, t('Could not export: $e', 'निर्यात गर्न सकिएन: $e', 'Export garna sakiyena: $e'));
    }
  }

  Widget _build(BuildContext context) {
    final bs = app.bs;
    final groups = <int, List<Day>>{};
    final titles = <int, String>{};
    for (final d in app.days) {
      final m = monthOf(d.date, bs);
      groups.putIfAbsent(m.$1, () => []).add(d);
      titles[m.$1] = m.$2;
    }
    final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
    if (keys.isEmpty) {
      return panel(title: t('Reports', 'रिपोर्ट'), body: Center(child: Text(t('No data yet', 'अहिले डेटा छैन', 'Data chhaina'))));
    }
    if (idx >= keys.length) idx = keys.length - 1;
    final key = keys[idx];
    final ds = groups[key]!;
    final primary = Theme.of(context).colorScheme.primary;

    var less = 0.0, add = 0.0, bestDay = 0.0;
    DateTime? bestDayDate;
    final byCat = <String, double>{};
    final byWd = List<double>.filled(7, 0);
    final allLess = <(Line, DateTime)>[];
    final spendDays = <DateTime>{};
    for (final d in ds) {
      var dl = 0.0;
      for (final l in d.lines) {
        if (l.isLess) {
          less += l.amount;
          dl += l.amount;
          final ck = l.cat ?? '_';
          byCat[ck] = (byCat[ck] ?? 0) + l.amount;
          byWd[d.date.weekday - 1] += l.amount;
          allLess.add((l, d.date));
        } else {
          add += l.amount;
        }
      }
      if (dl > 0) spendDays.add(dateOnly(d.date));
      if (dl > bestDay) {
        bestDay = dl;
        bestDayDate = d.date;
      }
    }

    // count the days of this month so far, and the days with no spending
    final today = dateOnly(DateTime.now());
    var cur = monthFirstDay(ds.first.date, bs);
    var totalDays = 0, noSpend = 0, guard = 0;
    while (monthOf(cur, bs).$1 == key && !cur.isAfter(today) && guard++ < 40) {
      totalDays++;
      if (!spendDays.contains(cur)) noSpend++;
      cur = DateTime(cur.year, cur.month, cur.day + 1);
    }
    final avg = totalDays > 0 ? less / totalDays : 0.0;

    String? vsText;
    if (idx + 1 < keys.length) {
      final prev = groups[keys[idx + 1]]!.fold(0.0, (a, d) => a + d.less);
      if (prev > 0) {
        final pct = ((less - prev) / prev * 100).round();
        final pm = titles[keys[idx + 1]]!;
        vsText = pct >= 0
            ? t('▲ ${pct.abs()}% more than $pm', '▲ $pm भन्दा ${pct.abs()}% बढी', '▲ $pm bhanda ${pct.abs()}% badhi')
            : t('▼ ${pct.abs()}% less than $pm', '▼ $pm भन्दा ${pct.abs()}% कम', '▼ $pm bhanda ${pct.abs()}% kam');
        vsText = nd(vsText);
      }
    }

    final catList = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    allLess.sort((a, b) => b.$1.amount.compareTo(a.$1.amount));
    final top = allLess.take(5).toList();
    final maxWd = byWd.reduce((a, b) => a > b ? a : b);
    var bestWd = 0;
    for (var i = 0; i < 7; i++) {
      if (byWd[i] > byWd[bestWd]) bestWd = i;
    }
    final wdLetters = ne ? ['सो', 'मं', 'बु', 'बि', 'शु', 'श', 'आ'] : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final titleEn = monthTitleEn(ds.first.date, bs);

    return panel(
      title: t('Reports', 'रिपोर्ट'),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: idx < keys.length - 1 ? () => setState(() => idx++) : null),
          Text(titles[key]!, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primary)),
          IconButton(
              icon: const Icon(Icons.chevron_right), onPressed: idx > 0 ? () => setState(() => idx--) : null),
        ]),
        _card(Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _stat(t('Spent', 'खर्च', 'Kharcha'), rs(less), Colors.redAccent),
            _stat(t('Received', 'आम्दानी', 'Aamdani'), rs(add), Colors.greenAccent),
            _stat(t('Net', 'बचत', 'Bachat'), rs(add - less), (add - less) >= 0 ? Colors.greenAccent : Colors.redAccent),
          ]),
          if (vsText != null) ...[
            const SizedBox(height: 10),
            Text(vsText, style: const TextStyle(color: Colors.white70)),
          ],
        ])),
        _header(context, t('BY CATEGORY', 'वर्ग अनुसार', 'CATEGORY KO HISAB')),
        _card(Column(children: [
          if (catList.isEmpty) Text(t('No spending yet', 'खर्च छैन', 'Kharcha chhaina')),
          for (final e in catList)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                      child: Text(e.key == '_'
                          ? withEmoji('🏷️', t('Uncategorized', 'वर्ग नतोकिएको', 'Uncategorized'))
                          : (app.catById(e.key) == null ? t('Other', 'अन्य', 'Aru') : catLabel(app.catById(e.key)!)))),
                  Text('${rs(e.value)}  (${nd('${(e.value / less * 100).round()}')}%)',
                      style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
                ]),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                    value: less == 0 ? 0 : e.value / less,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(6),
                    backgroundColor: Colors.white12),
              ]),
            ),
        ])),
        _header(context, t('HIGHLIGHTS', 'मुख्य कुरा', 'MUKHYA KURA')),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _kv(t('Daily average', 'दैनिक औसत', 'Din ko ausat'), rs(avg)),
          _kv(t('No-spend days', 'खर्च नभएका दिन', 'Kharcha nabhako din'), nd('$noSpend / $totalDays')),
          if (bestDayDate != null)
            _kv(t('Biggest spending day', 'सबैभन्दा धेरै खर्च भएको दिन', 'Sabbhanda mahango din'), '${dateLabel(bestDayDate)}  •  ${rs(bestDay)}'),
        ])),
        _header(context, t('TOP 5 EXPENSES', 'ठूला ५ खर्च', 'TOP 5 MAHANGO KHARCHA')),
        _card(Column(children: [
          if (top.isEmpty) Text(t('No spending yet', 'खर्च छैन', 'Kharcha chhaina')),
          for (final e in top)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                    child: Text('${emojiOn('cats') ? (app.catById(e.$1.cat)?.emoji ?? '•') : '•'} ${e.$1.note.isEmpty ? t('(no note)', '(टिप्पणी छैन)', '(note chhaina)') : e.$1.note}')),
                Text('${rs(e.$1.amount)}  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(dateLabel(e.$2), style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
              ]),
            ),
        ])),
        _header(context, t('SPENDING BY WEEKDAY', 'बार अनुसार खर्च', 'BAR ANUSAR KHARCHA')),
        _card(Column(children: [
          SizedBox(
            height: 90,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Container(
                      height: maxWd == 0 ? 2 : 4 + 60 * byWd[i] / maxWd,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                          color: i == bestWd && maxWd > 0 ? primary : Colors.white24, borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(height: 4),
                    Text(wdLetters[i], style: const TextStyle(fontSize: 12)),
                  ]),
                ),
            ]),
          ),
          if (maxWd > 0) ...[
            const SizedBox(height: 8),
            Text(t('Most spending: ${weekdaysEn[bestWd]} (${rs(maxWd)})', 'सबैभन्दा धेरै खर्च: ${weekdaysNe[bestWd]} (${rs(maxWd)})', 'Sabbhanda dherai kharcha: ${weekdaysEn[bestWd]} (${rs(maxWd)})'),
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ],
        ])),
        _header(context, t('EXPORT THIS MONTH', 'यो महिना निर्यात', 'YO MAHINA EXPORT GARA')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => _export(true, ds, titleEn),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: () => _export(false, ds, titleEn),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: const Text('Excel (CSV)'))),
          ]),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
      ]);

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(k, style: const TextStyle(color: Colors.white70))),
          const SizedBox(width: 8),
          Flexible(child: Text(v, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

// =====================================================================
//  UDHARO
// =====================================================================
Future<void> _recordPayment(Udharo u, double amt, bool record) async {
  u.payments.add(Payment(DateTime.now(), amt));
  if (u.left <= 0) u.status = 'done';
  if (record) {
    // money received for something I lent = income, money I paid back = spending
    await app.addEntry(DateTime.now(), Line(!u.iGave, amt, t('Loan: ${u.person}', 'उधारो: ${u.person}', 'Udharo: ${u.person}'), time: nowMins()));
  }
  await app.udharoChanged();
}

Future<void> _askPayment(BuildContext ctx, Udharo u, {required bool full}) async {
  if (u.left <= 0) {
    u.status = 'done';
    await app.udharoChanged();
    return;
  }
  final c = TextEditingController(text: full ? plainAmount(u.left) : '');
  var record = true;
  final ok = await showDialog<bool>(
      context: ctx,
      builder: (dc) => StatefulBuilder(
            builder: (dc, setS) => AlertDialog(
              title: Text(full ? t('Mark completed', 'पूरा भयो', 'Pura bhayo') : t('Part payment', 'आंशिक भुक्तानी', 'Aanshik payment')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${u.person}  •  ${t('left', 'बाँकी', 'baki')} ${rs(u.left)}'),
                TextField(
                  controller: c,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '${t('Rs', 'रु.')} ', labelText: t('Amount', 'रकम', 'Rakam')),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: record,
                  onChanged: (v) => setS(() => record = v ?? true),
                  title: Text(t('Also record it in my expenses', 'मेरो हिसाबमा पनि लेख्नुहोस्', 'Mero hisab ma pani lekhdinu'), style: const TextStyle(fontSize: 13)),
                ),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('Cancel', 'रद्द'))),
                TextButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
              ],
            ),
          ));
  if (ok != true) return;
  var v = double.tryParse(c.text.trim());
  if (v == null || v <= 0) return;
  if (v > u.left) v = u.left;
  await _recordPayment(u, v, record);
}

Future<void> _payLater(BuildContext ctx, Udharo u) async {
  final tomorrow = DateTime.now().add(const Duration(days: 1));
  final picked = await showDatePicker(
      context: ctx, initialDate: tomorrow, firstDate: DateTime(2000), lastDate: DateTime(2090));
  if (picked == null) return;
  u.due = dateOnly(picked);
  await app.udharoChanged();
}

Future<void> _cancelUdharo(BuildContext ctx, Udharo u) async {
  final ok = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
            title: Text(t('Cancel this loan?', 'यो उधारो रद्द गर्ने?', 'Yo udharo cancel garne?')),
            content: Text(t('${u.person} • ${rs(u.left)} left. It will be moved to history and nothing will be written in your expenses.', '${u.person} • ${rs(u.left)} बाँकी। यो इतिहासमा जान्छ र हिसाबमा केही लेखिँदैन।', '${u.person} • ${rs(u.left)} baki. History ma jancha, hisab ma kei lekhindaina.')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('No', 'होइन', 'Hoina'))),
              TextButton(onPressed: () => Navigator.pop(c, true), child: Text(t('Yes, cancel', 'हो, रद्द', 'Ho, cancel'))),
            ],
          ));
  if (ok != true) return;
  u.status = 'cancelled';
  await app.udharoChanged();
}

Future<void> showUdharoActions(BuildContext ctx, Udharo u) async {
  final open = u.status == 'open';
  final act = await showModalBottomSheet<String>(
      context: ctx,
      builder: (c) => SafeArea(
            child: Wrap(children: [
              ListTile(title: Text('${u.person}  •  ${rs(u.left)}', style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(u.note)),
              if (open) ...[
                ListTile(leading: const Icon(Icons.payments_outlined), title: Text(t('Part payment', 'आंशिक भुक्तानी', 'Aanshik payment')), onTap: () => Navigator.pop(c, 'part')),
                ListTile(leading: const Icon(Icons.check_circle_outline), title: Text(t('Mark completed', 'पूरा भयो', 'Pura bhayo')), onTap: () => Navigator.pop(c, 'done')),
                ListTile(leading: const Icon(Icons.event_outlined), title: Text(t('Pay later (change date)', 'पछि तिर्ने (मिति सार्नुहोस्)', 'Pachi tirne (miti sarne)')), onTap: () => Navigator.pop(c, 'later')),
                ListTile(leading: const Icon(Icons.cancel_outlined), title: Text(t('Cancel this loan', 'उधारो रद्द गर्नुहोस्', 'Udharo cancel gara')), onTap: () => Navigator.pop(c, 'cancel')),
              ] else
                ListTile(leading: const Icon(Icons.delete_outline), title: Text(t('Delete record', 'रेकर्ड मेट्नुहोस्', 'Record delete gara')), onTap: () => Navigator.pop(c, 'delete')),
            ]),
          ));
  if (act == null || !ctx.mounted) return;
  if (act == 'part') await _askPayment(ctx, u, full: false);
  if (act == 'done') await _askPayment(ctx, u, full: true);
  if (act == 'later') await _payLater(ctx, u);
  if (act == 'cancel') await _cancelUdharo(ctx, u);
  if (act == 'delete') {
    app.udharo.remove(u);
    await app.udharoChanged();
  }
}

Future<void> showAddUdharo(BuildContext ctx, bool defaultGave) async {
  final person = TextEditingController();
  final amount = TextEditingController();
  final note = TextEditingController();
  var gave = defaultGave;
  DateTime? due;
  var remind = true;
  var record = true;
  final ok = await showDialog<bool>(
      context: ctx,
      builder: (dc) => StatefulBuilder(
            builder: (dc, setS) => AlertDialog(
              title: Text(t('New loan', 'नयाँ उधारो', 'Naya udharo')),
              content: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: true, label: Text(t('To receive', 'लिनुपर्ने', 'Linu parne'))),
                      ButtonSegment(value: false, label: Text(t('To pay', 'तिर्नुपर्ने', 'Tirnu parne'))),
                    ],
                    selected: {gave},
                    onSelectionChanged: (s) => setS(() => gave = s.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                        gave
                            ? t('I gave money. They will pay me back.', 'मैले पैसा दिएँ। उनले मलाई फिर्ता गर्नुपर्छ।', 'Maile paisa diye. Usle farkaunu parchha.')
                            : t('I took money. I must pay it back.', 'मैले पैसा लिएँ। मैले फिर्ता गर्नुपर्छ।', 'Maile paisa liye. Maile farkaunu parchha.'),
                        style: const TextStyle(fontSize: 12, color: Colors.white60)),
                  ),
                  TextField(controller: person, textCapitalization: TextCapitalization.words, decoration: InputDecoration(labelText: t('Person name', 'व्यक्तिको नाम', 'Manchhe ko naam'))),
                  TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(prefixText: '${t('Rs', 'रु.')} ', labelText: t('Amount', 'रकम', 'Rakam'))),
                  TextField(controller: note, decoration: InputDecoration(labelText: t('Note (optional)', 'टिप्पणी (नभए पनि हुन्छ)', 'Note (optional)'))),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(due == null ? t('No due date', 'फिर्ता मिति छैन', 'Miti chhaina') : dateLabel(due!)),
                        onPressed: () async {
                          final p = await showDatePicker(
                              context: dc,
                              initialDate: due ?? DateTime.now().add(const Duration(days: 7)),
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2090));
                          if (p != null) setS(() => due = dateOnly(p));
                        },
                      ),
                    ),
                    if (due != null) IconButton(icon: const Icon(Icons.close), onPressed: () => setS(() => due = null)),
                  ]),
                  if (due != null)
                    SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: remind,
                        onChanged: (v) => setS(() => remind = v),
                        title: Text(t('Remind me on that day', 'त्यो दिन सम्झाउनुहोस्', 'Tyo din yaad dilau'), style: const TextStyle(fontSize: 13))),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: record,
                    onChanged: (v) => setS(() => record = v ?? true),
                    title: Text(t('Also record it in today\'s expenses', 'आजको हिसाबमा पनि लेख्नुहोस्', 'Aaja ko hisab ma pani lekhdinu'), style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('Cancel', 'रद्द'))),
                TextButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
              ],
            ),
          ));
  if (ok != true) return;
  final amt = double.tryParse(amount.text.trim());
  if (person.text.trim().isEmpty || amt == null || amt <= 0) return;
  final u = Udharo(
      id: app.newId(), person: person.text.trim(), amount: amt, iGave: gave, note: note.text.trim(), due: due, remind: remind && due != null);
  app.udharo.add(u);
  if (record) {
    // lending = money goes out (spent), borrowing = money comes in (received)
    await app.addEntry(DateTime.now(), Line(gave, amt, t('Loan: ${u.person}', 'उधारो: ${u.person}', 'Udharo: ${u.person}'), time: nowMins()));
  }
  if (u.remind) await Notifier.askPermission(); // asked now, the first time a reminder is really needed
  await app.udharoChanged();
}

// Shown when the app opens and an udharo is due (or overdue)
Future<void> showDueUdharo(BuildContext ctx) async {
  await showDialog<void>(
      context: ctx,
      builder: (dc) => StatefulBuilder(
            builder: (dc, setS) {
              final due = app.dueUdharo();
              if (due.isEmpty) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (dc.mounted) Navigator.pop(dc);
                });
              }
              return AlertDialog(
                title: Text(t('Loan due!', 'उधारोको म्याद आयो!', 'Udharo ko miti aayo!'), style: const TextStyle(fontSize: 18)),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView(shrinkWrap: true, children: [
                    for (final u in due)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(
                              u.iGave
                                  ? t('${u.person} should pay you ${rs(u.left)}', '${u.person} ले तपाईंलाई ${rs(u.left)} तिर्नुपर्छ', '${u.person} le timilai ${rs(u.left)} tirnu parchha')
                                  : t('You should pay ${u.person} ${rs(u.left)}', 'तपाईंले ${u.person} लाई ${rs(u.left)} तिर्नुपर्छ', 'Timile ${u.person} lai ${rs(u.left)} tirnu parchha'),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('${t('Due', 'म्याद', 'Miti')}: ${dateLabel(u.due!)}', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                          Wrap(spacing: 4, children: [
                            TextButton(
                                onPressed: () async {
                                  await _askPayment(dc, u, full: true);
                                  setS(() {});
                                },
                                child: Text(t('Completed', 'पूरा भयो', 'Sakiyo'))),
                            TextButton(
                                onPressed: () async {
                                  await _payLater(dc, u);
                                  setS(() {});
                                },
                                child: Text(t('Pay later', 'पछि', 'Pachi'))),
                            TextButton(
                                onPressed: () async {
                                  await _cancelUdharo(dc, u);
                                  setS(() {});
                                },
                                child: Text(t('Cancel', 'रद्द'))),
                          ]),
                        ]),
                      ),
                  ]),
                ),
                actions: [TextButton(onPressed: () => Navigator.pop(dc), child: Text(t('Close', 'बन्द', 'Band')))],
              );
            },
          ));
}

class UdharoScreen extends StatefulWidget {
  const UdharoScreen({super.key});
  @override
  State<UdharoScreen> createState() => _UdharoScreenState();
}

class _UdharoScreenState extends State<UdharoScreen> {
  bool receive = true;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (c, _) => _build(c));

  Widget _tile(Udharo u) {
    final today = dateOnly(DateTime.now());
    final overdue = u.status == 'open' && u.due != null && dateOnly(u.due!).isBefore(today);
    final dueToday = u.status == 'open' && u.due != null && dateOnly(u.due!) == today;
    String dueText = '';
    if (u.due != null) {
      dueText = overdue
          ? '${t('Overdue', 'म्याद नाघ्यो', 'Miti naghyo')}: ${dateLabel(u.due!)}'
          : (dueToday ? t('Due today', 'आज म्याद', 'Aaja miti') : '${t('Due', 'म्याद', 'Miti')}: ${dateLabel(u.due!)}');
    }
    final status = u.status == 'done'
        ? t('Completed', 'सकिएको', 'Sakiyo')
        : (u.status == 'cancelled' ? t('Cancelled', 'रद्द', 'Cancel bhayo') : '');
    return Opacity(
      opacity: u.status == 'open' ? 1 : 0.6,
      child: Card(
        color: cardColor(overdue),
        margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
        child: ListTile(
          onTap: () => showUdharoActions(context, u),
          title: Text(u.person, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text([
            if (u.paid > 0) '${t('Total', 'जम्मा', 'Jamma')} ${rs(u.amount)}  •  ${t('Paid', 'तिरेको', 'Tireko')} ${rs(u.paid)}',
            if (dueText.isNotEmpty) dueText,
            if (status.isNotEmpty) status,
            if (u.note.isNotEmpty) u.note,
          ].join('\n')),
          isThreeLine: u.paid > 0 || u.note.isNotEmpty,
          trailing: Text(rs(u.status == 'open' ? u.left : u.amount),
              style: TextStyle(fontWeight: FontWeight.bold, color: receive ? Colors.greenAccent : Colors.redAccent)),
        ),
      ),
    );
  }

  Widget _build(BuildContext context) {
    final open = app.udharo.where((u) => u.iGave == receive && u.status == 'open').toList()
      ..sort((a, b) => (a.due ?? DateTime(2100)).compareTo(b.due ?? DateTime(2100)));
    final past = app.udharo.where((u) => u.iGave == receive && u.status != 'open').toList()
      ..sort((a, b) => b.created.compareTo(a.created));
    final total = open.fold(0.0, (a, u) => a + u.left);
    return panel(
      title: t('Loans', 'उधारो', 'Udharo'),
      fab: FloatingActionButton.extended(heroTag: null, 
          onPressed: () => showAddUdharo(context, receive), icon: const Icon(Icons.add), label: Text(t('Add', 'थप्नुहोस्', 'Thap'))),
      body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: true, label: Text(t('To receive', 'लिनुपर्ने', 'Linu parne'))),
              ButtonSegment(value: false, label: Text(t('To pay', 'तिर्नुपर्ने', 'Tirnu parne'))),
            ],
            selected: {receive},
            onSelectionChanged: (s) => setState(() => receive = s.first),
          ),
        ),
        _card(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(receive ? t('Total to receive', 'जम्मा लिनुपर्ने', 'Jamma linu parne') : t('Total to pay', 'जम्मा तिर्नुपर्ने', 'Jamma tirnu parne')),
          Text(rs(total), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: receive ? Colors.greenAccent : Colors.redAccent)),
        ])),
        if (open.isEmpty)
          Padding(
              padding: const EdgeInsets.all(30),
              child: Center(child: Text(t('Nothing here. Tap "Add" to note a loan.', 'यहाँ केही छैन। उधारो लेख्न "थप्नुहोस्" थिच्नुहोस्।', 'Yaha kei chhaina. Udharo lekhna "Thap" thich.'), textAlign: TextAlign.center))),
        for (final u in open) _tile(u),
        if (past.isNotEmpty) _header(context, t('HISTORY', 'इतिहास', 'ITIHAS')),
        for (final u in past) _tile(u),
      ]),
    );
  }
}

// =====================================================================
//  BUDGET (monthly limit + categories)
// =====================================================================
class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});
  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (c, _) => _build(c));

  Future<void> _setCatLimit(Cat c) async {
    final ctl = TextEditingController(text: c.limit == null ? '' : plainAmount(c.limit!));
    final res = await showDialog<String>(
        context: context,
        builder: (dc) => AlertDialog(
              title: Text(catLabel(c)),
              content: TextField(
                controller: ctl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(prefixText: '${t('Rs', 'रु.')} ', labelText: t('Monthly limit', 'मासिक सीमा', 'Mahina ko limit')),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc, '__clear'), child: Text(t('No limit', 'सीमा छैन', 'Limit chhaina'))),
                TextButton(onPressed: () => Navigator.pop(dc), child: Text(t('Cancel', 'रद्द'))),
                TextButton(onPressed: () => Navigator.pop(dc, ctl.text), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
              ],
            ));
    if (res == null) return;
    if (res == '__clear') {
      c.limit = null;
    } else {
      final v = double.tryParse(res.trim());
      if (v == null || v <= 0) return;
      c.limit = v;
    }
    app.refresh();
    await app.saveCats();
  }

  Future<void> _editCat(Cat? c) async {
    final name = TextEditingController(text: c?.name ?? '');
    final emoji = TextEditingController(text: c?.emoji ?? '📦');
    final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
              title: Text(c == null ? t('Add category', 'वर्ग थप्नुहोस्', 'Category thap') : t('Rename', 'नाम बदल्नुहोस्', 'Naam badal')),
              content: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: t('Name', 'नाम', 'Naam'))),
                TextField(controller: emoji, decoration: InputDecoration(labelText: t('Emoji', 'इमोजी'))),
              ]),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('Cancel', 'रद्द'))),
                TextButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
              ],
            ));
    if (ok != true || name.text.trim().isEmpty) return;
    final em = emoji.text.trim().isEmpty ? '📦' : emoji.text.trim();
    if (c == null) {
      app.cats.add(Cat('c${app.newId()}', name.text.trim(), name.text.trim(), em, rom: name.text.trim()));
    } else {
      c.en = name.text.trim();
      c.nep = name.text.trim();
      c.rom = name.text.trim();
      c.emoji = em;
    }
    app.refresh();
    await app.saveCats();
  }

  Future<void> _deleteCat(Cat c) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
              title: Text(t('Delete "${c.name}"?', '"${c.name}" मेट्ने?', '"${c.name}" delete garne?')),
              content: Text(t('Old entries stay, they just lose this label.', 'पुराना हिसाब रहन्छन्, यो वर्ग मात्र हट्छ।', 'Purana hisab rahanchha, yo label matra jancha.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('Cancel', 'रद्द'))),
                TextButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('Delete', 'मेट्नुहोस्'))),
              ],
            ));
    if (ok != true) return;
    app.cats.remove(c);
    app.refresh();
    await app.saveCats();
  }

  Widget _build(BuildContext context) {
    final st = app.st;
    final now = DateTime.now();
    final spent = app.monthLess(now);
    final lim = st.limit;
    final over = lim != null && spent > lim;
    return panel(
      title: t('Budget', 'बजेट'),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        _header(context, t('MONTHLY LIMIT', 'मासिक सीमा', 'MAHINA KO LIMIT')),
        _card(
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(lim == null ? t('Not set (optional)', 'तोकिएको छैन (नतोके पनि हुन्छ)', 'Rakheko chhaina (optional)') : rs(lim),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                FilledButton.tonal(onPressed: () => showLimitDialog(context), child: Text(lim == null ? t('Set', 'तोक्नुहोस्', 'Rakha') : t('Change', 'बदल्नुहोस्', 'Badal'))),
              ]),
              if (lim != null) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                    value: (spent / lim).clamp(0.0, 1.0).toDouble(),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: over ? Colors.white : null,
                    backgroundColor: Colors.white12),
                const SizedBox(height: 6),
                Text(
                    over
                        ? t('${rs(spent)} spent, over by ${rs(spent - lim)}', '${rs(spent)} खर्च, ${rs(spent - lim)} बढी', '${rs(spent)} kharcha, ${rs(spent - lim)} badhi')
                        : t('${rs(spent)} spent, ${rs(lim - spent)} left', '${rs(spent)} खर्च, ${rs(lim - spent)} बाँकी', '${rs(spent)} kharcha, ${rs(lim - spent)} baki'),
                    style: const TextStyle(fontSize: 12.5)),
              ],
              const SizedBox(height: 6),
              Text(t('You get an alert and the screen turns dark red when you pass the limit. It never blocks you.', 'सीमा नाघ्दा अलर्ट आउँछ र स्क्रिन गाढा रातो हुन्छ। यसले केही रोक्दैन।', 'Limit nagheko bela alert aauchha ra screen dark red hunchha. Tara kehi rokdaina.'),
                  style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
            ]),
            over: over),
        _header(context, t('CATEGORIES (this month)', 'वर्गहरू (यो महिना)', 'CATEGORY (yo mahina)'),
            trailing: TextButton.icon(onPressed: () => _editCat(null), icon: const Icon(Icons.add, size: 18), label: Text(t('Add', 'थप्नुहोस्', 'Thap')))),
        for (final c in app.cats) _catTile(c, now),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: TextButton(
                onPressed: () async {
                  app.cats = defaultCats();
                  app.refresh();
                  await app.saveCats();
                },
                child: Text(t('Restore default categories', 'सुरुका वर्गहरू फिर्ता ल्याउनुहोस्', 'Suru ko category pharkau'))),
          ),
        ),
      ]),
    );
  }

  Widget _catTile(Cat c, DateTime now) {
    final spent = app.monthLess(now, cat: c.id);
    final lim = c.limit;
    final over = lim != null && spent > lim;
    return Card(
      color: cardColor(over),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ListTile(
        onTap: () => _setCatLimit(c),
        leading: emojiOn('cats') ? Text(c.emoji, style: const TextStyle(fontSize: 24)) : null,
        title: Text(c.name),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lim == null ? '${t('Spent', 'खर्च', 'Kharcha')} ${rs(spent)}  •  ${t('No limit', 'सीमा छैन', 'Limit chhaina')}' : '${rs(spent)} / ${rs(lim)}',
              style: const TextStyle(fontSize: 12.5)),
          if (lim != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                  value: (spent / lim).clamp(0.0, 1.0).toDouble(),
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(5),
                  color: over ? Colors.white : null,
                  backgroundColor: Colors.white12),
            ),
        ]),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'limit') _setCatLimit(c);
            if (v == 'edit') _editCat(c);
            if (v == 'del') _deleteCat(c);
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'limit', child: Text(t('Set limit', 'सीमा तोक्नुहोस्', 'Limit rakha'))),
            PopupMenuItem(value: 'edit', child: Text(t('Rename', 'नाम बदल्नुहोस्', 'Naam badal'))),
            PopupMenuItem(value: 'del', child: Text(t('Delete', 'मेट्नुहोस्'))),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
//  SETTINGS
// =====================================================================
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Settings get st => app.st;

  Future<void> _save() async {
    await st.save();
    app.refresh();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: app, builder: (c, _) => _build(c));

  Future<void> _backupNow() async {
    if (kIsWeb) return showSnack(context, t('Backup works on the phone only', 'ब्याकअप फोनमा मात्र चल्छ', 'Backup phone ma matra chalchha'));
    try {
      await Backup.write(tag: 'manual');
      st.lastBackup = DateTime.now();
      await _save();
      if (mounted) showSnack(context, t('Backup saved inside the app', 'ब्याकअप एप भित्र सुरक्षित भयो', 'Backup app bhitra save bhayo'));
    } catch (e) {
      if (mounted) showSnack(context, t('Backup failed: $e', 'ब्याकअप भएन: $e', 'Backup bhayena: $e'));
    }
  }

  Future<void> _saveCopy() async {
    try {
      final ok = await Backup.saveCopy();
      if (ok) {
        st.lastBackup = DateTime.now();
        await _save();
      }
      if (mounted) showSnack(context, ok ? t('Backup copy saved', 'ब्याकअप कपी सुरक्षित भयो', 'Backup copy save bhayo') : t('Cancelled', 'रद्द भयो', 'Cancel bhayo'));
    } catch (e) {
      if (mounted) showSnack(context, t('Could not save: $e', 'सुरक्षित गर्न सकिएन: $e', 'Save garna sakiyena: $e'));
    }
  }

  Future<void> _confirmRestore(BackupData b, String label) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => AlertDialog(
              title: Text(t('Restore this backup?', 'यो ब्याकअप फिर्ता ल्याउने?', 'Yo backup pharkaune?')),
              content: Text(t('$label\n${b.days.length} days of records.\n\nThis replaces what is in the app now. A safety copy of your current data is saved first.', '$label\n${b.days.length} दिनको हिसाब।\n\nयसले अहिलेको डेटा बदल्छ। पहिले अहिलेको डेटाको सुरक्षित कपी बन्छ।', '$label\n${b.days.length} din ko hisab.\n\nYesle ahile ko data replace garchha. Pahila ahile ko data ko safety copy banchha.')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('Cancel', 'रद्द'))),
                TextButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('Restore', 'फिर्ता ल्याउनुहोस्', 'Pharkau'))),
              ],
            ));
    if (ok != true) return;
    try {
      await Backup.write(tag: 'before_restore');
    } catch (_) {}
    await app.restoreAll(b);
    if (mounted) showSnack(context, t('Restored ${b.days.length} days', '${b.days.length} दिन फिर्ता आयो', '${b.days.length} din pharkiyo'));
  }

  Future<void> _restoreFromFile() async {
    try {
      final f = await FilePicker.pickFile();
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final b = Backup.decode(utf8.decode(bytes));
      if (b == null) return showSnack(context, t('That file is not a valid K.S.H.K backup', 'यो फाइल मान्य ब्याकअप होइन', 'Yo file valid K.S.H.K backup haina'));
      await _confirmRestore(b, f.name);
    } catch (e) {
      if (mounted) showSnack(context, t('Could not read file: $e', 'फाइल पढ्न सकिएन: $e', 'File padhna sakiyena: $e'));
    }
  }

  Future<void> _restoreFromApp() async {
    if (kIsWeb) return showSnack(context, t('Restore works on the phone only', 'फिर्ता ल्याउने फोनमा मात्र चल्छ', 'Restore phone ma matra chalchha'));
    try {
      final files = await Backup.list();
      if (!mounted) return;
      if (files.isEmpty) return showSnack(context, t('No backups inside the app yet', 'एप भित्र अहिले ब्याकअप छैन', 'App bhitra backup chhaina'));
      final pick = await showDialog<File>(
          context: context,
          builder: (dc) => SimpleDialog(
                title: Text(t('Choose a backup', 'ब्याकअप छान्नुहोस्', 'Backup chhana')),
                children: [
                  for (final f in files)
                    SimpleDialogOption(onPressed: () => Navigator.pop(dc, f), child: Text(f.uri.pathSegments.last, style: const TextStyle(fontSize: 13))),
                ],
              ));
      if (pick == null) return;
      final b = Backup.decode(await pick.readAsString());
      if (b == null) return showSnack(context, t('That backup file is damaged', 'यो ब्याकअप बिग्रिएको छ', 'Yo backup file bigreko chha'));
      await _confirmRestore(b, pick.uri.pathSegments.last);
    } catch (e) {
      if (mounted) showSnack(context, t('Could not restore: $e', 'फिर्ता ल्याउन सकिएन: $e', 'Restore garna sakiyena: $e'));
    }
  }

  Future<void> _pickBg() async {
    if (kIsWeb) return showSnack(context, t('Backgrounds work on the phone only', 'ब्याकग्राउन्ड फोनमा मात्र चल्छ', 'Background phone ma matra chalchha'));
    try {
      final f = await FilePicker.pickFile(type: FileType.image);
      if (f == null) return;
      final bytes = await f.readAsBytes();
      final dir = await getApplicationDocumentsDirectory();
      final out = File('${dir.path}/bg_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await out.writeAsBytes(bytes);
      final old = st.bgPath;
      st.bgPath = out.path;
      await _save();
      if (old != null) {
        try {
          await File(old).delete();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) showSnack(context, t('Could not set background: $e', 'ब्याकग्राउन्ड राख्न सकिएन: $e', 'Background rakhna sakiyena: $e'));
    }
  }

  Widget _build(BuildContext context) {
    final lb = st.lastBackup;
    final now = DateTime.now();
    return panel(
      title: t('Settings', 'सेटिङ'),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        _header(context, t('LANGUAGE', 'भाषा', 'BHASHA')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'rom', label: Text('Roman')),
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'ne', label: Text('नेपाली')),
            ],
            selected: {st.lang},
            onSelectionChanged: (s) async {
              st.lang = s.first;
              st.langChosen = true;
              app.applyLang();
              await _save();
              Notifier.reschedule();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(
              t('Roman = Nepali words in English letters, with a fun tone.', 'Roman = अंग्रेजी अक्षरमा नेपाली शब्द, रमाइलो शैलीमा।',
                  'Roman = Nepali shabda English akshar ma, ramailo style ma (default).'),
              style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ),
        if (st.lang == 'ne')
          SwitchListTile(
            value: st.nepDigits,
            onChanged: (v) async {
              st.nepDigits = v;
              app.applyLang();
              await _save();
            },
            title: const Text('नेपाली अंक (१२३)'),
          ),
        _header(context, t('THEME', 'थिम', 'THEME')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 10, runSpacing: 12, children: [
            for (final th in appThemes)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  st.theme = th.id;
                  await _save();
                },
                child: SizedBox(
                  width: 74,
                  child: Column(children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: th.seed,
                        border: Border.all(color: st.theme == th.id ? Colors.white : Colors.white24, width: st.theme == th.id ? 3 : 1),
                      ),
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: th.card, border: Border.all(color: Colors.white24)),
                          child: st.theme == th.id ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(th.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
          ]),
        ),
        _header(context, t('EMOJIS', 'इमोजी', 'EMOJI')),
        SwitchListTile(
          value: st.emojiAll,
          onChanged: (v) async {
            st.emojiAll = v;
            await _save();
            Notifier.reschedule();
          },
          title: Text(t('Show emojis', 'इमोजी देखाउने', 'Emoji dekhau')),
          subtitle: Text(t('Turn all emojis off, or choose where they appear.', 'सबै इमोजी बन्द गर्न वा कहाँ देखाउने छान्न सकिन्छ।',
              'Sabai emoji band garna ya kahaa dekhaune chhana.')),
        ),
        if (st.emojiAll) ...[
          SwitchListTile(
            value: st.emojiEntries,
            onChanged: (v) async {
              st.emojiEntries = v;
              await _save();
            },
            title: Text(t('On entries (category icon)', 'हिसाबमा (वर्गको चिन्ह)', 'Hisab ma (category ko emoji)')),
          ),
          SwitchListTile(
            value: st.emojiCats,
            onChanged: (v) async {
              st.emojiCats = v;
              await _save();
            },
            title: Text(t('In categories, buttons and reports', 'वर्ग, बटन र रिपोर्टमा', 'Category, button ra report ma')),
          ),
          SwitchListTile(
            value: st.emojiMsgs,
            onChanged: (v) async {
              st.emojiMsgs = v;
              await _save();
              Notifier.reschedule();
            },
            title: Text(t('In messages and reminders', 'सन्देश र सम्झनामा', 'Message ra reminder ma')),
          ),
        ],
        _header(context, t('DATE DISPLAY', 'मिति देखाउने तरिका', 'MITI KASARI DEKHAUNE')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<DateMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: DateMode.both, label: Text(t('BS + AD', 'वि.सं. + ई.सं.'))),
              ButtonSegment(value: DateMode.bs, label: Text(t('BS only', 'वि.सं.'))),
              ButtonSegment(value: DateMode.ad, label: Text(t('AD only', 'ई.सं.'))),
            ],
            selected: {st.dateMode},
            onSelectionChanged: (s) async {
              st.dateMode = s.first;
              await _save();
            },
          ),
        ),
        _header(context, t('TIME', 'समय', 'SAMAY')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, label: Text(t('12 hour (AM/PM)', '१२ घण्टे (AM/PM)', '12 ghante (AM/PM)'))),
              ButtonSegment(value: true, label: Text(t('24 hour', '२४ घण्टे', '24 ghante'))),
            ],
            selected: {st.hour24},
            onSelectionChanged: (s) async {
              st.hour24 = s.first;
              await _save();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
              '${t('Now', 'अहिले', 'Ahile')}: ${fmtTime(now.hour * 60 + now.minute, st.hour24)}   •   ${t('Time zone from your phone', 'फोनको समय क्षेत्र', 'Phone ko time zone')}: ${nd(tzText())}',
              style: const TextStyle(color: Colors.white60, fontSize: 12.5)),
        ),
        _header(context, t('REMINDERS', 'सम्झना', 'REMINDER')),
        SwitchListTile(
          value: st.reminders,
          onChanged: (v) async {
            if (v) {
              if (kIsWeb) return showSnack(context, t('Reminders work on the phone only', 'सम्झना फोनमा मात्र चल्छ', 'Reminder phone ma matra chalchha'));
              final ok = await Notifier.askPermission();
              if (!ok) {
                if (mounted) showSnack(context, t('Notifications are blocked for this app in phone settings.', 'फोन सेटिङमा यो एपको नोटिफिकेसन बन्द छ।', 'Phone settings ma yo app ko notification band chha.'));
                return;
              }
            }
            st.reminders = v;
            st.askedReminder = true;
            await _save();
            Notifier.reschedule();
          },
          title: Text(t('Nightly reminder', 'रातको सम्झना', 'Raat ko reminder')),
          subtitle: Text(t('Only if you have not written any entry that day.', 'त्यो दिन कुनै हिसाब नलेखेको खण्डमा मात्र।', 'Tyo din kei hisab nalekheko bhaye matra.')),
        ),
        if (st.reminders)
          ListTile(
            leading: const Icon(Icons.alarm),
            title: Text(t('Reminder time', 'सम्झना समय', 'Reminder samay')),
            trailing: Text(fmtTime(st.remHour * 60 + st.remMin, st.hour24), style: const TextStyle(fontWeight: FontWeight.bold)),
            onTap: () async {
              final r = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(hour: st.remHour, minute: st.remMin),
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: st.hour24), child: child!),
              );
              if (r == null) return;
              st.remHour = r.hour;
              st.remMin = r.minute;
              await _save();
              Notifier.reschedule();
            },
          ),
        _header(context, t('MORE TOOLS', 'थप सुविधा', 'THAP SUVIDHA')),
        ListTile(
          leading: const Icon(Icons.bolt_outlined),
          title: Text(t('Quick-add items', 'छिटो थप्ने सामान', 'Chhito thapne saman')),
          subtitle: Text(t('Petrol, snacks, bus fare… make your own', 'पेट्रोल, खाजा, बस भाडा… आफ्नै बनाउनुहोस्', 'Petrol, khaja, bus bhada… aafai banau')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickAddScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.autorenew),
          title: Text(t('Repeating entries', 'दोहोरिने हिसाब', 'Dohorine hisab')),
          subtitle: Text(t('Rent, salary, internet… added by themselves', 'घर भाडा, तलब, इन्टरनेट… आफैं थपिन्छ', 'Ghar bhada, talab, internet… aafai thapinchha')),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecurringScreen())),
        ),
        _header(context, t('BACKUP', 'ब्याकअप')),
        SwitchListTile(
          value: st.autoBackup,
          onChanged: (v) async {
            st.autoBackup = v;
            await _save();
          },
          title: Text(t('Auto backup every 10 days', 'हरेक १० दिनमा आफैं ब्याकअप', 'Har 10 din ma auto backup')),
          subtitle: Text(t('Saved inside the app folder. Removed if the app is uninstalled.', 'एपको फोल्डर भित्र रहन्छ। एप हटाए यो पनि हट्छ।', 'App folder bhitra baschha. App hataye yo pani jancha.')),
        ),
        ListTile(
          leading: const Icon(Icons.history),
          title: Text(lb == null ? t('No backup yet', 'अहिलेसम्म ब्याकअप छैन', 'Backup chhaina') : '${t('Last backup', 'पछिल्लो ब्याकअप', 'Pachhillo backup')}: ${dateLabel(lb)}, ${fmtTime(lb.hour * 60 + lb.minute, st.hour24)}'),
        ),
        ListTile(leading: const Icon(Icons.backup_outlined), title: Text(t('Back up now', 'अहिले ब्याकअप लिनुहोस्', 'Ahile backup lau')), onTap: _backupNow),
        ListTile(
            leading: const Icon(Icons.save_alt),
            title: Text(t('Save a copy to phone storage', 'फोनको स्टोरेजमा कपी राख्नुहोस्', 'Phone storage ma copy rakha')),
            subtitle: Text(t('Choose Downloads or Documents. Survives uninstall.', 'Downloads वा Documents छान्नुहोस्। एप हटाए पनि रहन्छ।', 'Downloads ya Documents chhana. App hataye pani rahanchha.')),
            onTap: _saveCopy),
        ListTile(leading: const Icon(Icons.restore), title: Text(t('Restore from a backup in the app', 'एप भित्रको ब्याकअपबाट फिर्ता', 'App bhitra ko backup bata pharkau')), onTap: _restoreFromApp),
        ListTile(leading: const Icon(Icons.folder_open), title: Text(t('Restore from a file', 'फाइलबाट फिर्ता ल्याउनुहोस्', 'File bata pharkau')), onTap: _restoreFromFile),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(t('Receipt photos are kept on the phone and are not inside the backup file.', 'रसिदका फोटो फोनमै रहन्छन्, ब्याकअप फाइलमा हुँदैनन्।', 'Receipt ko photo phone mai baschha, backup file ma hudaina.'),
              style: const TextStyle(fontSize: 11.5, color: Colors.white54)),
        ),
        _header(context, t('BACKGROUND', 'ब्याकग्राउन्ड')),
        ListTile(leading: const Icon(Icons.wallpaper), title: Text(t('Choose a picture from gallery', 'ग्यालरीबाट फोटो छान्नुहोस्', 'Gallery bata photo chhana')), onTap: _pickBg),
        if (st.bgPath != null) ...[
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text(t('Darkness over the picture', 'फोटोमाथि कालोपन', 'Photo mathi kalopan')),
            subtitle: Slider(
              value: st.bgDim,
              min: 0.3,
              max: 0.9,
              onChanged: (v) {
                st.bgDim = v;
                app.refresh();
              },
              onChangeEnd: (_) => st.save(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.hide_image_outlined),
            title: Text(t('Use default black background', 'सामान्य कालो ब्याकग्राउन्ड', 'Default kalo background')),
            onTap: () async {
              st.bgPath = null;
              await _save();
            },
          ),
        ],
        _header(context, t('ABOUT', 'यस एपबारे', 'YO APP BAARE')),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(appName),
          subtitle: Text('K.S.H.K  •  ${t('Version', 'संस्करण')} ${nd(appVersion)}\n${t('All data stays on this phone', 'सबै डेटा यही फोनमा रहन्छ', 'Sab data yehi phone ma baschha')}'),
          isThreeLine: true,
        ),
      ]),
    );
  }
}

// =====================================================================
//  QUICK-ADD ITEMS
// =====================================================================
class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({super.key});
  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  Future<void> _edit(QuickItem? q) async {
    final name = TextEditingController(text: q?.name ?? '');
    final amt = TextEditingController(text: q?.amt == null ? '' : plainAmount(q!.amt!));
    var cat = '';
    if (q != null && q.cat != null && app.catById(q.cat) != null) cat = q.cat!;
    var less = q?.less ?? true;
    final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => StatefulBuilder(
              builder: (dc, setS) => AlertDialog(
                title: Text(q == null ? t('New quick-add item', 'नयाँ छिटो थप्ने सामान', 'Naya chhito saman') : t('Edit', 'सच्याउनुहोस्')),
                content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: t('Name (e.g. Petrol)', 'नाम (जस्तै: पेट्रोल)', 'Naam (jastai: Petrol)'))),
                    TextField(
                        controller: amt,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(prefixText: '${t('Rs', 'रु.')} ', labelText: t('Usual amount (optional)', 'सामान्य रकम (नभए पनि हुन्छ)', 'Sadharan rakam (optional)'))),
                    const SizedBox(height: 10),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: cat,
                      items: [
                        DropdownMenuItem(value: '', child: Text(t('Uncategorized', 'वर्ग नतोकिएको', 'Uncategorized'))),
                        for (final c in app.cats) DropdownMenuItem(value: c.id, child: Text(catLabel(c))),
                      ],
                      onChanged: (v) => setS(() => cat = v ?? ''),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: true, label: Text(t('Spent', 'खर्च', 'Kharcha'))),
                        ButtonSegment(value: false, label: Text(t('Received', 'आम्दानी', 'Aamdani'))),
                      ],
                      selected: {less},
                      onSelectionChanged: (s) => setS(() => less = s.first),
                    ),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('Cancel', 'रद्द'))),
                  TextButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
                ],
              ),
            ));
    if (ok != true || name.text.trim().isEmpty) return;
    final a = double.tryParse(amt.text.trim());
    final cc = cat.isEmpty ? null : cat;
    if (q == null) {
      app.quick.add(QuickItem('q${app.newId()}', name.text.trim(), name.text.trim(), rom: name.text.trim(), cat: cc, amt: a, less: less));
    } else {
      q.en = name.text.trim();
      q.nep = name.text.trim();
      q.rom = name.text.trim();
      q.cat = cc;
      q.amt = a;
      q.less = less;
    }
    app.refresh();
    await app.saveQuick();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => subPage(
          title: t('Quick-add items', 'छिटो थप्ने सामान', 'Chhito thapne saman'),
          fab: FloatingActionButton.extended(heroTag: null, onPressed: () => _edit(null), icon: const Icon(Icons.add), label: Text(t('New item', 'नयाँ', 'Naya'))),
          body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t('These appear as buttons when you write an entry. Tap one to fill the name, category and amount at once.', 'हिसाब लेख्दा यी बटनका रूपमा देखिन्छन्। एक थिचेर नाम, वर्ग र रकम भरिन्छ।', 'Hisab lekhda yi button ko roop ma dekhinchhan. Ek thichda naam, category ra rakam eutai palta bharinchha.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            for (final q in app.quick)
              Card(
                color: cardColor(false),
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ListTile(
                  onTap: () => _edit(q),
                  leading: emojiOn('cats') ? Text(app.catById(q.cat)?.emoji ?? '🏷️', style: const TextStyle(fontSize: 22)) : null,
                  title: Text(q.name),
                  subtitle: Text([
                    q.less ? t('Spent', 'खर्च', 'Kharcha') : t('Received', 'आम्दानी', 'Aamdani'),
                    if (q.amt != null) rs(q.amt!),
                  ].join('  •  ')),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      app.quick.remove(q);
                      app.refresh();
                      await app.saveQuick();
                    },
                  ),
                ),
              ),
            Center(
              child: TextButton(
                  onPressed: () async {
                    app.quick = defaultQuick();
                    app.refresh();
                    await app.saveQuick();
                  },
                  child: Text(t('Restore default items', 'सुरुका सामान फिर्ता ल्याउनुहोस्', 'Suru ka saman pharkau'))),
            ),
          ]),
        ),
      );
}

// =====================================================================
//  REPEATING ENTRIES
// =====================================================================
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  Future<void> _add() async {
    final amt = TextEditingController();
    final note = TextEditingController();
    var less = true;
    var cat = '';
    var freq = 'monthly';
    var weekday = 1;
    var monthDay = 1;
    var bs = app.bs;
    final ok = await showDialog<bool>(
        context: context,
        builder: (dc) => StatefulBuilder(
              builder: (dc, setS) => AlertDialog(
                title: Text(t('New repeating entry', 'नयाँ दोहोरिने हिसाब', 'Naya dohorine hisab')),
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
                        controller: amt,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(prefixText: '${t('Rs', 'रु.')} ', labelText: t('Amount', 'रकम', 'Rakam'))),
                    TextField(controller: note, decoration: InputDecoration(labelText: t('For what? (e.g. House rent)', 'केको लागि? (जस्तै: घर भाडा)', 'Ke ko lagi? (jastai: Ghar Bhada)'))),
                    const SizedBox(height: 8),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: cat,
                      items: [
                        DropdownMenuItem(value: '', child: Text(t('Uncategorized', 'वर्ग नतोकिएको', 'Uncategorized'))),
                        for (final c in app.cats) DropdownMenuItem(value: c.id, child: Text(catLabel(c))),
                      ],
                      onChanged: (v) => setS(() => cat = v ?? ''),
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<String>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment(value: 'daily', label: Text(t('Daily', 'दिनहुँ', 'Roj'))),
                        ButtonSegment(value: 'weekly', label: Text(t('Weekly', 'साप्ताहिक', 'Haptaa'))),
                        ButtonSegment(value: 'monthly', label: Text(t('Monthly', 'मासिक', 'Mahina'))),
                      ],
                      selected: {freq},
                      onSelectionChanged: (s) => setS(() => freq = s.first),
                    ),
                    if (freq == 'weekly')
                      DropdownButton<int>(
                        isExpanded: true,
                        value: weekday,
                        items: [for (var i = 1; i <= 7; i++) DropdownMenuItem(value: i, child: Text(ne ? weekdaysNe[i - 1] : weekdaysEn[i - 1]))],
                        onChanged: (v) => setS(() => weekday = v ?? 1),
                      ),
                    if (freq == 'monthly') ...[
                      DropdownButton<int>(
                        isExpanded: true,
                        value: monthDay,
                        items: [for (var i = 1; i <= 28; i++) DropdownMenuItem(value: i, child: Text(nd(t('Day $i of the month', 'महिनाको $i गते', 'Mahina ko $i gate'))))],
                        onChanged: (v) => setS(() => monthDay = v ?? 1),
                      ),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: true, label: Text(t('BS month', 'वि.सं. महिना', 'BS mahina'))),
                          ButtonSegment(value: false, label: Text(t('AD month', 'ई.सं. महिना', 'AD mahina'))),
                        ],
                        selected: {bs},
                        onSelectionChanged: (s) => setS(() => bs = s.first),
                      ),
                    ],
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(dc, false), child: Text(t('Cancel', 'रद्द'))),
                  TextButton(onPressed: () => Navigator.pop(dc, true), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
                ],
              ),
            ));
    if (ok != true) return;
    final a = double.tryParse(amt.text.trim());
    if (a == null || a <= 0) return;
    final today = dateOnly(DateTime.now());
    app.rec.add(Recurring(
        id: app.newId(),
        isLess: less,
        amount: a,
        note: note.text.trim(),
        cat: cat.isEmpty ? null : cat,
        freq: freq,
        weekday: weekday,
        monthDay: monthDay,
        bs: bs,
        lastApplied: DateTime(today.year, today.month, today.day - 1)));
    await app.saveRec();
    final n = await app.applyRecurring(); // if it is due today, it is added right now
    app.refresh();
    if (mounted) {
      setState(() {});
      if (n > 0) showSnack(context, nd(t('Added $n entry for today', 'आजका लागि $n हिसाब थपियो', 'Aaja ko lagi $n hisab thapiyo')));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (c, _) => subPage(
          title: t('Repeating entries', 'दोहोरिने हिसाब', 'Dohorine hisab'),
          fab: FloatingActionButton.extended(heroTag: null, onPressed: _add, icon: const Icon(Icons.add), label: Text(t('New', 'नयाँ', 'Naya'))),
          body: ListView(padding: const EdgeInsets.only(bottom: 90), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t('These are added to your days by themselves. If you do not open the app for a few days, missed ones are added when you come back.', 'यी आफैं तपाईंको हिसाबमा थपिन्छन्। केही दिन एप नखोले पनि फर्किँदा छुटेका थपिन्छन्।', 'Yi aafai hisab ma thapinchhan. Kehi din app nakholda pani, farkeda chhuteka thapinchhan.'),
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            if (app.rec.isEmpty) Center(child: Padding(padding: const EdgeInsets.all(30), child: Text(t('Nothing repeating yet', 'दोहोरिने केही छैन', 'Dohorine kei chhaina')))),
            for (final r in app.rec)
              Card(
                color: cardColor(false),
                margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                child: ListTile(
                  leading: Icon(r.isLess ? Icons.arrow_upward : Icons.arrow_downward, color: r.isLess ? Colors.redAccent : Colors.greenAccent),
                  title: Text('${rs(r.amount)}${r.note.isEmpty ? '' : '  (${r.note})'}'),
                  subtitle: Text('${emojiOn('cats') ? (app.catById(r.cat)?.emoji ?? '') : ''} ${r.describe}'.trim()),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      app.rec.remove(r);
                      app.refresh();
                      await app.saveRec();
                    },
                  ),
                ),
              ),
          ]),
        ),
      );
}

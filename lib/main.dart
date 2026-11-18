import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'core.dart';
import 'home.dart';
import 'notify.dart';
import 'panels.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await app.load();
  runApp(const MemoApp());
}

class MemoApp extends StatelessWidget {
  const MemoApp({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          final th = curTheme;
          return MaterialApp(
            title: 'K.S.H.K',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorSchemeSeed: th.seed,
              scaffoldBackgroundColor: th.bg,
              appBarTheme: AppBarTheme(backgroundColor: th.bg),
            ),
            home: const Shell(),
          );
        },
      );
}

// The frame around everything: the main page is in the middle, other pages around it.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 2; // 0 Reports, 1 Udharo, 2 Home, 3 Budget, 4 Settings
  DateTime? _lastDuePrompt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResume();
  }

  Future<void> _boot() async {
    await _langPrompt();
    if (!mounted) return;
    await Notifier.init();
    await _autoBackup();
    await _recurring();
    await _monthPrompt();
    await _dueCheck();
    Notifier.reschedule();
  }

  Future<void> _onResume() async {
    if (!mounted) return;
    await _recurring();
    await _dueCheck();
    Notifier.reschedule();
  }

  // Small, one-time question. Nepali is the default.
  Future<void> _langPrompt() async {
    if (app.st.langChosen || !mounted) return;
    Future<void> choose(BuildContext dc, String lang) async {
      app.st.lang = lang;
      app.st.langChosen = true;
      app.applyLang();
      await app.st.save();
      app.refresh();
      if (dc.mounted) Navigator.pop(dc);
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dc) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 70),
        title: const Text('Language / Bhasha / भाषा', style: TextStyle(fontSize: 15)),
        actions: [
          TextButton(onPressed: () => choose(dc, 'en'), child: const Text('English')),
          TextButton(onPressed: () => choose(dc, 'ne'), child: const Text('नेपाली')),
          FilledButton(onPressed: () => choose(dc, 'rom'), child: const Text('Roman Nepali')),
        ],
      ),
    );
  }

  Future<void> _autoBackup() async {
    final st = app.st;
    if (kIsWeb || !st.autoBackup || app.days.isEmpty) return;
    final last = st.lastBackup;
    if (last != null && DateTime.now().difference(last).inDays < 10) return;
    try {
      await Backup.write(tag: 'auto');
      st.lastBackup = DateTime.now();
      await st.save();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(t('Auto backup done. Also save a copy to your phone storage?', 'आफैं ब्याकअप भयो। फोनको स्टोरेजमा पनि कपी राख्ने?', 'Auto backup bhayo. Phone storage ma pani copy rakhne?')),
        action: SnackBarAction(
            label: t('Save copy', 'कपी राख्नुहोस्', 'Copy rakha'),
            onPressed: () async {
              try {
                final ok = await Backup.saveCopy();
                if (ok && mounted) showSnack(context, t('Backup copy saved', 'ब्याकअप कपी सुरक्षित भयो', 'Backup copy save bhayo'));
              } catch (_) {}
            }),
      ));
    } catch (_) {}
  }

  Future<void> _recurring() async {
    final n = await app.applyRecurring();
    if (n > 0 && mounted) {
      showSnack(context, nd(t('Added $n repeating entries', '$n दोहोरिने हिसाब थपियो', '$n repeat hisab thapiyo')));
    }
  }

  // At the start of a new month: a small, optional chance to set or change the limit.
  Future<void> _monthPrompt() async {
    final st = app.st;
    final now = DateTime.now();
    final key = monthOf(now, app.bs).$1;
    if (st.lastPromptKey == null) {
      st.lastPromptKey = key; // first time ever: stay quiet
      await st.save();
      return;
    }
    if (st.lastPromptKey == key || !mounted) return;
    st.lastPromptKey = key;
    await st.save();
    final c = TextEditingController(text: st.limit == null ? '' : plainAmount(st.limit!));
    final res = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (bc) => Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(bc).viewInsets.bottom + 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(withEmoji('🎉', t('A new month has started!', 'नयाँ महिना सुरु भयो!', 'Naya mahina suru bhayo!'), 'msgs'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(monthOf(now, app.bs).$2, style: TextStyle(color: Theme.of(bc).colorScheme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(st.limit == null
                    ? t('Want to set a spending limit for this month? (optional)', 'यो महिनाको खर्च सीमा तोक्ने? (नतोके पनि हुन्छ)', 'Yo mahina ko kharcha limit rakhne? (nabhaye pani hunchha)')
                    : t('Your limit is ${rs(st.limit!)}. Keep it or change it.', 'तपाईंको सीमा ${rs(st.limit!)} छ। यही राख्ने कि बदल्ने?', 'Timro limit ${rs(st.limit!)} chha. Yehi rakhne ki badalne?')),
                TextField(
                  controller: c,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(prefixText: '${t('Rs', 'रु.')} ', labelText: t('Monthly limit', 'मासिक सीमा', 'Mahina ko limit')),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  TextButton(
                      onPressed: () => Navigator.pop(bc, 'skip'),
                      child: Text(st.limit == null ? t('Not now', 'अहिले होइन', 'Pachi') : t('Keep same', 'यही राख्ने', 'Yehi rakhne'))),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(bc, c.text), child: Text(t('Save', 'सुरक्षित', 'Save gara'))),
                ]),
              ]),
            ));
    if (res == null || res == 'skip') return;
    if (res.trim().isEmpty) {
      st.limit = null;
    } else {
      final v = double.tryParse(res.trim());
      if (v == null || v <= 0) return;
      st.limit = v;
    }
    await st.save();
    app.refresh();
  }

  // Udharo whose date has come: ask what to do. (Not more than once every 4 hours.)
  Future<void> _dueCheck() async {
    if (!mounted) return;
    if (app.dueUdharo().isEmpty) return;
    final now = DateTime.now();
    if (_lastDuePrompt != null && now.difference(_lastDuePrompt!).inHours < 4) return;
    _lastDuePrompt = now;
    await showDueUdharo(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final bg = hasBg(app.st);
        return AppBg(
          child: Scaffold(
            backgroundColor: bg ? Colors.transparent : null,
            body: IndexedStack(index: tab, children: [
              ReportsScreen(active: tab == 0),
              const UdharoScreen(),
              const HomeScreen(),
              const BudgetScreen(),
              const SettingsScreen(),
            ]),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              backgroundColor: bg ? curTheme.bg.withAlpha(0xCC) : null,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.bar_chart_outlined),
                    selectedIcon: const Icon(Icons.bar_chart),
                    label: t('Reports', 'रिपोर्ट')),
                NavigationDestination(
                    icon: const Icon(Icons.handshake_outlined),
                    selectedIcon: const Icon(Icons.handshake),
                    label: t('Loans', 'उधारो', 'Udharo')),
                NavigationDestination(
                    icon: const Icon(Icons.menu_book_outlined),
                    selectedIcon: const Icon(Icons.menu_book),
                    label: t('Home', 'हिसाब', 'Hisab')),
                NavigationDestination(
                    icon: const Icon(Icons.savings_outlined),
                    selectedIcon: const Icon(Icons.savings),
                    label: t('Budget', 'बजेट')),
                NavigationDestination(
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    label: t('Settings', 'सेटिङ')),
              ],
            ),
          ),
        );
      },
    );
  }
}

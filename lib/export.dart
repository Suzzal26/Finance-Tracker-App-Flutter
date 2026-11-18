import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'core.dart';

// Exports are always written in English letters so every phone and computer can read them.
// (The default PDF font has no Devanagari letters. The CSV keeps your notes exactly as typed.)
String _latin(String s) => s.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();

class _Row {
  final String title;
  final List<String> lines;
  final String total;
  _Row(this.title, this.lines, this.total);
}

class Exporter {
  static String _fileBase(String title) => 'KSHK_${title.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';

  static Future<bool> csv(List<Day> ds, String title) async {
    forceEn = true;
    final sb = StringBuffer();
    try {
      String esc(String s) => (s.contains(',') || s.contains('"') || s.contains('\n')) ? '"${s.replaceAll('"', '""')}"' : s;
      sb.writeln('Date (BS),Date (AD),Weekday,Time,Type,Amount,Category,Note');
      for (final d in ds) {
        for (final l in d.lines) {
          final cat = app.catById(l.cat)?.en ?? '';
          sb.writeln([
            esc(bsText(d.date)),
            esc(adText(d.date)),
            esc(dayName(d.date)),
            l.time == null ? '' : fmtTime(l.time!, true),
            l.isLess ? 'Spent' : 'Received',
            plainAmount(l.amount),
            esc(cat),
            esc(l.note),
          ].join(','));
        }
      }
    } finally {
      forceEn = false;
    }
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(sb.toString())]); // BOM so Excel reads UTF-8
    final uri = await FilePicker.saveFile(
        dialogTitle: 'Save CSV', fileName: '${_fileBase(title)}.csv', bytes: bytes);
    return uri != null;
  }

  static Future<bool> pdf(List<Day> ds, String title) async {
    final rows = <_Row>[];
    var less = 0.0, add = 0.0;
    forceEn = true;
    try {
      for (final d in ds) {
        final lines = <String>[];
        for (final l in d.lines) {
          final cat = app.catById(l.cat)?.en ?? '';
          final note = _latin(l.note);
          lines.add('${l.isLess ? 'Spent' : 'Received'}: Rs ${fmt(l.amount)}/-'
              '${note.isEmpty ? '' : '  ($note)'}'
              '${cat.isEmpty ? '' : '  [$cat]'}'
              '${l.time == null ? '' : '  ${fmtTime(l.time!, false)}'}');
        }
        less += d.less;
        add += d.add;
        rows.add(_Row('${bsText(d.date)} (${adText(d.date)}), ${dayName(d.date)}', lines, d.totalText));
      }
    } finally {
      forceEn = false;
    }
    final summary = 'Spent: Rs ${fmt(less)}/-    Received: Rs ${fmt(add)}/-    Net: Rs ${fmt(add - less)}/-';

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => [
        pw.Text(appNameEn, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(title, style: const pw.TextStyle(fontSize: 14)),
        pw.SizedBox(height: 4),
        pw.Text(summary),
        pw.Divider(),
        for (final r in rows)
          pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(r.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              for (final line in r.lines) pw.Text(line),
              pw.Text(r.total, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ]),
          ),
      ],
    ));
    final bytes = await doc.save();
    final uri = await FilePicker.saveFile(
        dialogTitle: 'Save PDF', fileName: '${_fileBase(title)}.pdf', bytes: Uint8List.fromList(bytes));
    return uri != null;
  }
}

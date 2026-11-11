import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company.dart';
import '../models/work_order.dart';
import 'pdf_zajednicko.dart';

// PDF radnog naloga za štampu (A4, uspravno): zaglavlje firme, podaci naloga,
// proizvodi koje treba izraditi i potpisi. Materijali se štampaju zasebno,
// na trebovanju.

Future<Uint8List> napraviRadniNalogPdf({
  required RadniNalog nalog,
  Company? firma,
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final broj = nalog.broj.trim();
  final stavke = nalog.trebovanje?.stavke ?? const <StavkaTrebovanja>[];
  final vrijednost = nalog.trebovanje?.vrijednost;

  final doc = pw.Document(
    title: 'Radni nalog $broj',
    author: firma?.name,
    theme: await pdfTema(),
  );

  doc.addPage(
    pdfStranica(
      format: format,
      naslovNastavka: 'Radni nalog $broj',
      build: (context) => [
        pdfZaglavlje(
          firma: firma,
          naslov: 'RADNI NALOG',
          podnaslov: broj.isEmpty ? 'za proizvodnju' : 'br. $broj',
        ),
        pw.SizedBox(height: 18),
        pdfPodaci([
          ('Datum', pdfDatum(nalog.datum)),
          ('Broj naloga', broj.isEmpty ? '—' : broj),
          ('Kupac', nalog.kupac ?? '—'),
          ('Izdaje', nalog.izvor?.naziv ?? '—'),
          ('Prima', nalog.odrediste?.naziv ?? '—'),
          ('Status', nalog.jeIzdat ? 'Izdat' : 'Nacrt'),
        ]),
        pw.SizedBox(height: 18),
        _tabela(stavke),
        if (vrijednost != null) ...[
          pw.SizedBox(height: 8),
          pdfUkupno('Vrijednost utrošenog materijala', pdfIznos(vrijednost)),
        ],
        pw.SizedBox(height: 48),
        pdfPotpisi([
          ('Izdao', nalog.izdao),
          ('Primio', null),
          ('Odobrio', nalog.potpisao),
        ]),
      ],
    ),
  );

  return doc.save();
}

const List<PdfKolona> _kolone = [
  ('R.br.', 0.6, false),
  ('ID', 1.2, false),
  ('Proizvod', 4.0, false),
  ('JM', 0.7, false),
  ('Količina', 1.3, true),
  ('Materijala', 1.1, true),
];

pw.Widget _tabela(List<StavkaTrebovanja> stavke) {
  if (stavke.isEmpty) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: pdfLinija, width: 0.7),
      ),
      child: pw.Text(
        'Nalog nema stavki.',
        style: const pw.TextStyle(fontSize: 9, color: pdfPriguseno),
      ),
    );
  }

  return pdfTabela(_kolone, [
    for (var i = 0; i < stavke.length; i++)
      pw.TableRow(
        children: [
          pdfCelija('${i + 1}.', _kolone[0], boja: pdfPriguseno),
          pdfCelija('${stavke[i].articleId}', _kolone[1]),
          pdfCelija(stavke[i].naziv, _kolone[2], bold: true),
          pdfCelija(stavke[i].jm, _kolone[3]),
          pdfCelija(pdfKolicina(stavke[i].kolicina), _kolone[4], bold: true),
          pdfCelija('${stavke[i].materijali.length}', _kolone[5]),
        ],
      ),
  ]);
}

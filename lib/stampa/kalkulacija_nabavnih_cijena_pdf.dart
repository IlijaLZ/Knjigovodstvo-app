import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company.dart';
import '../models/purchase_calculation.dart';
import 'pdf_zajednicko.dart';

// PDF kalkulacije nabavnih cijena (A4, položeno, zbog broja kolona):
// zaglavlje firme, podaci dokumenta, stavke, rekapitulacija i potpisi.

Future<Uint8List> napraviKalkulacijuNabavnihCijenaPdf({
  required Kalkulacija kalkulacija,
  Company? firma,
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final k = kalkulacija;
  final r = k.rekapitulacija;
  final broj = k.brojPrijemnice.trim();

  final doc = pw.Document(
    title: 'Kalkulacija nabavnih cijena $broj',
    author: firma?.name,
    theme: await pdfTema(),
  );

  doc.addPage(
    pdfStranica(
      format: format.landscape,
      naslovNastavka: 'Kalkulacija nabavnih cijena · Prijemnica $broj',
      build: (context) => [
        pdfZaglavlje(
          firma: firma,
          naslov: 'KALKULACIJA NABAVNIH CIJENA',
          podnaslov: broj.isEmpty ? '' : 'uz prijemnicu br. $broj',
        ),
        pw.SizedBox(height: 16),
        pdfPodaci([
          ('Datum', pdfDatum(k.datum)),
          ('Dobavljač', k.dobavljac ?? '—'),
          ('RC.BR (broj fakture)', k.brojFakture.isEmpty ? '—' : k.brojFakture),
          ('Prijemnica br.', broj.isEmpty ? '—' : broj),
          ('Objekat', k.skladiste?.naziv ?? '—'),
          ('Status', k.jeProknjizena ? 'Proknjižena' : 'Nacrt'),
        ]),
        pw.SizedBox(height: 16),
        _tabela(k.stavke, r),
        pw.SizedBox(height: 14),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(top: 40, right: 24),
                child: pdfPotpisi([
                  ('Kalkulisao', r.kalkulisao),
                  ('Robu primio', r.robuPrimio),
                ]),
              ),
            ),
            pw.Expanded(flex: 3, child: _rekapitulacija(r)),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

const List<PdfKolona> _kolone = [
  ('R.br.', 0.55, false),
  ('ID', 1.0, false),
  ('Artikal', 3.0, false),
  ('Dokument', 1.1, false),
  ('JM', 0.55, false),
  ('Količina', 1.0, true),
  ('Fakt. cijena', 1.1, true),
  ('Fakt. vrijednost', 1.3, true),
  ('Zavisni trošak', 1.2, true),
  ('Nab. cijena', 1.1, true),
  ('Nab. vrijednost', 1.3, true),
];

pw.Widget _tabela(List<StavkaKalkulacije> stavke, RekapitulacijaKalkulacije r) {
  final redovi = <pw.TableRow>[
    for (var i = 0; i < stavke.length; i++)
      pw.TableRow(
        children: [
          pdfCelija('${i + 1}.', _kolone[0], boja: pdfPriguseno),
          pdfCelija('${stavke[i].articleId}', _kolone[1]),
          pdfCelija(stavke[i].naziv, _kolone[2]),
          pdfCelija(stavke[i].dokument ?? '', _kolone[3]),
          pdfCelija(stavke[i].jm, _kolone[4]),
          pdfCelija(pdfKolicina(stavke[i].kolicina), _kolone[5]),
          pdfCelija(pdfIznos(stavke[i].fakturnaCijena), _kolone[6]),
          pdfCelija(pdfIznos(stavke[i].fakturnaVrijednost), _kolone[7]),
          pdfCelija(pdfIznos(stavke[i].zavisniTrosak), _kolone[8]),
          pdfCelija(pdfIznos(stavke[i].nabavnaCijena), _kolone[9]),
          pdfCelija(
            pdfIznos(stavke[i].nabavnaVrijednost),
            _kolone[10],
            bold: true,
          ),
        ],
      ),
    // Red zbira.
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: pdfGrupa),
      children: [
        for (var i = 0; i < _kolone.length; i++)
          switch (i) {
            2 => pdfCelija('Ukupno', _kolone[i], bold: true),
            7 => pdfCelija(
              pdfIznos(r.fakturnaVrijednost),
              _kolone[i],
              bold: true,
            ),
            8 => pdfCelija(pdfIznos(r.zavisniTroskovi), _kolone[i], bold: true),
            10 => pdfCelija(
              pdfIznos(r.nabavnaVrijednost),
              _kolone[i],
              bold: true,
            ),
            _ => pw.SizedBox(),
          },
      ],
    ),
  ];

  return pdfTabela(_kolone, redovi);
}

pw.Widget _rekapitulacija(RekapitulacijaKalkulacije r) {
  pw.Widget red(String oznaka, double iznos, {bool istaknuto = false}) {
    final stil = pw.TextStyle(
      fontSize: istaknuto ? 10.5 : 9.5,
      fontWeight: istaknuto ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: pdfTekst,
    );
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      color: istaknuto ? pdfGrupa : null,
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(oznaka, style: stil)),
          pw.Text(pdfIznos(iznos), style: stil),
        ],
      ),
    );
  }

  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfLinija, width: 0.7),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          color: pdfZaglavljeTabele,
          child: pw.Text(
            'REKAPITULACIJA',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: pdfPriguseno,
              letterSpacing: 0.6,
            ),
          ),
        ),
        red('Fakturna vrijednost', r.fakturnaVrijednost),
        red('Prevoz', r.prevoz),
        red('Špedicija', r.spedicija),
        red('Carina', r.carina),
        red('Zavisni troškovi ukupno', r.zavisniTroskovi),
        red('Nabavna vrijednost', r.nabavnaVrijednost, istaknuto: true),
      ],
    ),
  );
}

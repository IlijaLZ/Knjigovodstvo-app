import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company.dart';

// Zajednički dijelovi PDF dokumenata za štampu: boje, formati brojeva,
// fontovi, zaglavlje firme, blok podataka, tabela, rekapitulacija i potpisi.

const pdfAkcent = PdfColor.fromInt(0xFF0F5C66);
// Tamnija mint-zelena (svijetla se ne vidi na bijelom papiru).
const pdfMint = PdfColor.fromInt(0xFF1F9C78);
const pdfLinija = PdfColor.fromInt(0xFFCBD5E1);
const pdfZaglavljeTabele = PdfColor.fromInt(0xFFF1F5F9);
const pdfGrupa = PdfColor.fromInt(0xFFE6F4F3);
const pdfPriguseno = PdfColor.fromInt(0xFF64748B);
const pdfTekst = PdfColor.fromInt(0xFF0F172A);

String pdfIznos(double v) {
  final dijelovi = v.abs().toStringAsFixed(2).split('.');
  final cijeli = dijelovi[0];
  final b = StringBuffer();
  for (var i = 0; i < cijeli.length; i++) {
    if (i > 0 && (cijeli.length - i) % 3 == 0) b.write('.');
    b.write(cijeli[i]);
  }
  return '${v < 0 ? '-' : ''}$b,${dijelovi[1]}';
}

String pdfKolicina(double v) {
  var t = v.toStringAsFixed(4);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t.replaceAll('.', ',');
}

String pdfDatum(DateTime? d) {
  if (d == null) return '—';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}.';
}

// Naziv PDF fajla bez razmaka i specijalnih znakova.
String pdfNazivFajla(String naziv) =>
    '$naziv.pdf'.replaceAll(RegExp(r'[^\w.\-]'), '_');

// Fontovi sa našim slovima (č, ć, š, ž, đ), uključeni u aplikaciju.
Future<pw.ThemeData> pdfTema() async {
  final obicni = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
  final debeli = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
  return pw.ThemeData.withFont(
    base: pw.Font.ttf(obicni),
    bold: pw.Font.ttf(debeli),
  );
}

// Stranica sa zajedničkim marginama, zaglavljem od druge strane i podnožjem.
pw.MultiPage pdfStranica({
  required PdfPageFormat format,
  required String naslovNastavka,
  required List<pw.Widget> Function(pw.Context context) build,
}) {
  return pw.MultiPage(
    pageFormat: format,
    margin: const pw.EdgeInsets.fromLTRB(36, 32, 36, 32),
    header: (context) => context.pageNumber == 1
        ? pw.SizedBox()
        : pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 10),
            child: pw.Text(
              naslovNastavka,
              style: const pw.TextStyle(fontSize: 8, color: pdfPriguseno),
            ),
          ),
    footer: (context) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: pdfLinija, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Odštampano ${pdfDatum(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 8, color: pdfPriguseno),
          ),
          pw.Text(
            'Strana ${context.pageNumber} od ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: pdfPriguseno),
          ),
        ],
      ),
    ),
    build: build,
  );
}

// Firma lijevo, naziv dokumenta i podnaslov desno.
pw.Widget pdfZaglavlje({
  required Company? firma,
  required String naslov,
  required String podnaslov,
}) {
  final detalji = [
    if ((firma?.address ?? '').isNotEmpty) firma!.address!,
    if ((firma?.taxId ?? '').isNotEmpty) 'PIB: ${firma!.taxId}',
    if ((firma?.vatNumber ?? '').isNotEmpty) 'PDV: ${firma!.vatNumber}',
  ];

  final red = pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              firma?.name ?? '',
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: pdfTekst,
              ),
            ),
            for (final d in detalji)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 2),
                child: pw.Text(
                  d,
                  style: const pw.TextStyle(fontSize: 9, color: pdfPriguseno),
                ),
              ),
          ],
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.RichText(
            text: pw.TextSpan(
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
                color: pdfAkcent,
                letterSpacing: 1.5,
              ),
              children: [
                pw.TextSpan(text: naslov),
                const pw.TextSpan(
                  text: '.',
                  style: pw.TextStyle(color: pdfMint),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            podnaslov,
            style: const pw.TextStyle(fontSize: 9.5, color: pdfPriguseno),
          ),
        ],
      ),
    ],
  );

  // Traka brenda: kratki mint dio pa tanka petrolej linija.
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      red,
      pw.SizedBox(height: 12),
      pw.Row(
        children: [
          pw.Container(width: 56, height: 3, color: pdfMint),
          pw.Expanded(child: pw.Container(height: 1, color: pdfAkcent)),
        ],
      ),
    ],
  );
}

// Okvir sa podacima dokumenta, po tri polja u redu.
pw.Widget pdfPodaci(List<(String, String)> polja, {int uRedu = 3}) {
  pw.Widget polje((String, String) p) => pw.Expanded(
    child: pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            p.$1.toUpperCase(),
            style: const pw.TextStyle(
              fontSize: 7,
              color: pdfPriguseno,
              letterSpacing: 0.6,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            p.$2,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );

  final redovi = <pw.Widget>[];
  for (var i = 0; i < polja.length; i += uRedu) {
    final red = polja.skip(i).take(uRedu).toList();
    redovi.add(
      pw.Row(
        children: [
          for (final p in red) polje(p),
          // Popuna da zadnji red ima iste širine kolona.
          for (var j = red.length; j < uRedu; j++)
            pw.Expanded(child: pw.SizedBox()),
        ],
      ),
    );
  }

  return pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: pdfLinija, width: 0.7),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(children: redovi),
  );
}

// Kolona tabele: naslov, relativna širina i da li je desno poravnata.
typedef PdfKolona = (String naslov, double sirina, bool desno);

pw.Widget pdfCelija(
  String tekst,
  PdfKolona kolona, {
  bool bold = false,
  double velicina = 9,
  PdfColor boja = pdfTekst,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4.5),
    child: pw.Text(
      tekst,
      textAlign: kolona.$3 ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        fontSize: velicina,
        color: boja,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.TableRow pdfRedZaglavlja(List<PdfKolona> kolone) => pw.TableRow(
  decoration: const pw.BoxDecoration(color: pdfZaglavljeTabele),
  repeat: true,
  children: [
    for (final k in kolone)
      pdfCelija(k.$1, k, bold: true, velicina: 8, boja: pdfPriguseno),
  ],
);

pw.Table pdfTabela(List<PdfKolona> kolone, List<pw.TableRow> redovi) {
  return pw.Table(
    border: const pw.TableBorder(
      top: pw.BorderSide(color: pdfLinija, width: 0.7),
      bottom: pw.BorderSide(color: pdfLinija, width: 0.7),
      left: pw.BorderSide(color: pdfLinija, width: 0.7),
      right: pw.BorderSide(color: pdfLinija, width: 0.7),
      horizontalInside: pw.BorderSide(color: pdfLinija, width: 0.4),
    ),
    columnWidths: {
      for (var i = 0; i < kolone.length; i++)
        i: pw.FlexColumnWidth(kolone[i].$2),
    },
    children: [pdfRedZaglavlja(kolone), ...redovi],
  );
}

// Istaknut iznos desno ispod tabele ("Ukupna vrijednost: 1.234,00").
pw.Widget pdfUkupno(String oznaka, String vrijednost) {
  return pw.Align(
    alignment: pw.Alignment.centerRight,
    child: pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const pw.BoxDecoration(
        color: pdfGrupa,
        border: pw.Border(left: pw.BorderSide(color: pdfMint, width: 3)),
      ),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text('$oznaka:  ', style: const pw.TextStyle(fontSize: 10)),
          pw.Text(
            vrijednost,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    ),
  );
}

// Linije za potpis sa imenom iznad (ako je poznato) i ulogom ispod.
pw.Widget pdfPotpisi(List<(String uloga, String? ime)> potpisi) {
  return pw.Row(
    children: [
      for (final p in potpisi)
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 14),
            child: pw.Column(
              children: [
                pw.SizedBox(
                  height: 14,
                  child: pw.Text(
                    p.$2 ?? '',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ),
                pw.Container(height: 0.7, color: pdfTekst),
                pw.SizedBox(height: 4),
                pw.Text(
                  p.$1,
                  style: const pw.TextStyle(fontSize: 8.5, color: pdfPriguseno),
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

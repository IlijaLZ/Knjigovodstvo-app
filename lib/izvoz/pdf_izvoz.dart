import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../stampa/pdf_zajednicko.dart';
import 'excel_izvoz.dart';

// Izvoz istih listova kao za Excel (ListExcel) u PDF: svaki list počinje na
// novoj strani, sa naslovom, podnaslovima, tabelom i redom "Ukupno".
// Tabele sa puno kolona idu na položenu stranu i sitnija slova.

// Dijalog "Sačuvaj kao" za .pdf. Vraća false ako je korisnik odustao.
Future<bool> sacuvajPdf(
  String nazivFajla,
  List<ListExcel> listovi, {
  String? firma,
}) async {
  final bajtovi = await napraviPdfIzListova(listovi, firma: firma);
  final ime = nazivFajla.toLowerCase().endsWith('.pdf')
      ? nazivFajla
      : '$nazivFajla.pdf';

  final uri = await FilePicker.saveFile(
    fileName: ime,
    bytes: bajtovi,
    mimeType: 'application/pdf',
    dialogTitle: 'Sačuvaj PDF',
  );
  return uri != null;
}

Future<Uint8List> napraviPdfIzListova(
  List<ListExcel> listovi, {
  String? firma,
}) async {
  assert(listovi.isNotEmpty);
  final doc = pw.Document(
    title: listovi.first.naslov,
    author: firma,
    theme: await pdfTema(),
  );

  for (final list in listovi) {
    final brojKolona = list.kolone.length;
    final polozeno = brojKolona > 6;
    final velicina = brojKolona <= 6
        ? 9.0
        : brojKolona <= 10
        ? 8.0
        : 7.0;

    doc.addPage(
      pw.MultiPage(
        pageFormat: polozeno ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
        maxPages: 1000,
        header: (context) => context.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  list.naslov,
                  style: const pw.TextStyle(fontSize: 8, color: pdfPriguseno),
                ),
              ),
        footer: (context) => _podnozje(context),
        build: (context) => [
          _zaglavlje(list, firma),
          pw.SizedBox(height: 14),
          _tabela(list, velicina),
        ],
      ),
    );
  }

  return doc.save();
}

pw.Widget _zaglavlje(ListExcel list, String? firma) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if ((firma ?? '').isNotEmpty)
        pw.Text(
          firma!,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: pdfPriguseno,
          ),
        ),
      pw.SizedBox(height: 2),
      pw.Text(
        list.naslov,
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: pdfAkcent,
        ),
      ),
      for (final p in list.podnaslovi)
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 2),
          child: pw.Text(
            p,
            style: const pw.TextStyle(fontSize: 9, color: pdfPriguseno),
          ),
        ),
      pw.SizedBox(height: 10),
      pw.Row(
        children: [
          pw.Container(width: 56, height: 3, color: pdfMint),
          pw.Expanded(child: pw.Container(height: 1, color: pdfAkcent)),
        ],
      ),
    ],
  );
}

pw.Widget _podnozje(pw.Context context) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: pdfLinija, width: 0.5)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Izvezeno ${pdfDatum(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 8, color: pdfPriguseno),
        ),
        pw.Text(
          'Strana ${context.pageNumber} od ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: pdfPriguseno),
        ),
      ],
    ),
  );
}

// Tekst ćelije kao u Excelu: iznosi na 2 decimale, količine bez suvišnih
// nula, datumi dd.mm.gggg.
String pdfTekstCelije(Object? v, VrstaKolone vrsta) {
  if (v == null) return '';
  if (v is DateTime) return pdfDatum(v);
  if (v is num) {
    if (!v.isFinite) return '';
    return vrsta == VrstaKolone.iznos
        ? pdfIznos(v.toDouble())
        : pdfKolicina(v.toDouble());
  }
  return '$v';
}

pw.Widget _tabela(ListExcel list, double velicina) {
  final kolone = <PdfKolona>[
    for (final k in list.kolone)
      (
        k.naziv,
        k.sirina,
        k.vrsta == VrstaKolone.iznos || k.vrsta == VrstaKolone.broj,
      ),
  ];

  pw.TableRow red(List<Object?> vrijednosti, {bool ukupno = false}) {
    return pw.TableRow(
      decoration: ukupno
          ? const pw.BoxDecoration(
              color: pdfGrupa,
              border: pw.Border(
                top: pw.BorderSide(color: pdfAkcent, width: 0.8),
              ),
            )
          : null,
      children: [
        for (var i = 0; i < kolone.length; i++)
          pdfCelija(
            pdfTekstCelije(
              i < vrijednosti.length ? vrijednosti[i] : null,
              list.kolone[i].vrsta,
            ),
            kolone[i],
            bold: ukupno,
            velicina: velicina,
          ),
      ],
    );
  }

  return pdfTabela(kolone, [
    for (final r in list.redovi) red(r),
    if (list.ukupno != null) red(list.ukupno!, ukupno: true),
  ]);
}

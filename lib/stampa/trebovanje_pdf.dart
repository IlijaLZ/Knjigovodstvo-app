import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company.dart';
import '../models/work_order.dart';
import 'pdf_zajednicko.dart';

// PDF trebovanja za štampu (A4, uspravno): zaglavlje firme, podaci naloga,
// tok materijala, materijali grupisani po proizvodu i potpisi.

Future<Uint8List> napraviTrebovanjePdf({
  required Trebovanje trebovanje,
  required RadniNalog nalog,
  Company? firma,
  PdfPageFormat format = PdfPageFormat.a4,
}) async {
  final brojNaloga = trebovanje.brojNaloga ?? nalog.broj;
  final kupac = trebovanje.kupac ?? nalog.kupac ?? '—';
  final ukupnaVrijednost = trebovanje.vrijednost;

  final doc = pw.Document(
    title: 'Trebovanje $brojNaloga',
    author: firma?.name,
    theme: await pdfTema(),
  );

  doc.addPage(
    pdfStranica(
      format: format,
      naslovNastavka: 'Trebovanje · Radni nalog $brojNaloga',
      build: (context) => [
        pdfZaglavlje(
          firma: firma,
          naslov: 'TREBOVANJE',
          podnaslov:
              'materijala za radni nalog ${brojNaloga.isEmpty ? '' : 'br. $brojNaloga'}',
        ),
        pw.SizedBox(height: 18),
        pdfPodaci([
          ('Datum', pdfDatum(trebovanje.datum ?? nalog.datum)),
          ('Radni nalog', brojNaloga.isEmpty ? '—' : brojNaloga),
          ('Kupac', kupac),
          ('Izdaje', nalog.izvor?.naziv ?? '—'),
          ('Prima', nalog.odrediste?.naziv ?? '—'),
          ('Status', nalog.jeIzdat ? 'Izdato' : 'U pripremi'),
        ]),
        pw.SizedBox(height: 18),
        _tabela(trebovanje),
        if (ukupnaVrijednost != null) ...[
          pw.SizedBox(height: 8),
          pdfUkupno('Ukupna vrijednost', pdfIznos(ukupnaVrijednost)),
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
  ('Materijal', 3.6, false),
  ('JM', 0.7, false),
  ('Norma', 1.1, true),
  ('Trebovano', 1.3, true),
  ('Izdato', 1.3, true),
  ('Vrijednost', 1.4, true),
];

pw.Widget _tabela(Trebovanje t) {
  final redovi = <pw.TableRow>[];

  var rb = 0;
  for (final s in t.stavke) {
    // Red proizvoda preko cijele širine (ostale ćelije prazne).
    redovi.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: pdfGrupa),
        children: [
          pw.SizedBox(),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '#${s.articleId}  ',
                    style: const pw.TextStyle(fontSize: 8, color: pdfPriguseno),
                  ),
                  pw.TextSpan(
                    text: s.naziv,
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: pdfAkcent,
                    ),
                  ),
                ],
              ),
            ),
          ),
          pdfCelija(s.jm, _kolone[2], bold: true),
          pw.SizedBox(),
          pdfCelija(pdfKolicina(s.kolicina), _kolone[4], bold: true),
          pw.SizedBox(),
          pw.SizedBox(),
        ],
      ),
    );

    for (final m in s.materijali) {
      rb++;
      redovi.add(
        pw.TableRow(
          children: [
            pdfCelija('$rb.', _kolone[0], boja: pdfPriguseno),
            pdfCelija(m.naziv, _kolone[1]),
            pdfCelija(m.jm, _kolone[2]),
            pdfCelija(pdfKolicina(m.norma), _kolone[3]),
            pdfCelija(pdfKolicina(m.trazeno), _kolone[4]),
            pdfCelija(
              m.izdato == null ? '' : pdfKolicina(m.izdato!),
              _kolone[5],
            ),
            pdfCelija(
              m.vrijednost == null ? '' : pdfIznos(m.vrijednost!),
              _kolone[6],
            ),
          ],
        ),
      );
    }
  }

  return pdfTabela(_kolone, redovi);
}

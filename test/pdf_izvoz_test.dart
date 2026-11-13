import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/izvoz/excel_izvoz.dart';
import 'package:knjigovodstvo_app/izvoz/pdf_izvoz.dart';

ListExcel _list({int kolone = 4, int redova = 3}) => ListExcel(
  naziv: 'Stanje',
  naslov: 'Stanje magacina repromaterijala',
  podnaslovi: const ['Firma d.o.o.', 'Na dan 13.11.2026.'],
  kolone: [
    const KolonaExcel('Naziv', sirina: 30),
    const KolonaExcel('Datum', vrsta: VrstaKolone.datum),
    const KolonaExcel('Količina', vrsta: VrstaKolone.broj),
    const KolonaExcel('Vrijednost', vrsta: VrstaKolone.iznos),
    for (var i = 4; i < kolone; i++) KolonaExcel('Kolona $i'),
  ],
  redovi: [
    for (var i = 0; i < redova; i++)
      ['Tkanina čćšžđ $i', DateTime(2026, 11, 10), 12.5, 1234.5, null],
  ],
  ukupno: const ['Ukupno', null, 37.5, 3703.5],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('tekst ćelija kao u Excelu', () {
    expect(pdfTekstCelije(1234567.891, VrstaKolone.iznos), '1.234.567,89');
    expect(pdfTekstCelije(-5, VrstaKolone.iznos), '-5,00');
    expect(pdfTekstCelije(12.5, VrstaKolone.broj), '12,5');
    expect(pdfTekstCelije(3, VrstaKolone.broj), '3');
    expect(
      pdfTekstCelije(DateTime(2026, 1, 5), VrstaKolone.datum),
      '05.01.2026.',
    );
    expect(pdfTekstCelije(null, VrstaKolone.tekst), '');
    expect(pdfTekstCelije(double.nan, VrstaKolone.iznos), '');
    expect(pdfTekstCelije('abc', VrstaKolone.tekst), 'abc');
  });

  test('PDF iz više listova, široka tabela i puno redova', () async {
    final bajtovi = await napraviPdfIzListova([
      _list(),
      _list(kolone: 12, redova: 400),
      _list(redova: 0),
    ], firma: 'Firma d.o.o.');
    expect(String.fromCharCodes(bajtovi.take(5)), '%PDF-');
    expect(bajtovi.length, greaterThan(1000));
  });
}

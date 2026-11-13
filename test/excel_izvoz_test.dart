import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knjigovodstvo_app/izvoz/excel_izvoz.dart';

String _sadrzaj(Archive a, String putanja) =>
    utf8.decode(a.findFile(putanja)!.content as List<int>);

void main() {
  final list = ListExcel(
    naziv: 'Stanje: repro/2026',
    naslov: 'Stanje magacina <repro> & co',
    podnaslovi: ['La Vista', 'Stanje na dan 12.11.2026'],
    kolone: const [
      KolonaExcel('Datum', vrsta: VrstaKolone.datum),
      KolonaExcel('Artikal', sirina: 30),
      KolonaExcel('Količina', vrsta: VrstaKolone.broj),
      KolonaExcel('Vrijednost', vrsta: VrstaKolone.iznos),
    ],
    redovi: [
      [DateTime(2026, 11, 10), 'Tkanina "A"', 100, 5150.5],
      [null, 'Dugme', 0.007, null],
    ],
    ukupno: ['Ukupno', null, null, 5150.5],
  );

  test('xlsx ima sve dijelove i ispravan XML', () {
    final arhiva = ZipDecoder().decodeBytes(napraviXlsx([list]));
    for (final p in [
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'xl/styles.xml',
      'xl/worksheets/sheet1.xml',
    ]) {
      expect(arhiva.findFile(p), isNotNull, reason: p);
    }

    final list1 = _sadrzaj(arhiva, 'xl/worksheets/sheet1.xml');
    // Naslov i tekst su escapovani.
    expect(list1, contains('Stanje magacina &lt;repro&gt; &amp; co'));
    expect(list1, contains('Tkanina &quot;A&quot;'));
    // Zaglavlje je u 5. redu (naslov, 2 podnaslova, prazan red).
    expect(list1, contains('<c r="A5" s="1" t="inlineStr">'));
    // Datum kao Excel broj (10.11.2026 = 46336), iznos kao broj sa stilom.
    expect(list1, contains('<c r="A6" s="3"><v>46336</v></c>'));
    expect(list1, contains('<c r="D6" s="2"><v>5150.5</v></c>'));
    expect(list1, contains('<c r="C7"><v>0.007</v></c>'));
    // Prazna vrijednost ne pravi ćeliju.
    expect(list1, isNot(contains('r="A7"')));
    // Red ukupno je podebljan, filter pokriva zaglavlje i podatke.
    expect(list1, contains('<c r="D8" s="6"><v>5150.5</v></c>'));
    expect(list1, contains('<autoFilter ref="A5:D7"/>'));

    // Naziv lista bez zabranjenih znakova.
    expect(
      _sadrzaj(arhiva, 'xl/workbook.xml'),
      contains('name="Stanje- repro-2026"'),
    );
  });

  test('više listova sa istim nazivom dobija jedinstvene nazive', () {
    final arhiva = ZipDecoder().decodeBytes(napraviXlsx([list, list]));
    final wb = _sadrzaj(arhiva, 'xl/workbook.xml');
    expect(wb, contains('name="Stanje- repro-2026"'));
    expect(wb, contains('name="Stanje- repro-2026 (2)"'));
    expect(arhiva.findFile('xl/worksheets/sheet2.xml'), isNotNull);
  });

  test('naziv fajla bez zabranjenih znakova', () {
    expect(bezbjedanNazivFajla('Kartica a/b: c?'), 'Kartica a-b- c-');
  });

  // Za ručnu provjeru u Excelu/Numbers: XLSX_IZLAZ=/putanja/test.xlsx
  final izlaz = Platform.environment['XLSX_IZLAZ'];
  if (izlaz != null) {
    test('upiši primjer', () {
      File(izlaz).writeAsBytesSync(napraviXlsx([list]));
    });
  }
}

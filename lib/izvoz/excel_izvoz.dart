import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';

// Izvoz tabela u Excel (.xlsx).
//
// Paket `excel` traži staru verziju `archive` koja se ne slaže sa `pdf` i
// `image`, pa se .xlsx (zip sa nekoliko XML fajlova) pravi ovdje direktno.
// Brojevi se upisuju kao pravi brojevi (Excel ih može sabirati i
// filtrirati), datumi kao Excel datumi, a zaglavlje tabele ima filter i
// ostaje zamrznuto pri skrolovanju.

enum VrstaKolone {
  tekst,
  // Iznos sa 2 decimale i razdvajanjem hiljada.
  iznos,
  // Količina/cijena: onoliko decimala koliko broj ima.
  broj,
  datum,
}

class KolonaExcel {
  final String naziv;
  final VrstaKolone vrsta;

  // Širina u znakovima.
  final double sirina;

  const KolonaExcel(
    this.naziv, {
    this.vrsta = VrstaKolone.tekst,
    this.sirina = 14,
  });
}

class ListExcel {
  // Naziv lista (kartice) u Excelu; skraćuje se na 31 znak.
  final String naziv;

  // Naslov iznad tabele (npr. "Stanje magacina repromaterijala").
  final String naslov;

  // Redovi ispod naslova (firma, period, filter...).
  final List<String> podnaslovi;

  final List<KolonaExcel> kolone;

  // Vrijednosti: String, num, DateTime ili null (prazna ćelija).
  final List<List<Object?>> redovi;

  // Red "Ukupno" na dnu (null = bez njega).
  final List<Object?>? ukupno;

  const ListExcel({
    required this.naziv,
    required this.naslov,
    this.podnaslovi = const [],
    required this.kolone,
    required this.redovi,
    this.ukupno,
  });
}

const _mimeXlsx =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

// Dijalog "Sačuvaj kao" za .xlsx. Vraća false ako je korisnik odustao.
Future<bool> sacuvajExcel(String nazivFajla, List<ListExcel> listovi) async {
  final bajtovi = napraviXlsx(listovi);
  final ime = nazivFajla.toLowerCase().endsWith('.xlsx')
      ? nazivFajla
      : '$nazivFajla.xlsx';

  final uri = await FilePicker.saveFile(
    fileName: ime,
    bytes: bajtovi,
    mimeType: _mimeXlsx,
    dialogTitle: 'Sačuvaj Excel',
  );
  return uri != null;
}

// Naziv fajla bez znakova koje sistemi ne dozvoljavaju.
String bezbjedanNazivFajla(String naziv) => naziv
    .replaceAll(RegExp(r'[\\/:*?"<>|]'), '-')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

// ---------------------------------------------------------------------------
// Pravljenje .xlsx
// ---------------------------------------------------------------------------

// Indeksi stilova iz styles.xml (cellXfs).
const _sZaglavlje = 1;
const _sIznos = 2;
const _sDatum = 3;
const _sNaslov = 4;
const _sUkupnoTekst = 5;
const _sUkupnoIznos = 6;
const _sUkupnoBroj = 7;
const _sPodnaslov = 8;

Uint8List napraviXlsx(List<ListExcel> listovi) {
  assert(listovi.isNotEmpty);
  final arhiva = Archive();

  void dodaj(String putanja, String sadrzaj) {
    arhiva.addFile(ArchiveFile.bytes(putanja, utf8.encode(sadrzaj)));
  }

  final nazivi = _jedinstveniNazivi(listovi.map((l) => l.naziv).toList());

  dodaj('[Content_Types].xml', _contentTypes(listovi.length));
  dodaj('_rels/.rels', _rels);
  dodaj('xl/workbook.xml', _workbook(nazivi));
  dodaj('xl/_rels/workbook.xml.rels', _workbookRels(listovi.length));
  dodaj('xl/styles.xml', _stilovi);
  for (var i = 0; i < listovi.length; i++) {
    dodaj('xl/worksheets/sheet${i + 1}.xml', _list(listovi[i]));
  }

  return ZipEncoder().encodeBytes(arhiva);
}

String _list(ListExcel list) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">',
    );

  final brojKolona = list.kolone.length;
  // Naslov, podnaslovi, prazan red, pa zaglavlje tabele.
  final redZaglavlja = 1 + list.podnaslovi.length + 2;
  final zadnjaKolona = _kolona(brojKolona - 1);

  // Zaglavlje ostaje vidljivo pri skrolovanju.
  b.write(
    '<sheetViews><sheetView workbookViewId="0">'
    '<pane ySplit="$redZaglavlja" topLeftCell="A${redZaglavlja + 1}" '
    'activePane="bottomLeft" state="frozen"/>'
    '</sheetView></sheetViews>',
  );

  b.write('<cols>');
  for (var i = 0; i < brojKolona; i++) {
    b.write(
      '<col min="${i + 1}" max="${i + 1}" '
      'width="${list.kolone[i].sirina}" customWidth="1"/>',
    );
  }
  b.write('</cols><sheetData>');

  var red = 1;
  b.write(_red(red, [_tekst('A$red', list.naslov, _sNaslov)]));
  red++;
  for (final p in list.podnaslovi) {
    b.write(_red(red, [_tekst('A$red', p, _sPodnaslov)]));
    red++;
  }
  red++; // prazan red

  b.write(
    _red(red, [
      for (var i = 0; i < brojKolona; i++)
        _tekst('${_kolona(i)}$red', list.kolone[i].naziv, _sZaglavlje),
    ]),
  );
  red++;

  for (final vrijednosti in list.redovi) {
    b.write(_red(red, _celije(list.kolone, vrijednosti, red, ukupno: false)));
    red++;
  }

  if (list.ukupno != null) {
    b.write(_red(red, _celije(list.kolone, list.ukupno!, red, ukupno: true)));
  }

  b.write('</sheetData>');
  if (list.redovi.isNotEmpty) {
    b.write(
      '<autoFilter ref="A$redZaglavlja:$zadnjaKolona'
      '${redZaglavlja + list.redovi.length}"/>',
    );
  }
  b.write(
    '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" '
    'header="0.3" footer="0.3"/>',
  );
  b.write('</worksheet>');
  return b.toString();
}

List<String> _celije(
  List<KolonaExcel> kolone,
  List<Object?> vrijednosti,
  int red, {
  required bool ukupno,
}) {
  final celije = <String>[];
  for (var i = 0; i < kolone.length && i < vrijednosti.length; i++) {
    final v = vrijednosti[i];
    if (v == null) continue;
    final ref = '${_kolona(i)}$red';
    final vrsta = kolone[i].vrsta;

    if (v is num) {
      if (!v.isFinite) continue;
      final stil = switch ((vrsta, ukupno)) {
        (VrstaKolone.iznos, false) => _sIznos,
        (VrstaKolone.iznos, true) => _sUkupnoIznos,
        (_, true) => _sUkupnoBroj,
        _ => 0,
      };
      celije.add(_broj(ref, v, stil));
    } else if (v is DateTime) {
      celije.add(_broj(ref, _excelDatum(v), _sDatum));
    } else {
      celije.add(_tekst(ref, '$v', ukupno ? _sUkupnoTekst : 0));
    }
  }
  return celije;
}

String _red(int broj, List<String> celije) =>
    '<row r="$broj">${celije.join()}</row>';

String _tekst(String ref, String tekst, int stil) {
  final s = stil == 0 ? '' : ' s="$stil"';
  return '<c r="$ref"$s t="inlineStr"><is><t xml:space="preserve">'
      '${_escape(tekst)}</t></is></c>';
}

String _broj(String ref, num broj, int stil) {
  final s = stil == 0 ? '' : ' s="$stil"';
  return '<c r="$ref"$s><v>$broj</v></c>';
}

// Excel datum: broj dana od 30.12.1899.
int _excelDatum(DateTime d) => DateTime.utc(
  d.year,
  d.month,
  d.day,
).difference(DateTime.utc(1899, 12, 30)).inDays;

// 0 -> A, 25 -> Z, 26 -> AA.
String _kolona(int indeks) {
  var n = indeks + 1;
  var rezultat = '';
  while (n > 0) {
    final ostatak = (n - 1) % 26;
    rezultat = String.fromCharCode(65 + ostatak) + rezultat;
    n = (n - 1) ~/ 26;
  }
  return rezultat;
}

String _escape(String tekst) => tekst
    // Kontrolni znakovi nisu dozvoljeni u XML-u.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

// Naziv lista: max 31 znak, bez []:*?/\, jedinstven u fajlu.
List<String> _jedinstveniNazivi(List<String> nazivi) {
  final zauzeti = <String>{};
  return [
    for (final n in nazivi)
      () {
        var cist = n.replaceAll(RegExp(r'[\[\]:*?/\\]'), '-').trim();
        if (cist.isEmpty) cist = 'List';
        if (cist.length > 31) cist = cist.substring(0, 31);
        var kandidat = cist;
        var i = 2;
        while (!zauzeti.add(kandidat.toLowerCase())) {
          final sufiks = ' ($i)';
          kandidat =
              '${cist.substring(0, (31 - sufiks.length).clamp(0, cist.length))}$sufiks';
          i++;
        }
        return kandidat;
      }(),
  ];
}

String _contentTypes(int brojListova) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    )
    ..write(
      '<Default Extension="rels" '
      'ContentType="application/vnd.openxmlformats-package.relationships+xml"/>',
    )
    ..write('<Default Extension="xml" ContentType="application/xml"/>')
    ..write(
      '<Override PartName="/xl/workbook.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>',
    )
    ..write(
      '<Override PartName="/xl/styles.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
  for (var i = 1; i <= brojListova; i++) {
    b.write(
      '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/'
      'vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
    );
  }
  b.write('</Types>');
  return b.toString();
}

const _rels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<String> nazivi) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    )
    ..write('<sheets>');
  for (var i = 0; i < nazivi.length; i++) {
    b.write(
      '<sheet name="${_escape(nazivi[i])}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
    );
  }
  b.write('</sheets></workbook>');
  return b.toString();
}

String _workbookRels(int brojListova) {
  final b = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
  for (var i = 1; i <= brojListova; i++) {
    b.write(
      '<Relationship Id="rId$i" Type="http://schemas.openxmlformats.org/'
      'officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$i.xml"/>',
    );
  }
  b.write(
    '<Relationship Id="rId${brojListova + 1}" Type="http://schemas.openxmlformats.org/'
    'officeDocument/2006/relationships/styles" Target="styles.xml"/>',
  );
  b.write('</Relationships>');
  return b.toString();
}

// Fontovi: 0 obični, 1 podebljan, 2 naslov, 3 sivi.
// Ispune: 0 i 1 obavezne, 2 svijetlosiva za zaglavlje.
// Formati: 4 = #,##0.00, 164 = datum dd.mm.yyyy.
const _stilovi =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="dd.mm.yyyy"/></numFmts>'
    '<fonts count="4">'
    '<font><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/><family val="2"/></font>'
    '<font><b/><sz val="14"/><color rgb="FF0A3238"/><name val="Calibri"/><family val="2"/></font>'
    '<font><sz val="10"/><color rgb="FF64748B"/><name val="Calibri"/><family val="2"/></font>'
    '</fonts>'
    '<fills count="3">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '<fill><patternFill patternType="solid"><fgColor rgb="FFE6F4F3"/><bgColor indexed="64"/></patternFill></fill>'
    '</fills>'
    '<borders count="3">'
    '<border><left/><right/><top/><bottom/><diagonal/></border>'
    '<border><left/><right/><top/><bottom style="thin"><color rgb="FF0F5C66"/></bottom><diagonal/></border>'
    '<border><left/><right/><top style="thin"><color rgb="FF0F5C66"/></top><bottom/><diagonal/></border>'
    '</borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="9">'
    // 0 obično
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    // 1 zaglavlje tabele
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>'
    // 2 iznos
    '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 3 datum
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    // 4 naslov
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    // 5 ukupno tekst
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="2" xfId="0" applyFont="1" applyBorder="1"/>'
    // 6 ukupno iznos
    '<xf numFmtId="4" fontId="1" fillId="0" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>'
    // 7 ukupno broj
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="2" xfId="0" applyFont="1" applyBorder="1"/>'
    // 8 podnaslov
    '<xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

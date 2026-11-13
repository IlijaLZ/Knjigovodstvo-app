import '../models/utrosak.dart';
import '../models/work_order.dart';
import 'excel_izvoz.dart';

// Excel za trebovanja: jedno trebovanje (materijali jednog naloga) i utrošak
// materijala za period (izvještaj servera). Čista logika bez
// Fluttera, da se može testirati.

String _datum(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}.';

// Materijali jednog trebovanja, grupisani po proizvodu.
ListExcel trebovanjeList({
  required Trebovanje trebovanje,
  required RadniNalog nalog,
  required String firma,
}) {
  final broj = (trebovanje.brojNaloga ?? nalog.broj).trim();
  final kupac = trebovanje.kupac ?? nalog.kupac;
  final izdat = nalog.jeIzdat;

  return ListExcel(
    naziv: 'Trebovanje $broj',
    naslov: 'Trebovanje · Radni nalog $broj',
    podnaslovi: [
      firma,
      [
        if (kupac != null && kupac.isNotEmpty) 'Kupac: $kupac',
        'Datum: ${_datum(trebovanje.datum ?? nalog.datum)}',
        izdat ? 'Izdato ${_datum(nalog.izdatU)}' : 'U pripremi',
      ].join(' · '),
    ],
    kolone: const [
      KolonaExcel('Proizvod', sirina: 28),
      KolonaExcel('Kol. proizvoda', vrsta: VrstaKolone.broj, sirina: 14),
      KolonaExcel('Materijal', sirina: 28),
      KolonaExcel('JM', sirina: 7),
      KolonaExcel('Norma', vrsta: VrstaKolone.broj, sirina: 10),
      KolonaExcel('Traženo', vrsta: VrstaKolone.broj, sirina: 11),
      KolonaExcel('Izdato', vrsta: VrstaKolone.broj, sirina: 11),
      KolonaExcel('Vrijednost', vrsta: VrstaKolone.iznos, sirina: 14),
    ],
    redovi: [
      for (final s in trebovanje.stavke)
        for (final m in s.materijali)
          [
            s.naziv,
            s.kolicina,
            m.naziv,
            m.jm,
            m.norma,
            m.trazeno,
            // U pripremi `izdato` postoji samo za ručno upisane količine.
            m.izdato ?? (izdat ? null : m.trazeno),
            m.vrijednost,
          ],
    ],
    ukupno: [
      'Ukupno',
      null,
      '${trebovanje.materijali.length} materijala',
      null,
      null,
      null,
      null,
      trebovanje.vrijednost,
    ],
  );
}

// Utrošak materijala iz izvještaja servera: zbir po materijalu i drugi list
// sa svakim nalogom, proizvodom i materijalom.
List<ListExcel> utrosakListovi({
  required IzvjestajUtroska izvjestaj,
  required String firma,
  required DateTime od,
  required DateTime doDatuma,
}) {
  final period = '${_datum(od)} – ${_datum(doDatuma)}';
  final materijali = [...izvjestaj.materijali]
    ..sort((a, b) => b.vrijednost.compareTo(a.vrijednost));
  final nalozi = izvjestaj.poNalozima.map((r) => r.workOrderId).toSet();
  final poNalozima = [...izvjestaj.poNalozima]
    ..sort((a, b) {
      final c = (a.izdatU ?? DateTime(0)).compareTo(b.izdatU ?? DateTime(0));
      return c != 0 ? c : a.brojNaloga.compareTo(b.brojNaloga);
    });

  final napomena =
      'Period po datumu izdavanja naloga. Kartica artikla izdavanje knjiži '
      'na datum naloga, pa se za isti period može razlikovati.';

  return [
    ListExcel(
      naziv: 'Utrošak',
      naslov: 'Utrošak materijala',
      podnaslovi: [
        firma,
        [
          'Period: $period',
          if (nalozi.isNotEmpty) 'izdatih naloga: ${nalozi.length}',
        ].join(' · '),
        napomena,
      ],
      kolone: const [
        KolonaExcel('Šifra', sirina: 12),
        KolonaExcel('Materijal', sirina: 32),
        KolonaExcel('JM', sirina: 7),
        KolonaExcel('Izdato', vrsta: VrstaKolone.broj, sirina: 12),
        KolonaExcel('Prosj. cijena', vrsta: VrstaKolone.broj, sirina: 14),
        KolonaExcel('Vrijednost', vrsta: VrstaKolone.iznos, sirina: 15),
        KolonaExcel('Naloga', vrsta: VrstaKolone.broj, sirina: 9),
      ],
      redovi: [
        for (final m in materijali)
          [
            m.sifra,
            m.naziv,
            m.jm,
            m.kolicina,
            m.prosjecnaCijena == null
                ? null
                : (m.prosjecnaCijena! * 10000).roundToDouble() / 10000,
            m.vrijednost,
            m.brojNaloga,
          ],
      ],
      ukupno: [
        'Ukupno',
        '${materijali.length} materijala',
        null,
        null,
        null,
        izvjestaj.ukupnaVrijednost,
        null,
      ],
    ),
    ListExcel(
      naziv: 'Po nalozima',
      naslov: 'Utrošak materijala po radnim nalozima',
      podnaslovi: [firma, 'Period: $period'],
      kolone: const [
        KolonaExcel('Izdat', vrsta: VrstaKolone.datum, sirina: 12),
        KolonaExcel('Datum naloga', vrsta: VrstaKolone.datum, sirina: 13),
        KolonaExcel('Nalog', sirina: 14),
        KolonaExcel('Kupac', sirina: 24),
        KolonaExcel('Proizvod', sirina: 26),
        KolonaExcel('Kol. proizvoda', vrsta: VrstaKolone.broj, sirina: 14),
        KolonaExcel('Šifra mat.', sirina: 12),
        KolonaExcel('Materijal', sirina: 28),
        KolonaExcel('JM', sirina: 7),
        KolonaExcel('Izdato', vrsta: VrstaKolone.broj, sirina: 11),
        KolonaExcel('Vrijednost', vrsta: VrstaKolone.iznos, sirina: 14),
      ],
      redovi: [
        for (final r in poNalozima)
          [
            r.izdatU,
            r.datum,
            r.brojNaloga,
            r.kupac,
            r.proizvod,
            r.kolicinaProizvoda,
            r.sifra,
            r.naziv,
            r.jm,
            r.kolicina,
            r.vrijednost,
          ],
      ],
      ukupno: [
        'Ukupno',
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        null,
        poNalozima.fold<double>(0, (s, r) => s + r.vrijednost),
      ],
    ),
  ];
}

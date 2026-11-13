import 'package:get/get.dart';

import '../controllers/navigation_controller.dart';
import '../routes/app_routes.dart';
import 'analiticka_kartica_glasom.dart';
import 'izvoz_glasom.dart';

// Glasovne komande: izgovoreni tekst -> ekran.
// Cijela funkcija je u folderu lib/glasovne_komande/; za uklanjanje vidi
// README.md u istom folderu.

// Kako zec izgleda dok odgovara (svako raspoloženje ima svoju sliku).
enum ZecRaspolozenje {
  slusa, // ruka iza uha
  pise, // diktira se u polje — piše na bloku
  prica, // objašnjava
  racuna, // traži artikal lupom
  klik, // kalkulator "KLIK!" i palac gore — komanda izvršena
  zbunjen, // češe se po glavi — nije razumio
  greska, // zapetljan mikrofon — mikrofon/dozvola/mreža ne radi
}

typedef ZecKaze = void Function(String tekst, [ZecRaspolozenje raspolozenje]);

class GlasovnaKomanda {
  // Naziv ekrana kako piše u meniju (za poruku "Otvaram: …").
  final String naziv;

  // Svaka grupa je lista alternativa; komanda odgovara ako tekst sadrži
  // bar jednu alternativu iz SVAKE grupe. Alternative su korijeni riječi
  // bez kvačica (npr. 'trebovanj' hvata trebovanje, trebovanja, trebovanju).
  final List<List<String>> grupe;

  // Ekran (lista) koji se otvara u glavnom prozoru.
  final void Function(NavigationController c) otvori;

  // Ekran za dodavanje (ruta) koji se otvara preko liste, ili null.
  final String? ruta;

  // Poruka nakon što se na ekranu za dodavanje sačuva dokument.
  final String? sacuvano;

  // Poruka umjesto "Otvaram: …".
  final String? napomena;

  // Posebna radnja umjesto otvaranja ekrana; dobija cijeli izgovoreni tekst
  // (npr. naziv artikla) i funkciju kojom zec odgovara korisniku.
  final Future<void> Function(String izgovoreno, ZecKaze kaze)? akcija;

  // Riječi zbog kojih komanda NE odgovara (npr. "koštanja" kod nabavnih).
  final List<String> bez;

  // Rezervne riječi za zadnju grupu, koriste se tek kad nijedna komanda ne
  // odgovara ni tačno ni približno (npr. Apple "trebovanja" zna čuti samo
  // kao "trebao"). Razmak ispred = početak riječi.
  final List<String> rezerva;

  // Bez približnog poklapanja (npr. "zatvori" je jedno slovo od "otvori").
  final bool samoTacno;

  // Prije komande se zatvara sve otvoreno preko glavnog prozora (kartica,
  // dijalog…). Ne važi za "zatvori" i za izvoz ekrana koji je navrhu.
  final bool naGlavni;

  const GlasovnaKomanda(
    this.naziv,
    this.grupe,
    this.otvori, {
    this.ruta,
    this.sacuvano,
    this.napomena,
    this.akcija,
    this.bez = const [],
    this.rezerva = const [],
    this.samoTacno = false,
    this.naGlavni = true,
  });

  bool rezervno(String tekst) {
    if (rezerva.isEmpty || _zabranjeno(tekst)) return false;
    final t = ' $tekst ';
    final sve = [
      ...grupe.take(grupe.length - 1),
      [...grupe.last, ...rezerva],
    ];
    return sve.every((g) => g.any(t.contains));
  }

  bool _zabranjeno(String tekst) => bez.any(tekst.contains);

  bool odgovara(String tekst) =>
      !_zabranjeno(tekst) &&
      grupe.every((g) => g.any((rijec) => ' $tekst'.contains(rijec)));

  // Kao [odgovara], ali trpi greške prepoznavača: razmaci se ignorišu
  // ("trebao vanja" -> "trebaovanja") i dozvoljeno je malo slova razlike.
  bool priblizno(String tekst) {
    if (samoTacno || _zabranjeno(tekst)) return false;
    final spojeno = tekst.replaceAll(' ', '');
    return grupe.every(
      (g) => g.any((rijec) {
        final r = rijec.replaceAll(' ', '');
        if (r.isEmpty) return false;
        final dozvoljeno = _dozvoljenoGresaka(r.length);
        return dozvoljeno == 0
            ? spojeno.contains(r)
            : _udaljenostUTekstu(r, spojeno) <= dozvoljeno;
      }),
    );
  }
}

// Kratke riječi (radn, firm, kupc…) moraju se poklopiti tačno, inače bi
// hvatale svašta.
int _dozvoljenoGresaka(int duzina) => duzina >= 12
    ? 2
    : duzina >= 6
    ? 1
    : 0;

// Najmanji broj izmjena (slovo više, manje ili drugo) da se [uzorak] nađe
// bilo gdje unutar [tekst] (Levenshtein nad podnizom).
int _udaljenostUTekstu(String uzorak, String tekst) {
  var prethodni = List<int>.filled(tekst.length + 1, 0);
  for (var i = 1; i <= uzorak.length; i++) {
    final trenutni = List<int>.filled(tekst.length + 1, i);
    for (var j = 1; j <= tekst.length; j++) {
      final zamjena =
          prethodni[j - 1] + (uzorak[i - 1] == tekst[j - 1] ? 0 : 1);
      final brisanje = prethodni[j] + 1;
      final umetanje = trenutni[j - 1] + 1;
      trenutni[j] = [
        zamjena,
        brisanje,
        umetanje,
      ].reduce((a, b) => a < b ? a : b);
    }
    prethodni = trenutni;
  }
  return prethodni.reduce((a, b) => a < b ? a : b);
}

// Redoslijed je bitan: specifičnije komande idu prije opštijih
// (npr. "kalkulacija cijene koštanja" prije "kalkulacija").
// Riječi koje znače "dodaj novi dokument". Razmak ispred = početak riječi
// (da "ponovo" ne bude "novo").
const List<String> _dodavanje = [
  ' doda',
  ' novi',
  ' novo',
  ' nova',
  ' novu',
  ' novog',
  ' napravi',
  ' kreiraj',
  ' unesi',
  ' unos',
];

// ---- Izvoz u Excel ------------------------------------------------------
// Čim u rečenici bilo gdje ima riječ za izvoz ("excel", "izvezi"…), pravi
// se Excel: "radne naloge u excel", "u excel radne naloge" i "napravi mi u
// excelu radne naloge" izvoze radne naloge. Ostatak rečenice se traži kao
// obična komanda (sa svim greškama prepoznavača, npr. "trebao"), ali bez
// dodavanja: "napravi radni nalog u excelu" je izvoz, ne novi nalog.

// Počeci riječi za izvoz, i kako ih Apple zna čuti ("izvezi" -> "svezi",
// "izvesti"; "excel" -> "eksel"…).
const List<String> _rijeciIzvoza = [
  'izvez',
  'eksport',
  'export',
  'tabel',
  'izves',
  'izvoz',
  'svezi',
  'excel',
  'exel',
  'eksel',
  'ekscel',
  'ekcel',
];

bool _rijecIzvoza(String rijec) => _rijeciIzvoza.any(rijec.startsWith);

// Ako u (normalizovanoj) rečenici bilo gdje ima riječ za izvoz, vraća
// rečenicu bez tih riječi ("radne naloge u excel" -> "radne naloge u";
// samo "excel" -> ""). Inače null.
String? ostatakBezIzvoza(String tekst) {
  final rijeci = tekst.split(' ').where((r) => r.isNotEmpty).toList();
  if (!rijeci.any(_rijecIzvoza)) return null;
  return rijeci.where((r) => !_rijecIzvoza(r)).join(' ');
}

// "Izvezi u excel" bez ekrana: izvoz ekrana koji je otvoren.
final GlasovnaKomanda komandaIzvozaTrenutnog = GlasovnaKomanda(
  'Izvoz u Excel',
  const [],
  (c) {},
  akcija: izveziTrenutni,
  naGlavni: false,
);

// Ekrani sa dugmetom "Excel", po nazivu komande za otvaranje.
final Map<String, GlasovnaKomanda> _izvozEkrana = {
  for (final (naziv, otvori) in <(String, void Function(NavigationController))>[
    ('Kalkulacija nabavnih cijena', (c) => c.openKalkulacijaNabavnihCijena()),
    ('Radni nalog', (c) => c.openRadniNalog()),
    ('Artikli gotovih proizvoda', (c) => c.openArtikliGotovihProizvoda()),
    ('Artikli repromaterijala', (c) => c.openArtikliRepromaterijala()),
    ('Dobavljači', (c) => c.openDobavljaci()),
    ('Kupci', (c) => c.openKupci()),
    ('Magacin gotovih proizvoda', (c) => c.openStanjeGotovihProizvoda()),
    ('Magacin proizvodnje u toku', (c) => c.openStanjeProizvodnje()),
    ('Magacin repromaterijala', (c) => c.openStanjeMagacina()),
  ])
    naziv: GlasovnaKomanda(
      'Excel: $naziv',
      const [],
      otvori,
      akcija: (_, kaze) => izveziNaEkranu(naziv, otvori, kaze),
    ),
};

// Šta zec kaže kad se traži izvoz ekrana koji nema izvoz liste.
const Map<String, String> _bezIzvozaNapomena = {
  'Trebovanje':
      'Klik! Otvaram trebovanja. Za Excel otvori jedno trebovanje i reci '
      '„izvezi u excel”.',
};

// Ekran bez izvoza: samo se otvori (bez ekrana za dodavanje), uz objašnjenje.
GlasovnaKomanda _bezIzvoza(GlasovnaKomanda ekran) => GlasovnaKomanda(
  ekran.naziv,
  ekran.grupe,
  ekran.otvori,
  bez: ekran.bez,
  rezerva: ekran.rezerva,
  napomena:
      _bezIzvozaNapomena[ekran.naziv] ??
      'Klik! Otvaram ${ekran.naziv}. Tu nema izvoza u Excel.',
);

GlasovnaKomanda _komandaIzvoza(String ostatak) {
  final ekran = ostatak.isEmpty ? null : _trazi(ostatak, bezDodavanja: true);
  if (ekran == null) return komandaIzvozaTrenutnog;
  // Komande sa svojom radnjom (analitička kartica) rade kao i inače.
  return _izvozEkrana[ekran.naziv] ??
      (ekran.akcija != null ? ekran : _bezIzvoza(ekran));
}

// Kako Apple zna (pogrešno) čuti "trebovanje/trebovanja".
const List<String> _rezervaTrebovanje = [
  ' trebao',
  ' trebal',
  ' treba ',
  ' trebav',
  ' trebov',
];

final List<GlasovnaKomanda> glasovneKomande = [
  // "Zatvori …" / "nazad": prvo, da "zatvori trebovanja" ne otvori
  // trebovanja.
  GlasovnaKomanda(
    'Zatvori',
    [
      [
        ' zatvori',
        ' nazad',
        ' izadji',
        ' izlaz',
        ' odustani',
        ' vrati se nazad',
      ],
    ],
    (c) => c.openPocetna(),
    akcija: zatvoriEkran,
    samoTacno: true,
    naGlavni: false,
  ),
  // Dodavanje ide prije otvaranja liste: "novi radni nalog" ne smije samo
  // otvoriti listu radnih naloga.
  GlasovnaKomanda(
    'Novi radni nalog',
    [
      _dodavanje,
      // "novi nalog" je uvijek radni (knjiženje naloga nema unos).
      ['nalog', 'naloz'],
    ],
    (c) => c.openRadniNalog(),
    bez: ['knjiz'],
    ruta: AppRoutes.dodajRadniNalog,
    sacuvano: 'Radni nalog je sačuvan.',
  ),
  // Trebovanje nema svoj unos: pravi se iz radnog naloga.
  GlasovnaKomanda(
    'Novi radni nalog',
    [
      _dodavanje,
      ['trebovanj', 'trebovan'],
    ],
    (c) => c.openTrebovanje(),
    rezerva: _rezervaTrebovanje,
    ruta: AppRoutes.dodajRadniNalog,
    sacuvano: 'Radni nalog je sačuvan, trebovanje je spremno.',
    napomena:
        'Trebovanje se pravi iz radnog naloga — otvaram novi radni nalog.',
  ),
  GlasovnaKomanda(
    'Nova kalkulacija nabavnih cijena',
    [
      _dodavanje,
      ['kalkulacij', 'nabavn'],
    ],
    (c) => c.openKalkulacijaNabavnihCijena(),
    ruta: AppRoutes.dodajKalkulacijuNabavnuCijenu,
    sacuvano: 'Kalkulacija je sačuvana.',
    bez: ['kostanj'],
  ),
  GlasovnaKomanda('Kalk. cijene koštanja', [
    ['kostanj'],
  ], (c) => c.openKalkulacijaCijeneKostanja()),
  GlasovnaKomanda('Kalkulacija nabavnih cijena', [
    ['kalkulacij', 'nabavn'],
  ], (c) => c.openKalkulacijaNabavnihCijena()),
  GlasovnaKomanda('Knjiženje naloga', [
    ['knjizenj', 'knjizi'],
  ], (c) => c.openKnjizenjeNaloga()),
  // Apple "radni nalozi" zna čuti kao "radni nalazi".
  GlasovnaKomanda('Radni nalog', [
    ['radn'],
    ['nalog', 'naloz', 'nalaz'],
  ], (c) => c.openRadniNalog()),
  GlasovnaKomanda(
    'Trebovanje',
    [
      ['trebovanj', 'trebovan'],
    ],
    (c) => c.openTrebovanje(),
    rezerva: _rezervaTrebovanje,
  ),
  GlasovnaKomanda('Otpremnica', [
    ['otpremnic'],
  ], (c) => c.openOtpremnica()),
  // "Analitička kartica brašna": nađe artikal i otvori njegovu karticu.
  GlasovnaKomanda(
    'Analitička kartica',
    [
      ['analitick', 'analiticn'],
    ],
    (c) => c.openStanjeMagacina(),
    akcija: otvoriAnalitickuKarticu,
  ),
  GlasovnaKomanda(
    'Kartica glavne knjige',
    [
      ['kartic'],
    ],
    (c) => c.openKarticaGlavneKnjige(),
    bez: ['analitick', 'analiticn'],
  ),
  // Isto kao stavka "Glavna knjiga" u meniju.
  GlasovnaKomanda('Glavna knjiga', [
    ['glavn'],
    ['knjig'],
  ], (c) => c.openOFirmi()),
  GlasovnaKomanda('Artikli gotovih proizvoda', [
    ['artikl', 'artikal'],
    ['gotov'],
  ], (c) => c.openArtikliGotovihProizvoda()),
  // "Stanje/zalihe repromaterijala" je magacin, ne šifarnik artikala.
  GlasovnaKomanda(
    'Artikli repromaterijala',
    [
      ['artikl', 'artikal', 'repromaterijal'],
    ],
    (c) => c.openArtikliRepromaterijala(),
    bez: ['stanj', 'zalih', 'magacin'],
  ),
  GlasovnaKomanda('Dobavljači', [
    ['dobavljac'],
  ], (c) => c.openDobavljaci()),
  GlasovnaKomanda('Kupci', [
    ['kupc', 'kupac'],
  ], (c) => c.openKupci()),
  GlasovnaKomanda('Poslovne godine', [
    ['poslovn', 'godin'],
  ], (c) => c.openPoslovneGodine()),
  GlasovnaKomanda('Firme', [
    ['firm'],
  ], (c) => c.openFirme()),
  GlasovnaKomanda('Magacin gotovih proizvoda', [
    ['magacin', 'stanj', 'zalih', 'gotov'],
    ['gotov'],
  ], (c) => c.openStanjeGotovihProizvoda()),
  GlasovnaKomanda('Magacin proizvodnje u toku', [
    ['proizvodnj', 'u toku'],
  ], (c) => c.openStanjeProizvodnje()),
  GlasovnaKomanda('Magacin repromaterijala', [
    ['magacin', 'stanj', 'zalih'],
  ], (c) => c.openStanjeMagacina()),
  GlasovnaKomanda('Početna', [
    ['pocetn', 'naslovn', 'glavni ekran'],
  ], (c) => c.openPocetna()),
];

// Zatvara otvoreni ekran (karticu, unos naloga…) ili vraća na početnu.
Future<void> zatvoriEkran(String _, ZecKaze kaze) async {
  final navigator = Get.key.currentState;
  if (navigator != null && navigator.canPop()) {
    // maybePop: ekran za unos sam odlučuje (npr. ne pušta dok čuva).
    await navigator.maybePop();
    kaze('Klik! Zatvoreno.', ZecRaspolozenje.klik);
  } else {
    Get.find<NavigationController>().openPocetna();
    kaze('Klik! Vraćam te na početnu.', ZecRaspolozenje.klik);
  }
}

// Poznate greške Apple prepoznavanja, da oblačić pokaže ono što je
// korisnik stvarno rekao ("trebao Vanje" -> "trebovanje").
final List<(RegExp, String)> _ispravke = [
  (
    RegExp(r'\btreba?o?\s+vanj(a|e|i|u)\b', caseSensitive: false),
    'trebovanj\$1',
  ),
  (RegExp(r'\bzabavnih\b', caseSensitive: false), 'nabavnih'),
  (RegExp(r'\b(radn\w*)\s+nalaz(\w*)', caseSensitive: false), '\$1 naloz\$2'),
  // "izvezi" Apple zna čuti kao "svezi" ili "izvesti".
  (RegExp(r'^\s*(svezi|izvesti)\b', caseSensitive: false), 'izvezi'),
];

String ispraviPrikaz(String tekst) {
  var t = tekst;
  for (final (uzorak, zamjena) in _ispravke) {
    t = t.replaceAllMapped(uzorak, (m) {
      var z = zamjena;
      for (var i = 1; i <= m.groupCount; i++) {
        z = z.replaceAll('\$$i', m.group(i) ?? '');
      }
      return z;
    });
  }
  return t;
}

// Komanda za izgovoreni tekst, ili null. Ako u rečenici ima riječ za
// izvoz (bilo gdje), komanda izvozi traženi ekran.
GlasovnaKomanda? pronadjiKomandu(String izgovoreno) {
  final tekst = normalizuj(izgovoreno);
  if (tekst.isEmpty) return null;
  // "Zatvori" uvijek ima prednost ("zatvori excel").
  final zatvori = glasovneKomande.first;
  if (zatvori.odgovara(tekst)) return zatvori;
  final ostatak = ostatakBezIzvoza(tekst);
  if (ostatak != null) return _komandaIzvoza(ostatak);
  return _trazi(tekst);
}

// Prva komanda koja odgovara (normalizovanom) tekstu, ili null. Sa
// bezDodavanja se preskaču "zatvori" i ekrani za dodavanje (za izvoz).
GlasovnaKomanda? _trazi(String tekst, {bool bezDodavanja = false}) {
  final komande = bezDodavanja
      ? glasovneKomande.where((k) => k.ruta == null && k.akcija != zatvoriEkran)
      : glasovneKomande;
  // Prvo tačno poklapanje, pa tek onda približno, da približno ne "ukrade"
  // komandu koja se tačno poklapa niže u listi.
  for (final k in komande) {
    if (k.odgovara(tekst)) return k;
  }
  for (final k in komande) {
    if (k.priblizno(tekst)) return k;
  }
  for (final k in komande) {
    if (k.rezervno(tekst)) return k;
  }
  return null;
}

const Map<String, String> _bezKvacica = {
  'č': 'c',
  'ć': 'c',
  'š': 's',
  'ž': 'z',
  'đ': 'dj',
};

// Ćirilica -> latinica (ako prepoznavač vrati srpsku ćirilicu).
const Map<String, String> _cirilica = {
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'ђ': 'dj',
  'е': 'e',
  'ж': 'z',
  'з': 'z',
  'и': 'i',
  'ј': 'j',
  'к': 'k',
  'л': 'l',
  'љ': 'lj',
  'м': 'm',
  'н': 'n',
  'њ': 'nj',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'ћ': 'c',
  'у': 'u',
  'ф': 'f',
  'х': 'h',
  'ц': 'c',
  'ч': 'c',
  'џ': 'dz',
  'ш': 's',
};

// Mala slova, bez kvačica, latinica, samo slova i razmaci.
String normalizuj(String tekst) {
  final b = StringBuffer();
  for (final ch in tekst.toLowerCase().split('')) {
    b.write(_bezKvacica[ch] ?? _cirilica[ch] ?? ch);
  }
  return b
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

// Obrada diktata za polja: ispravke ("1232 ne nego 1234"), brojevi riječima
// ("hiljadu dvjesto" -> 1200), "obriši", "dalje" (sljedeće polje).
// Čista logika bez Fluttera, da se može testirati.

import 'dart:math' as math;

import 'glasovne_komande.dart' show normalizuj;

enum VrstaPolja { tekst, broj }

class RezultatDiktata {
  final String tekst;

  // Korisnik je rekao "obriši" — polje treba isprazniti.
  final bool obrisi;

  const RezultatDiktata(this.tekst, {this.obrisi = false});

  bool get prazno => tekst.isEmpty && !obrisi;
}

const _granicaPrije = r'(?<![\p{L}\p{N}])';
const _granicaPoslije = r'(?![\p{L}\p{N}])';

// "dalje", "sljedeće (polje)" -> prelazak u sljedeće polje.
final RegExp _dalje = RegExp(
  '$_granicaPrije(?:dalje|sljede[cć]e|slijede[cć]e|slede[cć]e|idu[cć]e|naredno)'
  '(?:\\s+polje)?$_granicaPoslije[,.]?',
  caseSensitive: false,
  unicode: true,
);

// Riječi kojima korisnik ispravlja ono što je upravo rekao.
const _ispravke =
    r'ne,?\s+nego|ne,?\s+ne|ma\s+ne|nego|ustvari|u\s+stvari|zapravo|'
    r'izvini(?:te)?|pardon|ispravka|pogre[sš]no|gre[sš]ka|odnosno';

final RegExp _ispravkaTekst = RegExp(
  '$_granicaPrije(?:$_ispravke)$_granicaPoslije[,.:]?',
  caseSensitive: false,
  unicode: true,
);

// U brojčanom polju i samo "ne" znači ispravku ("1232 ne 1234").
final RegExp _ispravkaBroj = RegExp(
  '$_granicaPrije(?:$_ispravke|ne)$_granicaPoslije[,.:]?',
  caseSensitive: false,
  unicode: true,
);

final RegExp _obrisi = RegExp(
  r'^(?:obrisi|izbrisi|brisi|ocisti|isprazni)(?: sve| polje| to)?$',
);

// Dijelovi diktata za uzastopna polja ("1234 dalje Marko" -> [1234, Marko]).
List<String> podijeliNaPolja(String izgovoreno) =>
    izgovoreno.split(_dalje).map((d) => d.trim()).toList();

// [oznaka] je naziv polja ("Izdao"); izbacuje se ako je izgovoren uz
// vrijednost ("Marko je izdao" -> "Marko").
RezultatDiktata obradiDiktat(String dio, VrstaPolja vrsta, {String? oznaka}) {
  var t = _ocisti(dio);
  if (_obrisi.hasMatch(normalizuj(t))) {
    return const RezultatDiktata('', obrisi: true);
  }

  // Vrijedi ono rečeno poslije zadnje ispravke. Ako poslije nje još ništa
  // nije rečeno (uživo: "1232 ne nego …"), ostaje ono prije.
  final uzorak = vrsta == VrstaPolja.broj ? _ispravkaBroj : _ispravkaTekst;
  final ispravke = uzorak.allMatches(t).toList();
  for (final m in ispravke.reversed) {
    final poslije = _ocisti(t.substring(m.end));
    if (poslije.isNotEmpty) {
      t = poslije;
      break;
    }
    t = _ocisti(t.substring(0, m.start));
  }
  if (_obrisi.hasMatch(normalizuj(t))) {
    return const RezultatDiktata('', obrisi: true);
  }
  t = bezNazivaPolja(t, oznaka);

  if (vrsta == VrstaPolja.broj) return RezultatDiktata(uBroj(t));
  // Tekstualno polje: ako je izgovoren samo broj ("sto dvadeset"), upiši
  // cifre; inače tekst kako je prepoznat.
  return RezultatDiktata(samoBroj(t) ? uBroj(t) : saZnakovima(t));
}

// Riječi oko vrijednosti koje nisu dio nje ("je", "neka bude", "upiši"…).
const Set<String> _popuna = {
  'je',
  'su',
  'to',
  'ovo',
  'ovaj',
  'ova',
  'ono',
  'neka',
  'bude',
  'upisi',
  'upisite',
  'stavi',
  'stavite',
  'napisi',
  'napisite',
  'unesi',
  'unesite',
  'pise',
  'treba',
  'da',
  'bio',
  'bila',
  'bilo',
  'mi',
  'nam',
  'a',
  'i',
  'kao',
  'polje',
  'u',
  'za',
  'jeste',
  'ga',
  'ju',
  'molim',
  'te',
};

// Korijen riječi naziva polja: "izdao" -> "izda" (hvata i "izdala").
String _korijenOznake(String rijec) => rijec.length <= 4
    ? rijec
    : rijec.substring(0, math.max(4, rijec.length - 2));

// Izbacuje naziv polja i popunu sa početka i kraja: "Marko je izdao",
// "izdao je Marko", "Broj računa je 1234". Sredina ostaje ("Marko i Ivan").
String bezNazivaPolja(String tekst, String? oznaka) {
  final korijeni = normalizuj(
    oznaka ?? '',
  ).split(' ').where((r) => r.length >= 3).map(_korijenOznake).toList();
  final rijeci = tekst
      .split(RegExp(r'\s+'))
      .where((r) => r.isNotEmpty)
      .toList();

  bool visak(String rijec) {
    final n = normalizuj(rijec).replaceAll(' ', '');
    if (n.isEmpty) return true;
    return _popuna.contains(n) || korijeni.any(n.startsWith);
  }

  // Bez naziva polja u rečenici ne diramo popunu ("da" može biti vrijednost).
  final imaNaziv = rijeci.any((r) {
    final n = normalizuj(r).replaceAll(' ', '');
    return n.isNotEmpty && korijeni.any(n.startsWith);
  });
  if (!imaNaziv) return tekst;

  var od = 0, doo = rijeci.length;
  while (od < doo && visak(rijeci[od])) {
    od++;
  }
  while (doo > od && visak(rijeci[doo - 1])) {
    doo--;
  }
  // Ako bi ostalo prazno (rečen samo naziv), ništa se ne izbacuje.
  if (od >= doo) return tekst;
  return _ocisti(rijeci.sublist(od, doo).join(' '));
}

String _ocisti(String s) =>
    s.trim().replaceAll(RegExp(r'^[,.:;\s]+|[,.:;!?\s]+$'), '').trim();

// --- Brojevi -----------------------------------------------------------------

const Map<String, int> _jedinice = {
  'nula': 0,
  'jedan': 1,
  'jedna': 1,
  'jedno': 1,
  'jednu': 1,
  'dva': 2,
  'dvije': 2,
  'dve': 2,
  'tri': 3,
  'cetiri': 4,
  'pet': 5,
  'sest': 6,
  'sedam': 7,
  'osam': 8,
  'devet': 9,
  'deset': 10,
  'jedanaest': 11,
  'dvanaest': 12,
  'trinaest': 13,
  'cetrnaest': 14,
  'petnaest': 15,
  'sesnaest': 16,
  'sedamnaest': 17,
  'osamnaest': 18,
  'devetnaest': 19,
  'dvadeset': 20,
  'trideset': 30,
  'cetrdeset': 40,
  'cetresdeset': 40,
  'pedeset': 50,
  'sezdeset': 60,
  'sedamdeset': 70,
  'osamdeset': 80,
  'devedeset': 90,
  'sto': 100,
  'stotinu': 100,
  'stotina': 100,
  'dvjesto': 200,
  'dvesta': 200,
  'dvjesta': 200,
  'dvista': 200,
  'tristo': 300,
  'trista': 300,
  'cetiristo': 400,
  'cetristo': 400,
  'petsto': 500,
  'pesto': 500,
  'seststo': 600,
  'sesto': 600,
  'sedamsto': 700,
  'osamsto': 800,
  'devetsto': 900,
};

const Map<String, int> _mnozitelji = {
  'hiljadu': 1000,
  'hiljada': 1000,
  'hiljade': 1000,
  'tisucu': 1000,
  'tisuca': 1000,
  'tisuce': 1000,
  'milion': 1000000,
  'miliona': 1000000,
  'milijun': 1000000,
  'milijuna': 1000000,
  'milijon': 1000000,
};

const Set<String> _decimalno = {
  'zarez',
  'koma',
  'cijelih',
  'cijela',
  'tacka',
  'tocka',
};

bool _brojRijec(String n) =>
    _jedinice.containsKey(n) || _mnozitelji.containsKey(n);

// Da li je izgovoreno samo broj (riječima i/ili ciframa).
bool samoBroj(String tekst) {
  // Znakovi ("318/20", "RN-5") znače oznaku, ne jedan broj.
  if (RegExp(r'[/\\\-_:+%()]').hasMatch(tekst)) return false;
  // Više separatora (15.11.2026) je datum/oznaka.
  if (RegExp(r'\d[.,]\d+[.,]\d').hasMatch(tekst)) return false;
  final rijeci = normalizuj(tekst).split(' ').where((r) => r.isNotEmpty);
  if (rijeci.isEmpty) return false;
  var imaBroj = false;
  var decimala = 0;
  for (final r in rijeci) {
    if (RegExp(r'^\d+$').hasMatch(r) || _brojRijec(r)) {
      imaBroj = true;
    } else if (_decimalno.contains(r)) {
      decimala++;
    } else if (r != 'i' && r != 'po') {
      return false;
    }
  }
  // Više "tačaka" je datum/oznaka (15.11.2026), ne decimalni broj.
  return imaBroj && decimala <= 1;
}

// Izgovoreni broj -> cifre sa decimalnim zarezom ("dva zarez pet" -> 2,5,
// "1.232" -> 1232, "12 34" -> 1234). Sve što nije broj se izbacuje.
String uBroj(String tekst) {
  // Tokeni sa originalnim ciframi i separatorima (1.232 / 2,5 / 2.5).
  final tokeni = tekst
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .toList();

  final izlaz = StringBuffer();
  var ukupno = 0, tekuci = 0;
  var imaRijeci = false;
  // Najmanje mjesto koje je u tekućem broju već popunjeno (1 = jedinice,
  // 2 = desetice, 3 = stotine); sljedeća riječ mora biti manjeg mjesta.
  var slobodno = 4;

  void isprazni() {
    if (!imaRijeci) return;
    izlaz.write(ukupno + tekuci);
    ukupno = 0;
    tekuci = 0;
    slobodno = 4;
    imaRijeci = false;
  }

  for (var i = 0; i < tokeni.length; i++) {
    final sirovo = tokeni[i];
    final n = normalizuj(sirovo).replaceAll(' ', '');
    if (RegExp(r'\d').hasMatch(sirovo)) {
      isprazni();
      izlaz.write(_cifre(sirovo));
    } else if (n == 'nula') {
      isprazni();
      izlaz.write('0');
    } else if (_jedinice.containsKey(n)) {
      final v = _jedinice[n]!;
      // Broj se slaže od većeg mjesta ka manjem (sto, dvadeset, tri). Ako
      // dođe isto ili veće mjesto, to je nova cifra/broj: "jedan dva tri"
      // -> 123, "dvadeset dvadeset" -> 2020.
      final mjesto = v >= 100
          ? 3
          : v >= 10
          ? 2
          : 1;
      if (tekuci > 0 && mjesto >= slobodno) isprazni();
      tekuci += v;
      slobodno = v >= 10 && v < 20 ? 1 : mjesto;
      imaRijeci = true;
    } else if (_mnozitelji.containsKey(n)) {
      final m = _mnozitelji[n]!;
      ukupno += (tekuci == 0 ? 1 : tekuci) * m;
      tekuci = 0;
      slobodno = 4;
      imaRijeci = true;
    } else if (_decimalno.contains(n)) {
      isprazni();
      izlaz.write(',');
    } else if (n == 'po' && i > 0 && normalizuj(tokeni[i - 1]) == 'i') {
      // "dva i po" -> 2,5
      isprazni();
      izlaz.write(',5');
    }
    // "i" između brojeva ("dvadeset i pet") i ostale riječi se preskaču.
  }
  isprazni();

  var r = izlaz.toString();
  // Najviše jedan decimalni zarez; višak (npr. "2,,5") se uklanja.
  final prvi = r.indexOf(',');
  if (prvi >= 0) {
    r = r.substring(0, prvi + 1) + r.substring(prvi + 1).replaceAll(',', '');
  }
  if (r.startsWith(',')) r = '0$r';
  if (r.endsWith(',')) r = r.substring(0, r.length - 1);
  return r;
}

// "1.232" -> 1232 (tačka kao separator hiljada), "2.5" / "2,5" -> 2,5.
String _cifre(String s) {
  var t = s.replaceAll(RegExp(r'[^0-9.,]'), '');
  if (RegExp(r'^\d{1,3}(\.\d{3})+(,\d+)?$').hasMatch(t)) {
    t = t.replaceAll('.', '');
  } else if (RegExp(r'^\d{1,3}(,\d{3})+\.\d+$').hasMatch(t)) {
    // 1,232.5 (engleski zapis)
    t = t.replaceAll(',', '').replaceAll('.', ',');
  } else {
    t = t.replaceAll('.', ',');
  }
  return t;
}

// --- Izgovoreni znakovi (tekstualna polja) -----------------------------------

// Kako se znak lijepi uz susjede: oba = bez razmaka s obje strane
// ("318/20", "RN-55"), lijevo = uz prethodno ("5%", "a,"), desno = uz
// sljedeće ("(").
enum _Lijepi { oba, lijevo, desno }

class _Znak {
  final String znak;
  final _Lijepi lijepi;

  // Samo između brojeva ("318 kroz 20"), inače je obična riječ
  // ("prolaz kroz magacin").
  final bool samoUzBrojeve;

  const _Znak(this.znak, this.lijepi, {this.samoUzBrojeve = false});
}

// Ključ: normalizovane riječi (dvije riječi prije jedne).
const Map<String, _Znak> _znakovi = {
  'kosa crta': _Znak('/', _Lijepi.oba),
  'kosa crtica': _Znak('/', _Lijepi.oba),
  'donja crta': _Znak('_', _Lijepi.oba),
  'otvorena zagrada': _Znak('(', _Lijepi.desno),
  'otvori zagradu': _Znak('(', _Lijepi.desno),
  'zatvorena zagrada': _Znak(')', _Lijepi.lijevo),
  'zatvori zagradu': _Znak(')', _Lijepi.lijevo),
  'kroz': _Znak('/', _Lijepi.oba, samoUzBrojeve: true),
  'slash': _Znak('/', _Lijepi.oba),
  'crtica': _Znak('-', _Lijepi.oba),
  'crta': _Znak('-', _Lijepi.oba),
  'povlaka': _Znak('-', _Lijepi.oba),
  'minus': _Znak('-', _Lijepi.oba, samoUzBrojeve: true),
  'plus': _Znak('+', _Lijepi.oba, samoUzBrojeve: true),
  'puta': _Znak('x', _Lijepi.oba, samoUzBrojeve: true),
  'tacka': _Znak('.', _Lijepi.oba),
  'tocka': _Znak('.', _Lijepi.oba),
  'dvotacka': _Znak(':', _Lijepi.oba),
  'dvotocka': _Znak(':', _Lijepi.oba),
  'zarez': _Znak(',', _Lijepi.lijevo),
  'posto': _Znak('%', _Lijepi.lijevo, samoUzBrojeve: true),
  'procenat': _Znak('%', _Lijepi.lijevo, samoUzBrojeve: true),
  'procenata': _Znak('%', _Lijepi.lijevo, samoUzBrojeve: true),
  'majmunce': _Znak('@', _Lijepi.oba),
  'taraba': _Znak('#', _Lijepi.desno),
  'hashtag': _Znak('#', _Lijepi.desno),
};

class _Tok {
  final String tekst;
  final _Znak? znak;
  final bool broj;

  // Za broj izgovoren riječima: vrijednost u ciframa ("318").
  final String? cifre;

  const _Tok(this.tekst, {this.znak, this.broj = false, this.cifre});
}

bool _cifreIliBroj(String s) => RegExp(r'^\d+([.,]\d+)?$').hasMatch(s);

// "318 kroz 20" -> 318/20, "tristo osamnaest kroz dvadeset" -> 318/20,
// "RN crtica 55" -> RN-55, "račun broj sto dvadeset" -> račun broj 120.
String saZnakovima(String tekst) {
  final rijeci = tekst
      .split(RegExp(r'\s+'))
      .where((r) => r.isNotEmpty)
      .toList();
  final n = rijeci.map((r) => normalizuj(r).replaceAll(' ', '')).toList();

  // 1) Znakovi (prvo po dvije riječi) i nizovi brojeva riječima.
  final tokovi = <_Tok>[];
  for (var i = 0; i < rijeci.length; i++) {
    final dvije = i + 1 < rijeci.length
        ? _znakovi['${n[i]} ${n[i + 1]}']
        : null;
    if (dvije != null) {
      tokovi.add(_Tok('${rijeci[i]} ${rijeci[i + 1]}', znak: dvije));
      i++;
    } else if (_znakovi.containsKey(n[i])) {
      tokovi.add(_Tok(rijeci[i], znak: _znakovi[n[i]]));
    } else if (_brojRijec(n[i])) {
      // Niz riječi-brojeva ("tristo osamnaest", "dvadeset i pet").
      var j = i;
      while (j + 1 < rijeci.length &&
          (_brojRijec(n[j + 1]) ||
              (n[j + 1] == 'i' &&
                  j + 2 < rijeci.length &&
                  _brojRijec(n[j + 2])))) {
        j++;
      }
      tokovi.add(
        _Tok(
          rijeci.sublist(i, j + 1).join(' '),
          broj: true,
          cifre: uBroj(rijeci.sublist(i, j + 1).join(' ')),
        ),
      );
      i = j;
    } else {
      tokovi.add(_Tok(rijeci[i], broj: _cifreIliBroj(rijeci[i])));
    }
  }

  bool jeBroj(int i) => i >= 0 && i < tokovi.length && tokovi[i].broj;

  // 2) Uslovni znakovi ("kroz", "minus", "posto") važe samo uz brojeve.
  for (var i = 0; i < tokovi.length; i++) {
    final z = tokovi[i].znak;
    if (z == null || !z.samoUzBrojeve) continue;
    final ok = z.lijepi == _Lijepi.lijevo
        ? jeBroj(i - 1)
        : jeBroj(i - 1) && jeBroj(i + 1);
    if (!ok) tokovi[i] = _Tok(tokovi[i].tekst);
  }

  // 3) Broj riječima -> cifre kad je uz znak ili je "pravi" broj (više
  //    riječi ili ≥ 10). "jedan radnik" ostaje kako je rečeno.
  bool uzZnak(int i) =>
      (i > 0 && tokovi[i - 1].znak != null) ||
      (i + 1 < tokovi.length && tokovi[i + 1].znak != null);
  for (var i = 0; i < tokovi.length; i++) {
    final c = tokovi[i].cifre;
    if (c == null) continue;
    final pravi = tokovi[i].tekst.contains(' ') || (int.tryParse(c) ?? 0) >= 10;
    if (uzZnak(i) || pravi) tokovi[i] = _Tok(c, broj: true);
  }

  // 4) Spajanje uz pravila lijepljenja.
  final b = StringBuffer();
  var lijepiSljedece = true; // na početku nema razmaka
  for (final t in tokovi) {
    final z = t.znak;
    if (z != null) {
      if (z.lijepi == _Lijepi.desno && !lijepiSljedece) b.write(' ');
      b.write(z.znak);
      lijepiSljedece = z.lijepi != _Lijepi.lijevo;
    } else {
      if (!lijepiSljedece) b.write(' ');
      b.write(t.tekst);
      lijepiSljedece = false;
    }
  }
  // Apple ponekad sam napiše "318 / 20" ili "RN - 55".
  return b
      .toString()
      .replaceAllMapped(
        RegExp(r'([\p{L}\p{N}])\s+([/\-_:])\s+([\p{L}\p{N}])', unicode: true),
        (m) => '${m[1]}${m[2]}${m[3]}',
      )
      .trim();
}

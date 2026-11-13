import 'package:flutter/material.dart';

import '../widgets/magacin_ui.dart' show OznakaPolja;
import 'diktat.dart';

// Diktiranje u polje koje je u fokusu (radi na svakom TextField-u, bez
// izmjena na ekranima). Upis ide kroz EditableText kao da je otkucan, pa
// važe i formatteri polja (npr. samo cifre) i poziva se onChanged ekrana
// (preračun zbirova, brisanje greške…).

class _Polje {
  final EditableTextState stanje;
  final String original;
  final String oznaka;

  // Naziv polja kako piše na ekranu (OznakaPolja/labelText), bez hintText-a
  // koji je primjer vrijednosti ("npr. Marko") — koristi se za izbacivanje
  // naziva iz diktata.
  final String? naziv;
  final VrstaPolja vrsta;
  bool dirano = false;
  bool obrisano = false;

  _Polje(this.stanje, this.original, this.oznaka, this.naziv, this.vrsta);

  String get tekst => stanje.widget.controller.text;
}

class DiktatSesija {
  final List<_Polje> _polja;

  DiktatSesija._(this._polja);

  // Sesija za polje u fokusu, ili null ako nijedno polje za unos nije u
  // fokusu (tada se izgovoreno tumači kao komanda).
  static DiktatSesija? izFokusa() {
    final polje = _poljeIzFokusa();
    return polje == null ? null : DiktatSesija._([polje]);
  }

  String get oznaka => _polja.first.oznaka;
  String get oznakaTrenutnog => _polja.last.oznaka;
  VrstaPolja get vrsta => _polja.first.vrsta;

  // Uživo primjenjuje izgovoreno na polja. "dalje" prelazi u sljedeće polje
  // (fokus se pomjera, pa se novo polje čeka do sljedećeg rezultata).
  Future<void> primijeni(String izgovoreno) async {
    final dijelovi = podijeliNaPolja(izgovoreno);
    while (dijelovi.length > _polja.length) {
      final sljedece = await _sljedecePolje(_polja.last);
      if (sljedece == null) break;
      _polja.add(sljedece);
    }
    for (var i = 0; i < _polja.length && i < dijelovi.length; i++) {
      final p = _polja[i];
      final r = obradiDiktat(dijelovi[i], p.vrsta, oznaka: p.naziv);
      if (r.prazno) continue;
      p.obrisano = r.obrisi;
      _upisi(p, r.obrisi ? '' : r.tekst);
    }
  }

  // Šta je upisano (za zeca). Prazno = ništa korisno nije upisano.
  List<(String oznaka, String vrijednost, bool obrisano)> get upisano => [
    for (final p in _polja)
      if (p.dirano && (p.tekst.isNotEmpty || p.obrisano))
        (p.oznaka, p.tekst, p.obrisano),
  ];

  // Vraća polja na ono što je bilo prije diktiranja.
  void ponisti() {
    for (final p in _polja) {
      if (p.dirano) _upisi(p, p.original);
    }
  }

  // Polja u kojima je nakon formattera ostalo prazno (npr. slova u polju za
  // broj) vraća na staro.
  void vratiPrazna() {
    for (final p in _polja) {
      if (p.dirano && p.tekst.isEmpty && !p.obrisano) _upisi(p, p.original);
    }
  }

  void _upisi(_Polje p, String tekst) {
    if (!p.stanje.mounted || p.tekst == tekst) return;
    p.dirano = true;
    p.stanje.userUpdateTextEditingValue(
      TextEditingValue(
        text: tekst,
        selection: TextSelection.collapsed(offset: tekst.length),
      ),
      SelectionChangedCause.keyboard,
    );
  }
}

_Polje? _poljeIzFokusa() {
  final kontekst = FocusManager.instance.primaryFocus?.context;
  if (kontekst == null || !kontekst.mounted) return null;
  final stanje =
      kontekst is StatefulElement && kontekst.state is EditableTextState
      ? kontekst.state as EditableTextState
      : kontekst.findAncestorStateOfType<EditableTextState>();
  if (stanje == null || stanje.widget.readOnly) return null;
  // Lozinke se ne diktiraju.
  if (stanje.widget.obscureText) return null;
  final broj = stanje.widget.keyboardType.index == TextInputType.number.index;
  return _Polje(
    stanje,
    stanje.widget.controller.text,
    _oznakaPolja(stanje.context) ?? 'ovo polje',
    _oznakaPolja(stanje.context, saPrimjerom: false),
    broj ? VrstaPolja.broj : VrstaPolja.tekst,
  );
}

// Fokus prelazi na sljedeće polje za unos (preskače dugmad, padajuće liste
// i polja samo za čitanje, npr. datum).
Future<_Polje?> _sljedecePolje(_Polje od) async {
  if (!od.stanje.mounted) return null;
  var cvor = od.stanje.widget.focusNode;
  for (var i = 0; i < 20; i++) {
    if (!cvor.nextFocus()) return null;
    // Promjena fokusa se primjenjuje asinhrono.
    await Future<void>.delayed(Duration.zero);
    final novo = _poljeIzFokusa();
    if (novo != null) {
      if (identical(novo.stanje, od.stanje)) return null; // obišli smo krug
      return novo;
    }
    final p = FocusManager.instance.primaryFocus;
    if (p == null) return null;
    cvor = p;
  }
  return null;
}

// Naziv polja: OznakaPolja iznad polja, labelText/hintText polja, ili
// "ovo polje".
String? _oznakaPolja(BuildContext ctx, {bool saPrimjerom = true}) {
  Element? textField;
  ctx.visitAncestorElements((e) {
    if (e.widget is TextField || e.widget is TextFormField) {
      textField = e;
    }
    return textField == null;
  });

  String? nadjeno;
  var nivo = 0;
  (textField ?? ctx as Element).visitAncestorElements((roditelj) {
    roditelj.visitChildElements((dijete) {
      nadjeno ??= _oznakaU(dijete, 2);
    });
    nivo++;
    return nadjeno == null && nivo < 2;
  });
  if (nadjeno != null) return nadjeno!;

  final w = textField?.widget;
  final dekoracija = w is TextField ? w.decoration : null;
  if (!saPrimjerom) return dekoracija?.labelText;
  return dekoracija?.labelText ?? dekoracija?.hintText ?? 'ovo polje';
}

String? _oznakaU(Element e, int dubina) {
  final w = e.widget;
  if (w is OznakaPolja) return w.tekst;
  if (w is TextField || w is TextFormField || dubina == 0) return null;
  String? r;
  e.visitChildElements((d) => r ??= _oznakaU(d, dubina - 1));
  return r;
}

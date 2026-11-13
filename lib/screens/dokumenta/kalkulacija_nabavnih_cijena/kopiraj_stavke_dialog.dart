import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/purchase_calculation.dart';
import 'package:knjigovodstvo_app/services/purchase_calculations_service.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';

// Kopiranje stavki iz ranije kalkulacije: korak 1 bira kalkulaciju (po
// defaultu one od istog dobavljača, najnovija prva), korak 2 bira stavke i
// mijenja količine/cijene. Ništa se ne snima — stavke se samo dodaju u formu.

class KopiranaStavka {
  final StavkaKalkulacije izvor;
  final double kolicina;
  final double fakturnaCijena;

  const KopiranaStavka({
    required this.izvor,
    required this.kolicina,
    required this.fakturnaCijena,
  });
}

class RezultatKopiranja {
  final Kalkulacija kalkulacija;
  final List<KopiranaStavka> stavke;

  // Prenijeti prevoz/špediciju/carinu, odnosno kalkulisao/robu primio iz
  // `kalkulacija.rekapitulacija`.
  final bool kopirajTroskove;
  final bool kopirajPotpise;

  const RezultatKopiranja({
    required this.kalkulacija,
    required this.stavke,
    this.kopirajTroskove = false,
    this.kopirajPotpise = false,
  });
}

// Isto kao u formi kalkulacije: zarez ili tačka su decimalni separator.
double _parse(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;

String _format(double value) {
  final dijelovi = value.toStringAsFixed(2).split('.');
  final cijeli = dijelovi[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '$cijeli,${dijelovi[1]}';
}

// Količine i cijene sa do 4 decimale, bez suvišnih nula, bez razdvajanja
// hiljada (da se mogu direktno mijenjati u polju).
String _format4(double value) {
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

String _formatDatum(DateTime? datum) {
  if (datum == null) return '—';
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}.';
}

final _decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

const _stilUnosa = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: MagacinBoje.naslov,
);

class KopirajStavkeDialog extends StatefulWidget {
  final int firmaId;

  // Dobavljač izabran na kalkulaciji koja se pravi (ako jeste).
  final int? dobavljacId;
  final String? dobavljacNaziv;

  // Kalkulacija koja se trenutno uređuje — ne nudi se za kopiranje.
  final int? trenutnaKalkulacijaId;

  // Artikli koji su već na kalkulaciji — po defaultu nisu označeni.
  final Set<int> postojeciArtikli;

  // Tip skladišta trenutne kalkulacije, za upozorenje ako se razlikuje.
  final String? tipSkladista;

  const KopirajStavkeDialog({
    super.key,
    required this.firmaId,
    this.dobavljacId,
    this.dobavljacNaziv,
    this.trenutnaKalkulacijaId,
    this.postojeciArtikli = const {},
    this.tipSkladista,
  });

  @override
  State<KopirajStavkeDialog> createState() => _KopirajStavkeDialogState();
}

class _RedStavke {
  final StavkaKalkulacije stavka;
  final TextEditingController kolicina;
  final TextEditingController cijena;
  final bool vecDodan;
  bool izabran;

  _RedStavke(this.stavka, {required this.vecDodan})
    : kolicina = TextEditingController(text: _format4(stavka.kolicina)),
      cijena = TextEditingController(text: _format4(stavka.fakturnaCijena)),
      izabran = !vecDodan;

  double get kolicinaBroj => _parse(kolicina.text);
  double get cijenaBroj => _parse(cijena.text);

  String? get greskaKolicine =>
      izabran && kolicinaBroj <= 0 ? 'Unesite količinu' : null;
  String? get greskaCijene =>
      izabran && cijena.text.trim().isEmpty ? 'Unesite cijenu' : null;

  void dispose() {
    kolicina.dispose();
    cijena.dispose();
  }
}

class _KopirajStavkeDialogState extends State<KopirajStavkeDialog> {
  final PurchaseCalculationsService _service = PurchaseCalculationsService();
  final _pretragaController = TextEditingController();

  // Korak 1: lista kalkulacija.
  late bool _samoDobavljac = widget.dobavljacId != null;
  final List<Kalkulacija> _lista = [];
  int _stranica = 0;
  int _zadnjaStranica = 1;
  bool _ucitavanjeListe = false;
  String? _greskaListe;
  Timer? _timer;
  int _zahtjev = 0;

  // Korak 2: stavke izabrane kalkulacije.
  Kalkulacija? _izabrana;
  List<_RedStavke> _redovi = [];
  bool _ucitavanjeStavki = false;
  String? _greskaStavki;
  bool _pokusanoDodavanje = false;
  bool _kopirajTroskove = false;
  bool _kopirajPotpise = false;

  @override
  void initState() {
    super.initState();
    _pretragaController.addListener(_naPromjenuPretrage);
    _ucitajListu(ispocetka: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pretragaController.dispose();
    for (final r in _redovi) {
      r.dispose();
    }
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Korak 1
  // ------------------------------------------------------------------

  String _zadnjaPretraga = '';

  void _naPromjenuPretrage() {
    final tekst = _pretragaController.text.trim();
    if (tekst == _zadnjaPretraga) return;
    _zadnjaPretraga = tekst;
    _timer?.cancel();
    _timer = Timer(
      const Duration(milliseconds: 350),
      () => _ucitajListu(ispocetka: true),
    );
    setState(() {});
  }

  Future<void> _ucitajListu({bool ispocetka = false}) async {
    final zahtjev = ++_zahtjev;
    final stranica = ispocetka ? 1 : _stranica + 1;
    final pretraga = _pretragaController.text.trim();

    setState(() {
      _ucitavanjeListe = true;
      _greskaListe = null;
      if (ispocetka) _lista.clear();
    });

    try {
      // Server traži po nazivu dobavljača ili broju fakture; dobavljač se
      // dodatno filtrira po id-u, jer naziv može odgovarati i drugima.
      final rezultat = await _service.fetchCalculations(
        widget.firmaId,
        page: stranica,
        search: pretraga.isNotEmpty
            ? pretraga
            : (_samoDobavljac ? widget.dobavljacNaziv : null),
      );
      if (!mounted || zahtjev != _zahtjev) return;

      setState(() {
        _stranica = rezultat.stranica;
        _zadnjaStranica = rezultat.zadnjaStranica;
        _lista.addAll(
          rezultat.kalkulacije.where(
            (k) =>
                k.id != widget.trenutnaKalkulacijaId &&
                (!_samoDobavljac || k.supplierId == widget.dobavljacId),
          ),
        );
      });
    } on ApiException catch (e) {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _greskaListe = e.message);
      }
    } finally {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _ucitavanjeListe = false);
      }
    }
  }

  void _promijeniFilter(bool samoDobavljac) {
    if (_samoDobavljac == samoDobavljac) return;
    setState(() => _samoDobavljac = samoDobavljac);
    _ucitajListu(ispocetka: true);
  }

  // ------------------------------------------------------------------
  // Korak 2
  // ------------------------------------------------------------------

  Future<void> _izaberi(Kalkulacija k) async {
    setState(() {
      _izabrana = k;
      _ucitavanjeStavki = true;
      _greskaStavki = null;
      _pokusanoDodavanje = false;
      _kopirajTroskove = false;
      _kopirajPotpise = false;
    });

    try {
      final puna = await _service.fetchCalculation(widget.firmaId, k.id);
      if (!mounted || _izabrana?.id != k.id) return;
      setState(() {
        _izabrana = puna;
        _redovi = puna.stavke
            .map(
              (s) => _RedStavke(
                s,
                vecDodan: widget.postojeciArtikli.contains(s.articleId),
              ),
            )
            .toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _greskaStavki = e.message);
    } finally {
      if (mounted) setState(() => _ucitavanjeStavki = false);
    }
  }

  void _nazad() {
    for (final r in _redovi) {
      r.dispose();
    }
    setState(() {
      _izabrana = null;
      _redovi = [];
      _greskaStavki = null;
    });
  }

  int get _brojIzabranih => _redovi.where((r) => r.izabran).length;

  bool get _imaTroskove {
    final r = _izabrana?.rekapitulacija;
    return r != null && (r.prevoz > 0 || r.spedicija > 0 || r.carina > 0);
  }

  bool get _imaPotpise {
    final r = _izabrana?.rekapitulacija;
    return r != null &&
        ((r.kalkulisao ?? '').trim().isNotEmpty ||
            (r.robuPrimio ?? '').trim().isNotEmpty);
  }

  // Ima li išta za kopiranje: stavke ili označeni dio zaglavlja.
  bool get _imaStaKopirati =>
      _brojIzabranih > 0 ||
      (_kopirajTroskove && _imaTroskove) ||
      (_kopirajPotpise && _imaPotpise);

  void _oznaciSve(bool vrijednost) {
    setState(() {
      for (final r in _redovi) {
        r.izabran = vrijednost;
      }
    });
  }

  void _dodaj() {
    final izabrani = _redovi.where((r) => r.izabran).toList();
    if (!_imaStaKopirati) return;

    final greska = izabrani.any(
      (r) => r.greskaKolicine != null || r.greskaCijene != null,
    );
    if (greska) {
      setState(() => _pokusanoDodavanje = true);
      return;
    }

    Navigator.of(context).pop(
      RezultatKopiranja(
        kalkulacija: _izabrana!,
        stavke: [
          for (final r in izabrani)
            KopiranaStavka(
              izvor: r.stavka,
              kolicina: r.kolicinaBroj,
              fakturnaCijena: r.cijenaBroj,
            ),
        ],
        kopirajTroskove: _kopirajTroskove && _imaTroskove,
        kopirajPotpise: _kopirajPotpise && _imaPotpise,
      ),
    );
  }

  // ------------------------------------------------------------------
  // Prikaz
  // ------------------------------------------------------------------

  Widget _naslov() {
    final korak2 = _izabrana != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (korak2)
          IconButton(
            tooltip: 'Nazad na listu',
            onPressed: _nazad,
            style: IconButton.styleFrom(foregroundColor: MagacinBoje.priguseno),
            icon: const Icon(Icons.arrow_back_rounded),
          )
        else
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: akcentSvijetlo,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.content_copy_rounded,
              color: akcentAplikacije,
              size: 21,
            ),
          ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                korak2 ? 'Izaberite stavke' : 'Kopiraj iz kalkulacije',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                korak2
                    ? 'Faktura ${_izabrana!.brojFakture} · '
                          '${_izabrana!.dobavljac ?? ''} · '
                          '${_formatDatum(_izabrana!.datum)}'
                    : 'Izaberite raniju kalkulaciju čije stavke želite '
                          'prenijeti.',
                style: const TextStyle(
                  fontSize: 13,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Zatvori',
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(foregroundColor: MagacinBoje.priguseno),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _filterDugme(String tekst, bool aktivan, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(tekst),
      selected: aktivan,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: aktivan ? akcentAplikacije : MagacinBoje.priguseno,
      ),
      backgroundColor: Colors.white,
      selectedColor: akcentSvijetlo,
      side: BorderSide(
        color: aktivan
            ? hoverNijansa(akcentAplikacije, 0.4)
            : MagacinBoje.linija,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _lista1() {
    final pretraga = TextField(
      controller: _pretragaController,
      style: _stilUnosa,
      decoration: dekoracijaPolja(
        hint: _samoDobavljac
            ? 'Broj fakture ili prijemnice…'
            : 'Dobavljač, broj fakture ili prijemnice…',
        ikona: Icons.search_rounded,
      ),
    );

    final filteri = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (widget.dobavljacId != null)
          _filterDugme(
            'Od: ${widget.dobavljacNaziv ?? 'izabranog dobavljača'}',
            _samoDobavljac,
            () => _promijeniFilter(true),
          ),
        _filterDugme(
          'Sve kalkulacije',
          !_samoDobavljac,
          () => _promijeniFilter(false),
        ),
      ],
    );

    Widget sadrzaj;
    if (_greskaListe != null && _lista.isEmpty) {
      sadrzaj = _poruka(
        Icons.error_outline_rounded,
        _greskaListe!,
        akcija: TextButton(
          onPressed: () => _ucitajListu(ispocetka: true),
          child: const Text('Pokušaj ponovo'),
        ),
      );
    } else if (_lista.isEmpty && _ucitavanjeListe) {
      sadrzaj = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_lista.isEmpty && _stranica >= _zadnjaStranica) {
      sadrzaj = _poruka(
        Icons.receipt_long_outlined,
        _samoDobavljac
            ? 'Nema ranijih kalkulacija od ovog dobavljača.'
            : 'Nema kalkulacija koje odgovaraju pretrazi.',
      );
    } else {
      // Prva u listi je najnovija, ako se ne pretražuje.
      final zadnjaOznaka =
          _samoDobavljac && _pretragaController.text.trim().isEmpty;
      sadrzaj = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _lista.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _redKalkulacije(_lista[i], zadnja: zadnjaOznaka && i == 0),
            ),
          if (_stranica < _zadnjaStranica)
            Center(
              child: _ucitavanjeListe
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => _ucitajListu(),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: const Text('Učitaj još'),
                    ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pretraga,
        const SizedBox(height: 12),
        filteri,
        const SizedBox(height: 14),
        sadrzaj,
      ],
    );
  }

  Widget _redKalkulacije(Kalkulacija k, {required bool zadnja}) {
    final vrijednost = k.rekapitulacija.fakturnaVrijednost;
    return _HoverKartica(
      onTap: () => _izaberi(k),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        k.dobavljac ?? 'Bez dobavljača',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: MagacinBoje.naslov,
                        ),
                      ),
                    ),
                    if (zadnja) ...[
                      const SizedBox(width: 8),
                      _znacka('Zadnja', akcentAplikacije, akcentSvijetlo),
                    ],
                    if (!k.jeProknjizena) ...[
                      const SizedBox(width: 6),
                      _znacka(
                        'Nacrt',
                        MagacinBoje.narandzasta,
                        MagacinBoje.narandzastaSvijetlo,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatDatum(k.datum)} · Faktura ${k.brojFakture}'
                  '${k.skladiste == null ? '' : ' · ${k.skladiste!.naziv}'}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: MagacinBoje.priguseno,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                vrijednost > 0 ? _format(vrijednost) : '',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${k.brojStavki} '
                '${k.brojStavki == 1 ? 'stavka' : (k.brojStavki > 1 && k.brojStavki < 5 ? 'stavke' : 'stavki')}',
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ],
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: MagacinBoje.svijetlo),
        ],
      ),
    );
  }

  Widget _znacka(String tekst, Color boja, Color pozadina) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: pozadina,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tekst,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: boja,
        ),
      ),
    );
  }

  Widget _poruka(IconData ikona, String tekst, {Widget? akcija}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 12),
      child: Column(
        children: [
          Icon(ikona, size: 30, color: MagacinBoje.svijetlo),
          const SizedBox(height: 10),
          Text(
            tekst,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: MagacinBoje.priguseno,
            ),
          ),
          if (akcija != null) ...[const SizedBox(height: 8), akcija],
        ],
      ),
    );
  }

  Widget _stavke2(double sirina) {
    if (_ucitavanjeStavki) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_greskaStavki != null) {
      return _poruka(
        Icons.error_outline_rounded,
        _greskaStavki!,
        akcija: TextButton(
          onPressed: () => _izaberi(_izabrana!),
          child: const Text('Pokušaj ponovo'),
        ),
      );
    }
    if (_redovi.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _poruka(Icons.inventory_2_outlined, 'Kalkulacija nema stavki.'),
          _opcijeZaglavlja(),
        ],
      );
    }

    final tipIzvora = _izabrana?.skladiste?.tip;
    final drugoSkladiste =
        widget.tipSkladista != null &&
        tipIzvora != null &&
        tipIzvora != widget.tipSkladista;
    final sveIzabrane = _redovi.every((r) => r.izabran);
    final siroko = sirina >= 520;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (drugoSkladiste)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MagacinBoje.narandzastaSvijetlo,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: MagacinBoje.narandzasta,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ova kalkulacija je za ${_izabrana!.skladiste!.naziv}. '
                    'Artikli možda ne pripadaju skladištu trenutne '
                    'kalkulacije.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: MagacinBoje.tekst,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Text(
              'Označeno $_brojIzabranih od ${_redovi.length}',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: MagacinBoje.priguseno,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _oznaciSve(!sveIzabrane),
              child: Text(sveIzabrane ? 'Poništi sve' : 'Označi sve'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final r in _redovi)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _redStavke(r, siroko),
          ),
        const SizedBox(height: 4),
        const Text(
          'Količine i cijene su iz izabrane kalkulacije — promijenite one '
          'koje su drugačije na novoj fakturi.',
          style: TextStyle(fontSize: 12, color: MagacinBoje.svijetlo),
        ),
        _opcijeZaglavlja(),
      ],
    );
  }

  // Kvačice za prenos dijela zaglavlja; prikazuju se samo ako izvor ima te
  // podatke. Po defaultu nisu označene.
  Widget _opcijeZaglavlja() {
    final r = _izabrana?.rekapitulacija;
    if (r == null || (!_imaTroskove && !_imaPotpise)) {
      return const SizedBox.shrink();
    }

    final troskovi = [
      if (r.prevoz > 0) 'prevoz ${_format(r.prevoz)}',
      if (r.spedicija > 0) 'špedicija ${_format(r.spedicija)}',
      if (r.carina > 0) 'carina ${_format(r.carina)}',
    ].join(' · ');

    final potpisi = [
      if ((r.kalkulisao ?? '').trim().isNotEmpty)
        'kalkulisao: ${r.kalkulisao!.trim()}',
      if ((r.robuPrimio ?? '').trim().isNotEmpty)
        'robu primio: ${r.robuPrimio!.trim()}',
    ].join(' · ');

    Widget opcija({
      required bool vrijednost,
      required ValueChanged<bool> promjena,
      required String naslov,
      required String opis,
    }) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => promjena(!vrijednost),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: vrijednost,
                activeColor: akcentAplikacije,
                onChanged: (v) => promjena(v ?? false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        naslov,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: MagacinBoje.naslov,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        opis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: MagacinBoje.priguseno,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
      decoration: BoxDecoration(
        color: MagacinBoje.zaglavlje,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MagacinBoje.linija),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 0, 2),
            child: Text(
              'IZ ZAGLAVLJA (OPCIONO)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: MagacinBoje.priguseno,
              ),
            ),
          ),
          if (_imaTroskove)
            opcija(
              vrijednost: _kopirajTroskove,
              promjena: (v) => setState(() => _kopirajTroskove = v),
              naslov: 'Kopiraj zavisne troškove',
              opis:
                  '${troskovi[0].toUpperCase()}${troskovi.substring(1)}. '
                  'Zamjenjuje troškove upisane na novoj kalkulaciji.',
            ),
          if (_imaPotpise)
            opcija(
              vrijednost: _kopirajPotpise,
              promjena: (v) => setState(() => _kopirajPotpise = v),
              naslov: 'Kopiraj potpise',
              opis: '${potpisi[0].toUpperCase()}${potpisi.substring(1)}.',
            ),
        ],
      ),
    );
  }

  Widget _redStavke(_RedStavke r, bool siroko) {
    final s = r.stavka;

    Widget polje(TextEditingController c, String hint, String? greska) {
      return TextField(
        controller: c,
        enabled: r.izabran,
        style: _stilUnosa,
        textAlign: TextAlign.right,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [_decimalFormatter],
        onChanged: (_) => setState(() {}),
        decoration:
            dekoracijaPolja(
              hint: hint,
              errorText: _pokusanoDodavanje ? greska : null,
            ).copyWith(
              suffixText: hint == 'Količina' ? s.jm : null,
              suffixStyle: const TextStyle(
                fontSize: 12,
                color: MagacinBoje.priguseno,
              ),
            ),
      );
    }

    final kolicina = polje(r.kolicina, 'Količina', r.greskaKolicine);
    final cijena = polje(r.cijena, 'Fakt. cijena', r.greskaCijene);

    final naziv = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.naziv,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: r.izabran ? MagacinBoje.naslov : MagacinBoje.svijetlo,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Flexible(
              child: Text(
                'Šifra ${s.sifra}',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ),
            if (r.vecDodan) ...[
              const SizedBox(width: 6),
              _znacka(
                'Već na kalkulaciji',
                MagacinBoje.narandzasta,
                MagacinBoje.narandzastaSvijetlo,
              ),
            ],
          ],
        ),
      ],
    );

    final oznaka = Checkbox(
      value: r.izabran,
      activeColor: akcentAplikacije,
      onChanged: (v) => setState(() => r.izabran = v ?? false),
    );

    return AnimatedContainer(
      duration: hoverTrajanje,
      curve: hoverKriva,
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      decoration: BoxDecoration(
        color: r.izabran ? Colors.white : MagacinBoje.zaglavlje,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: r.izabran
              ? hoverNijansa(akcentAplikacije, 0.35)
              : MagacinBoje.linija,
        ),
      ),
      child: siroko
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                oznaka,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: naziv,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 130, child: kolicina),
                const SizedBox(width: 8),
                SizedBox(width: 130, child: cijena),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                oznaka,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 10),
                      naziv,
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: kolicina),
                          const SizedBox(width: 8),
                          Expanded(child: cijena),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usko = MediaQuery.sizeOf(context).width < 600;
    final korak2 = _izabrana != null;

    Widget sadrzaj(double sirina) => korak2 ? _stavke2(sirina) : _lista1();

    final odustani = GlatkoDugme(
      tekst: korak2 ? 'Nazad' : 'Odustani',
      vrsta: VrstaDugmeta.sekundarno,
      onTap: korak2 ? _nazad : () => Navigator.of(context).pop(),
    );
    final dodaj = GlatkoDugme(
      tekst: switch (_brojIzabranih) {
        0 => 'Kopiraj',
        1 => 'Dodaj 1 stavku',
        final n => 'Dodaj $n stavki',
      },
      ikona: Icons.check_rounded,
      onTap: !_imaStaKopirati || _ucitavanjeStavki ? null : _dodaj,
    );

    if (usko) {
      return Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
                child: _naslov(),
              ),
              const Divider(height: 1, color: MagacinBoje.linija),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                    child: sadrzaj(c.maxWidth - 36),
                  ),
                ),
              ),
              if (korak2)
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: MagacinBoje.linija)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: odustani),
                      const SizedBox(width: 10),
                      Expanded(flex: 2, child: dodaj),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 14, 16),
              child: _naslov(),
            ),
            const Divider(height: 1, color: MagacinBoje.linija),
            Flexible(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                  child: sadrzaj(c.maxWidth - 48),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              decoration: const BoxDecoration(
                color: MagacinBoje.zaglavlje,
                border: Border(top: BorderSide(color: MagacinBoje.linija)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  odustani,
                  if (korak2) ...[const SizedBox(width: 10), dodaj],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Kartica kalkulacije u listi sa glatkim hoverom.
class _HoverKartica extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _HoverKartica({required this.onTap, required this.child});

  @override
  State<_HoverKartica> createState() => _HoverKarticaState();
}

class _HoverKarticaState extends State<_HoverKartica> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: hoverTrajanje,
          curve: hoverKriva,
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFF1F5F9) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover
                  ? hoverNijansa(akcentAplikacije, 0.35)
                  : MagacinBoje.linija,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

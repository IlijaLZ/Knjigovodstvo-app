import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../izvoz/dugme_izvoza.dart';
import '../../izvoz/excel_izvoz.dart';
import '../../models/auth_models.dart';
import '../../models/partner.dart';
import '../../services/partners_service.dart';
import '../../widgets/logo.dart';
import '../../widgets/magacin_ui.dart';
import '../../widgets/paginacija_widget.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _validirajObavezno(String? value) {
  if (value == null || value.trim().isEmpty) return 'Obavezno polje';
  return null;
}

// PIB: 8–13 cifara; crtice i razmaci se ignorišu (server ih uklanja).
String? _validirajPib(String? value) {
  final pib = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
  if (pib.isEmpty) return null;
  if (!RegExp(r'^\d{8,13}$').hasMatch(pib)) return 'PIB mora imati 8–13 cifara';
  return null;
}

String? _validirajEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return null;
  if (!_emailRegex.hasMatch(email)) return 'Neispravan email';
  return null;
}

void _poruka(BuildContext context, String tekst, {SnackBarAction? action}) {
  final sirina = MediaQuery.sizeOf(context).width;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(tekst),
        action: action,
        behavior: SnackBarBehavior.floating,
        width: sirina < 480 ? null : 440,
        backgroundColor: MagacinBoje.naslov,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

String _inicijali(String ime) {
  final dijelovi = ime.trim().split(RegExp(r'\s+')).where((d) => d.isNotEmpty);
  final slova = dijelovi.take(2).map((d) => d.characters.first.toUpperCase());
  return slova.isEmpty ? '?' : slova.join();
}

bool _prazno(String? s) => s == null || s.trim().isEmpty;

const Color _akcent = akcentAplikacije;
const Color _akcentSvijetlo = Color(0xFFE6F4F3);
const Color _akcentTamni = Color(0xFF0B434B);

// Boja i ikona po vrsti partnera, da se dobavljači i kupci lako razlikuju.
class _Tema {
  final Color boja;
  final Color tamna;
  final IconData ikona;
  final String opis;

  const _Tema(this.boja, this.tamna, this.ikona, this.opis);

  static _Tema za(VrstaPartnera v) => v == VrstaPartnera.dobavljac
      ? const _Tema(
          Color(0xFFEA580C),
          Color(0xFF9A3412),
          Icons.storefront_rounded,
          'Firme od kojih nabavljate robu i materijal.',
        )
      : const _Tema(
          Color(0xFF0D9488),
          Color(0xFF115E59),
          Icons.people_alt_rounded,
          'Firme i lica kojima prodajete gotove proizvode.',
        );
}

// Ispod ove širine partneri se prikazuju kao kartice umjesto tabele.
const double _sirinaTabele = 860;
const double _minSirinaTabele = 1000;
const double _visinaReda = 68;

// Kolone tabele: (naziv, flex).
const List<(String, int)> _kolone = [
  ('Naziv', 26),
  ('PIB', 12),
  ('PDV broj', 12),
  ('Adresa', 22),
  ('Kontakt', 22),
  ('', 11),
];

// Lista dobavljača ili kupaca izabrane firme, sa API-ja:
// GET /companies/{company}/suppliers|customers
class PartneriScreen extends StatefulWidget {
  final VrstaPartnera vrsta;

  const PartneriScreen({super.key, required this.vrsta});

  @override
  State<PartneriScreen> createState() => _PartneriScreenState();
}

class _PartneriScreenState extends State<PartneriScreen> {
  final searchController = TextEditingController();
  final ScrollController _horizontalni = ScrollController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final PartnersService _service = PartnersService();
  late final Worker _firmaWorker;

  List<Partner> partneri = [];
  bool _ucitavanje = false;
  String? _greska;

  int _stranica = 1;
  int _zadnjaStranica = 1;
  int _ukupno = 0;
  int? _od;
  int? _do;

  // Pretraga se šalje serveru tek kad korisnik prestane kucati.
  Timer? _pretragaTimer;
  String _pretraga = '';

  // Broj zadnjeg zahtjeva; stariji odgovori se ignorišu.
  int _zahtjev = 0;

  VrstaPartnera get _vrsta => widget.vrsta;
  _Tema get _tema => _Tema.za(_vrsta);
  bool get _imaFirmu => _firmaController.izabranaFirma.value != null;

  @override
  void initState() {
    super.initState();

    searchController.addListener(_promjenaPretrage);

    _firmaWorker = ever(_firmaController.izabranaFirma, (_) => _ucitaj());
    _ucitaj();
  }

  @override
  void dispose() {
    _pretragaTimer?.cancel();
    _firmaWorker.dispose();
    searchController.dispose();
    _horizontalni.dispose();
    super.dispose();
  }

  void _promjenaPretrage() {
    // Osvježava dugme za brisanje teksta.
    setState(() {});

    final tekst = searchController.text.trim();
    if (tekst == _pretraga) return;

    _pretragaTimer?.cancel();
    _pretragaTimer = Timer(const Duration(milliseconds: 400), () {
      _pretraga = tekst;
      _ucitaj();
    });
  }

  Future<void> _ucitaj([int stranica = 1]) async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      setState(() {
        partneri = [];
        _greska = null;
        _stranica = 1;
        _zadnjaStranica = 1;
        _ukupno = 0;
        _od = null;
        _do = null;
      });
      return;
    }

    setState(() {
      _ucitavanje = true;
      _greska = null;
    });

    try {
      final rezultat = await _service.fetchPartners(
        firma.id,
        _vrsta,
        page: stranica,
        search: _pretraga,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        partneri = rezultat.partneri;
        _stranica = rezultat.stranica;
        _zadnjaStranica = rezultat.zadnjaStranica;
        _ukupno = rezultat.ukupno;
        _od = rezultat.od;
        _do = rezultat.doBroja;
      });
    } on ApiException catch (e) {
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _greska = e.message);
    } finally {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _ucitavanje = false);
      }
    }
  }

  // Nakon uklanjanja zadnjeg reda na stranici vraća se na prethodnu.
  void _osvjeziNakonUklanjanja() {
    final stranica = partneri.length == 1 && _stranica > 1
        ? _stranica - 1
        : _stranica;
    _ucitaj(stranica);
  }

  Future<Partner?> _otvoriFormu(int firmaId, [Partner? partner]) {
    // Na uskom ekranu forma je preko cijelog ekrana.
    final usko = MediaQuery.sizeOf(context).width < 600;
    return showDialog<Partner>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _PartnerDialog(
        vrsta: _vrsta,
        firmaId: firmaId,
        partner: partner,
        cijeliEkran: usko,
      ),
    );
  }

  Future<void> _dodaj() async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final novi = await _otvoriFormu(firma.id);

    if (novi == null || !mounted) return;

    _poruka(context, '${_vrsta.jednina} ${novi.naziv} je dodat.');
    _ucitaj(_stranica);
  }

  Future<void> _izmijeni(Partner partner) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final izmijenjen = await _otvoriFormu(firma.id, partner);

    if (izmijenjen == null || !mounted) return;

    setState(() {
      final i = partneri.indexWhere((p) => p.id == izmijenjen.id);
      if (i != -1) partneri[i] = izmijenjen;
    });
  }

  Future<void> _obrisi(Partner partner) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _PotvrdaBrisanja(vrsta: _vrsta, partner: partner),
    );

    if (potvrda != true || !mounted) return;

    try {
      await _service.deletePartner(firma.id, _vrsta, partner.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _osvjeziNakonUklanjanja();
    _poruka(
      context,
      '${_vrsta.jednina} ${partner.naziv} je obrisan.',
      action: SnackBarAction(
        label: 'Poništi',
        textColor: const Color(0xFF7FE3C4),
        onPressed: () => _vrati(partner),
      ),
    );
  }

  Future<void> _vrati(Partner partner) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    try {
      await _service.restorePartner(firma.id, _vrsta, partner.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _ucitaj(_stranica);
    _poruka(context, '${_vrsta.jednina} ${partner.naziv} je vraćen.');
  }

  // ---------------------------------------------------------------------------
  // Sitni elementi
  // ---------------------------------------------------------------------------

  Widget _znak(String naziv, {double v = 40}) {
    final tema = _tema;
    return Container(
      width: v,
      height: v,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hoverNijansa(tema.boja, 0.12),
        borderRadius: BorderRadius.circular(v * 0.3),
      ),
      child: Text(
        _inicijali(naziv),
        style: TextStyle(
          fontSize: v * 0.34,
          fontWeight: FontWeight.w800,
          color: tema.tamna,
        ),
      ),
    );
  }

  Widget _tekst(String? tekst, {bool mono = false, bool jaci = false}) {
    final prazno = _prazno(tekst);
    return Text(
      prazno ? '—' : tekst!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        height: 1.35,
        fontWeight: jaci ? FontWeight.w600 : FontWeight.w500,
        color: prazno
            ? MagacinBoje.svijetlo
            : jaci
            ? MagacinBoje.naslov
            : MagacinBoje.tekst,
        fontFamily: mono && !prazno ? 'monospace' : null,
      ),
    );
  }

  // Tekst sa malom ikonom ispred (kontakt, grad).
  Widget _saIkonom(IconData ikona, String? tekst) {
    if (_prazno(tekst)) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikona, size: 13, color: MagacinBoje.svijetlo),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            tekst!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: MagacinBoje.tekst,
            ),
          ),
        ),
      ],
    );
  }

  Widget _skeleton(double sirina, {double visina = 10}) {
    return Container(
      width: sirina,
      height: visina,
      decoration: BoxDecoration(
        color: MagacinBoje.linija.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tabela (širok ekran)
  // ---------------------------------------------------------------------------

  Widget _celijaKolone(int i, Widget dijete) {
    return Expanded(
      flex: _kolone[i].$2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: i == _kolone.length - 1
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: dijete,
        ),
      ),
    );
  }

  Widget _zaglavljeTabele() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: MagacinBoje.zaglavlje,
        border: Border(
          top: BorderSide(color: MagacinBoje.linija),
          bottom: BorderSide(color: MagacinBoje.linija),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _kolone.length; i++)
            _celijaKolone(
              i,
              Text(
                _kolone[i].$1.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _akcije(Partner p) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IkonaAkcija(
          ikona: Icons.edit_rounded,
          poruka: 'Izmijeni',
          boja: _akcent,
          onTap: () => _izmijeni(p),
        ),
        const SizedBox(width: 6),
        IkonaAkcija(
          ikona: Icons.delete_outline_rounded,
          poruka: 'Obriši',
          boja: MagacinBoje.crvena,
          onTap: () => _obrisi(p),
        ),
      ],
    );
  }

  Widget _red(Partner p) {
    final bezKontakta = _prazno(p.telefon) && _prazno(p.email);
    return HoverRed(
      akcent: _tema.boja,
      visina: _visinaReda,
      builder: (hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _celijaKolone(
              0,
              Row(
                children: [
                  _znak(p.naziv),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      p.naziv,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _celijaKolone(1, _tekst(p.pib, mono: true)),
            _celijaKolone(2, _tekst(p.pdvBroj, mono: true)),
            _celijaKolone(
              3,
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tekst(p.adresa, jaci: true),
                  if (!_prazno(p.grad)) _saIkonom(Icons.place_outlined, p.grad),
                ],
              ),
            ),
            _celijaKolone(
              4,
              bezKontakta
                  ? _tekst(null)
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _saIkonom(Icons.phone_outlined, p.telefon),
                        _saIkonom(Icons.mail_outline_rounded, p.email),
                      ],
                    ),
            ),
            _celijaKolone(5, _akcije(p)),
          ],
        ),
      ),
    );
  }

  Widget _skeletonRed(int i) {
    return Container(
      height: _visinaReda,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Row(
        children: [
          _celijaKolone(
            0,
            Row(
              children: [
                _skeleton(40, visina: 40),
                const SizedBox(width: 12),
                _skeleton(i.isEven ? 130 : 90),
              ],
            ),
          ),
          for (int k = 1; k <= 4; k++) _celijaKolone(k, _skeleton(70)),
          _celijaKolone(5, _skeleton(74, visina: 30)),
        ],
      ),
    );
  }

  Widget _tabela(double sirina) {
    final sirinaTabele = sirina < _minSirinaTabele ? _minSirinaTabele : sirina;
    final prvo = _ucitavanje && partneri.isEmpty;

    Widget sadrzaj = SizedBox(
      width: sirinaTabele,
      child: Column(
        children: [
          _zaglavljeTabele(),
          if (prvo)
            for (int i = 0; i < 5; i++) _skeletonRed(i)
          else if (partneri.isEmpty)
            SizedBox(width: sirina, child: _praznoStanje())
          else
            AnimatedOpacity(
              duration: hoverTrajanje,
              opacity: _ucitavanje ? 0.55 : 1,
              child: Column(children: [for (final p in partneri) _red(p)]),
            ),
        ],
      ),
    );

    if (sirinaTabele > sirina) {
      sadrzaj = Scrollbar(
        controller: _horizontalni,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _horizontalni,
          scrollDirection: Axis.horizontal,
          child: sadrzaj,
        ),
      );
    }
    return sadrzaj;
  }

  // ---------------------------------------------------------------------------
  // Kartice (uzak ekran)
  // ---------------------------------------------------------------------------

  Widget _kartica(Partner p) {
    Widget podatak(IconData ikona, String naziv, String? vrijednost) {
      final prazno = _prazno(vrijednost);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikona, size: 15, color: MagacinBoje.svijetlo),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Text(
                naziv,
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ),
            Expanded(
              child: Text(
                prazno ? '—' : vrijednost!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: prazno ? MagacinBoje.svijetlo : MagacinBoje.naslov,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final adresa = [p.adresa, p.grad].where((s) => !_prazno(s)).join(', ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MagacinBoje.linija),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _znak(p.naziv, v: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.naziv,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    if (!_prazno(p.grad)) ...[
                      const SizedBox(height: 3),
                      _saIkonom(Icons.place_outlined, p.grad),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _akcije(p),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MagacinBoje.zaglavlje,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                podatak(Icons.badge_outlined, 'PIB', p.pib),
                podatak(Icons.receipt_outlined, 'PDV broj', p.pdvBroj),
                podatak(Icons.place_outlined, 'Adresa', adresa),
                podatak(Icons.phone_outlined, 'Telefon', p.telefon),
                podatak(Icons.mail_outline_rounded, 'Email', p.email),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartice() {
    if (_ucitavanje && partneri.isEmpty) {
      return Column(
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _skeleton(double.infinity, visina: 220),
            ),
        ],
      );
    }
    if (partneri.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MagacinBoje.linija),
        ),
        child: _praznoStanje(),
      );
    }
    return AnimatedOpacity(
      duration: hoverTrajanje,
      opacity: _ucitavanje ? 0.55 : 1,
      child: Column(
        children: [
          for (final p in partneri)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _kartica(p),
            ),
        ],
      ),
    );
  }

  Widget _praznoStanje() {
    final tema = _tema;
    final greska = _greska != null;
    final pretraga = _pretraga.isNotEmpty;
    final bezFirme = !_imaFirmu;

    final (IconData ikona, String naslov, String opis) = bezFirme
        ? (
            Icons.business_rounded,
            'Nije izabrana firma',
            'Izaberite firmu u gornjem desnom uglu da vidite '
                '${_vrsta.mnozina.toLowerCase()}.',
          )
        : greska
        ? (
            Icons.error_outline_rounded,
            '${_vrsta.mnozina} se ne mogu učitati',
            _greska!,
          )
        : pretraga
        ? (
            Icons.search_off_rounded,
            'Nema rezultata',
            'Nijedan ${_vrsta.jednina.toLowerCase()} ne odgovara pretrazi '
                '"$_pretraga".',
          )
        : (
            tema.ikona,
            _vrsta == VrstaPartnera.kupac
                ? 'Još nema kupaca'
                : 'Još nema dobavljača',
            'Dodajte prvog ${_vrsta.akuzativ} da biste ga mogli birati na '
                'dokumentima.',
          );

    final boja = greska ? MagacinBoje.crvena : tema.boja;
    final pozadina = greska
        ? MagacinBoje.crvenaSvijetlo
        : hoverNijansa(tema.boja, 0.1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: pozadina,
              shape: BoxShape.circle,
              border: Border.all(
                color: hoverNijansa(boja, 0.15, pozadina),
                width: 8,
              ),
            ),
            child: Icon(ikona, size: 28, color: boja),
          ),
          const SizedBox(height: 16),
          Text(
            naslov,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.naslov,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            opis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
          ),
          if (!bezFirme) ...[
            const SizedBox(height: 18),
            if (greska)
              GlatkoDugme(
                tekst: 'Pokušaj ponovo',
                ikona: Icons.refresh_rounded,
                vrsta: VrstaDugmeta.sekundarno,
                onTap: _ucitavanje ? null : () => _ucitaj(_stranica),
              )
            else if (pretraga)
              GlatkoDugme(
                tekst: 'Obriši pretragu',
                ikona: Icons.close_rounded,
                vrsta: VrstaDugmeta.sekundarno,
                onTap: searchController.clear,
              )
            else
              GlatkoDugme(
                tekst: 'Dodaj ${_vrsta.akuzativ}',
                ikona: Icons.add_rounded,
                onTap: _dodaj,
              ),
          ],
        ],
      ),
    );
  }

  Widget _paginacija() {
    final paginacija = Paginacija(
      stranica: _stranica,
      zadnjaStranica: _zadnjaStranica,
      ukupno: _ukupno,
      od: _od,
      doBroja: _do,
      zakljucano: _ucitavanje,
      prazno: 'Nema unosa',
      onStranica: _ucitaj,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        const minSirina = 680.0;
        if (constraints.maxWidth >= minSirina) return paginacija;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minSirina, child: paginacija),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Zaglavlje
  // ---------------------------------------------------------------------------

  Widget _pretrazivac() {
    return TextField(
      controller: searchController,
      enabled: _imaFirmu,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: MagacinBoje.naslov,
      ),
      decoration: dekoracijaPolja(
        hint: 'Pretraži po nazivu ili PIB-u…',
        ikona: Icons.search_rounded,
        suffix: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Obriši pretragu',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: MagacinBoje.priguseno,
                onPressed: searchController.clear,
              ),
      ).copyWith(fillColor: Colors.white),
    );
  }

  Widget _naslovStranice({required bool malo}) {
    final tema = _tema;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: malo ? 48 : 56,
          height: malo ? 48 : 56,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MagacinBoje.linija),
            boxShadow: [
              BoxShadow(
                color: tema.boja.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(tema.ikona, color: tema.boja, size: malo ? 24 : 28),
        ),
        SizedBox(width: malo ? 14 : 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Osnovni podaci',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 16,
                      color: MagacinBoje.svijetlo,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _vrsta.mnozina,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: tema.tamna,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _vrsta.mnozina,
                style: TextStyle(
                  fontSize: malo ? 26 : 32,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                tema.opis,
                style: const TextStyle(
                  fontSize: 14,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _brojKartica({
    required IconData ikona,
    required Color boja,
    required String naslov,
    required String vrijednost,
    required String napomena,
    required bool kompaktno,
  }) {
    final v = kompaktno ? 36.0 : 42.0;
    return Container(
      padding: EdgeInsets.all(kompaktno ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MagacinBoje.linija),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: v,
            height: v,
            decoration: BoxDecoration(
              color: hoverNijansa(boja, 0.1),
              borderRadius: BorderRadius.circular(v * 0.3),
            ),
            child: Icon(ikona, color: boja, size: v * 0.5),
          ),
          SizedBox(width: kompaktno ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  naslov,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: MagacinBoje.priguseno,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    vrijednost,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.naslov,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  napomena,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: MagacinBoje.svijetlo,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Svi aktivni partneri ove vrste uz trenutnu pretragu (sve stranice).
  Future<List<ListExcel>> _pripremiExcel() async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) throw ApiException('Nije izabrana firma.');

    final svi = <Partner>[];
    var stranica = 1;
    var zadnja = 1;
    do {
      final r = await _service.fetchPartners(
        firma.id,
        _vrsta,
        page: stranica,
        search: _pretraga,
        perPage: 100,
      );
      svi.addAll(r.partneri.where((p) => p.obrisan == null));
      zadnja = r.zadnjaStranica;
      stranica++;
    } while (stranica <= zadnja);

    return [
      ListExcel(
        naziv: _vrsta.mnozina,
        naslov: _vrsta.mnozina,
        podnaslovi: [
          firma.name,
          [
            '${svi.length} ukupno',
            if (_pretraga.isNotEmpty) 'Pretraga: $_pretraga',
          ].join(' · '),
        ],
        kolone: const [
          KolonaExcel('ID', vrsta: VrstaKolone.broj, sirina: 8),
          KolonaExcel('Naziv', sirina: 34),
          KolonaExcel('PIB', sirina: 16),
          KolonaExcel('PDV broj', sirina: 16),
          KolonaExcel('Adresa', sirina: 30),
          KolonaExcel('Grad', sirina: 16),
          KolonaExcel('Telefon', sirina: 16),
          KolonaExcel('Email', sirina: 28),
        ],
        redovi: [
          for (final p in svi)
            [
              p.id,
              p.naziv,
              p.pib,
              p.pdvBroj,
              p.adresa,
              p.grad,
              p.telefon,
              p.email,
            ],
        ],
      ),
    ];
  }

  Widget _zaglavlje() {
    final tema = _tema;
    final saPdv = partneri.where((p) => !_prazno(p.pdvBroj)).length;
    final gradova = partneri
        .map((p) => p.grad?.trim().toLowerCase())
        .where((g) => g != null && g.isNotEmpty)
        .toSet()
        .length;
    final naStranici = _zadnjaStranica > 1 ? 'na ovoj stranici' : 'ukupno';

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final malo = w < 600;
        final kompaktno = w < 520;

        final dodaj = GlatkoDugme(
          tekst: 'Dodaj ${_vrsta.akuzativ}',
          ikona: Icons.add_rounded,
          visina: 48,
          onTap: _imaFirmu ? _dodaj : null,
        );

        final excel = DugmeIzvoza(
          visina: 48,
          nazivFajla: () => _vrsta.mnozina,
          pripremi: _pripremiExcel,
        );

        final Widget vrh;
        if (w >= 1000) {
          vrh = Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _naslovStranice(malo: false)),
              const SizedBox(width: 24),
              SizedBox(width: 320, child: _pretrazivac()),
              const SizedBox(width: 10),
              if (_imaFirmu) ...[excel, const SizedBox(width: 10)],
              dodaj,
            ],
          );
        } else {
          vrh = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _naslovStranice(malo: malo),
              const SizedBox(height: 18),
              if (w >= 520)
                Row(
                  children: [
                    Expanded(child: _pretrazivac()),
                    const SizedBox(width: 10),
                    if (_imaFirmu) ...[excel, const SizedBox(width: 10)],
                    dodaj,
                  ],
                )
              else ...[
                _pretrazivac(),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_imaFirmu) ...[excel, const SizedBox(width: 10)],
                    Expanded(child: dodaj),
                  ],
                ),
              ],
            ],
          );
        }

        final kartice = [
          _brojKartica(
            ikona: tema.ikona,
            boja: tema.boja,
            naslov: _vrsta.mnozina,
            vrijednost: '$_ukupno',
            napomena: _pretraga.isEmpty ? 'ukupno' : 'za pretragu',
            kompaktno: kompaktno,
          ),
          _brojKartica(
            ikona: Icons.receipt_long_rounded,
            boja: _akcent,
            naslov: 'U sistemu PDV-a',
            vrijednost: '$saPdv',
            napomena: naStranici,
            kompaktno: kompaktno,
          ),
          _brojKartica(
            ikona: Icons.location_city_rounded,
            boja: MagacinBoje.zelena,
            naslov: 'Gradova',
            vrijednost: '$gradova',
            napomena: naStranici,
            kompaktno: kompaktno,
          ),
        ];

        // Tri u redu; na uskom ekranu prva preko cijele širine, ostale dvije
        // jedna pored druge.
        final Widget brojevi = w >= 700
            ? Row(
                children: [
                  for (int i = 0; i < kartice.length; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    Expanded(child: kartice[i]),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  kartice[0],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: kartice[1]),
                      const SizedBox(width: 12),
                      Expanded(child: kartice[2]),
                    ],
                  ),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            vrh,
            SizedBox(height: malo ? 18 : 24),
            if (_imaFirmu) brojevi,
          ],
        );
      },
    );
  }

  Widget _trakaGreske() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: MagacinBoje.crvenaSvijetlo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hoverNijansa(MagacinBoje.crvena, 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: MagacinBoje.crvena,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _greska!,
              style: const TextStyle(
                color: MagacinBoje.crvena,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: _ucitavanje ? null : () => _ucitaj(_stranica),
            style: TextButton.styleFrom(foregroundColor: MagacinBoje.crvena),
            child: const Text('Pokušaj ponovo'),
          ),
        ],
      ),
    );
  }

  Widget _alatnaTraka({bool kartice = false}) {
    return Padding(
      padding: kartice
          ? const EdgeInsets.symmetric(horizontal: 4)
          : const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Row(
        children: [
          Flexible(
            child: Text(
              'Svi ${_vrsta.mnozina.toLowerCase()}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: MagacinBoje.naslov,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: _akcentSvijetlo,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_ukupno',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _akcentTamni,
              ),
            ),
          ),
          const Spacer(),
          if (_ucitavanje)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _akcent),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MagacinBoje.pozadina,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final razmak = w < 600 ? 12.0 : 24.0;
          final tabela = w >= _sirinaTabele;

          return SingleChildScrollView(
            padding: EdgeInsets.all(razmak),
            child: Obx(() {
              // Prati izabranu firmu (zaglavlje i prazno stanje).
              _firmaController.izabranaFirma.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _zaglavlje(),
                  const SizedBox(height: 20),
                  if (_greska != null && partneri.isNotEmpty) _trakaGreske(),
                  if (tabela)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: MagacinBoje.linija),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0D0F172A),
                            blurRadius: 28,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _alatnaTraka(),
                          LayoutBuilder(
                            builder: (context, c) => _tabela(c.maxWidth),
                          ),
                          if (_imaFirmu)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              color: MagacinBoje.zaglavlje,
                              child: _paginacija(),
                            ),
                        ],
                      ),
                    )
                  else ...[
                    _alatnaTraka(kartice: true),
                    const SizedBox(height: 10),
                    _kartice(),
                    if (_imaFirmu)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: MagacinBoje.linija),
                        ),
                        child: _paginacija(),
                      ),
                  ],
                ],
              );
            }),
          );
        },
      ),
    );
  }
}

// ======================================================================
// POTVRDA BRISANJA
// ======================================================================
class _PotvrdaBrisanja extends StatelessWidget {
  final VrstaPartnera vrsta;
  final Partner partner;

  const _PotvrdaBrisanja({required this.vrsta, required this.partner});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: ZecStanja(
                  poza: PozaZeca.sjedi,
                  ikona: Icons.delete_outline_rounded,
                  boja: MagacinBoje.crvena,
                  pozadina: MagacinBoje.crvenaSvijetlo,
                  visina: 104,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Obriši ${vrsta.akuzativ}?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: partner.naziv,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' ostaje vidljiv na postojećim dokumentima, ali se '
                          'neće moći izabrati na novim. Brisanje možete '
                          'poništiti odmah nakon toga.',
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.45,
                  color: MagacinBoje.priguseno,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  GlatkoDugme(
                    tekst: 'Odustani',
                    vrsta: VrstaDugmeta.sekundarno,
                    onTap: () => Navigator.pop(context, false),
                  ),
                  GlatkoDugme(
                    tekst: 'Obriši',
                    ikona: Icons.delete_outline_rounded,
                    vrsta: VrstaDugmeta.opasno,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// DIJALOG ZA DODAVANJE / IZMJENU PARTNERA
// ======================================================================
class _PartnerDialog extends StatefulWidget {
  final VrstaPartnera vrsta;
  final int firmaId;
  final Partner? partner;

  // Na uskom ekranu forma zauzima cijeli ekran.
  final bool cijeliEkran;

  const _PartnerDialog({
    required this.vrsta,
    required this.firmaId,
    this.partner,
    this.cijeliEkran = false,
  });

  @override
  State<_PartnerDialog> createState() => _PartnerDialogState();
}

class _PartnerDialogState extends State<_PartnerDialog> {
  final _formKey = GlobalKey<FormState>();
  final PartnersService _service = PartnersService();

  late final nazivController = TextEditingController(
    text: widget.partner?.naziv,
  );
  late final pibController = TextEditingController(text: widget.partner?.pib);
  late final pdvController = TextEditingController(
    text: widget.partner?.pdvBroj,
  );
  late final adresaController = TextEditingController(
    text: widget.partner?.adresa,
  );
  late final gradController = TextEditingController(text: widget.partner?.grad);
  late final telefonController = TextEditingController(
    text: widget.partner?.telefon,
  );
  late final emailController = TextEditingController(
    text: widget.partner?.email,
  );

  bool _cuvanje = false;
  ApiException? _greska;

  bool get _izmjena => widget.partner != null;
  _Tema get _tema => _Tema.za(widget.vrsta);

  @override
  void dispose() {
    nazivController.dispose();
    pibController.dispose();
    pdvController.dispose();
    adresaController.dispose();
    gradController.dispose();
    telefonController.dispose();
    emailController.dispose();
    super.dispose();
  }

  String? _vrijednost(TextEditingController c) {
    final tekst = c.text.trim();
    return tekst.isEmpty ? null : tekst;
  }

  Future<void> _sacuvaj() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _cuvanje = true;
      _greska = null;
    });

    final unos = Partner(
      id: widget.partner?.id ?? 0,
      naziv: nazivController.text.trim(),
      pib: _vrijednost(pibController),
      pdvBroj: _vrijednost(pdvController),
      adresa: _vrijednost(adresaController),
      grad: _vrijednost(gradController),
      telefon: _vrijednost(telefonController),
      email: _vrijednost(emailController),
    );

    try {
      final Partner sacuvan;
      final stari = widget.partner;

      if (stari == null) {
        sacuvan = await _service.createPartner(
          widget.firmaId,
          widget.vrsta,
          unos,
        );
      } else {
        // Šalju se samo izmijenjena polja; obrisana vrijednost ide kao null.
        final staro = stari.toJson();
        final izmjene = unos.toJson()
          ..removeWhere((kljuc, vrijednost) => staro[kljuc] == vrijednost);

        sacuvan = izmjene.isEmpty
            ? stari
            : await _service.updatePartner(
                widget.firmaId,
                widget.vrsta,
                stari.id,
                izmjene,
              );
      }

      if (mounted) Navigator.pop(context, sacuvan);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _greska = e;
        _cuvanje = false;
      });
    }
  }

  Widget _polje(
    String label,
    TextEditingController controller,
    String apiPolje, {
    required int maxLength,
    required IconData ikona,
    String? hint,
    bool obavezno = false,
    FormFieldValidator<String>? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OznakaPolja(label, obavezno: obavezno),
        TextFormField(
          controller: controller,
          maxLength: maxLength,
          enabled: !_cuvanje,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MagacinBoje.naslov,
          ),
          decoration: dekoracijaPolja(hint: hint, ikona: ikona),
          forceErrorText: _greska?.fieldError(apiPolje),
          // Greška sa servera (npr. zauzet PIB) nestaje čim se polje mijenja;
          // inače bi forma ostala nevalidna i nakon ispravke.
          onChanged: (_) {
            if (_greska != null) setState(() => _greska = null);
          },
          validator: validator,
        ),
      ],
    );
  }

  Widget _sekcija(String naslov, IconData ikona, List<Widget> polja) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(ikona, size: 15, color: _akcent),
            const SizedBox(width: 7),
            Text(
              naslov.toUpperCase(),
              style: const TextStyle(
                fontSize: 10.5,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: _akcentTamni,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Divider(color: MagacinBoje.linija)),
          ],
        ),
        const SizedBox(height: 12),
        ...polja,
      ],
    );
  }

  // Dva polja jedno pored drugog, ili jedno ispod drugog na uskom.
  Widget _par(bool dvaStupca, Widget a, Widget b) {
    if (dvaStupca) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 14),
          Expanded(child: b),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [a, const SizedBox(height: 14), b],
    );
  }

  Widget _sadrzajForme(double sirina) {
    final dvaStupca = sirina >= 460;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sekcija('Osnovni podaci', _tema.ikona, [
            _polje(
              'Naziv',
              nazivController,
              'name',
              maxLength: 255,
              ikona: Icons.business_outlined,
              hint: 'npr. Firma d.o.o.',
              obavezno: true,
              validator: _validirajObavezno,
            ),
          ]),
          const SizedBox(height: 22),
          _sekcija('Porezni podaci', Icons.receipt_long_rounded, [
            _par(
              dvaStupca,
              _polje(
                'PIB',
                pibController,
                'tax_id',
                maxLength: 20,
                ikona: Icons.badge_outlined,
                hint: '8–13 cifara',
                validator: _validirajPib,
                keyboardType: TextInputType.number,
              ),
              _polje(
                'PDV broj',
                pdvController,
                'vat_number',
                maxLength: 20,
                ikona: Icons.receipt_outlined,
                hint: 'Opciono',
              ),
            ),
          ]),
          const SizedBox(height: 22),
          _sekcija('Adresa', Icons.place_rounded, [
            _par(
              dvaStupca,
              _polje(
                'Adresa',
                adresaController,
                'address',
                maxLength: 255,
                ikona: Icons.place_outlined,
                hint: 'Ulica i broj',
              ),
              _polje(
                'Grad',
                gradController,
                'city',
                maxLength: 100,
                ikona: Icons.location_city_outlined,
                hint: 'npr. Podgorica',
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ]),
          const SizedBox(height: 22),
          _sekcija('Kontakt', Icons.contact_phone_rounded, [
            _par(
              dvaStupca,
              _polje(
                'Telefon',
                telefonController,
                'phone',
                maxLength: 50,
                ikona: Icons.phone_outlined,
                hint: '+382 …',
                keyboardType: TextInputType.phone,
              ),
              _polje(
                'Email',
                emailController,
                'email',
                maxLength: 255,
                ikona: Icons.mail_outline_rounded,
                hint: 'ime@firma.com',
                validator: _validirajEmail,
                keyboardType: TextInputType.emailAddress,
              ),
            ),
          ]),
          AnimatedSize(
            duration: hoverTrajanje,
            curve: hoverKriva,
            alignment: Alignment.topCenter,
            child: _greska != null && _greska!.fieldErrors.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MagacinBoje.crvenaSvijetlo,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hoverNijansa(MagacinBoje.crvena, 0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            color: MagacinBoje.crvena,
                            size: 19,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _greska!.message,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: MagacinBoje.crvena,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _naslov() {
    final tema = _tema;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: hoverNijansa(tema.boja, 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            _izmjena ? Icons.edit_rounded : tema.ikona,
            color: tema.boja,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _izmjena
                    ? 'Izmijeni ${widget.vrsta.akuzativ}'
                    : 'Novi ${widget.vrsta.jednina.toLowerCase()}',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _izmjena
                    ? widget.partner!.naziv
                    : 'Obavezan je samo naziv; ostali podaci su opcioni.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Zatvori',
          onPressed: _cuvanje ? null : () => Navigator.pop(context),
          style: IconButton.styleFrom(
            foregroundColor: MagacinBoje.priguseno,
            hoverColor: const Color(0xFFF1F5F9),
          ),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  Widget _dugmad({required bool puno}) {
    final odustani = GlatkoDugme(
      tekst: 'Odustani',
      vrsta: VrstaDugmeta.sekundarno,
      onTap: _cuvanje ? null : () => Navigator.pop(context),
    );
    final sacuvaj = GlatkoDugme(
      tekst: _izmjena ? 'Sačuvaj izmjene' : 'Dodaj ${widget.vrsta.akuzativ}',
      ikona: Icons.check_rounded,
      ucitavanje: _cuvanje,
      onTap: _sacuvaj,
    );

    if (puno) {
      return Row(
        children: [
          Expanded(child: odustani),
          const SizedBox(width: 10),
          Expanded(flex: 2, child: sacuvaj),
        ],
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [odustani, const SizedBox(width: 10), sacuvaj],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cijeliEkran) {
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
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: _sadrzajForme(c.maxWidth - 36),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: MagacinBoje.linija)),
                ),
                child: _dugmad(puno: true),
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
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 16, 18),
              child: _naslov(),
            ),
            const Divider(height: 1, color: MagacinBoje.linija),
            Flexible(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
                  child: _sadrzajForme(c.maxWidth - 52),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
              decoration: const BoxDecoration(
                color: MagacinBoje.zaglavlje,
                border: Border(top: BorderSide(color: MagacinBoje.linija)),
              ),
              child: _dugmad(puno: false),
            ),
          ],
        ),
      ),
    );
  }
}

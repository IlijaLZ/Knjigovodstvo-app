import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../models/auth_models.dart';
import '../../models/company.dart';
import '../../services/companies_service.dart';
import '../../widgets/logo.dart';
import '../../widgets/magacin_ui.dart';
import '../../widgets/paginacija_widget.dart';

String? _validirajObavezno(String? value) {
  if (value == null || value.trim().isEmpty) return 'Obavezno polje';
  return null;
}

// PIB: 8–13 cifara; crtice i razmaci se ignorišu (server ih uklanja).
String? _validirajPib(String? value) {
  final pib = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
  if (pib.isEmpty) return 'Obavezno polje';
  if (!RegExp(r'^\d{8,13}$').hasMatch(pib)) return 'PIB mora imati 8–13 cifara';
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

const Color _akcent = akcentAplikacije;
const Color _akcentSvijetlo = Color(0xFFE6F4F3);
const Color _akcentTamni = Color(0xFF0B434B);

// Ispod ove širine firme se prikazuju kao kartice umjesto tabele.
const double _sirinaTabele = 860;
const double _minSirinaTabele = 1040;
const double _visinaReda = 68;

// Kolone tabele: (naziv, flex).
const List<(String, int)> _kolone = [
  ('Firma', 28),
  ('PIB', 13),
  ('PDV broj', 13),
  ('Adresa', 22),
  ('Ovlašteno lice', 17),
  ('Artikala', 9),
  ('', 18),
];

// Lista firmi prijavljenog korisnika, sa API-ja: GET /companies.
// Nakon svake promjene osvježava se i lista firmi u gornjem desnom uglu.
class FirmeScreen extends StatefulWidget {
  const FirmeScreen({super.key});

  @override
  State<FirmeScreen> createState() => _FirmeScreenState();
}

class _FirmeScreenState extends State<FirmeScreen> {
  final searchController = TextEditingController();
  final ScrollController _horizontalni = ScrollController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final CompaniesService _service = CompaniesService();

  List<Company> firme = [];
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

  @override
  void initState() {
    super.initState();

    searchController.addListener(_promjenaPretrage);
    _ucitaj();
  }

  @override
  void dispose() {
    _pretragaTimer?.cancel();
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
    final zahtjev = ++_zahtjev;

    setState(() {
      _ucitavanje = true;
      _greska = null;
    });

    try {
      final rezultat = await _service.fetchCompanies(
        page: stranica,
        search: _pretraga,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        firme = rezultat.firme;
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
    final stranica = firme.length == 1 && _stranica > 1
        ? _stranica - 1
        : _stranica;
    _ucitaj(stranica);
  }

  Future<Company?> _otvoriFormu([Company? firma]) {
    // Na uskom ekranu forma je preko cijelog ekrana.
    final usko = MediaQuery.sizeOf(context).width < 600;
    return showDialog<Company>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _FirmaDialog(firma: firma, cijeliEkran: usko),
    );
  }

  Future<void> _dodaj() async {
    final nova = await _otvoriFormu();

    if (nova == null || !mounted) return;

    _poruka(context, 'Firma ${nova.name} je dodata.');
    _firmaController.ucitajFirme();
    _ucitaj(_stranica);
  }

  Future<void> _izmijeni(Company firma) async {
    final izmijenjena = await _otvoriFormu(firma);

    if (izmijenjena == null || !mounted) return;

    setState(() {
      final i = firme.indexWhere((f) => f.id == izmijenjena.id);
      if (i != -1) firme[i] = izmijenjena;
    });
    _firmaController.ucitajFirme();
  }

  Future<void> _obrisi(Company firma) async {
    final potvrda = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _PotvrdaBrisanja(firma: firma),
    );

    if (potvrda != true || !mounted) return;

    try {
      await _service.deleteCompany(firma.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _firmaController.ucitajFirme();
    _osvjeziNakonUklanjanja();
    _poruka(
      context,
      'Firma ${firma.name} je obrisana.',
      action: SnackBarAction(
        label: 'Poništi',
        textColor: const Color(0xFF7FE3C4),
        onPressed: () => _vrati(firma),
      ),
    );
  }

  Future<void> _vrati(Company firma) async {
    try {
      await _service.restoreCompany(firma.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _firmaController.ucitajFirme();
    _ucitaj(_stranica);
    _poruka(context, 'Firma ${firma.name} je vraćena.');
  }

  void _izaberi(Company firma) {
    _firmaController.izaberiFirmu(firma);
    _poruka(context, 'Radite u firmi ${firma.name}.');
  }

  // ---------------------------------------------------------------------------
  // Prikaz
  // ---------------------------------------------------------------------------

  Widget _znakFirme(String naziv, {required bool izabrana, double v = 40}) {
    return Container(
      width: v,
      height: v,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: izabrana
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0A3238), _akcent],
              )
            : null,
        color: izabrana ? null : _akcentSvijetlo,
        borderRadius: BorderRadius.circular(v * 0.3),
      ),
      child: Text(
        _inicijali(naziv),
        style: TextStyle(
          fontSize: v * 0.34,
          fontWeight: FontWeight.w800,
          color: izabrana ? mint : _akcent,
        ),
      ),
    );
  }

  Widget _oznakaTrenutna() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: MagacinBoje.zelenaSvijetlo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 12, color: MagacinBoje.zelena),
          SizedBox(width: 3),
          Text(
            'Trenutna',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.zelena,
            ),
          ),
        ],
      ),
    );
  }

  Widget _akcije(Company firma, bool izabrana) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IkonaAkcija(
          ikona: izabrana
              ? Icons.check_circle_rounded
              : Icons.check_circle_outline_rounded,
          poruka: izabrana ? 'Trenutna firma' : 'Radi u ovoj firmi',
          boja: MagacinBoje.zelena,
          onTap: izabrana ? null : () => _izaberi(firma),
        ),
        const SizedBox(width: 6),
        IkonaAkcija(
          ikona: Icons.edit_rounded,
          poruka: 'Izmijeni',
          boja: _akcent,
          onTap: () => _izmijeni(firma),
        ),
        const SizedBox(width: 6),
        IkonaAkcija(
          ikona: Icons.delete_outline_rounded,
          poruka: 'Obriši',
          boja: MagacinBoje.crvena,
          onTap: () => _obrisi(firma),
        ),
      ],
    );
  }

  Widget _tekst(String? tekst, {bool mono = false}) {
    final prazno = tekst == null || tekst.isEmpty;
    return Text(
      prazno ? '—' : tekst,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: prazno ? MagacinBoje.svijetlo : MagacinBoje.tekst,
        fontFamily: mono && !prazno ? 'monospace' : null,
      ),
    );
  }

  Widget _celijaKolone(int i, Widget dijete) {
    final (_, flex) = _kolone[i];
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: i == 5
              ? Alignment.centerRight
              : i == 6
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

  Widget _red(Company firma, bool izabrana) {
    return HoverRed(
      akcent: _akcent,
      visina: _visinaReda,
      builder: (hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _celijaKolone(
              0,
              Row(
                children: [
                  _znakFirme(firma.name, izabrana: izabrana),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      firma.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                  ),
                  if (izabrana) ...[
                    const SizedBox(width: 8),
                    _oznakaTrenutna(),
                  ],
                ],
              ),
            ),
            _celijaKolone(1, _tekst(firma.taxId, mono: true)),
            _celijaKolone(2, _tekst(firma.vatNumber, mono: true)),
            _celijaKolone(3, _tekst(firma.address)),
            _celijaKolone(4, _tekst(firma.authorizedPerson)),
            _celijaKolone(
              5,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: MagacinBoje.zaglavlje,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MagacinBoje.linija),
                ),
                child: Text(
                  '${firma.articlesCount}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: MagacinBoje.tekst,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            _celijaKolone(6, _akcije(firma, izabrana)),
          ],
        ),
      ),
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
                _skeleton(i.isEven ? 140 : 100),
              ],
            ),
          ),
          for (int k = 1; k <= 4; k++) _celijaKolone(k, _skeleton(70)),
          _celijaKolone(5, _skeleton(28, visina: 20)),
          _celijaKolone(6, _skeleton(110, visina: 30)),
        ],
      ),
    );
  }

  Widget _tabela(double sirina) {
    final sirinaTabele = sirina < _minSirinaTabele ? _minSirinaTabele : sirina;
    final izabrana = _firmaController.izabranaFirma.value;
    final prvo = _ucitavanje && firme.isEmpty;

    Widget sadrzaj = SizedBox(
      width: sirinaTabele,
      child: Column(
        children: [
          _zaglavljeTabele(),
          if (prvo)
            for (int i = 0; i < 5; i++) _skeletonRed(i)
          else if (firme.isEmpty)
            _praznoStanje()
          else
            AnimatedOpacity(
              duration: hoverTrajanje,
              opacity: _ucitavanje ? 0.55 : 1,
              child: Column(
                children: [for (final f in firme) _red(f, f == izabrana)],
              ),
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

  Widget _kartica(Company firma, bool izabrana) {
    Widget podatak(IconData ikona, String naziv, String? vrijednost) {
      final prazno = vrijednost == null || vrijednost.isEmpty;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikona, size: 15, color: MagacinBoje.svijetlo),
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
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
                prazno ? '—' : vrijednost,
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

    return AnimatedContainer(
      duration: hoverTrajanje,
      curve: hoverKriva,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: izabrana ? hoverNijansa(_akcent, 0.45) : MagacinBoje.linija,
          width: izabrana ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _znakFirme(firma.name, izabrana: izabrana, v: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firma.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (izabrana) _oznakaTrenutna(),
                        Text(
                          '${firma.articlesCount} artikala',
                          style: const TextStyle(
                            fontSize: 12,
                            color: MagacinBoje.priguseno,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
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
                podatak(Icons.badge_outlined, 'PIB', firma.taxId),
                podatak(Icons.receipt_outlined, 'PDV broj', firma.vatNumber),
                podatak(Icons.place_outlined, 'Adresa', firma.address),
                podatak(
                  Icons.person_outline_rounded,
                  'Ovlašteno lice',
                  firma.authorizedPerson,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: izabrana
                    ? const SizedBox(
                        height: 40,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Trenutno radite u ovoj firmi',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: MagacinBoje.zelena,
                            ),
                          ),
                        ),
                      )
                    : GlatkoDugme(
                        tekst: 'Radi u ovoj firmi',
                        ikona: Icons.login_rounded,
                        vrsta: VrstaDugmeta.sekundarno,
                        visina: 40,
                        onTap: () => _izaberi(firma),
                      ),
              ),
              const SizedBox(width: 8),
              IkonaAkcija(
                ikona: Icons.edit_rounded,
                poruka: 'Izmijeni',
                boja: _akcent,
                onTap: () => _izmijeni(firma),
              ),
              const SizedBox(width: 6),
              IkonaAkcija(
                ikona: Icons.delete_outline_rounded,
                poruka: 'Obriši',
                boja: MagacinBoje.crvena,
                onTap: () => _obrisi(firma),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kartice() {
    final izabrana = _firmaController.izabranaFirma.value;
    if (_ucitavanje && firme.isEmpty) {
      return Column(
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _skeleton(double.infinity, visina: 200),
            ),
        ],
      );
    }
    if (firme.isEmpty) {
      return Container(
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
          for (final f in firme)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _kartica(f, f == izabrana),
            ),
        ],
      ),
    );
  }

  Widget _praznoStanje() {
    final greska = _greska != null;
    final pretraga = _pretraga.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZecStanja(
            poza: greska
                ? PozaZeca.lezi
                : pretraga
                ? PozaZeca.stoji
                : PozaZeca.klik,
            ikona: greska
                ? Icons.error_outline_rounded
                : pretraga
                ? Icons.search_off_rounded
                : Icons.business_rounded,
            boja: greska ? MagacinBoje.crvena : _akcent,
            pozadina: greska ? MagacinBoje.crvenaSvijetlo : _akcentSvijetlo,
            visina: greska ? 60 : 128,
          ),
          const SizedBox(height: 16),
          Text(
            greska
                ? 'Firme se ne mogu učitati'
                : pretraga
                ? 'Nema rezultata'
                : 'Još nema firmi',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.naslov,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _greska ??
                (pretraga
                    ? 'Nijedna firma ne odgovara pretrazi "$_pretraga".'
                    : 'Dodajte prvu firmu da biste počeli sa radom.'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
          ),
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
              tekst: 'Dodaj firmu',
              ikona: Icons.add_rounded,
              onTap: _dodaj,
            ),
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
      prazno: 'Nema firmi',
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

  Widget _pretrazivac() {
    return TextField(
      controller: searchController,
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

  // Naslov stranice: putanja, naslov i podnaslov.
  Widget _naslovStranice({required bool malo}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 14,
              color: MagacinBoje.svijetlo,
            ),
            SizedBox(width: 6),
            Text(
              'Osnovni podaci',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: MagacinBoje.priguseno,
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: MagacinBoje.svijetlo,
              ),
            ),
            Text(
              'Firme',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _akcent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Firme',
          style: TextStyle(
            fontSize: malo ? 26 : 32,
            height: 1.1,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: MagacinBoje.naslov,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Upravljajte firmama svog naloga i izaberite firmu u kojoj radite.',
          style: TextStyle(fontSize: 14, color: MagacinBoje.priguseno),
        ),
      ],
    );
  }

  BoxDecoration get _bijelaKartica => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: MagacinBoje.linija),
    boxShadow: const [
      BoxShadow(color: Color(0x080F172A), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x0A0F172A),
        blurRadius: 24,
        offset: Offset(0, 10),
      ),
    ],
  );

  // Istaknuta kartica sa podacima firme u kojoj korisnik trenutno radi.
  Widget _trenutnaFirma({required bool usko}) {
    final firma = _firmaController.izabranaFirma.value;

    Widget podatak(IconData ikona, String naziv, String? vrijednost) {
      final prazno = vrijednost == null || vrijednost.isEmpty;
      return ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 260),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: MagacinBoje.zaglavlje,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: MagacinBoje.linijaSvijetla),
              ),
              child: Icon(ikona, size: 15, color: MagacinBoje.priguseno),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    naziv.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.svijetlo,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    prazno ? '—' : vrijednost,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: prazno ? MagacinBoje.svijetlo : MagacinBoje.naslov,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: _bijelaKartica,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Tanka traka u boji uz lijevi rub.
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [mint, mintTamni],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(usko ? 18 : 22, 18, 18, 18),
            child: firma == null
                ? const Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: MagacinBoje.svijetlo,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Nije izabrana firma. Izaberite firmu iz liste.',
                          style: TextStyle(color: MagacinBoje.priguseno),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _znakFirme(firma.name, izabrana: true, v: 48),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: MagacinBoje.zelena,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'TRENUTNO RADITE U',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1,
                                        fontWeight: FontWeight.w800,
                                        color: MagacinBoje.zelena,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  firma.name,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    height: 1.2,
                                    fontWeight: FontWeight.w800,
                                    color: MagacinBoje.naslov,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          IkonaAkcija(
                            ikona: Icons.edit_rounded,
                            poruka: 'Izmijeni trenutnu firmu',
                            boja: _akcent,
                            onTap: () => _izmijeni(firma),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 20,
                        runSpacing: 12,
                        children: [
                          podatak(Icons.badge_outlined, 'PIB', firma.taxId),
                          podatak(
                            Icons.receipt_outlined,
                            'PDV broj',
                            firma.vatNumber,
                          ),
                          podatak(
                            Icons.place_outlined,
                            'Adresa',
                            firma.address,
                          ),
                          podatak(
                            Icons.person_outline_rounded,
                            'Ovlašteno lice',
                            firma.authorizedPerson,
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // Mala bijela kartica sa jednim brojem.
  Widget _brojKartica({
    required IconData ikona,
    required Color boja,
    required String naslov,
    required String vrijednost,
    required String napomena,
    bool kompaktno = false,
  }) {
    final v = kompaktno ? 36.0 : 44.0;
    return Container(
      padding: EdgeInsets.all(kompaktno ? 14 : 18),
      decoration: _bijelaKartica,
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
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    vrijednost,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.15,
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

  Widget _zaglavlje() {
    final artikala = firme.fold<int>(0, (s, f) => s + f.articlesCount);

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final malo = w < 600;

        final dodaj = GlatkoDugme(
          tekst: 'Dodaj firmu',
          ikona: Icons.add_rounded,
          visina: 48,
          onTap: _dodaj,
        );

        // Naslov + pretraga + dugme.
        final Widget vrh;
        if (w >= 980) {
          vrh = Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _naslovStranice(malo: false)),
              const SizedBox(width: 24),
              SizedBox(width: 320, child: _pretrazivac()),
              const SizedBox(width: 10),
              dodaj,
            ],
          );
        } else {
          vrh = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _naslovStranice(malo: malo),
              const SizedBox(height: 18),
              if (w >= 480)
                Row(
                  children: [
                    Expanded(child: _pretrazivac()),
                    const SizedBox(width: 10),
                    dodaj,
                  ],
                )
              else ...[
                _pretrazivac(),
                const SizedBox(height: 10),
                dodaj,
              ],
            ],
          );
        }

        final brojFirmi = _brojKartica(
          ikona: Icons.business_rounded,
          boja: _akcent,
          naslov: 'Firmi',
          vrijednost: '$_ukupno',
          napomena: _pretraga.isEmpty ? 'na vašem nalogu' : 'za pretragu',
          kompaktno: w < 480,
        );
        final brojArtikala = _brojKartica(
          ikona: Icons.category_rounded,
          boja: MagacinBoje.zelena,
          naslov: 'Artikala',
          vrijednost: '$artikala',
          napomena: _zadnjaStranica > 1 ? 'na ovoj stranici' : 'u svim firmama',
          kompaktno: w < 480,
        );

        // Trenutna firma + brojevi: pored, ili jedno ispod drugog.
        final Widget pregled;
        if (w >= 1100) {
          pregled = IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _trenutnaFirma(usko: false)),
                const SizedBox(width: 16),
                SizedBox(
                  width: 250,
                  child: Column(
                    children: [
                      Expanded(child: brojFirmi),
                      const SizedBox(height: 16),
                      Expanded(child: brojArtikala),
                    ],
                  ),
                ),
              ],
            ),
          );
        } else {
          pregled = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _trenutnaFirma(usko: malo),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: brojFirmi),
                  const SizedBox(width: 12),
                  Expanded(child: brojArtikala),
                ],
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            vrh,
            SizedBox(height: malo ? 18 : 24),
            pregled,
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
              // Obx prati izabranu firmu (oznaka "Trenutna" i kartice).
              _firmaController.izabranaFirma.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _zaglavlje(),
                  const SizedBox(height: 20),
                  if (_greska != null && firme.isNotEmpty) _trakaGreske(),
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

  Widget _alatnaTraka({bool kartice = false}) {
    return Padding(
      padding: kartice
          ? const EdgeInsets.symmetric(horizontal: 4)
          : const EdgeInsets.fromLTRB(20, 16, 16, 14),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              'Sve firme',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
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
}

// ======================================================================
// POTVRDA BRISANJA
// ======================================================================
class _PotvrdaBrisanja extends StatelessWidget {
  final Company firma;

  const _PotvrdaBrisanja({required this.firma});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
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
              const Text(
                'Obriši firmu?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Firma '),
                    TextSpan(
                      text: firma.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' će biti obrisana. Brisanje možete poništiti odmah '
                          'nakon toga.',
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
// DIJALOG ZA DODAVANJE / IZMJENU FIRME
// ======================================================================
class _FirmaDialog extends StatefulWidget {
  final Company? firma;

  // Na uskom ekranu forma zauzima cijeli ekran.
  final bool cijeliEkran;

  const _FirmaDialog({this.firma, this.cijeliEkran = false});

  @override
  State<_FirmaDialog> createState() => _FirmaDialogState();
}

class _FirmaDialogState extends State<_FirmaDialog> {
  final _formKey = GlobalKey<FormState>();
  final CompaniesService _service = CompaniesService();

  late final nazivController = TextEditingController(text: widget.firma?.name);
  late final adresaController = TextEditingController(
    text: widget.firma?.address,
  );
  late final pibController = TextEditingController(text: widget.firma?.taxId);
  late final pdvController = TextEditingController(
    text: widget.firma?.vatNumber,
  );
  late final ovlastenoLiceController = TextEditingController(
    text: widget.firma?.authorizedPerson,
  );

  bool _cuvanje = false;
  ApiException? _greska;

  bool get _izmjena => widget.firma != null;

  @override
  void dispose() {
    nazivController.dispose();
    adresaController.dispose();
    pibController.dispose();
    pdvController.dispose();
    ovlastenoLiceController.dispose();
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

    final unos = Company(
      id: widget.firma?.id ?? 0,
      name: nazivController.text.trim(),
      address: _vrijednost(adresaController),
      taxId: _vrijednost(pibController),
      vatNumber: _vrijednost(pdvController),
      authorizedPerson: _vrijednost(ovlastenoLiceController),
    );

    try {
      final Company sacuvana;
      final stara = widget.firma;

      if (stara == null) {
        sacuvana = await _service.createCompany(unos);
      } else {
        // Šalju se samo izmijenjena polja; obrisan PDV broj ide kao null.
        final staro = stara.toJson();
        final izmjene = unos.toJson()
          ..removeWhere((kljuc, vrijednost) => staro[kljuc] == vrijednost);

        sacuvana = izmjene.isEmpty
            ? stara
            : await _service.updateCompany(stara.id, izmjene);
      }

      if (mounted) Navigator.pop(context, sacuvana);
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

  Widget _sadrzajForme(double sirina) {
    final dvaStupca = sirina >= 460;

    final pib = _polje(
      'PIB',
      pibController,
      'tax_id',
      maxLength: 20,
      ikona: Icons.badge_outlined,
      hint: '8–13 cifara',
      obavezno: true,
      validator: _validirajPib,
      keyboardType: TextInputType.number,
    );
    final pdv = _polje(
      'PDV broj',
      pdvController,
      'vat_number',
      maxLength: 20,
      ikona: Icons.receipt_outlined,
      hint: 'Opciono',
    );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_izmjena) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _akcentSvijetlo,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hoverNijansa(_akcent, 0.18)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warehouse_rounded, size: 18, color: _akcent),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Uz firmu se automatski prave tri skladišta: '
                      'repromaterijal, proizvodnja u toku i gotovi proizvodi.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: _akcentTamni,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],
          _sekcija('Osnovni podaci', Icons.business_rounded, [
            _polje(
              'Naziv firme',
              nazivController,
              'name',
              maxLength: 255,
              ikona: Icons.business_outlined,
              hint: 'npr. Firma d.o.o.',
              obavezno: true,
              validator: _validirajObavezno,
            ),
            const SizedBox(height: 14),
            _polje(
              'Adresa',
              adresaController,
              'address',
              maxLength: 255,
              ikona: Icons.place_outlined,
              hint: 'Ulica i broj, grad',
              obavezno: true,
              validator: _validirajObavezno,
            ),
          ]),
          const SizedBox(height: 22),
          _sekcija('Porezni podaci', Icons.receipt_long_rounded, [
            if (dvaStupca)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: pib),
                  const SizedBox(width: 14),
                  Expanded(child: pdv),
                ],
              )
            else ...[
              pib,
              const SizedBox(height: 14),
              pdv,
            ],
          ]),
          const SizedBox(height: 22),
          _sekcija('Odgovorno lice', Icons.person_rounded, [
            _polje(
              'Ovlašteno lice',
              ovlastenoLiceController,
              'authorized_person',
              maxLength: 255,
              ikona: Icons.person_outline_rounded,
              hint: 'Ime i prezime',
              obavezno: true,
              validator: _validirajObavezno,
              textCapitalization: TextCapitalization.words,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _akcentSvijetlo,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            _izmjena ? Icons.edit_rounded : Icons.add_business_rounded,
            color: _akcent,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _izmjena ? 'Izmijeni firmu' : 'Nova firma',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _izmjena
                    ? widget.firma!.name
                    : 'Unesite podatke o firmi. Polja sa * su obavezna.',
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
      tekst: _izmjena ? 'Sačuvaj izmjene' : 'Dodaj firmu',
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
        constraints: const BoxConstraints(maxWidth: 580),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/controllers/poslovne_godine_controller.dart';
import 'package:knjigovodstvo_app/izvoz/dugme_izvoza.dart';
import 'package:knjigovodstvo_app/izvoz/excel_izvoz.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/purchase_calculation.dart';
import 'package:knjigovodstvo_app/routes/app_routes.dart';
import 'package:knjigovodstvo_app/services/purchase_calculations_service.dart';
import 'package:knjigovodstvo_app/widgets/logo.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';
import 'package:knjigovodstvo_app/widgets/paginacija_widget.dart';

String _formatDatum(DateTime? datum) {
  if (datum == null) return '';
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}';
}

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
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

const Color _akcent = akcentAplikacije;
const Color _akcentSvijetlo = Color(0xFFE6F4F3);
const Color _nacrt = Color(0xFFB45309);
const Color _nacrtSvijetlo = Color(0xFFFEF3C7);

// Filter po statusu: (oznaka, status za API; null = sve).
const List<(String, String?)> _statusi = [
  ('Sve', null),
  ('Nacrti', statusKalkulacijeNacrt),
  ('Proknjižene', statusKalkulacijeProknjizena),
];

// Ispod ove širine kalkulacije se prikazuju kao kartice umjesto tabele.
const double _sirinaTabele = 900;
const double _minSirinaTabele = 1200;
const double _visinaReda = 68;
const double _sirinaStatusa = 96;

// Kolone tabele: (naziv, flex).
const List<(String, int)> _kolone = [
  ('Dokument', 16),
  ('Status', 13),
  ('Datum', 10),
  ('Dobavljač', 16),
  ('Artikli', 17),
  ('Objekat', 12),
  ('Kalkulisao / primio', 13),
  ('Nabavna vrijednost', 13),
  ('', 17),
];

// Lista kalkulacija izabrane firme: GET /companies/{company}/purchase-calculations
class KalkulacijaNabavnihCijenaScreen extends StatefulWidget {
  const KalkulacijaNabavnihCijenaScreen({super.key});

  @override
  State<KalkulacijaNabavnihCijenaScreen> createState() =>
      _KalkulacijaNabavnihCijenaScreenState();
}

class _KalkulacijaNabavnihCijenaScreenState
    extends State<KalkulacijaNabavnihCijenaScreen> {
  final searchController = TextEditingController();
  final ScrollController _horizontalni = ScrollController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final PurchaseCalculationsService _service = PurchaseCalculationsService();
  late final Worker _firmaWorker;

  List<Kalkulacija> kalkulacije = [];

  // Nazivi artikala po kalkulaciji. Lista ne vraća stavke, pa se
  // dohvataju iz detalja svake kalkulacije na stranici.
  final Map<int, List<String>> _artikli = {};
  bool _ucitavanje = false;
  String? _greska;

  int _stranica = 1;
  int _zadnjaStranica = 1;
  int _ukupno = 0;
  int? _od;
  int? _do;

  Timer? _pretragaTimer;
  String _pretraga = '';

  // Filter po statusu (null = sve).
  String? _status;

  // Broj zadnjeg zahtjeva; stariji odgovori se ignorišu.
  int _zahtjev = 0;

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
    setState(() {});

    final tekst = searchController.text.trim();
    if (tekst == _pretraga) return;

    _pretragaTimer?.cancel();
    _pretragaTimer = Timer(const Duration(milliseconds: 400), () {
      _pretraga = tekst;
      _ucitaj();
    });
  }

  void _promjenaStatusa(String? status) {
    if (status == _status) return;
    setState(() => _status = status);
    _ucitaj();
  }

  Future<void> _ucitaj([int stranica = 1]) async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      setState(() {
        kalkulacije = [];
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
      final rezultat = await _service.fetchCalculations(
        firma.id,
        page: stranica,
        search: _pretraga,
        status: _status,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        kalkulacije = rezultat.kalkulacije;
        for (final k in rezultat.kalkulacije) {
          if (k.stavke.isNotEmpty) {
            _artikli[k.id] = k.stavke.map((s) => s.naziv).toList();
          }
        }
        _stranica = rezultat.stranica;
        _zadnjaStranica = rezultat.zadnjaStranica;
        _ukupno = rezultat.ukupno;
        _od = rezultat.od;
        _do = rezultat.doBroja;
      });
      _ucitajArtikle(firma.id, rezultat.kalkulacije, zahtjev);
    } on ApiException catch (e) {
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _greska = e.message);
    } finally {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _ucitavanje = false);
      }
    }
  }

  Future<void> _otvori([Kalkulacija? kalkulacija]) async {
    final sacuvano = await Get.toNamed(
      AppRoutes.dodajKalkulacijuNabavnuCijenu,
      arguments: kalkulacija?.id,
    );
    if (sacuvano != true || !mounted) return;
    _ucitaj(kalkulacija == null ? 1 : _stranica);
    _poruka(context, 'Kalkulacija je sačuvana.');
  }

  Future<bool> _potvrdi({
    required String naslov,
    required String tekst,
    required String dugme,
    required IconData ikona,
    required bool opasno,
  }) async {
    final potvrda = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => PotvrdaDijalog(
        naslov: naslov,
        tekst: tekst,
        dugme: dugme,
        ikona: ikona,
        opasno: opasno,
      ),
    );
    return potvrda == true;
  }

  String _oznaka(Kalkulacija k) =>
      k.brojPrijemnice.isNotEmpty ? k.brojPrijemnice : k.brojFakture;

  Future<void> _proknjizi(Kalkulacija kalkulacija) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      naslov: 'Proknjiži kalkulaciju?',
      tekst:
          'Knjiženjem kalkulacije ${_oznaka(kalkulacija)} roba ulazi na '
          'zalihu skladišta i upisuje se na karticu artikla. Kalkulacija se '
          'poslije ne može mijenjati ni brisati.',
      dugme: 'Proknjiži',
      ikona: Icons.inventory_2_rounded,
      opasno: false,
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.bookCalculation(firma.id, kalkulacija.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _poruka(context, 'Kalkulacija ${_oznaka(kalkulacija)} je proknjižena.');
    _ucitaj(_stranica);
  }

  Future<void> _obrisi(Kalkulacija kalkulacija) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      naslov: 'Obriši kalkulaciju?',
      tekst:
          'Kalkulacija ${_oznaka(kalkulacija)} će biti obrisana. Brisanje '
          'možete poništiti odmah nakon toga.',
      dugme: 'Obriši',
      ikona: Icons.delete_outline_rounded,
      opasno: true,
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.deleteCalculation(firma.id, kalkulacija.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    // Nakon brisanja zadnjeg reda na stranici vraća se na prethodnu.
    _ucitaj(
      kalkulacije.length == 1 && _stranica > 1 ? _stranica - 1 : _stranica,
    );
    _poruka(
      context,
      'Kalkulacija ${_oznaka(kalkulacija)} je obrisana.',
      action: SnackBarAction(
        label: 'Poništi',
        textColor: const Color(0xFF7FE3C4),
        onPressed: () => _vrati(firma.id, kalkulacija),
      ),
    );
  }

  Future<void> _vrati(int firmaId, Kalkulacija kalkulacija) async {
    try {
      await _service.restoreCalculation(firmaId, kalkulacija.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _ucitaj(_stranica);
    _poruka(context, 'Kalkulacija ${_oznaka(kalkulacija)} je vraćena.');
  }

  Future<void> _ucitajArtikle(
    int firmaId,
    List<Kalkulacija> lista,
    int zahtjev,
  ) async {
    // Uvijek osvježi — stavke izmijenjene kalkulacije su se mogle promijeniti.
    await Future.wait(
      lista.where((k) => k.stavke.isEmpty).map((k) async {
        try {
          final detalj = await _service.fetchCalculation(firmaId, k.id);
          if (!mounted || zahtjev != _zahtjev) return;
          setState(() {
            _artikli[k.id] = detalj.stavke.map((s) => s.naziv).toList();
          });
        } on ApiException {
          // Kolona ostaje prazna za kalkulaciju koja se ne može učitati.
        }
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Sitni elementi
  // ---------------------------------------------------------------------------

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

  Widget _statusOznaka(Kalkulacija k) {
    final proknjizena = k.jeProknjizena;
    final boja = proknjizena ? MagacinBoje.zelena : _nacrt;
    // Fiksna širina: oznaka je u svakom redu iste veličine i na istom mjestu.
    return Container(
      width: _sirinaStatusa,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: proknjizena ? MagacinBoje.zelenaSvijetlo : _nacrtSvijetlo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            proknjizena ? Icons.check_circle_rounded : Icons.edit_note_rounded,
            size: 12,
            color: boja,
          ),
          const SizedBox(width: 4),
          Text(
            proknjizena ? 'Proknjižena' : 'Nacrt',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: boja,
            ),
          ),
        ],
      ),
    );
  }

  // Broj prijemnice (glavna oznaka) i broj fakture (RC.BR) ispod.
  Widget _dokument(Kalkulacija k, {bool velik = false}) {
    final glavni = k.brojPrijemnice.isNotEmpty
        ? k.brojPrijemnice
        : (k.brojFakture.isNotEmpty ? k.brojFakture : '—');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          glavni,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: velik ? 15 : 13.5,
            fontWeight: FontWeight.w800,
            color: MagacinBoje.naslov,
            fontFamily: 'monospace',
          ),
        ),
        if (k.brojFakture.isNotEmpty && k.brojPrijemnice.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            'RC.BR ${k.brojFakture}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: MagacinBoje.priguseno,
            ),
          ),
        ],
      ],
    );
  }

  Widget _artikliTekst(Kalkulacija k, {int maxLines = 2}) {
    final nazivi = _artikli[k.id];
    if (nazivi == null) return _skeleton(110);
    if (nazivi.isEmpty) {
      return const Text('—', style: TextStyle(color: MagacinBoje.svijetlo));
    }
    return Tooltip(
      message: nazivi.join('\n'),
      child: Text(
        nazivi.join(', '),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.35,
          color: MagacinBoje.tekst,
        ),
      ),
    );
  }

  Widget _tekst(String? tekst, {bool jaci = false}) {
    final prazno = tekst == null || tekst.trim().isEmpty;
    return Text(
      prazno ? '—' : tekst,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        height: 1.3,
        fontWeight: jaci ? FontWeight.w600 : FontWeight.w500,
        color: prazno
            ? MagacinBoje.svijetlo
            : jaci
            ? MagacinBoje.naslov
            : MagacinBoje.tekst,
      ),
    );
  }

  Widget _akcije(Kalkulacija k) {
    // Kalkulacija iz zaključene poslovne godine se može samo pregledati.
    final zakljucena = PoslovneGodineController.zakljucenDatum(k.datum);
    final samoPregled = k.jeProknjizena || zakljucena;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (zakljucena && !k.jeProknjizena) ...[
          Tooltip(
            message: 'Poslovna godina ${k.datum!.year} je zaključena.',
            child: const Icon(
              Icons.lock_outline_rounded,
              size: 16,
              color: MagacinBoje.svijetlo,
            ),
          ),
          const SizedBox(width: 8),
        ],
        IkonaAkcija(
          ikona: samoPregled ? Icons.visibility_outlined : Icons.edit_rounded,
          poruka: samoPregled ? 'Pregled' : 'Izmijeni',
          boja: _akcent,
          onTap: () => _otvori(k),
        ),
        if (!samoPregled) ...[
          const SizedBox(width: 6),
          IkonaAkcija(
            ikona: Icons.inventory_2_outlined,
            poruka: 'Proknjiži',
            boja: MagacinBoje.zelena,
            onTap: () => _proknjizi(k),
          ),
          const SizedBox(width: 6),
          IkonaAkcija(
            ikona: Icons.delete_outline_rounded,
            poruka: 'Obriši',
            boja: MagacinBoje.crvena,
            onTap: () => _obrisi(k),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Tabela (širok ekran)
  // ---------------------------------------------------------------------------

  Widget _celijaKolone(int i, Widget dijete) {
    final desno = i >= _kolone.length - 2;
    return Expanded(
      flex: _kolone[i].$2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: desno ? Alignment.centerRight : Alignment.centerLeft,
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
        border: Border(bottom: BorderSide(color: MagacinBoje.linija)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _kolone.length; i++)
            _celijaKolone(
              i,
              Text(
                _kolone[i].$1.toUpperCase(),
                maxLines: 2,
                textAlign: i >= _kolone.length - 2
                    ? TextAlign.right
                    : TextAlign.left,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.3,
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

  Widget _red(Kalkulacija k) {
    final r = k.rekapitulacija;
    return HoverRed(
      akcent: _akcent,
      visina: _visinaReda,
      onTap: () => _otvori(k),
      builder: (hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _celijaKolone(0, _dokument(k)),
            _celijaKolone(1, _statusOznaka(k)),
            _celijaKolone(
              2,
              Text(
                _formatDatum(k.datum),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: MagacinBoje.priguseno,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _celijaKolone(3, _tekst(k.dobavljac, jaci: true)),
            _celijaKolone(4, _artikliTekst(k)),
            _celijaKolone(5, _tekst(k.skladiste?.naziv)),
            _celijaKolone(
              6,
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _osoba(Icons.calculate_outlined, r.kalkulisao),
                  const SizedBox(height: 3),
                  _osoba(Icons.inventory_outlined, r.robuPrimio),
                ],
              ),
            ),
            _celijaKolone(
              7,
              Text(
                '${_format(r.nabavnaVrijednost)} €',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _celijaKolone(8, _akcije(k)),
          ],
        ),
      ),
    );
  }

  Widget _osoba(IconData ikona, String? ime) {
    final prazno = ime == null || ime.trim().isEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(ikona, size: 13, color: MagacinBoje.svijetlo),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            prazno ? '—' : ime,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: prazno ? MagacinBoje.svijetlo : MagacinBoje.tekst,
            ),
          ),
        ),
      ],
    );
  }

  Widget _skeletonRed(int r) {
    return Container(
      height: _visinaReda,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Row(
        children: [
          _celijaKolone(0, _skeleton(r.isEven ? 120 : 90, visina: 12)),
          for (int k = 1; k < _kolone.length - 1; k++)
            _celijaKolone(
              k,
              _skeleton(
                k == 1 ? _sirinaStatusa : (k == 4 ? 140 : 70),
                visina: k == 1 ? 22 : 10,
              ),
            ),
          _celijaKolone(_kolone.length - 1, _skeleton(80, visina: 30)),
        ],
      ),
    );
  }

  Widget _tabela(double sirina) {
    final sirinaTabele = sirina < _minSirinaTabele ? _minSirinaTabele : sirina;
    final prvo = _ucitavanje && kalkulacije.isEmpty;

    Widget sadrzaj = SizedBox(
      width: sirinaTabele,
      child: Column(
        children: [
          _zaglavljeTabele(),
          if (prvo)
            for (int i = 0; i < 6; i++) _skeletonRed(i)
          else if (kalkulacije.isEmpty)
            SizedBox(width: sirina, child: _praznoStanje())
          else
            AnimatedOpacity(
              duration: hoverTrajanje,
              opacity: _ucitavanje ? 0.55 : 1,
              child: Column(children: [for (final k in kalkulacije) _red(k)]),
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

  Widget _kartica(Kalkulacija k) {
    final r = k.rekapitulacija;

    Widget podatak(IconData ikona, String naziv, Widget vrijednost) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikona, size: 15, color: MagacinBoje.svijetlo),
            const SizedBox(width: 8),
            SizedBox(
              width: 82,
              child: Text(
                naziv,
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ),
            Expanded(child: vrijednost),
          ],
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _otvori(k),
        borderRadius: BorderRadius.circular(16),
        hoverColor: hoverNijansa(_akcent, 0.03),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MagacinBoje.linija),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _dokument(k, velik: true)),
                  const SizedBox(width: 8),
                  _statusOznaka(k),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDatum(k.datum),
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MagacinBoje.zaglavlje,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    podatak(
                      Icons.storefront_outlined,
                      'Dobavljač',
                      _tekst(k.dobavljac, jaci: true),
                    ),
                    podatak(
                      Icons.category_outlined,
                      'Artikli',
                      _artikliTekst(k, maxLines: 3),
                    ),
                    podatak(
                      Icons.warehouse_outlined,
                      'Objekat',
                      _tekst(k.skladiste?.naziv),
                    ),
                    podatak(
                      Icons.calculate_outlined,
                      'Kalkulisao',
                      _tekst(r.kalkulisao),
                    ),
                    podatak(
                      Icons.inventory_outlined,
                      'Robu primio',
                      _tekst(r.robuPrimio),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'NABAVNA VRIJEDNOST',
                          style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w800,
                            color: MagacinBoje.svijetlo,
                          ),
                        ),
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${_format(r.nabavnaVrijednost)} €',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: MagacinBoje.naslov,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _akcije(k),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kartice() {
    if (_ucitavanje && kalkulacije.isEmpty) {
      return Column(
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _skeleton(double.infinity, visina: 260),
            ),
        ],
      );
    }
    if (kalkulacije.isEmpty) {
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
          for (final k in kalkulacije)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _kartica(k),
            ),
        ],
      ),
    );
  }

  Widget _praznoStanje() {
    final greska = _greska != null;
    final filtrirano = _pretraga.isNotEmpty || _status != null;
    final bezFirme = !_imaFirmu;

    final (IconData ikona, String naslov, String opis) = bezFirme
        ? (
            Icons.business_rounded,
            'Nije izabrana firma',
            'Izaberite firmu u gornjem desnom uglu da vidite kalkulacije.',
          )
        : greska
        ? (
            Icons.error_outline_rounded,
            'Kalkulacije se ne mogu učitati',
            _greska!,
          )
        : filtrirano
        ? (
            Icons.search_off_rounded,
            'Nema rezultata',
            'Nijedna kalkulacija ne odgovara izabranom filteru.',
          )
        : (
            Icons.receipt_long_rounded,
            'Još nema kalkulacija',
            'Dodajte prvu kalkulaciju nabavnih cijena za prijem robe.',
          );

    final boja = greska ? MagacinBoje.crvena : _akcent;
    final pozadina = greska ? MagacinBoje.crvenaSvijetlo : _akcentSvijetlo;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZecStanja(
            // Prazna lista: zec pruža kalkulator; pretraga ili bez firme:
            // zec traži; greška: zec leži.
            poza: greska
                ? PozaZeca.lezi
                : filtrirano || bezFirme
                ? PozaZeca.stoji
                : PozaZeca.klik,
            ikona: ikona,
            boja: boja,
            pozadina: pozadina,
            visina: greska ? 60 : 128,
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
            else if (filtrirano)
              GlatkoDugme(
                tekst: 'Poništi filtere',
                ikona: Icons.close_rounded,
                vrsta: VrstaDugmeta.sekundarno,
                onTap: () {
                  _status = null;
                  searchController.clear();
                  _pretraga = '';
                  _ucitaj();
                },
              )
            else
              GlatkoDugme(
                tekst: 'Nova kalkulacija',
                ikona: Icons.add_rounded,
                onTap: () => _otvori(),
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
      prazno: 'Nema kalkulacija',
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
  // Zaglavlje: naslov, nova kalkulacija, kartice statusa i pretraga
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
        hint: 'Dobavljač, faktura ili prijemnica…',
        ikona: Icons.search_rounded,
        suffix: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Obriši pretragu',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: MagacinBoje.priguseno,
                onPressed: searchController.clear,
              ),
      ),
    );
  }

  // Sve kalkulacije uz trenutni filter i pretragu (sve stranice), zajedno sa
  // stavkama (include=items): list "Kalkulacije" i list "Stavke".
  Future<List<ListExcel>> _pripremiExcel() async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) throw ApiException('Nije izabrana firma.');

    final sve = <Kalkulacija>[];
    var stranica = 1;
    var zadnja = 1;
    do {
      final r = await _service.fetchCalculations(
        firma.id,
        page: stranica,
        search: _pretraga,
        status: _status,
        perPage: 100,
        saStavkama: true,
      );
      sve.addAll(r.kalkulacije);
      zadnja = r.zadnjaStranica;
      stranica++;
    } while (stranica <= zadnja);

    final nazivStatusa =
        _statusi.where((s) => s.$2 == _status).firstOrNull?.$1 ?? 'Sve';
    double suma(double Function(RekapitulacijaKalkulacije) f) =>
        sve.fold(0, (s, k) => s + f(k.rekapitulacija));

    return [
      ListExcel(
        naziv: 'Kalkulacije',
        naslov: 'Kalkulacije nabavnih cijena',
        podnaslovi: [
          firma.name,
          [
            'Status: $nazivStatusa',
            if (_pretraga.isNotEmpty) 'Pretraga: $_pretraga',
            'Izvezeno ${_formatDatum(DateTime.now())}',
          ].join(' · '),
        ],
        kolone: const [
          KolonaExcel('Datum', vrsta: VrstaKolone.datum, sirina: 12),
          KolonaExcel('Prijemnica', sirina: 14),
          KolonaExcel('Faktura', sirina: 14),
          KolonaExcel('Dobavljač', sirina: 28),
          KolonaExcel('Skladište', sirina: 22),
          KolonaExcel('Status', sirina: 12),
          KolonaExcel('Stavki', vrsta: VrstaKolone.broj, sirina: 8),
          KolonaExcel('Fakt. vrijednost', vrsta: VrstaKolone.iznos, sirina: 16),
          KolonaExcel('Prevoz', vrsta: VrstaKolone.iznos, sirina: 11),
          KolonaExcel('Špedicija', vrsta: VrstaKolone.iznos, sirina: 11),
          KolonaExcel('Carina', vrsta: VrstaKolone.iznos, sirina: 11),
          KolonaExcel('Zavisni troškovi', vrsta: VrstaKolone.iznos, sirina: 16),
          KolonaExcel('Nab. vrijednost', vrsta: VrstaKolone.iznos, sirina: 16),
        ],
        redovi: [
          for (final k in sve)
            [
              k.datum,
              k.brojPrijemnice,
              k.brojFakture,
              k.dobavljac,
              k.skladiste?.naziv,
              k.jeProknjizena ? 'Proknjižena' : 'Nacrt',
              k.brojStavki,
              k.rekapitulacija.fakturnaVrijednost,
              k.rekapitulacija.prevoz,
              k.rekapitulacija.spedicija,
              k.rekapitulacija.carina,
              k.rekapitulacija.zavisniTroskovi,
              k.rekapitulacija.nabavnaVrijednost,
            ],
        ],
        ukupno: [
          'Ukupno',
          null,
          null,
          '${sve.length} kalkulacija',
          null,
          null,
          null,
          suma((r) => r.fakturnaVrijednost),
          suma((r) => r.prevoz),
          suma((r) => r.spedicija),
          suma((r) => r.carina),
          suma((r) => r.zavisniTroskovi),
          suma((r) => r.nabavnaVrijednost),
        ],
      ),
      ListExcel(
        naziv: 'Stavke',
        naslov: 'Stavke kalkulacija nabavnih cijena',
        podnaslovi: [firma.name, 'Status: $nazivStatusa'],
        kolone: const [
          KolonaExcel('Datum', vrsta: VrstaKolone.datum, sirina: 12),
          KolonaExcel('Prijemnica', sirina: 14),
          KolonaExcel('Faktura', sirina: 14),
          KolonaExcel('Dobavljač', sirina: 26),
          KolonaExcel('Status', sirina: 12),
          KolonaExcel('Šifra', sirina: 10),
          KolonaExcel('Artikal', sirina: 30),
          KolonaExcel('JM', sirina: 7),
          KolonaExcel('Količina', vrsta: VrstaKolone.broj, sirina: 11),
          KolonaExcel('Fakt. cijena', vrsta: VrstaKolone.broj, sirina: 13),
          KolonaExcel('Fakt. vrijednost', vrsta: VrstaKolone.iznos, sirina: 16),
          KolonaExcel('Zavisni trošak', vrsta: VrstaKolone.iznos, sirina: 15),
          KolonaExcel('Nab. cijena', vrsta: VrstaKolone.broj, sirina: 13),
          KolonaExcel('Nab. vrijednost', vrsta: VrstaKolone.iznos, sirina: 16),
        ],
        redovi: [
          for (final k in sve)
            for (final st in k.stavke)
              [
                k.datum,
                k.brojPrijemnice,
                k.brojFakture,
                k.dobavljac,
                k.jeProknjizena ? 'Proknjižena' : 'Nacrt',
                st.sifra,
                st.naziv,
                st.jm,
                st.kolicina,
                st.fakturnaCijena,
                st.fakturnaVrijednost,
                st.zavisniTrosak,
                st.nabavnaCijena,
                st.nabavnaVrijednost,
              ],
        ],
        ukupno: [
          'Ukupno',
          null,
          null,
          null,
          null,
          null,
          '${sve.fold<int>(0, (s, k) => s + k.stavke.length)} stavki',
          null,
          null,
          null,
          sve.fold<double>(
            0,
            (s, k) => k.stavke.fold(s, (z, st) => z + st.fakturnaVrijednost),
          ),
          sve.fold<double>(
            0,
            (s, k) => k.stavke.fold(s, (z, st) => z + st.zavisniTrosak),
          ),
          null,
          sve.fold<double>(
            0,
            (s, k) => k.stavke.fold(s, (z, st) => z + st.nabavnaVrijednost),
          ),
        ],
      ),
    ];
  }

  Widget _zaglavlje() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final malo = w < 600;

        final naslov = Row(
          children: [
            ZnakDokumenta(ikona: Icons.receipt_long_rounded, malo: malo),
            SizedBox(width: malo ? 14 : 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DOKUMENTA',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                      color: _akcent.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kalkulacije nabavnih cijena',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: malo ? 22 : 28,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final nova = GlatkoDugme(
          tekst: 'Nova kalkulacija',
          ikona: Icons.add_rounded,
          visina: 48,
          onTap: _imaFirmu ? () => _otvori() : null,
        );

        final kartice = KarticeFiltera(
          opcije: _statusi,
          izabrano: _status,
          onIzaberi: _imaFirmu ? _promjenaStatusa : null,
        );

        final excel = DugmeIzvoza(
          visina: 48,
          nazivFajla: () =>
              'Kalkulacije nabavnih cijena ${_formatDatum(DateTime.now())}'
                  .replaceAll('.', '-'),
          pripremi: _pripremiExcel,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (w >= 640)
              Row(
                children: [
                  Expanded(child: naslov),
                  const SizedBox(width: 20),
                  if (_imaFirmu) ...[excel, const SizedBox(width: 10)],
                  nova,
                ],
              )
            else ...[
              naslov,
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_imaFirmu) ...[excel, const SizedBox(width: 10)],
                  Expanded(child: nova),
                ],
              ),
            ],
            SizedBox(height: malo ? 18 : 24),
            // Kartice statusa lijevo, pretraga desno; ispod linija.
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: MagacinBoje.linija)),
              ),
              child: w >= 860
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        kartice,
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: SizedBox(width: 340, child: _pretrazivac()),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _pretrazivac(),
                        const SizedBox(height: 8),
                        kartice,
                      ],
                    ),
            ),
          ],
        );
      },
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
              // Prati izabranu firmu (dugmad i prazno stanje).
              _firmaController.izabranaFirma.value;
              // Prati zaključene godine (zaključani dokumenti).
              PoslovneGodineController.instanca?.godine.length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _zaglavlje(),
                  const SizedBox(height: 20),
                  if (_greska != null && kalkulacije.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                      decoration: BoxDecoration(
                        color: MagacinBoje.crvenaSvijetlo,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: hoverNijansa(MagacinBoje.crvena, 0.3),
                        ),
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
                            onPressed: _ucitavanje
                                ? null
                                : () => _ucitaj(_stranica),
                            style: TextButton.styleFrom(
                              foregroundColor: MagacinBoje.crvena,
                            ),
                            child: const Text('Pokušaj ponovo'),
                          ),
                        ],
                      ),
                    ),
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
                          SizedBox(
                            height: 3,
                            child: _ucitavanje
                                ? const LinearProgressIndicator(
                                    color: _akcent,
                                    backgroundColor: _akcentSvijetlo,
                                  )
                                : null,
                          ),
                          LayoutBuilder(
                            builder: (context, c) => _tabela(c.maxWidth),
                          ),
                          if (_imaFirmu)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: const BoxDecoration(
                                color: MagacinBoje.zaglavlje,
                                border: Border(
                                  top: BorderSide(color: MagacinBoje.linija),
                                ),
                              ),
                              child: _paginacija(),
                            ),
                        ],
                      ),
                    )
                  else ...[
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

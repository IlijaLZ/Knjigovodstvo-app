import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/controllers/poslovne_godine_controller.dart';
import 'package:knjigovodstvo_app/izvoz/dugme_izvoza.dart';
import 'package:knjigovodstvo_app/izvoz/excel_izvoz.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/routes/app_routes.dart';
import 'package:knjigovodstvo_app/services/work_orders_service.dart';
import 'package:knjigovodstvo_app/widgets/logo.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';
import 'package:knjigovodstvo_app/widgets/paginacija_widget.dart';

String _formatDatum(DateTime? datum) {
  if (datum == null) return '';
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}';
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
const Color _izdat = Color(0xFF0369A1);
const Color _izdatSvijetlo = Color(0xFFE0F2FE);

// Filter po statusu: (oznaka, status za API; null = sve).
const List<(String, String?)> _statusi = [
  ('Sve', null),
  ('Nacrti', statusNacrt),
  ('Izdati', statusIzdat),
];

// Ispod ove širine nalozi se prikazuju kao kartice umjesto tabele.
const double _sirinaTabele = 860;
const double _minSirinaTabele = 980;
const double _visinaReda = 66;
const double _sirinaStatusa = 92;

// Kolone tabele: (naziv, flex).
const List<(String, int)> _kolone = [
  ('Broj naloga', 16),
  ('Status', 14),
  ('Datum', 11),
  ('Kupac', 20),
  ('Izdao / potpisao', 17),
  ('Proizvoda', 10),
  ('', 16),
];

// Lista radnih naloga izabrane firme: GET /companies/{company}/work-orders
class RadniNalogScreen extends StatefulWidget {
  const RadniNalogScreen({super.key});

  @override
  State<RadniNalogScreen> createState() => _RadniNalogScreenState();
}

class _RadniNalogScreenState extends State<RadniNalogScreen> {
  final searchController = TextEditingController();
  final ScrollController _horizontalni = ScrollController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final WorkOrdersService _service = WorkOrdersService();
  late final Worker _firmaWorker;

  List<RadniNalog> nalozi = [];
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
        nalozi = [];
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
      final rezultat = await _service.fetchWorkOrders(
        firma.id,
        page: stranica,
        search: _pretraga,
        status: _status,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        nalozi = rezultat.nalozi;
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

  Future<void> _otvori([RadniNalog? nalog]) async {
    final sacuvano = await Get.toNamed(
      AppRoutes.dodajRadniNalog,
      arguments: nalog?.id,
    );
    if (sacuvano != true || !mounted) return;
    _ucitaj(nalog == null ? 1 : _stranica);
    _poruka(context, 'Radni nalog je sačuvan.');
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

  Future<void> _izdaj(RadniNalog nalog) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      naslov: 'Izdaj radni nalog?',
      tekst:
          'Izdavanjem naloga ${nalog.broj} materijal se skida sa skladišta '
          'sirovina i prenosi u proizvodnju. Nalog se poslije ne može '
          'mijenjati ni brisati.',
      dugme: 'Izdaj',
      ikona: Icons.outbox_rounded,
      opasno: false,
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.issueWorkOrder(firma.id, nalog.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _poruka(context, 'Radni nalog ${nalog.broj} je izdat.');
    _ucitaj(_stranica);
  }

  Future<void> _obrisi(RadniNalog nalog) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      naslov: 'Obriši radni nalog?',
      tekst:
          'Radni nalog ${nalog.broj} će biti obrisan. Brisanje možete '
          'poništiti odmah nakon toga.',
      dugme: 'Obriši',
      ikona: Icons.delete_outline_rounded,
      opasno: true,
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.deleteWorkOrder(firma.id, nalog.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    // Nakon brisanja zadnjeg reda na stranici vraća se na prethodnu.
    _ucitaj(nalozi.length == 1 && _stranica > 1 ? _stranica - 1 : _stranica);
    _poruka(
      context,
      'Radni nalog ${nalog.broj} je obrisan.',
      action: SnackBarAction(
        label: 'Poništi',
        textColor: const Color(0xFF7FE3C4),
        onPressed: () => _vrati(firma.id, nalog),
      ),
    );
  }

  Future<void> _vrati(int firmaId, RadniNalog nalog) async {
    try {
      await _service.restoreWorkOrder(firmaId, nalog.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _ucitaj(_stranica);
    _poruka(context, 'Radni nalog ${nalog.broj} je vraćen.');
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

  // Fiksna širina: oznaka je u svakom redu iste veličine i na istom mjestu.
  Widget _statusOznaka(RadniNalog n) {
    final izdat = n.jeIzdat;
    final boja = izdat ? _izdat : _nacrt;
    return Container(
      width: _sirinaStatusa,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: izdat ? _izdatSvijetlo : _nacrtSvijetlo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            izdat ? Icons.outbox_rounded : Icons.edit_note_rounded,
            size: 12,
            color: boja,
          ),
          const SizedBox(width: 4),
          Text(
            izdat ? 'Izdat' : 'Nacrt',
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

  Widget _broj(RadniNalog n, {bool velik = false}) {
    return Text(
      n.broj.isEmpty ? '—' : n.broj,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: velik ? 15 : 13.5,
        fontWeight: FontWeight.w800,
        color: MagacinBoje.naslov,
        fontFamily: 'monospace',
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

  Widget _brojProizvoda(RadniNalog n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: MagacinBoje.zaglavlje,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MagacinBoje.linija),
      ),
      child: Text(
        '${n.brojStavki}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: MagacinBoje.tekst,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  Widget _akcije(RadniNalog n) {
    // Nalog iz zaključene poslovne godine se može samo pregledati.
    final zakljucen = PoslovneGodineController.zakljucenDatum(n.datum);
    final samoPregled = n.jeIzdat || zakljucen;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (zakljucen && !n.jeIzdat) ...[
          Tooltip(
            message: 'Poslovna godina ${n.datum!.year} je zaključena.',
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
          onTap: () => _otvori(n),
        ),
        if (!samoPregled) ...[
          const SizedBox(width: 6),
          IkonaAkcija(
            ikona: Icons.outbox_rounded,
            poruka: 'Izdaj nalog',
            boja: _izdat,
            onTap: () => _izdaj(n),
          ),
          const SizedBox(width: 6),
          IkonaAkcija(
            ikona: Icons.delete_outline_rounded,
            poruka: 'Obriši',
            boja: MagacinBoje.crvena,
            onTap: () => _obrisi(n),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

  Widget _red(RadniNalog n) {
    return HoverRed(
      akcent: _akcent,
      visina: _visinaReda,
      onTap: () => _otvori(n),
      builder: (hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _celijaKolone(0, _broj(n)),
            _celijaKolone(1, _statusOznaka(n)),
            _celijaKolone(
              2,
              Text(
                _formatDatum(n.datum),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: MagacinBoje.priguseno,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            _celijaKolone(3, _tekst(n.kupac, jaci: true)),
            _celijaKolone(
              4,
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _osoba(Icons.edit_document, n.izdao),
                  const SizedBox(height: 3),
                  _osoba(Icons.draw_outlined, n.potpisao),
                ],
              ),
            ),
            _celijaKolone(5, _brojProizvoda(n)),
            _celijaKolone(6, _akcije(n)),
          ],
        ),
      ),
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
          _celijaKolone(0, _skeleton(r.isEven ? 100 : 76, visina: 12)),
          _celijaKolone(1, _skeleton(_sirinaStatusa, visina: 22)),
          for (int k = 2; k < _kolone.length - 1; k++)
            _celijaKolone(k, _skeleton(k == 3 ? 140 : 60)),
          _celijaKolone(_kolone.length - 1, _skeleton(80, visina: 30)),
        ],
      ),
    );
  }

  Widget _tabela(double sirina) {
    final sirinaTabele = sirina < _minSirinaTabele ? _minSirinaTabele : sirina;
    final prvo = _ucitavanje && nalozi.isEmpty;

    Widget sadrzaj = SizedBox(
      width: sirinaTabele,
      child: Column(
        children: [
          _zaglavljeTabele(),
          if (prvo)
            for (int i = 0; i < 6; i++) _skeletonRed(i)
          else if (nalozi.isEmpty)
            SizedBox(width: sirina, child: _praznoStanje())
          else
            AnimatedOpacity(
              duration: hoverTrajanje,
              opacity: _ucitavanje ? 0.55 : 1,
              child: Column(children: [for (final n in nalozi) _red(n)]),
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

  Widget _kartica(RadniNalog n) {
    Widget podatak(IconData ikona, String naziv, Widget vrijednost) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(ikona, size: 15, color: MagacinBoje.svijetlo),
            const SizedBox(width: 8),
            SizedBox(
              width: 76,
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
        onTap: () => _otvori(n),
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
                children: [
                  Expanded(child: _broj(n, velik: true)),
                  const SizedBox(width: 8),
                  _statusOznaka(n),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDatum(n.datum),
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
                      Icons.person_outline_rounded,
                      'Kupac',
                      _tekst(n.kupac, jaci: true),
                    ),
                    podatak(Icons.edit_document, 'Izdao', _tekst(n.izdao)),
                    podatak(
                      Icons.draw_outlined,
                      'Potpisao',
                      _tekst(n.potpisao),
                    ),
                    podatak(
                      Icons.inventory_2_outlined,
                      'Proizvoda',
                      _tekst('${n.brojStavki}', jaci: true),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerRight, child: _akcije(n)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kartice() {
    if (_ucitavanje && nalozi.isEmpty) {
      return Column(
        children: [
          for (int i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _skeleton(double.infinity, visina: 230),
            ),
        ],
      );
    }
    if (nalozi.isEmpty) {
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
          for (final n in nalozi)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _kartica(n),
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
            'Izaberite firmu u gornjem desnom uglu da vidite radne naloge.',
          )
        : greska
        ? (
            Icons.error_outline_rounded,
            'Radni nalozi se ne mogu učitati',
            _greska!,
          )
        : filtrirano
        ? (
            Icons.search_off_rounded,
            'Nema rezultata',
            'Nijedan radni nalog ne odgovara izabranom filteru.',
          )
        : (
            Icons.assignment_rounded,
            'Još nema radnih naloga',
            'Dodajte prvi radni nalog za proizvodnju.',
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
                tekst: 'Novi radni nalog',
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
      prazno: 'Nema radnih naloga',
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
  // Zaglavlje: naslov, novi nalog, kartice statusa i pretraga
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
        hint: 'Kupac ili broj naloga…',
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

  // Svi nalozi uz trenutni filter i pretragu (sve stranice). Materijali se
  // izvoze sa ekrana Trebovanje.
  Future<List<ListExcel>> _pripremiExcel() async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) throw ApiException('Nije izabrana firma.');

    final svi = <RadniNalog>[];
    var stranica = 1;
    var zadnja = 1;
    do {
      final r = await _service.fetchWorkOrders(
        firma.id,
        page: stranica,
        search: _pretraga,
        status: _status,
        perPage: 100,
      );
      svi.addAll(r.nalozi);
      zadnja = r.zadnjaStranica;
      stranica++;
    } while (stranica <= zadnja);

    final nazivStatusa =
        _statusi.where((s) => s.$2 == _status).firstOrNull?.$1 ?? 'Sve';

    return [
      ListExcel(
        naziv: 'Radni nalozi',
        naslov: 'Radni nalozi',
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
          KolonaExcel('Broj naloga', sirina: 16),
          KolonaExcel('Kupac', sirina: 28),
          KolonaExcel('Status', sirina: 11),
          KolonaExcel('Proizvoda', vrsta: VrstaKolone.broj, sirina: 11),
          KolonaExcel('Izdat', vrsta: VrstaKolone.datum, sirina: 12),
          KolonaExcel('Izdao', sirina: 20),
          KolonaExcel('Potpisao', sirina: 20),
        ],
        redovi: [
          for (final n in svi)
            [
              n.datum,
              n.broj,
              n.kupac,
              n.jeIzdat ? 'Izdat' : 'Nacrt',
              n.brojStavki,
              n.izdatU,
              n.izdao,
              n.potpisao,
            ],
        ],
        ukupno: ['Ukupno', '${svi.length} naloga'],
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
            ZnakDokumenta(ikona: Icons.assignment_rounded, malo: malo),
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
                    'Radni nalozi',
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

        final novi = GlatkoDugme(
          tekst: 'Novi radni nalog',
          ikona: Icons.add_rounded,
          visina: 48,
          onTap: _imaFirmu ? () => _otvori() : null,
        );

        final excel = DugmeIzvoza(
          visina: 48,
          nazivFajla: () => 'Radni nalozi ${_formatDatum(DateTime.now())}'
              .replaceAll('.', '-'),
          pripremi: _pripremiExcel,
        );

        final kartice = KarticeFiltera(
          opcije: _statusi,
          izabrano: _status,
          onIzaberi: _imaFirmu ? _promjenaStatusa : null,
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
                  novi,
                ],
              )
            else ...[
              naslov,
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_imaFirmu) ...[excel, const SizedBox(width: 10)],
                  Expanded(child: novi),
                ],
              ),
            ],
            SizedBox(height: malo ? 18 : 24),
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
                  if (_greska != null && nalozi.isNotEmpty)
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

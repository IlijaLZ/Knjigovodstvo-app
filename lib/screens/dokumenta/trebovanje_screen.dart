import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/models/article.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/services/work_orders_service.dart';
import 'package:knjigovodstvo_app/stampa/pregled_stampe.dart';
import 'package:knjigovodstvo_app/stampa/trebovanje_pdf.dart';
import 'package:knjigovodstvo_app/widgets/logo.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';
import 'package:knjigovodstvo_app/widgets/paginacija_widget.dart';

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

// Količine normativa znaju biti male (0,007 kg) pa prikazujemo do 4 decimale.
String _formatKolicina(double value) {
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

String _formatDatum(DateTime? datum) {
  if (datum == null) return '';
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}';
}

const Color _akcent = akcentAplikacije;
const Color _akcentSvijetlo = Color(0xFFE6F4F3);
const Color _akcentTamni = Color(0xFF0B434B);
const Color _priprema = Color(0xFFB45309);
const Color _pripremaSvijetlo = Color(0xFFFEF3C7);
const Color _izdato = Color(0xFF0369A1);
const Color _izdatoSvijetlo = Color(0xFFE0F2FE);

// Filter po statusu naloga: (oznaka, status za API; null = sve).
const List<(String, String?)> _statusi = [
  ('Sve', null),
  ('U pripremi', statusNacrt),
  ('Izdata', statusIzdat),
];

// Ispod ove širine trebovanja se prikazuju kao kartice umjesto tabele.
const double _sirinaTabele = 860;
const double _minSirinaTabele = 1000;
const double _visinaReda = 66;
const double _sirinaStatusa = 104;

// Kolone tabele: (naziv, flex).
const List<(String, int)> _kolone = [
  ('Radni nalog', 15),
  ('Status', 15),
  ('Datum', 11),
  ('Kupac', 20),
  ('Tok materijala', 22),
  ('Proizvoda', 10),
  ('', 8),
];

// Oznaka statusa trebovanja (prema statusu naloga), fiksne širine.
Widget _statusOznaka(bool izdat) {
  final boja = izdat ? _izdato : _priprema;
  return Container(
    width: _sirinaStatusa,
    padding: const EdgeInsets.symmetric(vertical: 4),
    decoration: BoxDecoration(
      color: izdat ? _izdatoSvijetlo : _pripremaSvijetlo,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          izdat ? Icons.outbox_rounded : Icons.hourglass_top_rounded,
          size: 12,
          color: boja,
        ),
        const SizedBox(width: 4),
        Text(
          izdat ? 'Izdato' : 'U pripremi',
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

// Mala ikona skladišta u boji tog magacina.
Widget _znakSkladista(Skladiste? s, {double v = 22}) {
  final tema = TemaSkladista.za(s?.tip ?? '');
  return Container(
    width: v,
    height: v,
    decoration: BoxDecoration(
      color: tema.svijetla,
      borderRadius: BorderRadius.circular(v * 0.3),
    ),
    child: Icon(tema.ikona, size: v * 0.58, color: tema.boja),
  );
}

// Svaki radni nalog ima tačno jedno trebovanje (pravi se pri snimanju
// naloga), pa se lista trebovanja čita iz liste naloga, a sadržaj sa
// GET /companies/{company}/work-orders/{workOrder}/requisition.
class TrebovanjeScreen extends StatefulWidget {
  const TrebovanjeScreen({super.key});

  @override
  State<TrebovanjeScreen> createState() => _TrebovanjeScreenState();
}

class _TrebovanjeScreenState extends State<TrebovanjeScreen> {
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

  // Filter po statusu naloga (null = sve).
  String? _status;

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

  void _prikaziTrebovanje(RadniNalog nalog) {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    showDialog(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _TrebovanjeDialog(firmaId: firma.id, nalog: nalog),
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

  // Izdaje → Prima, sa ikonama magacina.
  Widget _tok(RadniNalog n) {
    Widget mjesto(Skladiste? s) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _znakSkladista(s, v: 20),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            s?.naziv ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: MagacinBoje.tekst),
          ),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mjesto(n.izvor),
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Icon(
            Icons.arrow_downward_rounded,
            size: 12,
            color: MagacinBoje.svijetlo,
          ),
        ),
        mjesto(n.odrediste),
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
      onTap: () => _prikaziTrebovanje(n),
      builder: (hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _celijaKolone(0, _broj(n)),
            _celijaKolone(1, _statusOznaka(n.jeIzdat)),
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
            _celijaKolone(4, _tok(n)),
            _celijaKolone(5, _brojProizvoda(n)),
            _celijaKolone(
              6,
              IkonaAkcija(
                ikona: Icons.visibility_outlined,
                poruka: 'Pregled',
                boja: _akcent,
                onTap: () => _prikaziTrebovanje(n),
              ),
            ),
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
            _celijaKolone(k, _skeleton(k == 4 ? 140 : 60)),
          _celijaKolone(_kolone.length - 1, _skeleton(34, visina: 34)),
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
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _prikaziTrebovanje(n),
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
                  _statusOznaka(n.jeIzdat),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  _formatDatum(n.datum),
                  if ((n.kupac ?? '').isNotEmpty) n.kupac!,
                ].join('  ·  '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MagacinBoje.zaglavlje,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(child: _tok(n)),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'PROIZVODA',
                          style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 0.7,
                            fontWeight: FontWeight.w800,
                            color: MagacinBoje.svijetlo,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _brojProizvoda(n),
                      ],
                    ),
                  ],
                ),
              ),
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
              child: _skeleton(double.infinity, visina: 170),
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
            'Izaberite firmu u gornjem desnom uglu da vidite trebovanja.',
          )
        : greska
        ? (
            Icons.error_outline_rounded,
            'Trebovanja se ne mogu učitati',
            _greska!,
          )
        : filtrirano
        ? (
            Icons.search_off_rounded,
            'Nema rezultata',
            'Nijedno trebovanje ne odgovara izabranom filteru.',
          )
        : (
            Icons.move_down_rounded,
            'Još nema trebovanja',
            'Trebovanje nastaje automatski kad sačuvate radni nalog.',
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
          if (!bezFirme && (greska || filtrirano)) ...[
            const SizedBox(height: 18),
            if (greska)
              GlatkoDugme(
                tekst: 'Pokušaj ponovo',
                ikona: Icons.refresh_rounded,
                vrsta: VrstaDugmeta.sekundarno,
                onTap: _ucitavanje ? null : () => _ucitaj(_stranica),
              )
            else
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
      prazno: 'Nema trebovanja',
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

  Widget _zaglavlje() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final malo = w < 600;

        final naslov = Row(
          children: [
            ZnakDokumenta(ikona: Icons.move_down_rounded, malo: malo),
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
                    'Trebovanja',
                    style: TextStyle(
                      fontSize: malo ? 22 : 28,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Materijal koji radni nalozi traže iz magacina '
                    'repromaterijala.',
                    style: TextStyle(
                      fontSize: 13,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final kartice = KarticeFiltera(
          opcije: _statusi,
          izabrano: _status,
          onIzaberi: _imaFirmu ? _promjenaStatusa : null,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            naslov,
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
              // Prati izabranu firmu (filteri i prazno stanje).
              _firmaController.izabranaFirma.value;
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

// ======================================================================
// PREGLED TREBOVANJA JEDNOG NALOGA: podaci, tok, proizvodi i materijali
// ======================================================================
class _TrebovanjeDialog extends StatefulWidget {
  final int firmaId;
  final RadniNalog nalog;

  const _TrebovanjeDialog({required this.firmaId, required this.nalog});

  @override
  State<_TrebovanjeDialog> createState() => _TrebovanjeDialogState();
}

class _TrebovanjeDialogState extends State<_TrebovanjeDialog> {
  final WorkOrdersService _service = WorkOrdersService();

  Trebovanje? _trebovanje;
  String? _greska;

  static const _brojStil = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: MagacinBoje.tekst,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  void initState() {
    super.initState();
    _ucitaj();
  }

  void _stampaj() {
    final t = _trebovanje;
    if (t == null) return;

    final n = widget.nalog;
    final firma = Get.find<FirmaController>().izabranaFirma.value;
    final broj = (t.brojNaloga ?? n.broj).trim();

    prikaziPregledStampe(
      context,
      naslov: 'Trebovanje · Radni nalog $broj',
      nazivFajla: 'trebovanje_${broj.isEmpty ? n.id : broj}.pdf'.replaceAll(
        RegExp(r'[^\w.\-]'),
        '_',
      ),
      napravi: (format) => napraviTrebovanjePdf(
        trebovanje: t,
        nalog: n,
        firma: firma,
        format: format,
      ),
    );
  }

  Future<void> _ucitaj() async {
    setState(() {
      _greska = null;
      _trebovanje = null;
    });

    try {
      final trebovanje = await _service.fetchRequisition(
        widget.firmaId,
        widget.nalog.id,
      );
      if (mounted) setState(() => _trebovanje = trebovanje);
    } on ApiException catch (e) {
      if (mounted) setState(() => _greska = e.message);
    }
  }

  // ---- Dijelovi ------------------------------------------------------

  Widget _sekcija(String naslov, IconData ikona, {String? desno}) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Row(
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
          if (desno != null) ...[
            const SizedBox(width: 10),
            Text(
              desno,
              style: const TextStyle(
                fontSize: 12,
                color: MagacinBoje.priguseno,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _podatak(IconData ikona, String naziv, String vrijednost) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: MagacinBoje.zaglavlje,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: MagacinBoje.linijaSvijetla),
          ),
          child: Icon(ikona, size: 16, color: MagacinBoje.priguseno),
        ),
        const SizedBox(width: 10),
        Expanded(
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
                vrijednost.isEmpty ? '—' : vrijednost,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.naslov,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _podaci(Trebovanje t, double sirina) {
    final n = widget.nalog;
    final polja = [
      _podatak(Icons.event_outlined, 'Datum', _formatDatum(t.datum)),
      _podatak(Icons.tag_rounded, 'Radni nalog', t.brojNaloga ?? n.broj),
      _podatak(Icons.person_outline_rounded, 'Kupac', t.kupac ?? n.kupac ?? ''),
    ];
    final kolone = sirina >= 560 ? 3 : 1;
    const razmak = 14.0;
    final w = (sirina - (kolone - 1) * razmak) / kolone;
    return Wrap(
      spacing: razmak,
      runSpacing: 14,
      children: [for (final p in polja) SizedBox(width: w, child: p)],
    );
  }

  Widget _tok(double sirina) {
    final n = widget.nalog;
    Widget mjesto(String oznaka, Skladiste? s) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MagacinBoje.zaglavlje,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MagacinBoje.linijaSvijetla),
        ),
        child: Row(
          children: [
            _znakSkladista(s, v: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    oznaka.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.svijetlo,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s?.naziv ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final strelica = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Icon(
        sirina >= 460
            ? Icons.arrow_forward_rounded
            : Icons.arrow_downward_rounded,
        color: MagacinBoje.svijetlo,
        size: 20,
      ),
    );

    if (sirina >= 460) {
      return Row(
        children: [
          mjesto('Izdaje', n.izvor),
          strelica,
          mjesto('Prima', n.odrediste),
        ],
      );
    }
    return Column(
      children: [
        Row(children: [mjesto('Izdaje', n.izvor)]),
        strelica,
        Row(children: [mjesto('Prima', n.odrediste)]),
      ],
    );
  }

  Widget _proizvodi(Trebovanje t) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MagacinBoje.linija),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (int i = 0; i < t.stavke.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(
                        top: BorderSide(color: MagacinBoje.linijaSvijetla),
                      ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _akcentSvijetlo,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _akcentTamni,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.stavke[i].naziv,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: MagacinBoje.naslov,
                          ),
                        ),
                        Text(
                          idArtikla(t.stavke[i].articleId),
                          style: const TextStyle(
                            fontSize: 11,
                            color: MagacinBoje.priguseno,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: _formatKolicina(t.stavke[i].kolicina),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: MagacinBoje.naslov,
                          ),
                        ),
                        TextSpan(
                          text: ' ${t.stavke[i].jm}',
                          style: const TextStyle(color: MagacinBoje.priguseno),
                        ),
                      ],
                    ),
                    style: _brojStil.copyWith(fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- Materijali: tabela (široko) ili kartice (usko) ----------------

  static const List<(String, int)> _koloneMaterijala = [
    ('Materijal', 32),
    ('Norma', 13),
    ('Trebovano', 15),
    ('Izdato', 17),
    ('Vrijednost', 15),
  ];

  Widget _celija(int i, Widget dijete) {
    return Expanded(
      flex: _koloneMaterijala[i].$2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: i == 0 ? Alignment.centerLeft : Alignment.centerRight,
          child: dijete,
        ),
      ),
    );
  }

  // Izdato: kad se razlikuje od traženog, istaknuto sa razlikom.
  Widget _izdato(MaterijalTrebovanja m) {
    final izdato = m.izdato ?? m.trazeno;
    final razlika = izdato - m.trazeno;
    if (razlika.abs() < 0.00005) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '${_formatKolicina(izdato)} ${m.jm}',
          style: _brojStil.copyWith(fontWeight: FontWeight.w600),
        ),
      );
    }
    return Tooltip(
      message: 'Trebovano ${_formatKolicina(m.trazeno)} ${m.jm}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: hoverNijansa(_priprema, 0.4)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '${_formatKolicina(izdato)} ${m.jm}  '
            '(${razlika > 0 ? '+' : '−'}${_formatKolicina(razlika.abs())})',
            style: _brojStil.copyWith(
              fontWeight: FontWeight.w700,
              color: _priprema,
            ),
          ),
        ),
      ),
    );
  }

  String _vrijednost(MaterijalTrebovanja m) =>
      m.vrijednost == null ? '—' : '${_format(m.vrijednost!)} €';

  Widget _grupaProizvoda(StavkaTrebovanja s) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF4FAFA),
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.subdirectory_arrow_right_rounded,
            size: 15,
            color: _akcent,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${s.naziv}  ·  ${_formatKolicina(s.kolicina)} ${s.jm}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _akcentTamni,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ukupno(Trebovanje t) {
    final v = t.vrijednost;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: const BoxDecoration(
        color: _akcentSvijetlo,
        border: Border(top: BorderSide(color: MagacinBoje.linija)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ukupna vrijednost',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _akcentTamni,
              ),
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                v == null ? 'obračunava se pri izdavanju' : '${_format(v)} €',
                style: _brojStil.copyWith(
                  fontSize: v == null ? 12.5 : 15,
                  fontWeight: v == null ? FontWeight.w600 : FontWeight.w800,
                  color: _akcentTamni,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabelaMaterijala(Trebovanje t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          color: MagacinBoje.zaglavlje,
          child: Row(
            children: [
              for (int i = 0; i < _koloneMaterijala.length; i++)
                _celija(
                  i,
                  Text(
                    _koloneMaterijala[i].$1.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
                ),
            ],
          ),
        ),
        for (final s in t.stavke) ...[
          _grupaProizvoda(s),
          for (final m in s.materijali)
            HoverRed(
              akcent: _akcent,
              visina: 52,
              builder: (hover) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    _celija(
                      0,
                      Text(
                        m.naziv,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: MagacinBoje.naslov,
                        ),
                      ),
                    ),
                    _celija(
                      1,
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${_formatKolicina(m.norma)} ${m.jm}',
                          style: _brojStil.copyWith(
                            color: MagacinBoje.priguseno,
                          ),
                        ),
                      ),
                    ),
                    _celija(
                      2,
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '${_formatKolicina(m.trazeno)} ${m.jm}',
                          style: _brojStil,
                        ),
                      ),
                    ),
                    _celija(3, _izdato(m)),
                    _celija(
                      4,
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _vrijednost(m),
                          style: _brojStil.copyWith(
                            fontWeight: FontWeight.w800,
                            color: m.vrijednost == null
                                ? MagacinBoje.svijetlo
                                : MagacinBoje.naslov,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
        _ukupno(t),
      ],
    );
  }

  Widget _karticeMaterijala(Trebovanje t) {
    Widget metrika(String naziv, Widget vrijednost) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          naziv.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w800,
            color: MagacinBoje.svijetlo,
          ),
        ),
        const SizedBox(height: 3),
        Align(alignment: Alignment.centerLeft, child: vrijednost),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in t.stavke) ...[
          _grupaProizvoda(s),
          for (final m in s.materijali)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    m.naziv,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: metrika(
                          'Norma',
                          Text(
                            '${_formatKolicina(m.norma)} ${m.jm}',
                            style: _brojStil,
                          ),
                        ),
                      ),
                      Expanded(
                        child: metrika(
                          'Trebovano',
                          Text(
                            '${_formatKolicina(m.trazeno)} ${m.jm}',
                            style: _brojStil,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: metrika('Izdato', _izdato(m))),
                      Expanded(
                        child: metrika(
                          'Vrijednost',
                          Text(
                            _vrijednost(m),
                            style: _brojStil.copyWith(
                              fontWeight: FontWeight.w800,
                              color: MagacinBoje.naslov,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        _ukupno(t),
      ],
    );
  }

  Widget _sadrzaj(double sirina) {
    final t = _trebovanje;

    if (_greska != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          children: [
            const ZecStanja(
              poza: PozaZeca.lezi,
              ikona: Icons.error_outline_rounded,
              boja: MagacinBoje.crvena,
              pozadina: MagacinBoje.crvenaSvijetlo,
              visina: 60,
            ),
            const SizedBox(height: 12),
            Text(
              _greska!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: MagacinBoje.naslov,
              ),
            ),
            const SizedBox(height: 14),
            GlatkoDugme(
              tekst: 'Pokušaj ponovo',
              ikona: Icons.refresh_rounded,
              vrsta: VrstaDugmeta.sekundarno,
              onTap: _ucitaj,
            ),
          ],
        ),
      );
    }

    if (t == null) {
      return const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: ZecRacuna(tekst: 'Računam materijale…')),
      );
    }

    final brojMaterijala = t.materijali.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _podaci(t, sirina),
        _sekcija('Tok materijala', Icons.swap_horiz_rounded),
        _tok(sirina),
        _sekcija(
          'Proizvodi',
          Icons.inventory_2_outlined,
          desno: '${t.stavke.length}',
        ),
        _proizvodi(t),
        _sekcija(
          'Materijali',
          Icons.category_outlined,
          desno: '$brojMaterijala',
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MagacinBoje.linija),
          ),
          clipBehavior: Clip.antiAlias,
          child: sirina >= 620 ? _tabelaMaterijala(t) : _karticeMaterijala(t),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final usko = MediaQuery.sizeOf(context).width < 600;
    final n = widget.nalog;

    final naslov = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _akcentSvijetlo,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.move_down_rounded, color: _akcent, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TREBOVANJE',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w800,
                  color: _akcent,
                ),
              ),
              const SizedBox(height: 3),
              Wrap(
                spacing: 10,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Radni nalog ${n.broj}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                  _statusOznaka(n.jeIzdat),
                ],
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

    final zatvori = GlatkoDugme(
      tekst: 'Zatvori',
      vrsta: VrstaDugmeta.sekundarno,
      onTap: () => Navigator.of(context).pop(),
    );

    final stampaj = GlatkoDugme(
      tekst: 'Štampaj',
      ikona: Icons.print_outlined,
      onTap: _trebovanje == null ? null : _stampaj,
    );

    if (usko) {
      return Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
                child: naslov,
              ),
              const Divider(height: 1, color: MagacinBoje.linija),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                    child: _sadrzaj(c.maxWidth - 36),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: MagacinBoje.linija)),
                ),
                child: Row(
                  children: [
                    Expanded(child: zatvori),
                    const SizedBox(width: 10),
                    Expanded(child: stampaj),
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
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 14, 16),
              child: naslov,
            ),
            const Divider(height: 1, color: MagacinBoje.linija),
            Flexible(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                  child: _sadrzaj(c.maxWidth - 48),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
              decoration: const BoxDecoration(
                color: MagacinBoje.zaglavlje,
                border: Border(top: BorderSide(color: MagacinBoje.linija)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [zatvori, const SizedBox(width: 10), stampaj],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

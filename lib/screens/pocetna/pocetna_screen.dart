import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/niske_zalihe_controller.dart';
import '../../models/article.dart';
import '../../models/auth_models.dart';
import '../../models/partner.dart';
import '../../models/purchase_calculation.dart';
import '../../models/stock.dart';
import '../../models/work_order.dart';
import '../../services/partners_service.dart';
import '../../services/purchase_calculations_service.dart';
import '../../services/stocks_service.dart';
import '../../services/work_orders_service.dart';
import '../../widgets/logo.dart';
import '../../widgets/magacin_ui.dart';

// Početna stranica: pozdrav, pregled izabrane firme, stanje tri magacina,
// dokumenti koji čekaju i zadnji dokumenti, te brze akcije.

const _akcent = akcentAplikacije;
const _gradijent = [Color(0xFF062226), Color(0xFF0D4950), Color(0xFF0F5C66)];

// Redoslijed magacina na početnoj (tok robe kroz proizvodnju).
const _tipoviSkladista = ['raw_materials', 'production', 'finished_goods'];

String _kolicina(double v) {
  var t = v.toStringAsFixed(4);
  t = t.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return t.replaceAll('.', ',');
}

String _datum(DateTime? d) {
  if (d == null) return '—';
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd.$mm.${d.year}.';
}

const _dani = [
  'Ponedjeljak',
  'Utorak',
  'Srijeda',
  'Četvrtak',
  'Petak',
  'Subota',
  'Nedjelja',
];

const _mjeseci = [
  'januar',
  'februar',
  'mart',
  'april',
  'maj',
  'juni',
  'juli',
  'august',
  'septembar',
  'oktobar',
  'novembar',
  'decembar',
];

String _pozdrav(DateTime sada) {
  if (sada.hour < 12) return 'Dobro jutro';
  if (sada.hour < 18) return 'Dobar dan';
  return 'Dobro veče';
}

// Sažetak jednog magacina.
class _Magacin {
  final String tip;
  final String naziv;
  final int brojArtikala;

  const _Magacin({
    required this.tip,
    required this.naziv,
    required this.brojArtikala,
  });
}

class PocetnaScreen extends StatefulWidget {
  const PocetnaScreen({super.key});

  @override
  State<PocetnaScreen> createState() => _PocetnaScreenState();
}

class _PocetnaScreenState extends State<PocetnaScreen> {
  final FirmaController _firmaController = Get.find<FirmaController>();
  final PurchaseCalculationsService _kalkulacijeService =
      PurchaseCalculationsService();
  final WorkOrdersService _naloziService = WorkOrdersService();
  final StocksService _stanjaService = StocksService();
  final PartnersService _partneriService = PartnersService();

  late final Worker _firmaWorker;

  bool _ucitavanje = false;
  String? _greska;

  List<_Magacin> _magacini = [];
  List<RadniNalog> _zadnjiNalozi = [];
  List<Kalkulacija> _zadnjeKalkulacije = [];
  int _naloziNacrt = 0;
  int _naloziUkupno = 0;
  int _kalkulacijeNacrt = 0;
  int _kalkulacijeUkupno = 0;
  int _dobavljaci = 0;
  int _kupci = 0;

  // Broj zadnjeg zahtjeva; stariji odgovori se ignorišu.
  int _zahtjev = 0;

  NavigationController get _nav => Get.find<NavigationController>();

  // Repromaterijal ispod minimalne količine (dijeli se sa menijem).
  NiskeZaliheController get _niske => Get.find<NiskeZaliheController>();
  List<NiskaZaliha> get _niskeZalihe => _niske.stavke;

  @override
  void initState() {
    super.initState();
    _firmaWorker = ever(_firmaController.izabranaFirma, (_) => _ucitaj());
    _ucitaj();
  }

  @override
  void dispose() {
    _firmaWorker.dispose();
    super.dispose();
  }

  Future<void> _ucitaj() async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      setState(() {
        _magacini = [];
        _zadnjiNalozi = [];
        _zadnjeKalkulacije = [];
        _naloziNacrt = 0;
        _naloziUkupno = 0;
        _kalkulacijeNacrt = 0;
        _kalkulacijeUkupno = 0;
        _dobavljaci = 0;
        _kupci = 0;
        _greska = null;
      });
      return;
    }

    setState(() {
      _ucitavanje = true;
      _greska = null;
    });

    try {
      unawaited(_niske.osvjezi());
      final rezultati = await Future.wait([
        _ucitajMagacine(firma.id),
        _naloziService.fetchWorkOrders(firma.id),
        _naloziService.fetchWorkOrders(firma.id, status: statusNacrt),
        _kalkulacijeService.fetchCalculations(firma.id),
        _kalkulacijeService.fetchCalculations(
          firma.id,
          status: statusKalkulacijeNacrt,
        ),
        _partneriService.fetchPartners(firma.id, VrstaPartnera.dobavljac),
        _partneriService.fetchPartners(firma.id, VrstaPartnera.kupac),
      ]);
      if (!mounted || zahtjev != _zahtjev) return;

      final nalozi = rezultati[1] as StranicaNaloga;
      final kalkulacije = rezultati[3] as StranicaKalkulacija;

      setState(() {
        _magacini = rezultati[0] as List<_Magacin>;
        _zadnjiNalozi = nalozi.nalozi.take(5).toList();
        _naloziUkupno = nalozi.ukupno;
        _naloziNacrt = (rezultati[2] as StranicaNaloga).ukupno;
        _zadnjeKalkulacije = kalkulacije.kalkulacije.take(5).toList();
        _kalkulacijeUkupno = kalkulacije.ukupno;
        _kalkulacijeNacrt = (rezultati[4] as StranicaKalkulacija).ukupno;
        _dobavljaci = (rezultati[5] as StranicaPartnera).ukupno;
        _kupci = (rezultati[6] as StranicaPartnera).ukupno;
      });
    } on ApiException catch (e) {
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _greska = e.message);
    } catch (_) {
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _greska = 'Podaci se trenutno ne mogu učitati.');
    } finally {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _ucitavanje = false);
      }
    }
  }

  // Broj artikala na stanju po skladištu (iz `meta.total`, jedan red).
  Future<List<_Magacin>> _ucitajMagacine(int firmaId) async {
    final skladista = await _kalkulacijeService.fetchWarehouses(firmaId);
    return _brojeviMagacina(firmaId, skladista);
  }

  Future<List<_Magacin>> _brojeviMagacina(
    int firmaId,
    List<Skladiste> skladista,
  ) {
    return Future.wait(
      _tipoviSkladista.map((tip) async {
        final skladiste = skladista.where((s) => s.tip == tip).firstOrNull;
        if (skladiste == null) {
          return _Magacin(
            tip: tip,
            naziv: nazivSkladista(tip, ''),
            brojArtikala: 0,
          );
        }

        final s = await _stanjaService.fetchStocks(
          firmaId,
          warehouseId: skladiste.id,
          perPage: 1,
        );

        return _Magacin(
          tip: tip,
          naziv: skladiste.naziv,
          brojArtikala: s.ukupno,
        );
      }),
    );
  }

  // Broj dokumenata vezanih za magacin, za podnožje kartice.
  String _dokumentiMagacina(String tip) => switch (tip) {
    'raw_materials' => '$_kalkulacijeUkupno kalkulacija prijema',
    'production' =>
      '$_naloziUkupno ${_naloziUkupno == 1 ? 'radni nalog' : 'radnih naloga'}',
    _ => '$_kupci ${_kupci == 1 ? 'kupac' : 'kupaca'}',
  };

  void _otvoriStanje(String tip) => switch (tip) {
    'raw_materials' => _nav.openStanjeMagacina(),
    'production' => _nav.openStanjeProizvodnje(),
    _ => _nav.openStanjeGotovihProizvoda(),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MagacinBoje.pozadina,
      child: LayoutBuilder(
        builder: (context, c) {
          final sirina = c.maxWidth;
          final uskoPadding = sirina < 600 ? 16.0 : 28.0;

          return RefreshIndicator(
            onRefresh: _ucitaj,
            color: _akcent,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                uskoPadding,
                uskoPadding,
                uskoPadding,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1280),
                  child: Obx(() {
                    final firma = _firmaController.izabranaFirma.value;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _hero(sirina, firma?.name, firma?.articlesCount),
                        if (_greska != null) ...[
                          const SizedBox(height: 16),
                          _porukaGreske(),
                        ],
                        if (firma == null &&
                            !_firmaController.isLoading.value) ...[
                          const SizedBox(height: 24),
                          _bezFirme(),
                        ] else ...[
                          if (_niskeZalihe.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _upozorenjeZalihe(sirina),
                          ],
                          const SizedBox(height: 28),
                          _naslovSekcije(
                            'Magacini',
                            'Broj artikala na stanju po skladištu',
                          ),
                          const SizedBox(height: 14),
                          _magaciniRed(sirina),
                          const SizedBox(height: 28),
                          _dokumenti(sirina),
                          const SizedBox(height: 28),
                          _naslovSekcije(
                            'Brze akcije',
                            'Najčešće korištene stranice',
                          ),
                          const SizedBox(height: 14),
                          _brzeAkcije(sirina),
                        ],
                      ],
                    );
                  }),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Zaglavlje
  // -------------------------------------------------------------------------

  Widget _hero(double sirina, String? nazivFirme, int? brojArtikala) {
    final sada = DateTime.now();
    final usko = sirina < 720;
    final prviPut = _ucitavanje && _magacini.isEmpty;
    String broj(int n) => prviPut ? '…' : '$n';

    final kartice = [
      StatKartica(
        brend: true,
        ikona: Icons.category_rounded,
        naslov: 'Artikli',
        vrijednost: '${brojArtikala ?? 0}',
        napomena: 'U šifarniku firme',
      ),
      StatKartica(
        brend: true,
        ikona: Icons.handshake_rounded,
        naslov: 'Partneri',
        vrijednost: broj(_dobavljaci + _kupci),
        napomena: '$_dobavljaci dobavljača · $_kupci kupaca',
      ),
      StatKartica(
        brend: true,
        ikona: Icons.assignment_late_rounded,
        naslov: 'Nalozi u nacrtu',
        vrijednost: broj(_naloziNacrt),
        napomena: _naloziNacrt == 0
            ? 'Sve je izdato'
            : 'Od $_naloziUkupno ukupno',
        upozorenje: _naloziNacrt > 0,
      ),
      StatKartica(
        brend: true,
        ikona: Icons.pending_actions_rounded,
        naslov: 'Neproknjižene kalk.',
        vrijednost: broj(_kalkulacijeNacrt),
        napomena: _kalkulacijeNacrt == 0
            ? 'Sve je proknjiženo'
            : 'Od $_kalkulacijeUkupno ukupno',
        upozorenje: _kalkulacijeNacrt > 0,
      ),
    ];

    final p = usko ? 20.0 : 28.0;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradijent,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x330F5C66),
            blurRadius: 30,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(p),
        child: _sadrzajZaglavlja(
          sada: sada,
          usko: usko,
          sirina: sirina,
          nazivFirme: nazivFirme,
          kartice: kartice,
        ),
      ),
    );
  }

  Widget _sadrzajZaglavlja({
    required DateTime sada,
    required bool usko,
    required double sirina,
    required String? nazivFirme,
    required List<StatKartica> kartice,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_dani[sada.weekday - 1]}, ${sada.day}. '
                    '${_mjeseci[sada.month - 1]} ${sada.year}.',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                      color: mint,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${_pozdrav(sada)}!',
                    style: TextStyle(
                      fontSize: usko ? 24 : 30,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.business_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          nazivFirme ?? 'Nijedna firma nije izabrana',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _dugmeOsvjezi(),
          ],
        ),
        const SizedBox(height: 22),
        _mreza(
          sirina: sirina,
          kolone: sirina < 980 ? 2 : 4,
          razmak: 12,
          djeca: usko ? kartice.map((k) => k.kompaktna()).toList() : kartice,
        ),
      ],
    );
  }

  Widget _dugmeOsvjezi() {
    return Tooltip(
      message: 'Osvježi podatke',
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _ucitavanje ? null : _ucitaj,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Center(
              child: _ucitavanje
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: mint,
                      ),
                    )
                  : const Icon(Icons.refresh_rounded, color: mint, size: 21),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Magacini
  // -------------------------------------------------------------------------

  static const double _visinaZeca = 88;

  Widget _saZecomNaCosku(Widget kartica) {
    const visina = _visinaZeca;
    const zecSirina = visina * 328 / 680;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        kartica,
        Positioned(
          right: -zecSirina * 0.3,
          top: -visina * 0.74,
          child: IgnorePointer(
            child: SizedBox(
              width: zecSirina * 1.3,
              height: visina,
              child: Stack(
                alignment: Alignment.topCenter,
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: visina * 0.74 - 5,
                    child: Container(
                      width: zecSirina * 1.1,
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x330A3238),
                            blurRadius: 10,
                            spreadRadius: -2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Zec(PozaZeca.ruke, visina: visina),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _magaciniRed(double sirina) {
    final magacini = _magacini.isEmpty
        ? _tipoviSkladista
              .map(
                (t) => _Magacin(
                  tip: t,
                  naziv: nazivSkladista(t, ''),
                  brojArtikala: 0,
                ),
              )
              .toList()
        : _magacini;
    final ukupno = magacini.fold<int>(0, (s, m) => s + m.brojArtikala);

    final jednaKolona = sirina < 760;
    Widget kartica(_Magacin m) => _KarticaMagacina(
      magacin: m,
      udio: ukupno <= 0 ? 0 : m.brojArtikala / ukupno,
      dokumenti: _dokumentiMagacina(m.tip),
      ucitavanje: _ucitavanje && _magacini.isEmpty,
      onTap: () => _otvoriStanje(m.tip),
    );

    return _mreza(
      sirina: sirina,
      kolone: jednaKolona ? 1 : 3,
      razmak: 16,
      djeca: [
        for (final m in magacini)
          if (m.tip == 'finished_goods')
            // Kalkulino sjedi na magacinu gotovih proizvoda. Kad su kartice
            // jedna ispod druge, dobija mjesto da ne zaklanja karticu iznad.
            Padding(
              padding: EdgeInsets.only(
                top: jednaKolona ? _visinaZeca * 0.74 - 16 : 0,
              ),
              child: _saZecomNaCosku(kartica(m)),
            )
          else
            kartica(m),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Dokumenti
  // -------------------------------------------------------------------------

  Widget _dokumenti(double sirina) {
    final nalozi = _PanelDokumenata(
      naslov: 'Poslednji radni nalozi',
      ikona: Icons.assignment_rounded,
      boja: const Color(0xFF2563EB),
      ucitavanje: _ucitavanje && _zadnjiNalozi.isEmpty,
      prazno: 'Još nema radnih naloga.',
      onSve: _nav.openRadniNalog,
      redovi: [
        for (final n in _zadnjiNalozi)
          _RedDokumenta(
            broj: n.broj.isEmpty ? 'Nalog #${n.id}' : 'Nalog ${n.broj}',
            opis: n.kupac ?? 'Bez kupca',
            datum: _datum(n.datum),
            gotov: n.jeIzdat,
            gotovTekst: 'Izdat',
            nacrtTekst: 'Nacrt',
            desno: '${n.brojStavki} stav.',
          ),
      ],
    );

    final kalkulacije = _PanelDokumenata(
      naslov: 'Poslednje kalkulacije',
      ikona: Icons.calculate_rounded,
      boja: const Color(0xFFD97706),
      ucitavanje: _ucitavanje && _zadnjeKalkulacije.isEmpty,
      prazno: 'Još nema kalkulacija nabavnih cijena.',
      onSve: _nav.openKalkulacijaNabavnihCijena,
      redovi: [
        for (final k in _zadnjeKalkulacije)
          _RedDokumenta(
            broj: k.brojPrijemnice.isEmpty
                ? 'Kalkulacija #${k.id}'
                : 'Prijemnica ${k.brojPrijemnice}',
            opis: k.dobavljac ?? 'Bez dobavljača',
            datum: _datum(k.datum),
            gotov: k.jeProknjizena,
            gotovTekst: 'Proknjižena',
            nacrtTekst: 'Nacrt',
            desno: '${k.brojStavki} stav.',
          ),
      ],
    );

    if (sirina < 980) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [nalozi, const SizedBox(height: 16), kalkulacije],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: nalozi),
          const SizedBox(width: 16),
          Expanded(child: kalkulacije),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Brze akcije
  // -------------------------------------------------------------------------

  Widget _brzeAkcije(double sirina) {
    final akcije = [
      _BrzaAkcija(
        'Nova kalkulacija',
        'Prijem robe od dobavljača',
        Icons.add_shopping_cart_rounded,
        const Color(0xFFD97706),
        _nav.openKalkulacijaNabavnihCijena,
      ),
      _BrzaAkcija(
        'Radni nalog',
        'Pokreni proizvodnju',
        Icons.assignment_add,
        const Color(0xFF2563EB),
        _nav.openRadniNalog,
      ),
      _BrzaAkcija(
        'Trebovanje',
        'Izdavanje materijala',
        Icons.outbox_rounded,
        const Color(0xFF7C3AED),
        _nav.openTrebovanje,
      ),
      _BrzaAkcija(
        'Otpremnica',
        'Isporuka kupcu',
        Icons.local_shipping_outlined,
        const Color(0xFF059669),
        _nav.openOtpremnica,
      ),
      _BrzaAkcija(
        'Artikli',
        'Šifarnik repromaterijala',
        Icons.category_rounded,
        const Color(0xFF0891B2),
        _nav.openArtikliRepromaterijala,
      ),
      _BrzaAkcija(
        'Partneri',
        'Dobavljači i kupci',
        Icons.people_alt_rounded,
        const Color(0xFFDB2777),
        _nav.openDobavljaci,
      ),
    ];

    final kolone = sirina < 560 ? 2 : (sirina < 980 ? 3 : 6);
    return _mreza(
      sirina: sirina,
      kolone: kolone,
      razmak: 14,
      djeca: [for (final a in akcije) _KarticaAkcije(akcija: a)],
    );
  }

  // -------------------------------------------------------------------------
  // Pomoćno
  // -------------------------------------------------------------------------

  // Jednostavna mreža: redovi sa jednakim kolonama.
  Widget _mreza({
    required double sirina,
    required int kolone,
    required double razmak,
    required List<Widget> djeca,
  }) {
    final redovi = <Widget>[];
    for (var i = 0; i < djeca.length; i += kolone) {
      final red = <Widget>[];
      for (var j = 0; j < kolone; j++) {
        if (j > 0) red.add(SizedBox(width: razmak));
        final index = i + j;
        red.add(
          Expanded(
            child: index < djeca.length ? djeca[index] : const SizedBox(),
          ),
        );
      }
      if (redovi.isNotEmpty) redovi.add(SizedBox(height: razmak));
      redovi.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: red,
          ),
        ),
      );
    }
    return Column(children: redovi);
  }

  Widget _naslovSekcije(String naslov, String podnaslov) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          naslov,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MagacinBoje.naslov,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          podnaslov,
          style: const TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
        ),
      ],
    );
  }

  // Obavještenje: repromaterijal ispod minimalne količine.
  Widget _upozorenjeZalihe(double sirina) {
    const prikazano = 5;
    final broj = _niskeZalihe.length;
    final usko = sirina < 600;

    final naslov = broj == 1
        ? '1 artikal ispod minimalne količine'
        : '$broj artikala ispod minimalne količine';

    Widget red(NiskaZaliha z) {
      final nema = z.kolicina <= 0;
      final boja = nema ? MagacinBoje.crvena : MagacinBoje.narandzasta;
      final jm = z.artikal.jm;

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(
              nema ? Icons.remove_circle_outline_rounded : Icons.south_rounded,
              size: 18,
              color: boja,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: z.artikal.naziv,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    TextSpan(
                      text: '  ${idArtikla(z.artikal.id)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: MagacinBoje.priguseno,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              usko
                  ? '${_kolicina(z.kolicina)} / ${_kolicina(z.minimum)} $jm'
                  : 'Stanje ${_kolicina(z.kolicina)} $jm · '
                        'min. ${_kolicina(z.minimum)} $jm',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: boja,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      decoration: BoxDecoration(
        color: MagacinBoje.narandzastaSvijetlo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                color: MagacinBoje.narandzasta,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      naslov,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF92400E),
                      ),
                    ),
                    const Text(
                      'Magacin repromaterijala — vrijeme je za nabavku.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
              if (!usko)
                TextButton(
                  onPressed: _nav.openStanjeMagacina,
                  child: const Text('Pogledaj stanje'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFFDE68A)),
          const SizedBox(height: 4),
          ..._niskeZalihe.take(prikazano).map(red),
          if (broj > prikazano || usko)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _nav.openStanjeMagacina,
                child: Text(
                  broj > prikazano
                      ? 'Još ${broj - prikazano} — pogledaj stanje'
                      : 'Pogledaj stanje',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _porukaGreske() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: MagacinBoje.crvenaSvijetlo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: MagacinBoje.crvena,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _greska!,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(onPressed: _ucitaj, child: const Text('Pokušaj ponovo')),
        ],
      ),
    );
  }

  Widget _bezFirme() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MagacinBoje.linija),
      ),
      child: Column(
        children: [
          ZecStanja(
            poza: PozaZeca.stoji,
            ikona: Icons.add_business_rounded,
            boja: _akcent,
            pozadina: akcentSvijetlo,
          ),
          const SizedBox(height: 14),
          const Text(
            'Počnite dodavanjem firme',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.naslov,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Uz svaku firmu automatski se kreiraju tri magacina.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MagacinBoje.priguseno),
          ),
          const SizedBox(height: 18),
          GlatkoDugme(
            tekst: 'Dodaj firmu',
            ikona: Icons.add_rounded,
            onTap: _nav.openFirme,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Kartica magacina
// ---------------------------------------------------------------------------

class _KarticaMagacina extends StatefulWidget {
  final _Magacin magacin;
  final double udio;
  final String dokumenti;
  final bool ucitavanje;
  final VoidCallback onTap;

  const _KarticaMagacina({
    required this.magacin,
    required this.udio,
    required this.dokumenti,
    required this.ucitavanje,
    required this.onTap,
  });

  @override
  State<_KarticaMagacina> createState() => _KarticaMagacinaState();
}

class _KarticaMagacinaState extends State<_KarticaMagacina> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.magacin;
    final tema = TemaSkladista.za(m.tip);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: hoverTrajanje,
          curve: hoverKriva,
          transform: Matrix4.translationValues(0, _hover ? -3 : 0, 0),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _hover
                  ? tema.boja.withValues(alpha: 0.45)
                  : MagacinBoje.linija,
            ),
            boxShadow: [
              BoxShadow(
                color: tema.boja.withValues(alpha: _hover ? 0.16 : 0.05),
                blurRadius: _hover ? 24 : 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [tema.boja, tema.tamna],
                      ),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(tema.ikona, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.naziv,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: MagacinBoje.naslov,
                          ),
                        ),
                        Text(
                          tema.opis,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MagacinBoje.priguseno,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSlide(
                    duration: hoverTrajanje,
                    curve: hoverKriva,
                    offset: Offset(_hover ? 0.15 : 0, 0),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 20,
                      color: _hover ? tema.boja : MagacinBoje.svijetlo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'ARTIKALA NA STANJU',
                style: TextStyle(
                  fontSize: 10.5,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w700,
                  color: tema.tamna.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 4),
              widget.ucitavanje
                  ? _Skeleton(sirina: 80, visina: 26, boja: tema.svijetla)
                  : FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${m.brojArtikala}',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: MagacinBoje.naslov,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Stack(
                  children: [
                    Container(height: 6, color: tema.svijetla),
                    AnimatedFractionallySizedBox(
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      widthFactor: widget.udio.clamp(0, 1).toDouble(),
                      child: Container(height: 6, color: tema.boja),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.dokumenti,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: MagacinBoje.tekst,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${(widget.udio * 100).round()}% artikala',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: tema.tamna,
                    ),
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

// ---------------------------------------------------------------------------
// Panel zadnjih dokumenata
// ---------------------------------------------------------------------------

class _RedDokumenta {
  final String broj;
  final String opis;
  final String datum;
  final bool gotov;
  final String gotovTekst;
  final String nacrtTekst;
  final String desno;

  const _RedDokumenta({
    required this.broj,
    required this.opis,
    required this.datum,
    required this.gotov,
    required this.gotovTekst,
    required this.nacrtTekst,
    required this.desno,
  });
}

class _PanelDokumenata extends StatelessWidget {
  final String naslov;
  final IconData ikona;
  final Color boja;
  final bool ucitavanje;
  final String prazno;
  final VoidCallback onSve;
  final List<_RedDokumenta> redovi;

  const _PanelDokumenata({
    required this.naslov,
    required this.ikona,
    required this.boja,
    required this.ucitavanje,
    required this.prazno,
    required this.onSve,
    required this.redovi,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MagacinBoje.linija),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 10, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: boja.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(ikona, color: boja, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    naslov,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onSve,
                  iconAlignment: IconAlignment.end,
                  icon: const Icon(Icons.chevron_right_rounded, size: 18),
                  label: const Text('Sve'),
                  style: TextButton.styleFrom(foregroundColor: _akcent),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: MagacinBoje.linijaSvijetla),
          if (ucitavanje)
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const _Skeleton(sirina: 120, visina: 14),
                    const Spacer(),
                    const _Skeleton(sirina: 70, visina: 14),
                  ],
                ),
              )
          else if (redovi.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  const Zec(PozaZeca.klik, visina: 96),
                  const SizedBox(height: 10),
                  Text(
                    prazno,
                    style: const TextStyle(color: MagacinBoje.priguseno),
                  ),
                ],
              ),
            )
          else
            for (final r in redovi)
              HoverRed(
                akcent: boja,
                visina: 62,
                onTap: onSve,
                builder: (_) => _red(r),
              ),
        ],
      ),
    );
  }

  Widget _red(_RedDokumenta r) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.broj,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: MagacinBoje.naslov,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${r.opis} · ${r.datum}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: MagacinBoje.priguseno,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Status(
                gotov: r.gotov,
                tekst: r.gotov ? r.gotovTekst : r.nacrtTekst,
              ),
              const SizedBox(height: 4),
              Text(
                r.desno,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: MagacinBoje.tekst,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  final bool gotov;
  final String tekst;

  const _Status({required this.gotov, required this.tekst});

  @override
  Widget build(BuildContext context) {
    final boja = gotov ? MagacinBoje.zelena : const Color(0xFFB45309);
    final pozadina = gotov
        ? MagacinBoje.zelenaSvijetlo
        : const Color(0xFFFEF3C7);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: pozadina,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: boja, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            tekst,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: boja,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Brze akcije
// ---------------------------------------------------------------------------

class _BrzaAkcija {
  final String naziv;
  final String opis;
  final IconData ikona;
  final Color boja;
  final VoidCallback otvori;

  const _BrzaAkcija(this.naziv, this.opis, this.ikona, this.boja, this.otvori);
}

class _KarticaAkcije extends StatefulWidget {
  final _BrzaAkcija akcija;

  const _KarticaAkcije({required this.akcija});

  @override
  State<_KarticaAkcije> createState() => _KarticaAkcijeState();
}

class _KarticaAkcijeState extends State<_KarticaAkcije> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.akcija;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: a.otvori,
        child: AnimatedContainer(
          duration: hoverTrajanje,
          curve: hoverKriva,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hover ? hoverNijansa(a.boja, 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _hover
                  ? a.boja.withValues(alpha: 0.4)
                  : MagacinBoje.linija,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: hoverTrajanje,
                curve: hoverKriva,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _hover ? a.boja : a.boja.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  a.ikona,
                  size: 20,
                  color: _hover ? Colors.white : a.boja,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                a.naziv,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                a.opis,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Siva traka umjesto teksta dok se podaci učitavaju.
class _Skeleton extends StatelessWidget {
  final double sirina;
  final double visina;
  final Color boja;

  const _Skeleton({
    required this.sirina,
    required this.visina,
    this.boja = MagacinBoje.linijaSvijetla,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: sirina,
      height: visina,
      decoration: BoxDecoration(
        color: boja,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

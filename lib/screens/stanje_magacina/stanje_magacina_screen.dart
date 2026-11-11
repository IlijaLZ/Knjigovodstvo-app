import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../controllers/niske_zalihe_controller.dart';
import '../../models/article.dart';
import '../../models/auth_models.dart';
import '../../models/stock.dart';
import '../../models/work_order.dart';
import '../../services/purchase_calculations_service.dart';
import '../../services/stocks_service.dart';
import '../../widgets/logo.dart';
import '../../widgets/magacin_ui.dart';
import '../../widgets/paginacija_widget.dart';
import '../analiticka_kartica.dart';

String _format(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

// Količine API vraća sa 4 decimale; nule na kraju se ne prikazuju.
String _format4(double value) {
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

// Stanje jednog skladišta firme (tip: raw_materials, production,
// finished_goods). Lista dolazi iz GET /companies/{company}/stocks;
// sume ulaza/izlaza i datum zadnje promjene računaju se iz kartice artikla.
class StanjeMagacinaScreen extends StatefulWidget {
  final String tipSkladista;

  const StanjeMagacinaScreen({super.key, required this.tipSkladista});

  @override
  State<StanjeMagacinaScreen> createState() => _StanjeMagacinaScreenState();
}

class _StanjeMagacinaScreenState extends State<StanjeMagacinaScreen> {
  final FirmaController _firmaController = Get.find<FirmaController>();
  final StocksService _service = StocksService();
  final PurchaseCalculationsService _skladistaService =
      PurchaseCalculationsService();
  final TextEditingController searchController = TextEditingController();
  final ScrollController _horizontalni = ScrollController();

  late final Worker _firmaWorker;

  Skladiste? _skladiste;
  int? _skladisteFirma;

  List<StanjeArtikla> _stanja = [];
  final Map<int, SumeKartice> _sume = {};
  bool _ucitavanje = false;
  String? _greska;

  int _stranica = 1;
  int _zadnjaStranica = 1;
  int _ukupno = 0;
  int? _od;
  int? _do;

  Timer? _pretragaTimer;
  String _pretraga = '';

  // Broj zadnjeg zahtjeva; stariji odgovori se ignorišu.
  int _zahtjev = 0;

  String get _naslov => nazivSkladista(widget.tipSkladista, 'Stanje magacina');

  @override
  void initState() {
    super.initState();
    searchController.addListener(_promjenaPretrage);
    _firmaWorker = ever(_firmaController.izabranaFirma, (_) => _ucitaj());
    _ucitaj();
    // Kružić u meniju prati najnovije stanje repromaterijala.
    if (widget.tipSkladista == 'raw_materials') {
      unawaited(Get.find<NiskeZaliheController>().osvjezi());
    }
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

  Future<void> _ucitaj([int stranica = 1]) async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      setState(() {
        _stanja = [];
        _sume.clear();
        _greska = 'Nije izabrana firma.';
        _ukupno = 0;
        _stranica = 1;
        _zadnjaStranica = 1;
      });
      return;
    }

    setState(() {
      _ucitavanje = true;
      _greska = null;
    });

    try {
      // Skladište ovog tipa se traži jednom po firmi.
      if (_skladisteFirma != firma.id) {
        final skladista = await _skladistaService.fetchWarehouses(firma.id);
        _skladiste = skladista
            .where((s) => s.tip == widget.tipSkladista)
            .firstOrNull;
        _skladisteFirma = firma.id;
      }
      if (!mounted || zahtjev != _zahtjev) return;

      if (_skladiste == null) {
        setState(() {
          _stanja = [];
          _sume.clear();
          _ukupno = 0;
          _greska = 'Firma nema skladište "$_naslov".';
        });
        return;
      }

      final rezultat = await _service.fetchStocks(
        firma.id,
        warehouseId: _skladiste!.id,
        search: _pretraga,
        page: stranica,
      );
      if (!mounted || zahtjev != _zahtjev) return;

      setState(() {
        _stanja = rezultat.stanja;
        _sume.clear();
        _stranica = rezultat.stranica;
        _zadnjaStranica = rezultat.zadnjaStranica;
        _ukupno = rezultat.ukupno;
        _od = rezultat.od;
        _do = rezultat.doBroja;
      });

      unawaited(_ucitajSume(firma.id, zahtjev));
    } on ApiException catch (e) {
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _greska = e.message);
    } finally {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _ucitavanje = false);
      }
    }
  }

  // Sume za artikle na trenutnoj stranici; svaki red se popuni čim stigne.
  Future<void> _ucitajSume(int companyId, int zahtjev) async {
    await Future.wait(
      _stanja.map((s) async {
        final articleId = s.artikal.id;
        if (articleId == null) return;
        try {
          final sume = await _service.fetchSume(
            companyId,
            articleId,
            warehouseId: _skladiste?.id,
          );
          if (!mounted || zahtjev != _zahtjev) return;
          setState(() => _sume[s.id] = sume);
        } on ApiException catch (e) {
          if (!mounted || zahtjev != _zahtjev) return;
          setState(() => _greska ??= e.message);
        }
      }),
    );
  }

  void _otvoriKarticu(StanjeArtikla s) {
    final articleId = s.artikal.id;
    if (articleId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalitickaKarticaScreen(
          articleId: articleId,
          naziv: s.artikal.naziv,
          jm: s.artikal.jm,
          warehouseId: _skladiste?.id,
          skladiste: _skladiste?.naziv,
          tipSkladista: _skladiste?.tip,
        ),
      ),
    );
  }

  List<String> _celije(int index, StanjeArtikla s) {
    final sume = _sume[s.id];
    String ili(String Function(SumeKartice) f) => sume == null ? '…' : f(sume);

    return [
      '${(_od ?? 1) + index}',
      ili((x) => _formatDatum(x.zadnjiDatum)),
      nazivSaId(s.artikal.id, s.artikal.naziv, razmak: ' - '),
      ili((x) => _format4(x.ulaz)),
      ili((x) => _format4(x.izlaz)),
      _format4(s.kolicina),
      // Kad je zaliha 0, /stocks vraća 0, a artikal čuva zadnju prosječnu
      // cijenu (average_purchase_price).
      '${_format(s.kolicina == 0 ? (s.artikal.cijena ?? 0) : s.prosjecnaCijena)} €',
      ili((x) => '${_format(x.vrijednostUlaz)} €'),
      ili((x) => '${_format(x.vrijednostIzlaz)} €'),
      '${_format(s.vrijednost)} €',
    ];
  }

  // ---------------------------------------------------------------------------
  // Prikaz
  // ---------------------------------------------------------------------------

  TemaSkladista get _tema => TemaSkladista.za(widget.tipSkladista);

  // Zbirni podaci za trenutnu stranicu (za kartice u zaglavlju).
  double get _vrijednostStranice =>
      _stanja.fold(0, (suma, s) => suma + s.vrijednost);
  int get _bezZalihe => _stanja.where((s) => s.kolicina <= 0).length;

  // Artikli koji imaju zalihu, ali ispod praga minimalne količine.
  // Minimalna količina se prati samo u magacinu repromaterijala; u
  // proizvodnji i gotovim proizvodima nema upozorenja.
  bool get _pratiMinimum => widget.tipSkladista == 'raw_materials';

  bool _ispodMin(StanjeArtikla s) =>
      _pratiMinimum && s.artikal.ispodMinimuma(s.kolicina);

  int get _ispodMinimuma =>
      _stanja.where((s) => s.kolicina > 0 && _ispodMin(s)).length;
  double get _najvecaVrijednost =>
      _stanja.fold(0, (m, s) => s.vrijednost > m ? s.vrijednost : m);

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

  Widget _celija(
    String tekst, {
    required double sirina,
    Alignment poravnanje = Alignment.centerRight,
    FontWeight tezina = FontWeight.w500,
    Color? boja,
    double velicina = 13,
  }) {
    return SizedBox(
      width: sirina,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Align(
          alignment: poravnanje,
          child: tekst == '…'
              ? _skeleton(48)
              : Text(
                  tekst,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: velicina,
                    fontWeight: tezina,
                    color: boja ?? MagacinBoje.tekst,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
        ),
      ),
    );
  }

  // Količina ulaza/izlaza sa malom strelicom smjera.
  Widget _kretanje(String tekst, {required bool ulaz, required double sirina}) {
    final boja = ulaz ? MagacinBoje.zelena : MagacinBoje.crvena;
    final prazno = tekst == '0';
    return SizedBox(
      width: sirina,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Align(
          alignment: Alignment.centerRight,
          child: tekst == '…'
              ? _skeleton(48)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ulaz
                          ? Icons.south_west_rounded
                          : Icons.north_east_rounded,
                      size: 13,
                      color: prazno ? MagacinBoje.svijetlo : boja,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        tekst,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: prazno ? MagacinBoje.svijetlo : boja,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _nazivCelija(
    StanjeArtikla s, {
    EdgeInsets padding = const EdgeInsets.symmetric(horizontal: 14),
  }) {
    final tema = _tema;
    final naziv = s.artikal.naziv.trim();
    final inicijal = naziv.isEmpty ? '?' : naziv.characters.first.toUpperCase();

    return SizedBox(
      width: padding == EdgeInsets.zero ? null : _sirine[2],
      child: Padding(
        padding: padding,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tema.boja.withValues(alpha: 0.18),
                    tema.boja.withValues(alpha: 0.08),
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                inicijal,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: tema.tamna,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    naziv,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          idArtikla(s.artikal.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MagacinBoje.priguseno,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (s.artikal.jm.isNotEmpty) ...[
                        Container(
                          width: 3,
                          height: 3,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: const BoxDecoration(
                            color: MagacinBoje.svijetlo,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Text(
                          s.artikal.jm,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: MagacinBoje.priguseno,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Oznaka količine na stanju: zelena kad ima zalihe, narandžasta kad je
  // ispod minimalne količine, crvena kad nema.
  Widget _saldoOznaka(String tekst, StanjeArtikla s, {double velicina = 12.5}) {
    final nema = s.kolicina <= 0;
    final malo = !nema && _ispodMin(s);
    final boja = nema || malo ? MagacinBoje.crvena : MagacinBoje.zelena;
    final oznaka = Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: nema || malo
            ? MagacinBoje.crvenaSvijetlo
            : MagacinBoje.zelenaSvijetlo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (malo)
            Icon(Icons.warning_amber_rounded, size: velicina + 1, color: boja)
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: boja, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              tekst,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: velicina,
                fontWeight: FontWeight.w800,
                color: boja,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );

    final minimum = s.artikal.minimalnaKolicina;
    if (!_pratiMinimum || !s.artikal.imaMinimalnuKolicinu) return oznaka;
    return Tooltip(
      message: malo || nema
          ? 'Ispod minimalne količine (${_format4(minimum!)} ${s.artikal.jm})'
          : 'Minimalna količina: ${_format4(minimum!)} ${s.artikal.jm}',
      child: oznaka,
    );
  }

  Widget _saldoPill(String tekst, StanjeArtikla s) {
    return SizedBox(
      width: _sirine[5],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: Alignment.centerRight,
          child: _saldoOznaka(tekst, s),
        ),
      ),
    );
  }

  // Vrijednost salda sa trakom udjela u najvećoj vrijednosti na stranici.
  Widget _vrijednostCelija(String tekst, StanjeArtikla s) {
    final max = _najvecaVrijednost;
    final udio = max <= 0 ? 0.0 : (s.vrijednost / max).clamp(0.0, 1.0);
    return SizedBox(
      width: _sirine[9],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              tekst,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: MagacinBoje.naslov,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 4,
                width: 80,
                child: Stack(
                  children: [
                    Container(color: MagacinBoje.linija),
                    FractionallySizedBox(
                      widthFactor: udio,
                      child: Container(color: _tema.boja),
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

  Widget _zaglavljeGrupa() {
    Widget grupa(
      double sirina, [
      String? naslov,
      Color? boja,
      IconData? ikona,
    ]) {
      return SizedBox(
        width: sirina,
        height: 38,
        child: naslov == null
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: boja!.withValues(alpha: 0.08),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    border: Border(bottom: BorderSide(color: boja, width: 2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(ikona, size: 14, color: boja),
                      const SizedBox(width: 6),
                      Text(
                        naslov.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w800,
                          color: boja,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    return Row(
      children: [
        grupa(_sirine[0] + _sirine[1] + _sirine[2]),
        grupa(
          _sirine[3] + _sirine[4] + _sirine[5],
          'Količina',
          MagacinBoje.plava,
          Icons.scale_rounded,
        ),
        grupa(_sirine[6]),
        grupa(
          _sirine[7] + _sirine[8] + _sirine[9],
          'Vrijednost',
          MagacinBoje.zelena,
          Icons.payments_rounded,
        ),
        grupa(_sirine[10]),
      ],
    );
  }

  Widget _zaglavljeKolona() {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: MagacinBoje.zaglavlje,
        border: Border(
          top: BorderSide(color: MagacinBoje.linija),
          bottom: BorderSide(color: MagacinBoje.linija),
        ),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _zaglavlja.length; i++)
            SizedBox(
              width: _sirine[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: i == 0 || i == 10
                      ? Alignment.center
                      : i <= 2
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Text(
                    _zaglavlja[i].toUpperCase(),
                    textAlign: i <= 2 ? TextAlign.left : TextAlign.right,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.3,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _red(int rowIndex, StanjeArtikla stanje) {
    final celije = _celije(rowIndex, stanje);

    return HoverRed(
      akcent: _tema.boja,
      visina: _visinaReda,
      pozadina: _ispodMin(stanje) ? MagacinBoje.crvenaPozadina : Colors.white,
      onTap: () => _otvoriKarticu(stanje),
      builder: (hover) => Row(
        children: [
          _celija(
            celije[0],
            sirina: _sirine[0],
            poravnanje: Alignment.center,
            boja: MagacinBoje.svijetlo,
            velicina: 12,
            tezina: FontWeight.w700,
          ),
          _celija(
            celije[1],
            sirina: _sirine[1],
            poravnanje: Alignment.centerLeft,
            boja: MagacinBoje.priguseno,
            velicina: 12.5,
          ),
          _nazivCelija(stanje),
          _kretanje(celije[3], ulaz: true, sirina: _sirine[3]),
          _kretanje(celije[4], ulaz: false, sirina: _sirine[4]),
          _saldoPill(celije[5], stanje),
          _celija(celije[6], sirina: _sirine[6], tezina: FontWeight.w600),
          _celija(celije[7], sirina: _sirine[7], boja: MagacinBoje.priguseno),
          _celija(celije[8], sirina: _sirine[8], boja: MagacinBoje.priguseno),
          _vrijednostCelija(celije[9], stanje),
          SizedBox(
            width: _sirine[10],
            child: Center(
              child: Tooltip(
                message: 'Analitička kartica',
                // Na hover dugme dobije svijetlu boju magacina, a strelica
                // se blago pomjeri udesno.
                child: AnimatedContainer(
                  duration: hoverTrajanje,
                  curve: hoverKriva,
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: hover ? _tema.svijetla : MagacinBoje.zaglavlje,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hover
                          ? hoverNijansa(_tema.boja, 0.35)
                          : MagacinBoje.linija,
                    ),
                  ),
                  child: AnimatedSlide(
                    duration: hoverTrajanje,
                    curve: hoverKriva,
                    offset: hover ? const Offset(0.12, 0) : Offset.zero,
                    child: TweenAnimationBuilder<Color?>(
                      duration: hoverTrajanje,
                      curve: hoverKriva,
                      tween: ColorTween(
                        end: hover ? _tema.tamna : MagacinBoje.priguseno,
                      ),
                      builder: (context, boja, _) => Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: boja,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Red koji se prikazuje dok stiže prva stranica.
  Widget _skeletonRed(int i) {
    return Container(
      height: _visinaReda,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _sirine[0],
            child: Center(child: _skeleton(18)),
          ),
          SizedBox(
            width: _sirine[1],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _skeleton(64),
              ),
            ),
          ),
          SizedBox(
            width: _sirine[2],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _skeleton(36, visina: 36),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _skeleton(i.isEven ? 150 : 110),
                      const SizedBox(height: 8),
                      _skeleton(60, visina: 8),
                    ],
                  ),
                ],
              ),
            ),
          ),
          for (int k = 3; k <= 9; k++)
            SizedBox(
              width: _sirine[k],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _skeleton(k == 5 ? 60 : 48),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _praznoStanje(double sirina) {
    final greska = _greska != null;
    final tema = _tema;
    return Container(
      width: sirina,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZecStanja(
            // Greška: zec leži; inače stoji u majici boje magacina.
            poza: greska ? PozaZeca.lezi : tema.zec,
            ikona: greska
                ? Icons.error_outline_rounded
                : _pretraga.isEmpty
                ? tema.ikona
                : Icons.search_off_rounded,
            boja: greska ? MagacinBoje.crvena : tema.boja,
            pozadina: greska ? MagacinBoje.crvenaSvijetlo : tema.svijetla,
            // Ležeći zec (greška) je širok, pa je niži; stojeći je pune visine.
            visina: greska ? 60 : 128,
          ),
          const SizedBox(height: 18),
          Text(
            greska
                ? 'Podaci se ne mogu učitati'
                : _pretraga.isEmpty
                ? 'Magacin je prazan'
                : 'Nema rezultata',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.naslov,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _greska ??
                (_pretraga.isEmpty
                    ? 'Nema artikala na stanju u ovom skladištu.'
                    : 'Nijedan artikal ne odgovara pretrazi "$_pretraga".'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
          ),
          if (greska) ...[
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _ucitavanje ? null : () => _ucitaj(_stranica),
              style: OutlinedButton.styleFrom(
                foregroundColor: MagacinBoje.naslov,
                side: const BorderSide(color: MagacinBoje.linija),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Pokušaj ponovo'),
            ),
          ],
          if (!greska && _pretraga.isNotEmpty) ...[
            const SizedBox(height: 18),
            TextButton.icon(
              onPressed: searchController.clear,
              style: TextButton.styleFrom(foregroundColor: tema.boja),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Obriši pretragu'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _alatnaTraka({required bool kompaktno}) {
    final tema = _tema;
    return Padding(
      padding: EdgeInsets.fromLTRB(kompaktno ? 16 : 20, 16, 16, 4),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              'Artikli na stanju',
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
              color: tema.svijetla,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_ukupno',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: tema.tamna,
              ),
            ),
          ),
          const Spacer(),
          if (_ucitavanje)
            Padding(
              padding: EdgeInsets.only(right: kompaktno ? 0 : 12),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: tema.boja,
                ),
              ),
            ),
          if (!kompaktno) ...[
            const Icon(
              Icons.touch_app_outlined,
              size: 15,
              color: MagacinBoje.svijetlo,
            ),
            const SizedBox(width: 6),
            const Text(
              'Klik na red otvara analitičku karticu',
              style: TextStyle(fontSize: 12, color: MagacinBoje.priguseno),
            ),
          ],
        ],
      ),
    );
  }

  // Paginacija; na uskom ekranu se horizontalno skroluje umjesto da puca.
  Widget _paginacija() {
    final paginacija = Paginacija(
      stranica: _stranica,
      zadnjaStranica: _zadnjaStranica,
      ukupno: _ukupno,
      od: _od,
      doBroja: _do,
      zakljucano: _ucitavanje,
      prazno: 'Nema artikala',
      onStranica: _ucitaj,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: MagacinBoje.zaglavlje,
        border: Border(top: BorderSide(color: MagacinBoje.linija)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const minSirina = 680.0;
          if (constraints.maxWidth >= minSirina) return paginacija;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(width: minSirina, child: paginacija),
          );
        },
      ),
    );
  }

  BoxDecoration get _okvirKartice => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: MagacinBoje.linija),
    boxShadow: const [
      BoxShadow(color: Color(0x0A0F172A), blurRadius: 3, offset: Offset(0, 1)),
      BoxShadow(
        color: Color(0x0D0F172A),
        blurRadius: 28,
        offset: Offset(0, 12),
      ),
    ],
  );

  Widget _tabela({required bool kompaktno}) {
    final ukupnaSirina = _sirine.reduce((a, b) => a + b);
    final prvoUcitavanje = _ucitavanje && _stanja.isEmpty;

    return Container(
      decoration: _okvirKartice,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _alatnaTraka(kompaktno: kompaktno),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final sirina = ukupnaSirina > constraints.maxWidth
                    ? ukupnaSirina
                    : constraints.maxWidth;
                return Scrollbar(
                  controller: _horizontalni,
                  thumbVisibility: ukupnaSirina > constraints.maxWidth,
                  child: SingleChildScrollView(
                    controller: _horizontalni,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: sirina,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _zaglavljeGrupa(),
                          _zaglavljeKolona(),
                          Expanded(
                            child: prvoUcitavanje
                                ? ListView.builder(
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: 8,
                                    itemBuilder: (context, i) =>
                                        _skeletonRed(i),
                                  )
                                : _stanja.isEmpty
                                ? SingleChildScrollView(
                                    child: _praznoStanje(sirina),
                                  )
                                : AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _ucitavanje ? 0.55 : 1,
                                    child: ListView.builder(
                                      itemCount: _stanja.length,
                                      itemBuilder: (context, i) =>
                                          _red(i, _stanja[i]),
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          _paginacija(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Uski ekran: artikli kao kartice umjesto tabele
  // ---------------------------------------------------------------------------

  Widget _metrika(
    String naslov,
    String tekst, {
    Color? boja,
    bool podebljano = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          naslov.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9.5,
            letterSpacing: 0.7,
            fontWeight: FontWeight.w800,
            color: MagacinBoje.svijetlo,
          ),
        ),
        const SizedBox(height: 4),
        if (tekst == '…')
          _skeleton(44)
        else
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              tekst,
              style: TextStyle(
                fontSize: 13,
                fontWeight: podebljano ? FontWeight.w800 : FontWeight.w600,
                color: boja ?? MagacinBoje.tekst,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }

  Widget _karticaArtikla(int index, StanjeArtikla s) {
    final tema = _tema;
    final celije = _celije(index, s);
    final jm = s.artikal.jm.isEmpty ? '' : ' ${s.artikal.jm}';

    return Material(
      color: _ispodMin(s) ? MagacinBoje.crvenaPozadina : Colors.white,
      child: InkWell(
        onTap: () => _otvoriKarticu(s),
        hoverColor: tema.boja.withValues(alpha: 0.04),
        splashColor: tema.boja.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _nazivCelija(s, padding: EdgeInsets.zero)),
                  const SizedBox(width: 10),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: tema.svijetla,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: tema.tamna,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: MagacinBoje.zaglavlje,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MagacinBoje.linijaSvijetla),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text(
                          'NA STANJU',
                          style: TextStyle(
                            fontSize: 9.5,
                            letterSpacing: 0.7,
                            fontWeight: FontWeight.w800,
                            color: MagacinBoje.svijetlo,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Spacer(),
                        Flexible(
                          flex: 6,
                          child: _saldoOznaka('${celije[5]}$jm', s),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: MagacinBoje.linija),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _metrika(
                            'Ulaz',
                            celije[3],
                            boja: MagacinBoje.zelena,
                          ),
                        ),
                        Expanded(
                          child: _metrika(
                            'Izlaz',
                            celije[4],
                            boja: MagacinBoje.crvena,
                          ),
                        ),
                        Expanded(child: _metrika('Prosj. cijena', celije[6])),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(height: 1, color: MagacinBoje.linija),
                    ),
                    Row(
                      children: [
                        Expanded(child: _metrika('Vr. ulaz', celije[7])),
                        Expanded(child: _metrika('Vr. izlaz', celije[8])),
                        Expanded(
                          child: _metrika(
                            'Vrijednost',
                            celije[9],
                            boja: MagacinBoje.naslov,
                            podebljano: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.history_rounded,
                    size: 14,
                    color: MagacinBoje.svijetlo,
                  ),
                  const SizedBox(width: 5),
                  if (celije[1] == '…')
                    _skeleton(70, visina: 8)
                  else
                    Flexible(
                      child: Text(
                        celije[1].isEmpty
                            ? 'Bez promjena'
                            : 'Zadnja promjena ${celije[1]}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MagacinBoje.priguseno,
                        ),
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

  Widget _skeletonKartica(int i) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _skeleton(36, visina: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeleton(i.isEven ? 150 : 110),
                    const SizedBox(height: 8),
                    _skeleton(60, visina: 8),
                  ],
                ),
              ),
              _skeleton(64, visina: 22),
            ],
          ),
          const SizedBox(height: 12),
          _skeleton(double.infinity, visina: 96),
        ],
      ),
    );
  }

  Widget _listaKartica() {
    final prvoUcitavanje = _ucitavanje && _stanja.isEmpty;

    return Container(
      decoration: _okvirKartice,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _alatnaTraka(kompaktno: true),
          const SizedBox(height: 8),
          const Divider(height: 1, color: MagacinBoje.linija),
          if (prvoUcitavanje)
            for (int i = 0; i < 4; i++) _skeletonKartica(i)
          else if (_stanja.isEmpty)
            _praznoStanje(double.infinity)
          else
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _ucitavanje ? 0.55 : 1,
              child: Column(
                children: [
                  for (int i = 0; i < _stanja.length; i++)
                    _karticaArtikla(i, _stanja[i]),
                ],
              ),
            ),
          _paginacija(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Zaglavlje
  // ---------------------------------------------------------------------------

  Widget _pretrazivac() {
    return TextField(
      controller: searchController,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: Colors.white,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.14),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Colors.white.withValues(alpha: 0.85),
        ),
        hintText: 'Pretraži po šifri ili nazivu…',
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white, width: 1.5),
        ),
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Obriši pretragu',
                icon: const Icon(Icons.close_rounded),
                color: Colors.white,
                onPressed: searchController.clear,
              ),
      ),
    );
  }

  Widget _dugmeOsvjezi() {
    return Tooltip(
      message: 'Osvježi',
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _ucitavanje ? null : () => _ucitaj(_stranica),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _naslovBlok({required bool malo}) {
    final tema = _tema;
    return Row(
      children: [
        Container(
          width: malo ? 46 : 56,
          height: malo ? 46 : 56,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(malo ? 13 : 16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
          ),
          child: Icon(tema.ikona, color: Colors.white, size: malo ? 24 : 30),
        ),
        SizedBox(width: malo ? 12 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'STANJE MAGACINA',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _naslov,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: malo ? 20 : 26,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                tema.opis,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: malo ? 12 : 13,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _zaglavlje() {
    final tema = _tema;
    final naStranici = _zadnjaStranica > 1 ? 'na ovoj stranici' : 'ukupno';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: tema.gradijent,
        ),
        boxShadow: [
          BoxShadow(
            color: tema.boja.withValues(alpha: 0.28),
            blurRadius: 32,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final malo = w < 600;
          final razmak = malo ? 18.0 : 26.0;
          final unutra = w - 2 * razmak;

          // 4 kartice u redu na širokom, 2 na užem ekranu.
          const gap = 12.0;
          final kolone = unutra >= 860 ? 4 : 2;
          final sirinaKartice = (unutra - (kolone - 1) * gap) / kolone;
          final bezIkone = sirinaKartice < 190;

          final kartice = [
            StatKartica(
              ikona: Icons.category_rounded,
              naslov: 'Artikala',
              vrijednost: '$_ukupno',
              napomena: 'u skladištu',
            ),
            StatKartica(
              ikona: Icons.account_balance_wallet_rounded,
              naslov: 'Vrijednost zalihe',
              vrijednost: '${_format(_vrijednostStranice)} €',
              napomena: naStranici,
            ),
            StatKartica(
              ikona: Icons.check_circle_rounded,
              naslov: 'Na stanju',
              vrijednost: '${_stanja.length - _bezZalihe}',
              napomena: _ispodMinimuma > 0
                  ? '$_ispodMinimuma ispod minimuma'
                  : naStranici,
              upozorenje: _ispodMinimuma > 0,
            ),
            StatKartica(
              ikona: Icons.warning_amber_rounded,
              naslov: 'Bez zalihe',
              vrijednost: '$_bezZalihe',
              napomena: naStranici,
              upozorenje: _bezZalihe > 0,
            ),
          ];

          return Stack(
            children: [
              // Dekorativni krugovi u pozadini.
              Positioned(right: -60, top: -80, child: _krug(240, 0.08)),
              Positioned(right: 140, bottom: -110, child: _krug(200, 0.06)),
              Positioned(
                right: 30,
                bottom: -20,
                child: Icon(
                  tema.ikona,
                  size: 150,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(razmak),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (w >= 820)
                      Row(
                        children: [
                          Expanded(child: _naslovBlok(malo: false)),
                          const SizedBox(width: 20),
                          SizedBox(width: 320, child: _pretrazivac()),
                          const SizedBox(width: 10),
                          _dugmeOsvjezi(),
                        ],
                      )
                    else ...[
                      _naslovBlok(malo: malo),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _pretrazivac()),
                          const SizedBox(width: 10),
                          _dugmeOsvjezi(),
                        ],
                      ),
                    ],
                    SizedBox(height: malo ? 16 : 22),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final k in kartice)
                          SizedBox(
                            width: sirinaKartice,
                            child: bezIkone ? k.kompaktna() : k,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _krug(double velicina, double alfa) {
    return Container(
      width: velicina,
      height: velicina,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alfa),
      ),
    );
  }

  Widget _trakaGreske() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MagacinBoje.crvenaSvijetlo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MagacinBoje.crvena.withValues(alpha: 0.3)),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MagacinBoje.pozadina,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final usko = w < 700;
            final razmak = w < 600 ? 12.0 : 24.0;
            final padding = EdgeInsets.fromLTRB(razmak, razmak, razmak, razmak);
            final greska = _greska != null && _stanja.isNotEmpty;

            // Uski ekran: cijela stranica se skroluje, artikli su kartice.
            if (usko) {
              return SingleChildScrollView(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _zaglavlje(),
                    const SizedBox(height: 16),
                    if (greska) _trakaGreske(),
                    _listaKartica(),
                  ],
                ),
              );
            }

            // Nizak prozor: zaglavlje i tabela se skroluju zajedno, a tabela
            // zadržava upotrebljivu visinu.
            if (h < 720) {
              return SingleChildScrollView(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _zaglavlje(),
                    const SizedBox(height: 20),
                    if (greska) _trakaGreske(),
                    SizedBox(
                      height: (h - 2 * razmak).clamp(460.0, double.infinity),
                      child: _tabela(kompaktno: w < 1000),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _zaglavlje(),
                  const SizedBox(height: 20),
                  if (greska) _trakaGreske(),
                  Expanded(child: _tabela(kompaktno: w < 1000)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

const double _visinaReda = 64;

const List<double> _sirine = [
  56, // Rb
  110, // Datum
  320, // Artikal
  110, // Kol. ulaz
  110, // Kol. izlaz
  125, // Kol. saldo
  125, // Prosječna cijena
  120, // Vr. ulaz
  120, // Vr. izlaz
  135, // Vr. saldo
  70, // Akcije
];

const List<String> _zaglavlja = [
  '#',
  'Zadnja promjena',
  'Artikal',
  'Ulaz',
  'Izlaz',
  'Saldo',
  'Prosječna nabavna cijena',
  'Ulaz',
  'Izlaz',
  'Saldo',
  '',
];

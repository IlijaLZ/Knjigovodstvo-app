import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/controllers/poslovne_godine_controller.dart';
import 'package:knjigovodstvo_app/izvoz/dugme_izvoza.dart';
import 'package:knjigovodstvo_app/izvoz/excel_izvoz.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/stock_card.dart';
import 'package:knjigovodstvo_app/services/articles_service.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';
import 'package:knjigovodstvo_app/widgets/paginacija_widget.dart';

String _format(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

// Količine i jedinične cijene API vraća sa 4 decimale.
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

const double _visinaReda = 60;

const List<double> _sirine = [
  56, // Rb
  105, // Datum
  130, // Br. dokumenta
  250, // Dokument
  110, // Ulaz
  110, // Izlaz
  125, // Saldo
  130, // Prosječna cijena
  125, // Duguje
  125, // Potražuje
  135, // Saldo
];

const List<String> _zaglavlja = [
  '#',
  'Datum',
  'Br. dokumenta',
  'Dokument',
  'Ulaz',
  'Izlaz',
  'Saldo',
  'Prosječna nabavna cijena',
  'Duguje',
  'Potražuje',
  'Saldo',
];

// Analitička kartica artikla:
// GET /companies/{company}/articles/{article}/stock-card
// Ako je zadat warehouseId, prikazuju se samo promjene na tom skladištu.
class AnalitickaKarticaScreen extends StatefulWidget {
  final int articleId;
  final String naziv;
  final String? jm;
  final int? warehouseId;
  final String? skladiste;

  // Tip skladišta (raw_materials, production, finished_goods) za boju ekrana.
  final String? tipSkladista;

  const AnalitickaKarticaScreen({
    super.key,
    required this.articleId,
    required this.naziv,
    this.jm,
    this.warehouseId,
    this.skladiste,
    this.tipSkladista,
  });

  @override
  State<AnalitickaKarticaScreen> createState() =>
      _AnalitickaKarticaScreenState();
}

class _AnalitickaKarticaScreenState extends State<AnalitickaKarticaScreen> {
  final FirmaController _firmaController = Get.find<FirmaController>();
  final ArticlesService _service = ArticlesService();
  final ScrollController _horizontalni = ScrollController();

  List<PromjenaKartice> _promjene = [];
  bool _ucitavanje = false;
  String? _greska;

  int _stranica = 1;
  int _zadnjaStranica = 1;
  int _ukupno = 0;
  int? _od;
  int? _do;
  int _zahtjev = 0;

  // Period kartice: poslovna godina (podrazumijevano tekuća) ili ručno
  // izabran period od–do. Bez oba: sve promjene, bez početnog stanja.
  int? _godina = DateTime.now().year;
  DateTimeRange? _period;
  StanjeKartice? _pocetno;
  StanjeKartice? _zavrsno;

  // Stanje (količina, vrijednost) prije prvog reda svake stranice, za tekući
  // saldo. Puni se pri učitavanju stranica; briše se pri promjeni perioda.
  final Map<int, (double, double)> _pocetakStranice = {};

  TemaSkladista get _tema => TemaSkladista.za(widget.tipSkladista ?? '');

  String get _jm => (widget.jm ?? '').isEmpty ? '' : ' ${widget.jm}';

  @override
  void initState() {
    super.initState();
    _ucitaj();
  }

  @override
  void dispose() {
    _horizontalni.dispose();
    super.dispose();
  }

  Future<void> _ucitaj([int stranica = 1]) async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;
    if (firma == null) {
      setState(() => _greska = 'Nije izabrana firma.');
      return;
    }

    setState(() {
      _ucitavanje = true;
      _greska = null;
    });

    try {
      final rezultat = await _service.fetchStockCard(
        firma.id,
        widget.articleId,
        warehouseId: widget.warehouseId,
        dateFrom: _datumOd,
        dateTo: _datumDo,
        page: stranica,
      );
      if (!mounted || zahtjev != _zahtjev) return;

      final brojStranice = rezultat.stranica;
      if (brojStranice == 1) {
        final pocetno = rezultat.pocetnoStanje;
        _pocetakStranice
          ..clear()
          ..[1] = pocetno == null
              ? (0, 0)
              : (pocetno.kolicina, pocetno.vrijednost);
      }
      final pocetak = await _pocetakZa(firma.id, brojStranice, zahtjev);
      if (pocetak == null || !mounted || zahtjev != _zahtjev) return;
      final (promjene, kraj) = tekuciSaldo(rezultat.promjene, pocetak);
      _pocetakStranice[brojStranice + 1] = kraj;

      setState(() {
        _promjene = promjene;
        _pocetno = rezultat.pocetnoStanje;
        _zavrsno = rezultat.zavrsnoStanje;
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

  // Stanje prije prvog reda stranice [stranica]. Ako nije poznato (skok na
  // stranicu bez učitavanja prethodnih), učitavaju se prethodne stranice i
  // saldo se sabira od početnog stanja. null ako je zahtjev zastario.
  Future<(double, double)?> _pocetakZa(
    int firmaId,
    int stranica,
    int zahtjev,
  ) async {
    if (_pocetakStranice.containsKey(stranica)) {
      return _pocetakStranice[stranica];
    }

    if (!_pocetakStranice.containsKey(1)) {
      final prva = await _service.fetchStockCard(
        firmaId,
        widget.articleId,
        warehouseId: widget.warehouseId,
        dateFrom: _datumOd,
        dateTo: _datumDo,
      );
      if (zahtjev != _zahtjev) return null;
      final p = prva.pocetnoStanje;
      _pocetakStranice[1] = p == null ? (0, 0) : (p.kolicina, p.vrijednost);
    }

    var poznata = stranica;
    while (!_pocetakStranice.containsKey(poznata)) {
      poznata--;
    }
    for (var s = poznata; s < stranica; s++) {
      final r = await _service.fetchStockCard(
        firmaId,
        widget.articleId,
        warehouseId: widget.warehouseId,
        dateFrom: _datumOd,
        dateTo: _datumDo,
        page: s,
      );
      if (zahtjev != _zahtjev) return null;
      final (_, kraj) = tekuciSaldo(r.promjene, _pocetakStranice[s]!);
      _pocetakStranice[s + 1] = kraj;
    }
    return _pocetakStranice[stranica];
  }

  String _dokument(PromjenaKartice p) =>
      widget.warehouseId == null && p.skladiste != null
      ? '${p.nazivDokumenta} · ${p.skladiste!.naziv}'
      : p.nazivDokumenta;

  DateTime? get _datumOd =>
      _period?.start ?? (_godina == null ? null : DateTime(_godina!, 1, 1));

  DateTime? get _datumDo =>
      _period?.end ?? (_godina == null ? null : DateTime(_godina!, 12, 31));

  String get _nazivPerioda => _period != null
      ? '${_formatDatum(_period!.start)} – ${_formatDatum(_period!.end)}'
      : _godina == null
      ? 'Sve promjene'
      : '$_godina. godina';

  // Vrijednosti menija: godina, 0 = sve promjene, -1 = ručni period.
  static const int _sve = 0;
  static const int _rucniPeriod = -1;

  Future<void> _izaberiPeriod(int izbor) async {
    int? godina;
    DateTimeRange? period;

    if (izbor == _rucniPeriod) {
      final sada = DateTime.now();
      period = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(sada.year + 1, 12, 31),
        initialDateRange:
            _period ??
            DateTimeRange(
              start: _datumOd ?? DateTime(sada.year, 1, 1),
              end: _datumDo ?? DateTime(sada.year, 12, 31),
            ),
        helpText: 'Period kartice',
        saveText: 'Primijeni',
      );
      if (period == null || !mounted) return;
    } else if (izbor != _sve) {
      godina = izbor;
    }

    if (godina == _godina && period == _period) return;
    setState(() {
      _godina = godina;
      _period = period;
      _pocetno = null;
      _zavrsno = null;
      _pocetakStranice.clear();
    });
    _ucitaj();
  }

  // Godine za izbor: poslovne godine firme (najnovija prva); ako još nisu
  // učitane, tekuća i četiri prethodne.
  List<(int, bool)> get _godine {
    final c = PoslovneGodineController.instanca;
    final godine = c?.godine ?? const [];
    if (godine.isNotEmpty) {
      return [for (final g in godine) (g.godina, g.zakljucena)];
    }
    final sada = DateTime.now().year;
    return [for (int g = sada; g > sada - 5; g--) (g, false)];
  }

  // "Početno stanje" je prvi red prve stranice, "Stanje na dan" zadnji red
  // zadnje stranice (promjene idu hronološki).
  bool get _prikaziPocetno => _pocetno != null && _stranica == 1;
  bool get _prikaziZavrsno => _zavrsno != null && _stranica >= _zadnjaStranica;

  String _nazivZavrsnog(StanjeKartice s) => s.datum == null
      ? 'Trenutno stanje'
      : 'Stanje na dan ${_formatDatum(s.datum)}';

  // Bez izabranog magacina stanja su zbir svih magacina.
  String? get _napomenaStanja =>
      widget.warehouseId == null ? 'zbir svih magacina' : null;

  // Redovi tabele/liste: početno stanje, promjene, završno stanje.
  // I bez prometa u periodu prikazuju se oba stanja (iz meta, ne računaju se
  // iz stavki).
  int get _brojRedova {
    return _promjene.length +
        (_prikaziPocetno ? 1 : 0) +
        (_prikaziZavrsno ? 1 : 0);
  }

  // (početno?, promjena, završno?) za red na poziciji i.
  Widget _redNa(
    int i, {
    required Widget Function(String naziv, StanjeKartice s, bool pocetno)
    stanje,
    required Widget Function(int index, PromjenaKartice p) promjena,
  }) {
    if (_prikaziPocetno) {
      if (i == 0) return stanje('Početno stanje', _pocetno!, true);
      i--;
    }
    if (i < _promjene.length) return promjena(i, _promjene[i]);
    return stanje(_nazivZavrsnog(_zavrsno!), _zavrsno!, false);
  }

  // ---------------------------------------------------------------------------
  // Zbirni podaci (za kartice u zaglavlju)
  // ---------------------------------------------------------------------------

  double get _ulazStranice => _promjene.fold(0, (s, p) => s + p.ulaz);

  // Stanje (količina, vrijednost) prije prve promjene na stranici: na prvoj
  // je to početno stanje, na ostalim prenos sa prethodne stranice.
  (double, double) get _prenos => _pocetakStranice[_stranica] ?? (0, 0);

  // Ulaz u zaglavlju uključuje početno stanje (prenos), kao i saldo, pa
  // važi: ulaz − izlaz = saldo.
  double get _ulazSaPrenosom => _prenos.$1 + _ulazStranice;

  // Saldo nakon zadnje promjene na ovoj stranici (null dok se ne učita).
  (double, double)? get _krajStranice => _pocetakStranice[_stranica + 1];
  double get _izlazStranice => _promjene.fold(0, (s, p) => s + p.izlaz);

  // Najnovija promjena na stranici (po datumu, pa po id-u): njen saldo je
  // stanje nakon zadnje promjene.
  PromjenaKartice? get _zadnja {
    PromjenaKartice? zadnja;
    for (final p in _promjene) {
      if (zadnja == null) {
        zadnja = p;
        continue;
      }
      final a = p.datum ?? DateTime(0);
      final b = zadnja.datum ?? DateTime(0);
      if (a.isAfter(b) || (a == b && p.id > zadnja.id)) zadnja = p;
    }
    return zadnja;
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

  // Ikona smjera promjene: zelena za ulaz, crvena za izlaz.
  Widget _ikonaVrste(PromjenaKartice p, {double velicina = 32}) {
    final ulaz = p.ulaz > 0 || (p.ulaz == 0 && p.izlaz == 0);
    final boja = ulaz ? MagacinBoje.zelena : MagacinBoje.crvena;
    return Container(
      width: velicina,
      height: velicina,
      decoration: BoxDecoration(
        color: ulaz ? MagacinBoje.zelenaSvijetlo : MagacinBoje.crvenaSvijetlo,
        borderRadius: BorderRadius.circular(velicina * 0.3),
      ),
      child: Icon(
        ulaz ? Icons.south_west_rounded : Icons.north_east_rounded,
        size: velicina * 0.5,
        color: boja,
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
          child: Text(
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

  // Količina/iznos koji je 0 prikazuje se blijedo, da se ističu promjene.
  Widget _kretanje(double vrijednost, String tekst, Color boja, double sirina) {
    final nula = vrijednost == 0;
    return _celija(
      nula ? '—' : tekst,
      sirina: sirina,
      boja: nula ? MagacinBoje.svijetlo : boja,
      tezina: nula ? FontWeight.w500 : FontWeight.w700,
    );
  }

  Widget _saldoOznaka(String tekst, double kolicina) {
    final nema = kolicina <= 0;
    final boja = nema ? MagacinBoje.crvena : MagacinBoje.zelena;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: nema ? MagacinBoje.crvenaSvijetlo : MagacinBoje.zelenaSvijetlo,
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
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              tekst,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: boja,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tabela (širok ekran)
  // ---------------------------------------------------------------------------

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
        grupa(_sirine[0] + _sirine[1] + _sirine[2] + _sirine[3]),
        grupa(
          _sirine[4] + _sirine[5] + _sirine[6],
          'Količinski',
          MagacinBoje.plava,
          Icons.scale_rounded,
        ),
        grupa(_sirine[7]),
        grupa(
          _sirine[8] + _sirine[9] + _sirine[10],
          'Vrijednosno',
          MagacinBoje.zelena,
          Icons.payments_rounded,
        ),
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
                  alignment: i == 0
                      ? Alignment.center
                      : i <= 3
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: Text(
                    _zaglavlja[i].toUpperCase(),
                    textAlign: i <= 3 ? TextAlign.left : TextAlign.right,
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

  Widget _red(int index, PromjenaKartice p) {
    return HoverRed(
      akcent: _tema.boja,
      visina: _visinaReda,
      builder: (hover) => Row(
        children: [
          _celija(
            '${(_od ?? 1) + index}',
            sirina: _sirine[0],
            poravnanje: Alignment.center,
            boja: MagacinBoje.svijetlo,
            velicina: 12,
            tezina: FontWeight.w700,
          ),
          _celija(
            _formatDatum(p.datum),
            sirina: _sirine[1],
            poravnanje: Alignment.centerLeft,
            boja: MagacinBoje.priguseno,
            velicina: 12.5,
          ),
          SizedBox(
            width: _sirine[2],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Align(
                alignment: Alignment.centerLeft,
                child: (p.brojDokumenta ?? '').isEmpty
                    ? const Text(
                        '—',
                        style: TextStyle(color: MagacinBoje.svijetlo),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: MagacinBoje.zaglavlje,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: MagacinBoje.linija),
                        ),
                        child: Text(
                          p.brojDokumenta!,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: MagacinBoje.tekst,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
              ),
            ),
          ),
          SizedBox(
            width: _sirine[3],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  _ikonaVrste(p),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _dokument(p),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _kretanje(p.ulaz, _format4(p.ulaz), MagacinBoje.zelena, _sirine[4]),
          _kretanje(p.izlaz, _format4(p.izlaz), MagacinBoje.crvena, _sirine[5]),
          SizedBox(
            width: _sirine[6],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: _saldoOznaka(_format4(p.saldoKolicina), p.saldoKolicina),
              ),
            ),
          ),
          _celija(
            '${_format(p.prosjecnaCijena)} €',
            sirina: _sirine[7],
            tezina: FontWeight.w600,
          ),
          _kretanje(
            p.vrijednostUlaz,
            '${_format(p.vrijednostUlaz)} €',
            MagacinBoje.tekst,
            _sirine[8],
          ),
          _kretanje(
            p.vrijednostIzlaz,
            '${_format(p.vrijednostIzlaz)} €',
            MagacinBoje.tekst,
            _sirine[9],
          ),
          _celija(
            '${_format(p.saldoVrijednost)} €',
            sirina: _sirine[10],
            tezina: FontWeight.w800,
            boja: MagacinBoje.naslov,
            velicina: 13.5,
          ),
        ],
      ),
    );
  }

  Widget _redStanja(String naziv, StanjeKartice s, bool pocetno) {
    final tema = _tema;
    return Container(
      height: _visinaReda,
      decoration: BoxDecoration(
        color: hoverNijansa(tema.boja, 0.06),
        border: Border(
          top: pocetno
              ? BorderSide.none
              : BorderSide(color: hoverNijansa(tema.boja, 0.25)),
          bottom: pocetno
              ? BorderSide(color: hoverNijansa(tema.boja, 0.25))
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _sirine[0],
            child: Icon(
              pocetno ? Icons.flag_outlined : Icons.flag_rounded,
              size: 16,
              color: tema.boja,
            ),
          ),
          _celija(
            _formatDatum(s.datum),
            sirina: _sirine[1],
            poravnanje: Alignment.centerLeft,
            boja: MagacinBoje.priguseno,
            velicina: 12.5,
          ),
          _celija('', sirina: _sirine[2], poravnanje: Alignment.centerLeft),
          SizedBox(
            width: _sirine[3],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    naziv,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: tema.tamna,
                    ),
                  ),
                  if (_napomenaStanja case final napomena?)
                    Text(
                      napomena,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: MagacinBoje.priguseno,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _celija('', sirina: _sirine[4]),
          _celija('', sirina: _sirine[5]),
          SizedBox(
            width: _sirine[6],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Align(
                alignment: Alignment.centerRight,
                child: _saldoOznaka(_format4(s.kolicina), s.kolicina),
              ),
            ),
          ),
          // Cijena = vrijednost / količina; prazno kad je količina 0.
          _celija(
            s.kolicina == 0 ? '' : '${_format(s.prosjecnaCijena)} €',
            sirina: _sirine[7],
            tezina: FontWeight.w600,
          ),
          _celija('', sirina: _sirine[8]),
          _celija('', sirina: _sirine[9]),
          _celija(
            '${_format(s.vrijednost)} €',
            sirina: _sirine[10],
            tezina: FontWeight.w800,
            boja: MagacinBoje.naslov,
            velicina: 13.5,
          ),
        ],
      ),
    );
  }

  Widget _karticaStanja(String naziv, StanjeKartice s, bool pocetno) {
    final tema = _tema;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: hoverNijansa(tema.boja, 0.06),
        border: const Border(
          bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
        ),
      ),
      child: Row(
        children: [
          Icon(
            pocetno ? Icons.flag_outlined : Icons.flag_rounded,
            size: 18,
            color: tema.boja,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  naziv,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: tema.tamna,
                  ),
                ),
                if (pocetno && s.datum != null)
                  Text(
                    _formatDatum(s.datum),
                    style: const TextStyle(
                      fontSize: 12,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
                if (_napomenaStanja case final napomena?)
                  Text(
                    napomena,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _saldoOznaka('${_format4(s.kolicina)}$_jm', s.kolicina),
              const SizedBox(height: 4),
              Text(
                '${_format(s.vrijednost)} €',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.naslov,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _izborGodine() {
    final tema = _tema;
    final godine = _godine;
    return PopupMenuButton<int>(
      tooltip: 'Period kartice',
      initialValue: _period != null ? _rucniPeriod : _godina ?? _sve,
      onSelected: _izaberiPeriod,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        for (final (g, zakljucena) in godine)
          PopupMenuItem(
            value: g,
            child: Row(
              children: [
                Text('$g. godina'),
                if (zakljucena) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: MagacinBoje.svijetlo,
                  ),
                ],
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _rucniPeriod,
          child: Row(
            children: [
              Icon(Icons.date_range_rounded, size: 16),
              SizedBox(width: 8),
              Text('Period od–do…'),
            ],
          ),
        ),
        const PopupMenuItem(value: _sve, child: Text('Sve promjene')),
      ],
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MagacinBoje.linija),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_rounded, size: 15, color: tema.boja),
            const SizedBox(width: 6),
            Text(
              _nazivPerioda,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: MagacinBoje.naslov,
              ),
            ),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 20,
              color: MagacinBoje.priguseno,
            ),
          ],
        ),
      ),
    );
  }

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
          for (int k = 1; k <= 3; k++)
            SizedBox(
              width: _sirine[k],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    if (k == 3) ...[
                      _skeleton(32, visina: 32),
                      const SizedBox(width: 10),
                    ],
                    _skeleton(k == 3 ? (i.isEven ? 140 : 100) : 64),
                  ],
                ),
              ),
            ),
          for (int k = 4; k <= 10; k++)
            SizedBox(
              width: _sirine[k],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _skeleton(k == 6 ? 60 : 48),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _praznoStanje() {
    final greska = _greska != null;
    final tema = _tema;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 64, horizontal: 20),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: greska ? MagacinBoje.crvenaSvijetlo : tema.svijetla,
              shape: BoxShape.circle,
              border: Border.all(
                color: (greska ? MagacinBoje.crvena : tema.boja).withValues(
                  alpha: 0.15,
                ),
                width: 8,
              ),
            ),
            child: Icon(
              greska ? Icons.error_outline_rounded : Icons.receipt_long_rounded,
              size: 30,
              color: greska ? MagacinBoje.crvena : tema.boja,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            greska ? 'Kartica se ne može učitati' : 'Nema promjena',
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
                (_datumOd == null && _datumDo == null
                    ? 'Artikal još nema ulaza ni izlaza na kartici.'
                    : 'Artikal nema ulaza ni izlaza u izabranom periodu.'),
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
        ],
      ),
    );
  }

  // Sve promjene u izabranom periodu (sve stranice) sa početnim i završnim
  // stanjem, kao na ekranu.
  Future<List<ListExcel>> _pripremiExcel() async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) throw ApiException('Nije izabrana firma.');

    final promjene = <PromjenaKartice>[];
    StanjeKartice? pocetno;
    StanjeKartice? zavrsno;
    var stranica = 1;
    var zadnja = 1;
    do {
      final r = await _service.fetchStockCard(
        firma.id,
        widget.articleId,
        warehouseId: widget.warehouseId,
        dateFrom: _datumOd,
        dateTo: _datumDo,
        page: stranica,
        perPage: 200,
      );
      if (stranica == 1) pocetno = r.pocetnoStanje;
      zavrsno = r.zavrsnoStanje;
      promjene.addAll(r.promjene);
      zadnja = r.zadnjaStranica;
      stranica++;
    } while (stranica <= zadnja);

    final saSkladistem = widget.warehouseId == null;
    double suma(double Function(PromjenaKartice) f) =>
        promjene.fold(0, (s, p) => s + f(p));

    List<Object?> redStanja(String naziv, StanjeKartice s) => [
      s.datum,
      naziv,
      null,
      if (saSkladistem) null,
      null,
      null,
      s.prosjecnaCijena,
      null,
      null,
      s.kolicina,
      s.vrijednost,
    ];

    return [
      ListExcel(
        naziv: 'Kartica',
        naslov: 'Analitička kartica: ${widget.naziv}',
        podnaslovi: [
          firma.name,
          [
            'Artikal ID ${widget.articleId}',
            if (_jm.isNotEmpty) 'JM:$_jm',
            widget.skladiste ?? 'Sva skladišta',
            'Period: $_nazivPerioda',
          ].join(' · '),
        ],
        kolone: [
          const KolonaExcel('Datum', vrsta: VrstaKolone.datum, sirina: 12),
          const KolonaExcel('Dokument', sirina: 26),
          const KolonaExcel('Broj dok.', sirina: 14),
          if (saSkladistem) const KolonaExcel('Skladište', sirina: 22),
          const KolonaExcel('Ulaz', vrsta: VrstaKolone.broj, sirina: 11),
          const KolonaExcel('Izlaz', vrsta: VrstaKolone.broj, sirina: 11),
          const KolonaExcel('Cijena', vrsta: VrstaKolone.broj, sirina: 11),
          const KolonaExcel(
            'Vrij. ulaza',
            vrsta: VrstaKolone.iznos,
            sirina: 13,
          ),
          const KolonaExcel(
            'Vrij. izlaza',
            vrsta: VrstaKolone.iznos,
            sirina: 13,
          ),
          const KolonaExcel('Saldo kol.', vrsta: VrstaKolone.broj, sirina: 12),
          const KolonaExcel(
            'Saldo vrij.',
            vrsta: VrstaKolone.iznos,
            sirina: 14,
          ),
        ],
        redovi: [
          if (pocetno != null) redStanja('Početno stanje', pocetno),
          for (final p in promjene)
            [
              p.datum,
              p.nazivDokumenta,
              p.brojDokumenta,
              if (saSkladistem) p.skladiste?.naziv,
              p.ulaz == 0 ? null : p.ulaz,
              p.izlaz == 0 ? null : p.izlaz,
              p.cijena,
              p.vrijednostUlaz == 0 ? null : p.vrijednostUlaz,
              p.vrijednostIzlaz == 0 ? null : p.vrijednostIzlaz,
              p.saldoKolicina,
              p.saldoVrijednost,
            ],
          if (zavrsno != null) redStanja(_nazivZavrsnog(zavrsno), zavrsno),
        ],
        ukupno: [
          'Ukupno promet',
          '${promjene.length} promjena',
          null,
          if (saSkladistem) null,
          suma((p) => p.ulaz),
          suma((p) => p.izlaz),
          null,
          suma((p) => p.vrijednostUlaz),
          suma((p) => p.vrijednostIzlaz),
          null,
          null,
        ],
      ),
    ];
  }

  Widget _alatnaTraka() {
    final tema = _tema;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 4),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              'Promjene na kartici',
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
          if (_ucitavanje) ...[
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: tema.boja,
              ),
            ),
            const SizedBox(width: 10),
          ],
          _izborGodine(),
          const SizedBox(width: 8),
          DugmeIzvoza(
            visina: 36,
            nazivFajla: () => 'Kartica ${widget.naziv} $_nazivPerioda'
                .replaceAll('.', '')
                .replaceAll('–', '-'),
            pripremi: _pripremiExcel,
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
      prazno: 'Nema promjena',
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

  BoxDecoration get _okvir => BoxDecoration(
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

  Widget _tabela() {
    final ukupnaSirina = _sirine.reduce((a, b) => a + b);
    final prvoUcitavanje = _ucitavanje && _promjene.isEmpty;

    return Container(
      decoration: _okvir,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _alatnaTraka(),
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
                                : _brojRedova == 0
                                ? SingleChildScrollView(
                                    child: SizedBox(
                                      width: sirina,
                                      child: _praznoStanje(),
                                    ),
                                  )
                                : AnimatedOpacity(
                                    duration: const Duration(milliseconds: 200),
                                    opacity: _ucitavanje ? 0.55 : 1,
                                    child: ListView.builder(
                                      itemCount: _brojRedova,
                                      itemBuilder: (context, i) => _redNa(
                                        i,
                                        stanje: _redStanja,
                                        promjena: _red,
                                      ),
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
  // Kartice (uzak ekran)
  // ---------------------------------------------------------------------------

  Widget _metrika(
    String naslov,
    double vrijednost,
    String tekst, {
    Color? boja,
    bool podebljano = false,
  }) {
    final nula = vrijednost == 0 && !podebljano;
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
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            nula ? '—' : tekst,
            style: TextStyle(
              fontSize: 13,
              fontWeight: podebljano ? FontWeight.w800 : FontWeight.w600,
              color: nula ? MagacinBoje.svijetlo : boja ?? MagacinBoje.tekst,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }

  Widget _karticaPromjene(int index, PromjenaKartice p) {
    final brojDokumenta = p.brojDokumenta ?? '';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _ikonaVrste(p, velicina: 36),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _dokument(p),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (brojDokumenta.isNotEmpty) 'Br. $brojDokumenta',
                        _formatDatum(p.datum),
                      ].where((t) => t.isNotEmpty).join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: MagacinBoje.priguseno,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '#${(_od ?? 1) + index}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.svijetlo,
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
                    Expanded(
                      child: _metrika(
                        'Ulaz',
                        p.ulaz,
                        _format4(p.ulaz),
                        boja: MagacinBoje.zelena,
                      ),
                    ),
                    Expanded(
                      child: _metrika(
                        'Izlaz',
                        p.izlaz,
                        _format4(p.izlaz),
                        boja: MagacinBoje.crvena,
                      ),
                    ),
                    Expanded(
                      child: _metrika(
                        'Saldo',
                        p.saldoKolicina,
                        '${_format4(p.saldoKolicina)}$_jm',
                        boja: p.saldoKolicina <= 0
                            ? MagacinBoje.crvena
                            : MagacinBoje.zelena,
                        podebljano: true,
                      ),
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
                        'Duguje',
                        p.vrijednostUlaz,
                        '${_format(p.vrijednostUlaz)} €',
                      ),
                    ),
                    Expanded(
                      child: _metrika(
                        'Potražuje',
                        p.vrijednostIzlaz,
                        '${_format(p.vrijednostIzlaz)} €',
                      ),
                    ),
                    Expanded(
                      child: _metrika(
                        'Saldo',
                        p.saldoVrijednost,
                        '${_format(p.saldoVrijednost)} €',
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
                Icons.sell_outlined,
                size: 14,
                color: MagacinBoje.svijetlo,
              ),
              const SizedBox(width: 5),
              const Flexible(
                child: Text(
                  'Prosječna nabavna cijena',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: MagacinBoje.priguseno),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_format(p.prosjecnaCijena)} €',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.naslov,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
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
                    _skeleton(80, visina: 8),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _skeleton(double.infinity, visina: 96),
        ],
      ),
    );
  }

  Widget _listaKartica() {
    final prvoUcitavanje = _ucitavanje && _promjene.isEmpty;
    return Container(
      decoration: _okvir,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _alatnaTraka(),
          const SizedBox(height: 8),
          const Divider(height: 1, color: MagacinBoje.linija),
          if (prvoUcitavanje)
            for (int i = 0; i < 4; i++) _skeletonKartica(i)
          else if (_brojRedova == 0)
            _praznoStanje()
          else
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _ucitavanje ? 0.55 : 1,
              child: Column(
                children: [
                  for (int i = 0; i < _brojRedova; i++)
                    _redNa(
                      i,
                      stanje: _karticaStanja,
                      promjena: _karticaPromjene,
                    ),
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

  Widget _staklenoDugme({
    required IconData ikona,
    required String poruka,
    required VoidCallback? onTap,
    double velicina = 44,
  }) {
    return Tooltip(
      message: poruka,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            width: velicina,
            height: velicina,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(ikona, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _cip(IconData ikona, String tekst) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikona, size: 13, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              tekst,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _zaglavlje() {
    final tema = _tema;
    final zadnja = _zadnja;
    final naStranici = _zadnjaStranica > 1 ? 'na ovoj stranici' : 'ukupno';
    final mozeNazad = Navigator.of(context).canPop();

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

          const gap = 12.0;
          final kolone = unutra >= 860 ? 4 : 2;
          final sirinaKartice = (unutra - (kolone - 1) * gap) / kolone;
          final bezIkone = sirinaKartice < 190;

          final kartice = [
            StatKartica(
              ikona: Icons.receipt_long_rounded,
              naslov: 'Promjena',
              vrijednost: '$_ukupno',
              napomena: 'na kartici',
            ),
            StatKartica(
              ikona: Icons.south_west_rounded,
              naslov: 'Ulaz',
              vrijednost: '${_format4(_ulazSaPrenosom)}$_jm',
              napomena: _prenos.$1 == 0
                  ? naStranici
                  : 'uklj. ${_stranica == 1 ? 'početno stanje' : 'prenos'} '
                        '${_format4(_prenos.$1)}',
            ),
            StatKartica(
              ikona: Icons.north_east_rounded,
              naslov: 'Izlaz',
              vrijednost: '${_format4(_izlazStranice)}$_jm',
              napomena: naStranici,
            ),
            // Na stranici koja nije zadnja saldo je stanje na kraju te
            // stranice, da bi se slagao sa ulazom i izlazom iznad.
            if (_stranica < _zadnjaStranica && _krajStranice != null)
              StatKartica(
                ikona: Icons.inventory_rounded,
                naslov: 'Saldo',
                vrijednost: '${_format4(_krajStranice!.$1)}$_jm',
                napomena: '${_format(_krajStranice!.$2)} € · kraj stranice',
                upozorenje: _krajStranice!.$1 <= 0,
              )
            else if (_zavrsno case final z?)
              StatKartica(
                ikona: Icons.inventory_rounded,
                naslov: 'Saldo',
                vrijednost: '${_format4(z.kolicina)}$_jm',
                napomena:
                    '${_format(z.vrijednost)} € · '
                    '${z.datum == null ? 'trenutno' : _formatDatum(z.datum)}',
                upozorenje: z.kolicina <= 0,
              )
            else
              StatKartica(
                ikona: Icons.inventory_rounded,
                naslov: 'Saldo',
                vrijednost: zadnja == null
                    ? '—'
                    : '${_format4(zadnja.saldoKolicina)}$_jm',
                napomena: zadnja == null
                    ? null
                    : '${_format(zadnja.saldoVrijednost)} € · '
                          '${_formatDatum(zadnja.datum)}',
                upozorenje: zadnja != null && zadnja.saldoKolicina <= 0,
              ),
          ];

          final dugmad = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _staklenoDugme(
                ikona: Icons.refresh_rounded,
                poruka: 'Osvježi',
                onTap: _ucitavanje ? null : () => _ucitaj(_stranica),
              ),
            ],
          );

          return Stack(
            children: [
              Positioned(right: -60, top: -80, child: _krug(240, 0.08)),
              Positioned(right: 140, bottom: -110, child: _krug(200, 0.06)),
              Positioned(
                right: 30,
                bottom: -20,
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 150,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
              Padding(
                padding: EdgeInsets.all(razmak),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (mozeNazad) ...[
                          _staklenoDugme(
                            ikona: Icons.arrow_back_rounded,
                            poruka: 'Nazad',
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          SizedBox(width: malo ? 12 : 16),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'ANALITIČKA KARTICA',
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
                                widget.naziv,
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
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _cip(
                                    Icons.tag_rounded,
                                    '${widget.articleId}',
                                  ),
                                  if ((widget.jm ?? '').isNotEmpty)
                                    _cip(Icons.straighten_rounded, widget.jm!),
                                  _cip(
                                    tema.ikona,
                                    widget.skladiste ?? 'Sva skladišta',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        dugmad,
                      ],
                    ),
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
            final razmak = w < 600 ? 12.0 : 24.0;
            final padding = EdgeInsets.all(razmak);
            final greska = _greska != null && _promjene.isNotEmpty;

            // Uzak ekran: cijela stranica se skroluje, promjene su kartice.
            if (w < 700) {
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

            // Nizak prozor: zaglavlje i tabela se skroluju zajedno.
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
                      child: _tabela(),
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
                  Expanded(child: _tabela()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

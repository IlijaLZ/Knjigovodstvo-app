import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../controllers/navigation_controller.dart';
import '../../controllers/niske_zalihe_controller.dart';
import '../../models/article.dart';
import '../../models/auth_models.dart';
import '../../services/articles_service.dart';
import '../../widgets/logo.dart';
import '../../widgets/magacin_ui.dart';
import '../../widgets/paginacija_widget.dart';

// Jedinice mjere iz šifarnika API-ja, prikazane kao u aplikaciji (kom, pak).
final List<String> _jediniceMjere = jediniceMjereApi.map(jmIzApi).toList();

double _parse(String text) {
  return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
}

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

String _formatKolicina(double value) {
  return value.toString().replaceAll('.', ',');
}

String? _validirajObavezno(String? value) {
  if (value == null || value.trim().isEmpty) return 'Obavezno polje';
  return null;
}

String? _validirajKolicinu(String? value) {
  if (value == null || value.trim().isEmpty) return 'Obavezno polje';
  final broj = double.tryParse(value.trim().replaceAll(',', '.'));
  if (broj == null) return 'Unesite ispravan broj';
  if (broj <= 0) return 'Mora biti veće od 0';
  return null;
}

// "50.0000" iz API-ja se u formi prikazuje kao "50", "12.5000" kao "12,5".
String _formatMinimum(double value) {
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

// Minimalna količina nije obavezna; ako je unesena mora biti broj >= 0.
String? _validirajMinimum(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final broj = double.tryParse(value.trim().replaceAll(',', '.'));
  if (broj == null) return 'Unesite ispravan broj';
  if (broj < 0) return 'Ne može biti manje od 0';
  return null;
}

final _decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'));

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
const Color _akcentTamni = Color(0xFF0B434B);
const Color _narandzasta = Color(0xFFC2410C);
const Color _narandzastaSvijetlo = Color(0xFFFFF7ED);

const _stilUnosa = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: MagacinBoje.naslov,
);

// Boja i ikona tipa artikla; iste kao kod odgovarajućeg magacina.
TemaSkladista _temaTipa(String? tip) => TemaSkladista.za(
  tip == tipGotovProizvod ? 'finished_goods' : 'raw_materials',
);

// Ispod ove širine artikli se prikazuju kao kartice umjesto tabele.
const double _sirinaTabele = 760;
const double _minSirinaTabele = 820;
const double _visinaReda = 64;

// ======================================================================
// ZAJEDNIČKI DIJELOVI DIJALOGA
// ======================================================================

// Okvir dijaloga: naslov, sadržaj koji se skroluje i dugmad na dnu.
// Na uskom ekranu zauzima cijeli ekran.
class _OkvirDijaloga extends StatelessWidget {
  final IconData ikona;
  final Color boja;
  final String naslov;
  final String? podnaslov;
  final double maxSirina;
  final bool zakljucano;
  final Widget Function(double sirina) sadrzaj;
  final Widget dugmad;
  final VoidCallback onZatvori;

  const _OkvirDijaloga({
    required this.ikona,
    required this.boja,
    required this.naslov,
    required this.sadrzaj,
    required this.dugmad,
    required this.onZatvori,
    this.podnaslov,
    this.maxSirina = 600,
    this.zakljucano = false,
  });

  Widget _zaglavlje() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: hoverNijansa(boja, 0.12),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(ikona, color: boja, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                naslov,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              if (podnaslov != null) ...[
                const SizedBox(height: 2),
                Text(
                  podnaslov!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: MagacinBoje.priguseno,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Zatvori',
          onPressed: zakljucano ? null : onZatvori,
          style: IconButton.styleFrom(
            foregroundColor: MagacinBoje.priguseno,
            hoverColor: const Color(0xFFF1F5F9),
          ),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final usko = MediaQuery.sizeOf(context).width < 600;

    if (usko) {
      return Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
                child: _zaglavlje(),
              ),
              const Divider(height: 1, color: MagacinBoje.linija),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                    child: sadrzaj(c.maxWidth - 36),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: MagacinBoje.linija)),
                ),
                child: dugmad,
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
        constraints: BoxConstraints(maxWidth: maxSirina),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 16, 18),
              child: _zaglavlje(),
            ),
            const Divider(height: 1, color: MagacinBoje.linija),
            Flexible(
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(26, 22, 26, 24),
                  child: sadrzaj(c.maxWidth - 52),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(26, 14, 26, 14),
              decoration: const BoxDecoration(
                color: MagacinBoje.zaglavlje,
                border: Border(top: BorderSide(color: MagacinBoje.linija)),
              ),
              child: dugmad,
            ),
          ],
        ),
      ),
    );
  }
}

// Dva dugmeta na dnu dijaloga; na uskom ekranu preko cijele širine.
Widget _dugmadDijaloga(
  BuildContext context, {
  required GlatkoDugme odustani,
  required GlatkoDugme potvrdi,
}) {
  if (MediaQuery.sizeOf(context).width < 600) {
    return Row(
      children: [
        Expanded(child: odustani),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: potvrdi),
      ],
    );
  }
  return Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [odustani, const SizedBox(width: 10), potvrdi],
  );
}

Widget _sekcija(
  String naslov,
  IconData ikona,
  List<Widget> sadrzaj, {
  String? opis,
}) {
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
      if (opis != null) ...[
        const SizedBox(height: 4),
        Text(
          opis,
          style: const TextStyle(fontSize: 12.5, color: MagacinBoje.priguseno),
        ),
      ],
      const SizedBox(height: 12),
      ...sadrzaj,
    ],
  );
}

// Traka sa porukom (greška, upozorenje, informacija).
Widget _traka(
  String tekst, {
  required IconData ikona,
  required Color boja,
  required Color pozadina,
  Widget? akcija,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
    decoration: BoxDecoration(
      color: pozadina,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: hoverNijansa(boja, 0.25, pozadina)),
    ),
    child: Row(
      children: [
        Icon(ikona, size: 18, color: boja),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tekst,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: boja,
            ),
          ),
        ),
        ?akcija,
      ],
    ),
  );
}

Widget _greskaTraka(String tekst) => _traka(
  tekst,
  ikona: Icons.error_outline_rounded,
  boja: MagacinBoje.crvena,
  pozadina: MagacinBoje.crvenaSvijetlo,
);

// Polje samo za prikaz (cijena, iznos) u istom stilu kao unos.
Widget _poljePrikaz(String oznaka, String vrijednost, {String? jedinica}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      OznakaPolja(oznaka),
      Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MagacinBoje.linijaSvijetla),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                vrijednost,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.tekst,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            if (jedinica != null)
              Text(
                jedinica,
                style: const TextStyle(
                  fontSize: 13,
                  color: MagacinBoje.priguseno,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

// Oznaka artikla: njegov ID (#12).
Widget _idOznaka(int? id, {double velicina = 11}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: MagacinBoje.zaglavlje,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: MagacinBoje.linija),
    ),
    child: Text(
      idArtikla(id),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: velicina,
        fontWeight: FontWeight.w700,
        color: MagacinBoje.tekst,
        fontFamily: 'monospace',
      ),
    ),
  );
}

// Lista artikala izabrane firme jednog tipa (repromaterijal ili gotov
// proizvod), sa API-ja: GET /companies/{company}/articles?type=...
class ArtikliScreen extends StatefulWidget {
  final String tip;

  const ArtikliScreen({super.key, required this.tip});

  @override
  State<ArtikliScreen> createState() => _ArtikliScreenState();
}

class _ArtikliScreenState extends State<ArtikliScreen> {
  final searchController = TextEditingController();
  final ScrollController _horizontalni = ScrollController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final ArticlesService _service = ArticlesService();
  late final Worker _firmaWorker;

  List<Artikal> artikli = [];
  bool _ucitavanje = false;
  String? _greska;

  // Paginacija sa servera (meta iz odgovora); veličinu stranice zadaje server.
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

  bool get _gotovProizvod => widget.tip == tipGotovProizvod;
  TemaSkladista get _tema => _temaTipa(widget.tip);
  bool get _imaFirmu => _firmaController.izabranaFirma.value != null;

  String get _naslov =>
      _gotovProizvod ? 'Artikli gotovih proizvoda' : 'Artikli repromaterijala';

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

  // Učitava zadatu stranicu; bez parametra kreće od prve (nova firma ili
  // pretraga).
  Future<void> _ucitaj([int stranica = 1]) async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      setState(() {
        artikli = [];
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
      final rezultat = await _service.fetchArticles(
        firma.id,
        type: widget.tip,
        page: stranica,
        search: _pretraga,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        artikli = rezultat.artikli;
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

  // Nakon brisanja zadnjeg reda na stranici vraća se na prethodnu.
  void _osvjeziStranicu({bool uklonjenRed = false}) {
    final stranica = uklonjenRed && artikli.length == 1 && _stranica > 1
        ? _stranica - 1
        : _stranica;
    _ucitaj(stranica);
  }

  Future<void> _dodajNoviArtikal() async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final noviArtikal = await showDialog<Artikal>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _ArtikalDialog(tip: widget.tip, firmaId: firma.id),
    );

    if (noviArtikal == null || !mounted) return;

    _poruka(context, 'Artikal ${noviArtikal.naziv} je dodat.');
    _ucitaj(_stranica);
    _osvjeziNiskeZalihe();
  }

  Future<void> _izmijeniArtikal(Artikal artikal) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final izmijenjen = await showDialog<Artikal>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x800F172A),
      builder: (context) =>
          _ArtikalDialog(tip: widget.tip, firmaId: firma.id, artikal: artikal),
    );

    if (izmijenjen == null || !mounted) return;

    setState(() {
      final i = artikli.indexWhere((a) => a.id == izmijenjen.id);
      if (i != -1) artikli[i] = izmijenjen;
    });
    _osvjeziNiskeZalihe();
  }

  // Promjena minimalne količine mijenja upozorenja (kružić u meniju).
  void _osvjeziNiskeZalihe() {
    if (widget.tip == tipRepromaterijal) {
      Get.find<NiskeZaliheController>().osvjezi();
    }
  }

  Future<void> _prikaziNormative(Artikal artikal) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null || artikal.id == null) return;

    final izmijenjeno = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x800F172A),
      builder: (context) =>
          _NormativiDialog(firmaId: firma.id, artikal: artikal),
    );

    // Izmjena normativa mijenja broj stavki i cijenu koštanja proizvoda.
    if (izmijenjeno == true && mounted) _ucitaj(_stranica);
  }

  Future<void> _obrisiArtikal(Artikal artikal) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null || artikal.id == null) return;

    final potvrda = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _PotvrdaBrisanja(artikal: artikal),
    );

    if (potvrda != true || !mounted) return;

    try {
      await _service.deleteArticle(firma.id, artikal.id!);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _osvjeziStranicu(uklonjenRed: true);
    _poruka(
      context,
      'Artikal ${artikal.naziv} je obrisan.',
      action: SnackBarAction(
        label: 'Poništi',
        textColor: const Color(0xFF7FE3C4),
        onPressed: () => _vratiArtikal(firma.id, artikal),
      ),
    );
  }

  Future<void> _vratiArtikal(int firmaId, Artikal artikal) async {
    try {
      await _service.restoreArticle(firmaId, artikal.id!);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _ucitaj(_stranica);
    _poruka(context, 'Artikal ${artikal.naziv} je vraćen.');
  }

  // ---------------------------------------------------------------------------
  // Sitni elementi
  // ---------------------------------------------------------------------------

  // Cijena za prikaz: repromaterijal prosječna nabavna, gotov proizvod
  // cijena koštanja po normativu.
  String? _cijena(Artikal a) =>
      a.cijena != null ? '${_format(a.cijenaNormativa)} €' : null;

  Widget _znak(Artikal a, {double v = 38}) {
    final tema = _tema;
    final naziv = a.naziv.trim();
    return Container(
      width: v,
      height: v,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tema.svijetla,
        borderRadius: BorderRadius.circular(v * 0.3),
      ),
      child: Text(
        naziv.isEmpty ? '?' : naziv.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: v * 0.4,
          fontWeight: FontWeight.w800,
          color: tema.tamna,
        ),
      ),
    );
  }

  Widget _jmOznaka(String jm) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: MagacinBoje.zaglavlje,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MagacinBoje.linija),
      ),
      child: Text(
        jm.isEmpty ? '—' : jm,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: MagacinBoje.tekst,
        ),
      ),
    );
  }

  // Broj stavki normativa; klik otvara normative.
  Widget _normativOznaka(Artikal a) {
    final poznat = a.poznatBrojNormativa;
    final broj = a.brojNormativa;
    final tekst = !poznat
        ? 'Prikaži'
        : broj == 1
        ? '1 stavka'
        : broj >= 2 && broj <= 4
        ? '$broj stavke'
        : '$broj stavki';
    final bez = poznat && broj == 0;
    return Tooltip(
      message: 'Normativ',
      child: InkWell(
        onTap: () => _prikaziNormative(a),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: bez ? _narandzastaSvijetlo : _akcentSvijetlo,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                bez ? Icons.warning_amber_rounded : Icons.account_tree_rounded,
                size: 13,
                color: bez ? _narandzasta : _akcent,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  bez ? 'Bez normativa' : tekst,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: bez ? _narandzasta : _akcentTamni,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _akcije(Artikal a) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_gotovProizvod) ...[
          IkonaAkcija(
            ikona: Icons.account_tree_rounded,
            poruka: 'Normativ',
            boja: _tema.boja,
            onTap: () => _prikaziNormative(a),
          ),
          const SizedBox(width: 6),
        ],
        IkonaAkcija(
          ikona: Icons.edit_rounded,
          poruka: 'Izmijeni',
          boja: _akcent,
          onTap: () => _izmijeniArtikal(a),
        ),
        const SizedBox(width: 6),
        IkonaAkcija(
          ikona: Icons.delete_outline_rounded,
          poruka: 'Obriši',
          boja: MagacinBoje.crvena,
          onTap: () => _obrisiArtikal(a),
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

  // Kolone: (naziv, flex).
  List<(String, int)> get _kolone => _gotovProizvod
      ? const [
          ('Artikal', 34),
          ('Jedinica mjere', 11),
          ('Normativ', 18),
          ('Cijena koštanja', 16),
          ('', 18),
        ]
      : const [
          ('Artikal', 40),
          ('Jedinica mjere', 12),
          ('Prosječna nabavna cijena', 16),
          ('', 13),
        ];

  Widget _celijaKolone(int i, Widget dijete) {
    final kolone = _kolone;
    final desno = i >= kolone.length - 2;
    return Expanded(
      flex: kolone[i].$2,
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
    final kolone = _kolone;
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
          for (int i = 0; i < kolone.length; i++)
            _celijaKolone(
              i,
              Text(
                kolone[i].$1.toUpperCase(),
                maxLines: 2,
                textAlign: i >= kolone.length - 2
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

  Widget _red(Artikal a) {
    final cijena = _cijena(a);
    return HoverRed(
      akcent: _tema.boja,
      visina: _visinaReda,
      // Brojač kolona mora biti unutar builder-a: builder se ponovo poziva
      // na svaki hover, pa bi brojač izvan njega nastavio od zadnje kolone.
      builder: (hover) {
        int i = 0;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _celijaKolone(
                i++,
                Row(
                  children: [
                    _znak(a),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.naziv,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: MagacinBoje.naslov,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _idOznaka(a.id, velicina: 10.5),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _celijaKolone(i++, _jmOznaka(a.jm)),
              if (_gotovProizvod) _celijaKolone(i++, _normativOznaka(a)),
              _celijaKolone(
                i++,
                Text(
                  cijena ?? '—',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: cijena == null
                        ? FontWeight.w500
                        : FontWeight.w800,
                    color: cijena == null
                        ? MagacinBoje.svijetlo
                        : MagacinBoje.naslov,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _celijaKolone(i++, _akcije(a)),
            ],
          ),
        );
      },
    );
  }

  Widget _skeletonRed(int r) {
    final kolone = _kolone;
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
                _skeleton(38, visina: 38),
                const SizedBox(width: 12),
                _skeleton(r.isEven ? 160 : 110),
              ],
            ),
          ),
          for (int k = 1; k < kolone.length - 1; k++)
            _celijaKolone(k, _skeleton(56, visina: 20)),
          _celijaKolone(kolone.length - 1, _skeleton(80, visina: 30)),
        ],
      ),
    );
  }

  Widget _tabela(double sirina) {
    final sirinaTabele = sirina < _minSirinaTabele ? _minSirinaTabele : sirina;
    final prvo = _ucitavanje && artikli.isEmpty;

    Widget sadrzaj = SizedBox(
      width: sirinaTabele,
      child: Column(
        children: [
          _zaglavljeTabele(),
          if (prvo)
            for (int i = 0; i < 6; i++) _skeletonRed(i)
          else if (artikli.isEmpty)
            SizedBox(width: sirina, child: _praznoStanje())
          else
            AnimatedOpacity(
              duration: hoverTrajanje,
              opacity: _ucitavanje ? 0.55 : 1,
              child: Column(children: [for (final a in artikli) _red(a)]),
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

  Widget _kartica(Artikal a) {
    final cijena = _cijena(a);
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _znak(a, v: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      a.naziv,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _idOznaka(a.id),
                        _jmOznaka(a.jm),
                        if (_gotovProizvod) _normativOznaka(a),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: MagacinBoje.zaglavlje,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _gotovProizvod
                        ? 'Cijena koštanja'
                        : 'Prosječna nabavna cijena',
                    style: const TextStyle(
                      fontSize: 12,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
                ),
                Text(
                  cijena ?? '—',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: cijena == null
                        ? MagacinBoje.svijetlo
                        : MagacinBoje.naslov,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: _akcije(a)),
        ],
      ),
    );
  }

  Widget _kartice() {
    if (_ucitavanje && artikli.isEmpty) {
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
    if (artikli.isEmpty) {
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
          for (final a in artikli)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _kartica(a),
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
            'Izaberite firmu u gornjem desnom uglu da vidite artikle.',
          )
        : greska
        ? (Icons.error_outline_rounded, 'Artikli se ne mogu učitati', _greska!)
        : pretraga
        ? (
            Icons.search_off_rounded,
            'Nema rezultata',
            'Nijedan artikal ne odgovara pretrazi "$_pretraga".',
          )
        : (
            tema.ikona,
            'Još nema artikala',
            _gotovProizvod
                ? 'Dodajte prvi gotov proizvod zajedno sa njegovim normativom.'
                : 'Dodajte prvi artikal repromaterijala.',
          );

    final boja = greska ? MagacinBoje.crvena : tema.boja;
    final pozadina = greska ? MagacinBoje.crvenaSvijetlo : tema.svijetla;

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
                tekst: 'Dodaj artikal',
                ikona: Icons.add_rounded,
                onTap: _dodajNoviArtikal,
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
      prazno: 'Nema artikala',
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
      style: _stilUnosa,
      decoration: dekoracijaPolja(
        hint: 'Pretraži po nazivu…',
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
      children: [
        Container(
          width: malo ? 44 : 50,
          height: malo ? 44 : 50,
          decoration: BoxDecoration(
            color: tema.svijetla,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(tema.ikona, color: tema.boja, size: malo ? 22 : 25),
        ),
        SizedBox(width: malo ? 12 : 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _naslov,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: malo ? 20 : 23,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _gotovProizvod
                    ? 'Proizvodi sa normativom sirovina i cijenom koštanja'
                    : 'Sirovine i materijal sa prosječnom nabavnom cijenom',
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
      ],
    );
  }

  Widget _zaglavlje() {
    final tema = _tema;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final malo = w < 600;
        final razmak = malo ? 16.0 : 22.0;

        final prekidac = _PrekidacTipa(
          tip: widget.tip,
          puno: w < 820,
          onIzaberi: (tip) {
            final nav = Get.find<NavigationController>();
            tip == tipGotovProizvod
                ? nav.openArtikliGotovihProizvoda()
                : nav.openArtikliRepromaterijala();
          },
        );

        final dodaj = GlatkoDugme(
          tekst: 'Dodaj artikal',
          ikona: Icons.add_rounded,
          visina: 48,
          onTap: _imaFirmu ? _dodajNoviArtikal : null,
        );

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: MagacinBoje.linija),
            boxShadow: const [
              BoxShadow(
                color: Color(0x080F172A),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
              BoxShadow(
                color: Color(0x0A0F172A),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tanka traka u boji tipa artikla.
              AnimatedContainer(
                duration: hoverTrajanje,
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tema.boja, hoverNijansa(tema.boja, 0.35)],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(razmak, razmak, razmak, 16),
                child: w >= 820
                    ? Row(
                        children: [
                          Expanded(child: _naslovStranice(malo: false)),
                          const SizedBox(width: 20),
                          prekidac,
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _naslovStranice(malo: malo),
                          const SizedBox(height: 14),
                          prekidac,
                        ],
                      ),
              ),
              const Divider(height: 1, color: MagacinBoje.linijaSvijetla),
              Container(
                color: const Color(0xFFFCFDFE),
                padding: EdgeInsets.fromLTRB(razmak, 16, razmak, razmak),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (w >= 560)
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
                ),
              ),
            ],
          ),
        );
      },
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
              'Svi artikli',
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
                  if (_greska != null && artikli.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _traka(
                        _greska!,
                        ikona: Icons.error_outline_rounded,
                        boja: MagacinBoje.crvena,
                        pozadina: MagacinBoje.crvenaSvijetlo,
                        akcija: TextButton(
                          onPressed: _ucitavanje
                              ? null
                              : () => _ucitaj(_stranica),
                          style: TextButton.styleFrom(
                            foregroundColor: MagacinBoje.crvena,
                          ),
                          child: const Text('Pokušaj ponovo'),
                        ),
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
// POTVRDA BRISANJA ARTIKLA
// ======================================================================
class _PotvrdaBrisanja extends StatelessWidget {
  final Artikal artikal;

  const _PotvrdaBrisanja({required this.artikal});

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
                'Obriši artikal?',
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
                    const TextSpan(text: 'Artikal '),
                    TextSpan(
                      text: nazivSaId(artikal.id, artikal.naziv),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' će biti obrisan. Brisanje možete poništiti odmah '
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
// TABELA NORMATIVA (prikaz u dijalogu)
// Ako je onIzmijeni/onObrisi != null, svaki red ima dugme za tu akciju.
// Na uskom prostoru stavke su prikazane kao lista umjesto tabele.
// ======================================================================
class _NormativiTabela extends StatelessWidget {
  final List<Normativ> normativi;
  final ValueChanged<Normativ>? onIzmijeni;
  final ValueChanged<Normativ>? onObrisi;

  const _NormativiTabela({
    required this.normativi,
    this.onIzmijeni,
    this.onObrisi,
  });

  bool get _akcije => onIzmijeni != null || onObrisi != null;

  Widget _naziv(Normativ n) {
    if (n.jePovezan) {
      return Text(
        n.naziv,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: MagacinBoje.naslov,
        ),
      );
    }
    return Tooltip(
      message:
          'Stavka nije povezana sa sirovinom. '
          'Izaberite sirovinu preko izmjene stavke.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            n.naziv.isEmpty ? '—' : n.naziv,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: MagacinBoje.naslov,
            ),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _narandzastaSvijetlo,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: hoverNijansa(_narandzasta, 0.25)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off_rounded, size: 12, color: _narandzasta),
                SizedBox(width: 4),
                Text(
                  'Nepovezano',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _narandzasta,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _akcijeStavke(Normativ n) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onIzmijeni != null)
          IkonaAkcija(
            ikona: n.jePovezan ? Icons.edit_rounded : Icons.link_rounded,
            poruka: n.jePovezan ? 'Izmijeni stavku' : 'Poveži sa sirovinom',
            boja: n.jePovezan ? _akcent : _narandzasta,
            onTap: () => onIzmijeni!(n),
          ),
        if (onIzmijeni != null && onObrisi != null) const SizedBox(width: 6),
        if (onObrisi != null)
          IkonaAkcija(
            ikona: Icons.delete_outline_rounded,
            poruka: 'Ukloni stavku',
            boja: MagacinBoje.crvena,
            onTap: () => onObrisi!(n),
          ),
      ],
    );
  }

  static const _brojStil = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: MagacinBoje.tekst,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _tabela(double ukupno) {
    Widget celija(int flex, Widget dijete, {bool desno = false}) => Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: desno ? Alignment.centerRight : Alignment.centerLeft,
          child: dijete,
        ),
      ),
    );

    Widget zaglavlje(String t) => Text(
      t.toUpperCase(),
      style: const TextStyle(
        fontSize: 10,
        letterSpacing: 0.9,
        fontWeight: FontWeight.w800,
        color: MagacinBoje.priguseno,
      ),
    );

    return Column(
      children: [
        Container(
          height: 40,
          color: MagacinBoje.zaglavlje,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              celija(34, zaglavlje('Sirovina')),
              celija(16, zaglavlje('Cijena'), desno: true),
              celija(18, zaglavlje('Količina'), desno: true),
              celija(16, zaglavlje('Iznos'), desno: true),
              if (_akcije) const SizedBox(width: 96),
            ],
          ),
        ),
        for (final n in normativi)
          Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: n.jePovezan ? Colors.white : _narandzastaSvijetlo,
              border: const Border(
                top: BorderSide(color: MagacinBoje.linijaSvijetla),
              ),
            ),
            child: Row(
              children: [
                celija(34, _naziv(n)),
                celija(
                  16,
                  Text('${_format(n.cijena)} €', style: _brojStil),
                  desno: true,
                ),
                celija(
                  18,
                  Text(
                    '${_formatKolicina(n.kolicina)} ${n.jm}',
                    style: _brojStil,
                  ),
                  desno: true,
                ),
                celija(
                  16,
                  Text(
                    '${_format(n.iznos)} €',
                    style: _brojStil.copyWith(
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                  desno: true,
                ),
                if (_akcije)
                  SizedBox(
                    width: 96,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: _akcijeStavke(n),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        _ukupnoRed(ukupno),
      ],
    );
  }

  Widget _lista(double ukupno) {
    return Column(
      children: [
        for (final n in normativi)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: n.jePovezan ? Colors.white : _narandzastaSvijetlo,
              border: const Border(
                bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _naziv(n),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatKolicina(n.kolicina)} ${n.jm} × '
                        '${_format(n.cijena)} €',
                        style: const TextStyle(
                          fontSize: 12,
                          color: MagacinBoje.priguseno,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${_format(n.iznos)} €',
                      style: _brojStil.copyWith(
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    if (_akcije) ...[
                      const SizedBox(height: 6),
                      _akcijeStavke(n),
                    ],
                  ],
                ),
              ],
            ),
          ),
        _ukupnoRed(ukupno),
      ],
    );
  }

  Widget _ukupnoRed(double ukupno) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: _akcentSvijetlo,
        border: Border(top: BorderSide(color: MagacinBoje.linija)),
      ),
      child: Row(
        children: [
          const Icon(Icons.functions_rounded, size: 16, color: _akcent),
          const SizedBox(width: 6),
          const Expanded(
            child: Text(
              'Ukupno po normativu',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _akcentTamni,
              ),
            ),
          ),
          Text(
            '${_format(ukupno)} €',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _akcentTamni,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ukupno = normativi.fold<double>(0, (suma, n) => suma + n.iznos);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MagacinBoje.linija),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, c) =>
            c.maxWidth >= 640 ? _tabela(ukupno) : _lista(ukupno),
      ),
    );
  }
}

// ======================================================================
// POLJE ZA IZBOR SIROVINE: prikazuje izabranu sirovinu, a klik otvara
// pretragu repromaterijala (_IzborSirovineDialog).
// ======================================================================
class _SirovinaPolje extends StatefulWidget {
  final int firmaId;
  final String? naziv;
  final Set<int> zauzete;
  final String? errorText;
  final bool enabled;
  final ValueChanged<Artikal> onIzaberi;

  const _SirovinaPolje({
    required this.firmaId,
    required this.naziv,
    required this.onIzaberi,
    this.zauzete = const {},
    this.errorText,
    this.enabled = true,
  });

  @override
  State<_SirovinaPolje> createState() => _SirovinaPoljeState();
}

class _SirovinaPoljeState extends State<_SirovinaPolje> {
  bool _hover = false;

  Future<void> _otvori() async {
    final sirovina = await showDialog<Artikal>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (_) => _IzborSirovineDialog(
        firmaId: widget.firmaId,
        zauzete: widget.zauzete,
      ),
    );
    if (sirovina != null) widget.onIzaberi(sirovina);
  }

  @override
  Widget build(BuildContext context) {
    final greska = widget.errorText != null;
    final prazno = widget.naziv == null;
    final aktivno = widget.enabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OznakaPolja('Sirovina', obavezno: true),
        MouseRegion(
          cursor: aktivno ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: aktivno ? _otvori : null,
            child: AnimatedContainer(
              duration: hoverTrajanje,
              curve: hoverKriva,
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: !aktivno
                    ? const Color(0xFFF1F5F9)
                    : _hover
                    ? const Color(0xFFF1F5F9)
                    : MagacinBoje.zaglavlje,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: greska
                      ? hoverNijansa(MagacinBoje.crvena, 0.5)
                      : _hover && aktivno
                      ? const Color(0xFFCBD5E1)
                      : MagacinBoje.linija,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 19,
                    color: greska ? MagacinBoje.crvena : MagacinBoje.svijetlo,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.naziv ?? 'Izaberite sirovinu…',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: prazno
                          ? const TextStyle(
                              fontSize: 14,
                              color: MagacinBoje.svijetlo,
                            )
                          : _stilUnosa,
                    ),
                  ),
                  const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: MagacinBoje.priguseno,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (greska)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 6),
            child: Text(
              widget.errorText!,
              style: const TextStyle(fontSize: 12, color: MagacinBoje.crvena),
            ),
          ),
      ],
    );
  }
}

// ======================================================================
// DIJALOG: izbor sirovine za stavku normativa
// GET /companies/{company}/articles?type=raw_material&search=...&per_page=20
// Sirovine koje su već u normativu se ne mogu ponovo izabrati.
// ======================================================================
class _IzborSirovineDialog extends StatefulWidget {
  final int firmaId;
  final Set<int> zauzete;

  const _IzborSirovineDialog({required this.firmaId, this.zauzete = const {}});

  @override
  State<_IzborSirovineDialog> createState() => _IzborSirovineDialogState();
}

class _IzborSirovineDialogState extends State<_IzborSirovineDialog> {
  final ArticlesService _service = ArticlesService();
  final pretragaController = TextEditingController();

  List<Artikal> _rezultati = [];
  bool _ucitavanje = false;
  String? _greska;
  Timer? _timer;
  int _zahtjev = 0;

  @override
  void initState() {
    super.initState();
    _trazi();
  }

  @override
  void dispose() {
    _timer?.cancel();
    pretragaController.dispose();
    super.dispose();
  }

  void _promjenaPretrage(String _) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), _trazi);
  }

  Future<void> _trazi() async {
    final zahtjev = ++_zahtjev;
    setState(() {
      _ucitavanje = true;
      _greska = null;
    });

    try {
      final sirovine = await _service.fetchMaterials(
        widget.firmaId,
        search: pretragaController.text,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _rezultati = sirovine);
    } on ApiException catch (e) {
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        _rezultati = [];
        _greska = e.message;
      });
    } finally {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _ucitavanje = false);
      }
    }
  }

  Widget _stavka(Artikal sirovina) {
    final zauzeta = widget.zauzete.contains(sirovina.id);
    final tema = _temaTipa(tipRepromaterijal);
    return _HoverStavka(
      enabled: !zauzeta,
      onTap: () => Navigator.of(context).pop(sirovina),
      child: Opacity(
        opacity: zauzeta ? 0.5 : 1,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tema.svijetla,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                sirovina.naziv.trim().isEmpty
                    ? '?'
                    : sirovina.naziv.trim().characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: tema.tamna,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sirovina.naziv,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _idOznaka(sirovina.id, velicina: 10.5),
                      Text(
                        sirovina.cijena != null
                            ? '${_format(sirovina.cijena!)} € / ${sirovina.jm}'
                            : sirovina.jm,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MagacinBoje.priguseno,
                        ),
                      ),
                      if (zauzeta)
                        const Text(
                          '· već u normativu',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _narandzasta,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!zauzeta)
              const Icon(
                Icons.chevron_right_rounded,
                color: MagacinBoje.svijetlo,
              ),
          ],
        ),
      ),
    );
  }

  Widget _lista() {
    if (_greska != null) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: _greskaTraka(_greska!),
      );
    }
    if (_ucitavanje && _rezultati.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _akcent),
          ),
        ),
      );
    }
    if (_rezultati.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, color: MagacinBoje.svijetlo),
            SizedBox(height: 8),
            Text(
              'Nema sirovina za ovu pretragu.',
              textAlign: TextAlign.center,
              style: TextStyle(color: MagacinBoje.priguseno),
            ),
          ],
        ),
      );
    }

    return AnimatedOpacity(
      duration: hoverTrajanje,
      opacity: _ucitavanje ? 0.55 : 1,
      child: ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: _rezultati.length,
        itemBuilder: (context, index) => _stavka(_rezultati[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visina = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Izaberi sirovinu',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zatvori',
                    onPressed: () => Navigator.of(context).pop(),
                    style: IconButton.styleFrom(
                      foregroundColor: MagacinBoje.priguseno,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: TextField(
                controller: pretragaController,
                autofocus: true,
                onChanged: _promjenaPretrage,
                style: _stilUnosa,
                decoration: dekoracijaPolja(
                  hint: 'Naziv sirovine…',
                  ikona: Icons.search_rounded,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: MagacinBoje.linija),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (visina * 0.5).clamp(200.0, 380.0),
              ),
              child: Padding(padding: const EdgeInsets.all(8), child: _lista()),
            ),
          ],
        ),
      ),
    );
  }
}

// Stavka liste sa glatkim hoverom.
class _HoverStavka extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;

  const _HoverStavka({
    required this.enabled,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HoverStavka> createState() => _HoverStavkaState();
}

class _HoverStavkaState extends State<_HoverStavka> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final h = _hover && widget.enabled;
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: hoverTrajanje,
          curve: hoverKriva,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: h ? const Color(0xFFF1F5F9) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ======================================================================
// UNOS STAVKE NORMATIVA: sirovina i količina. Naziv, cijenu i JM server
// preuzima od sirovine; ovdje se prikazuju samo informativno. onDodaj
// vraća true kad je stavka prihvaćena, pa se polja prazne.
// ======================================================================
class _NormativUnos extends StatefulWidget {
  final int firmaId;
  final Set<int> zauzete;
  final bool enabled;
  final Future<bool> Function(Normativ) onDodaj;

  const _NormativUnos({
    required this.firmaId,
    required this.onDodaj,
    this.zauzete = const {},
    this.enabled = true,
  });

  @override
  State<_NormativUnos> createState() => _NormativUnosState();
}

class _NormativUnosState extends State<_NormativUnos> {
  final _formKey = GlobalKey<FormState>();
  final kolicinaController = TextEditingController();
  Artikal? _sirovina;
  String? _greskaSirovine;

  double get _cijena => _sirovina?.cijena ?? 0;

  double get _iznos => _cijena * _parse(kolicinaController.text);

  @override
  void initState() {
    super.initState();
    // Iznos se osvježava dok korisnik kuca.
    kolicinaController.addListener(_osvjezi);
  }

  @override
  void dispose() {
    kolicinaController.dispose();
    super.dispose();
  }

  void _osvjezi() => setState(() {});

  Future<void> _dodaj() async {
    if (!widget.enabled) return;

    final sirovina = _sirovina;
    setState(() {
      _greskaSirovine = sirovina == null
          ? 'Izaberite sirovinu'
          : widget.zauzete.contains(sirovina.id)
          ? 'Sirovina je već u normativu'
          : null;
    });

    final kolicinaOk = _formKey.currentState!.validate();
    if (sirovina == null || _greskaSirovine != null || !kolicinaOk) return;

    final dodato = await widget.onDodaj(
      Normativ(
        materialId: sirovina.id,
        naziv: sirovina.naziv,
        cijena: _cijena,
        kolicina: _parse(kolicinaController.text),
        jm: sirovina.jm,
      ),
    );

    if (!dodato || !mounted) return;
    setState(() => _sirovina = null);
    kolicinaController.clear();
  }

  @override
  Widget build(BuildContext context) {
    const broj = TextInputType.numberWithOptions(decimal: true);
    final sirovina = _sirovina;

    final polje = _SirovinaPolje(
      firmaId: widget.firmaId,
      naziv: sirovina == null ? null : nazivSaId(sirovina.id, sirovina.naziv),
      zauzete: widget.zauzete,
      enabled: widget.enabled,
      errorText: _greskaSirovine,
      onIzaberi: (s) => setState(() {
        _sirovina = s;
        _greskaSirovine = null;
      }),
    );

    final kolicina = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OznakaPolja('Količina', obavezno: true),
        TextFormField(
          controller: kolicinaController,
          enabled: widget.enabled,
          keyboardType: broj,
          inputFormatters: [_decimalFormatter],
          style: _stilUnosa,
          decoration: dekoracijaPolja(
            hint: '0',
          ).copyWith(suffixText: sirovina?.jm),
          validator: _validirajKolicinu,
          onFieldSubmitted: (_) => _dodaj(),
        ),
      ],
    );

    final cijena = _poljePrikaz(
      'Cijena',
      sirovina?.cijena == null ? '—' : _format(sirovina!.cijena!),
      jedinica: '€',
    );
    final iznos = _poljePrikaz('Iznos', _format(_iznos), jedinica: '€');

    final dugme = GlatkoDugme(
      tekst: 'Dodaj stavku',
      ikona: Icons.add_rounded,
      vrsta: VrstaDugmeta.sekundarno,
      visina: 48,
      onTap: widget.enabled ? _dodaj : null,
    );

    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: MagacinBoje.linija),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            // Široko: sve u jednom redu. Usko: sirovina, pa količina/cijena/
            // iznos, pa dugme preko cijele širine.
            if (c.maxWidth >= 700) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 34, child: polje),
                  const SizedBox(width: 12),
                  Expanded(flex: 16, child: kolicina),
                  const SizedBox(width: 12),
                  Expanded(flex: 14, child: cijena),
                  const SizedBox(width: 12),
                  Expanded(flex: 14, child: iznos),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 25),
                    child: dugme,
                  ),
                ],
              );
            }
            final tri = c.maxWidth >= 420;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                polje,
                const SizedBox(height: 12),
                if (tri)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: kolicina),
                      const SizedBox(width: 10),
                      Expanded(child: cijena),
                      const SizedBox(width: 10),
                      Expanded(child: iznos),
                    ],
                  )
                else ...[
                  kolicina,
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: cijena),
                      const SizedBox(width: 10),
                      Expanded(child: iznos),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                dugme,
              ],
            );
          },
        ),
      ),
    );
  }
}

// ======================================================================
// POP UP: DODAJ / IZMIJENI ARTIKAL
// Gotov proizvod se kreira zajedno sa normativom (bar jedna stavka);
// repromaterijal nema normativ. Pri izmjeni se mijenjaju samo šifra, naziv
// i JM — normativ se uređuje posebno.
// Vraća sačuvani Artikal ili null ako korisnik odustane.
// ======================================================================
class _ArtikalDialog extends StatefulWidget {
  final String tip;
  final int firmaId;
  final Artikal? artikal;

  const _ArtikalDialog({
    required this.tip,
    required this.firmaId,
    this.artikal,
  });

  @override
  State<_ArtikalDialog> createState() => _ArtikalDialogState();
}

class _ArtikalDialogState extends State<_ArtikalDialog> {
  final _artikalFormKey = GlobalKey<FormState>();
  final ArticlesService _service = ArticlesService();

  late final sifraController = TextEditingController(
    text: widget.artikal?.sifra,
  );
  late final nazivController = TextEditingController(
    text: widget.artikal?.naziv,
  );
  late String _jm =
      widget.artikal?.jm ?? (_saNormativom ? jmIzApi('pcs') : 'kg');
  late final minimumController = TextEditingController(
    text: widget.artikal?.minimalnaKolicina == null
        ? ''
        : _formatMinimum(widget.artikal!.minimalnaKolicina!),
  );

  final List<Normativ> _normativi = [];
  bool _prikaziGreskuNormativa = false;

  bool _cuvanje = false;
  ApiException? _greska;

  bool get _izmjena => widget.artikal != null;

  bool get _saNormativom => !_izmjena && widget.tip == tipGotovProizvod;

  bool get _repromaterijal => widget.tip == tipRepromaterijal;

  // Minimalna količina sa servera; lista artikala je ne mora vratiti, pa se
  // kod izmjene repromaterijala čita iz detalja artikla.
  late double? _pocetniMinimum = widget.artikal?.minimalnaKolicina;
  bool _ucitavanjeMinimuma = false;

  @override
  void initState() {
    super.initState();
    if (_izmjena && _repromaterijal) _ucitajMinimum();
  }

  // GET /companies/{company}/articles/{article} — minimum_quantity iz detalja.
  Future<void> _ucitajMinimum() async {
    final pocetniTekst = minimumController.text;
    setState(() => _ucitavanjeMinimuma = true);

    try {
      final detalj = await _service.fetchArticle(
        widget.firmaId,
        widget.artikal!.id!,
      );
      if (!mounted) return;
      _pocetniMinimum = detalj.minimalnaKolicina;
      // Ne gazi ono što je korisnik već počeo kucati.
      if (minimumController.text == pocetniTekst) {
        minimumController.text = _pocetniMinimum == null
            ? ''
            : _formatMinimum(_pocetniMinimum!);
      }
    } catch (_) {
      // Ostaje vrijednost iz liste.
    } finally {
      if (mounted) setState(() => _ucitavanjeMinimuma = false);
    }
  }

  // Prazno polje = bez praga (null).
  double? get _minimum {
    final tekst = minimumController.text.trim().replaceAll(',', '.');
    return tekst.isEmpty ? null : double.tryParse(tekst);
  }

  @override
  void dispose() {
    sifraController.dispose();
    nazivController.dispose();
    minimumController.dispose();
    super.dispose();
  }

  // Greška sa servera nestaje čim se polje mijenja; inače bi forma ostala
  // nevalidna i nakon ispravke.
  void _ocistiGresku() {
    if (_greska != null) setState(() => _greska = null);
  }

  Future<bool> _dodajNormativ(Normativ normativ) async {
    setState(() {
      _normativi.add(normativ);
      _prikaziGreskuNormativa = false;
      _greska = null;
    });
    return true;
  }

  Future<void> _sacuvaj() async {
    if (_ucitavanjeMinimuma) return;
    final artikalOk = _artikalFormKey.currentState!.validate();

    setState(() {
      _prikaziGreskuNormativa = _saNormativom && _normativi.isEmpty;
    });

    if (!artikalOk || _prikaziGreskuNormativa) return;

    setState(() {
      _cuvanje = true;
      _greska = null;
    });

    final sifra = sifraController.text.trim();
    final naziv = nazivController.text.trim();

    try {
      final Artikal sacuvan;
      final stari = widget.artikal;

      if (stari == null) {
        sacuvan = await _service.createArticle(
          widget.firmaId,
          type: widget.tip,
          code: sifra.isEmpty ? null : sifra,
          name: naziv,
          unitOfMeasure: _jm,
          minimumQuantity: _repromaterijal ? _minimum : null,
          bomItems: _normativi,
        );
      } else {
        // Šalju se samo izmijenjena polja.
        sacuvan = await _service.updateArticle(
          widget.firmaId,
          stari.id!,
          izmijenjenaSifra: sifra != stari.sifra,
          code: sifra.isEmpty ? null : sifra,
          name: naziv != stari.naziv ? naziv : null,
          unitOfMeasure: _jm != stari.jm ? _jm : null,
          izmijenjenMinimum: _repromaterijal && _minimum != _pocetniMinimum,
          minimumQuantity: _minimum,
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

  Widget _tekstPolje(
    String oznaka,
    TextEditingController controller,
    String apiPolje, {
    required int maxLength,
    required IconData ikona,
    String? hint,
    bool obavezno = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OznakaPolja(oznaka, obavezno: obavezno),
        TextFormField(
          controller: controller,
          maxLength: maxLength,
          enabled: !_cuvanje,
          textInputAction: TextInputAction.next,
          style: _stilUnosa,
          decoration: dekoracijaPolja(hint: hint, ikona: ikona),
          forceErrorText: _greska?.fieldError(apiPolje),
          onChanged: (_) => _ocistiGresku(),
          validator: obavezno ? _validirajObavezno : null,
        ),
      ],
    );
  }

  Widget _minimumPolje() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OznakaPolja('Minimalna količina'),
        TextFormField(
          controller: minimumController,
          enabled: !_cuvanje && !_ucitavanjeMinimuma,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_decimalFormatter],
          style: _stilUnosa,
          decoration: dekoracijaPolja(
            hint: _ucitavanjeMinimuma ? 'Učitavanje…' : 'npr. 100 ($_jm)',
            ikona: Icons.notifications_active_outlined,
          ),
          forceErrorText: _greska?.fieldError('minimum_quantity'),
          onChanged: (_) => _ocistiGresku(),
          validator: _validirajMinimum,
        ),
        const SizedBox(height: 6),
        const Text(
          'Kad količina na stanju padne ispod ovog praga, artikal se '
          'prikazuje kao upozorenje. Ostavite prazno ako ne treba.',
          style: TextStyle(fontSize: 12, color: MagacinBoje.priguseno),
        ),
      ],
    );
  }

  Widget _jmDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OznakaPolja('Jedinica mjere', obavezno: true),
        DropdownButtonFormField<String>(
          initialValue: _jm,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          dropdownColor: Colors.white,
          style: _stilUnosa,
          icon: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: MagacinBoje.priguseno,
          ),
          decoration: dekoracijaPolja(ikona: Icons.straighten_rounded),
          items: _jediniceMjere
              .map((jm) => DropdownMenuItem(value: jm, child: Text(jm)))
              .toList(),
          forceErrorText: _greska?.fieldError('unit_of_measure'),
          onChanged: _cuvanje
              ? null
              : (v) {
                  if (v == null) return;
                  setState(() {
                    _jm = v;
                    _greska = null;
                  });
                },
        ),
      ],
    );
  }

  Widget _sadrzaj(double sirina) {
    final dvaStupca = sirina >= 460;
    final greskaNormativa = _greska?.fieldErrors.entries
        .where((e) => e.key.startsWith('bom_items'))
        .firstOrNull
        ?.value
        .first;

    final sifra = _tekstPolje(
      'Šifra',
      sifraController,
      'code',
      maxLength: 50,
      ikona: Icons.qr_code_rounded,
      hint: 'npr. RM-001 (nije obavezno)',
      obavezno: false,
    );

    final naziv = _tekstPolje(
      'Naziv artikla',
      nazivController,
      'name',
      maxLength: 255,
      ikona: Icons.label_outline_rounded,
      hint: 'Puni naziv artikla',
    );

    // Naziv preko cijelog reda, ispod šifra i JM, pa minimalna količina.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: _artikalFormKey,
          child: _sekcija('Podaci o artiklu', Icons.inventory_2_rounded, [
            naziv,
            const SizedBox(height: 14),
            if (dvaStupca)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: sifra),
                  const SizedBox(width: 14),
                  Expanded(flex: 2, child: _jmDropdown()),
                ],
              )
            else ...[
              sifra,
              const SizedBox(height: 14),
              _jmDropdown(),
            ],
            if (_repromaterijal) ...[
              const SizedBox(height: 14),
              _minimumPolje(),
            ],
          ]),
        ),

        // Normativ (samo novi gotov proizvod).
        if (_saNormativom) ...[
          const SizedBox(height: 24),
          _sekcija(
            'Normativ',
            Icons.account_tree_rounded,
            opis:
                'Sirovine koje ulaze u jedan komad proizvoda. Potrebna je '
                'bar jedna stavka.',
            [
              _NormativUnos(
                firmaId: widget.firmaId,
                zauzete: _normativi.map((n) => n.materialId!).toSet(),
                enabled: !_cuvanje,
                onDodaj: _dodajNormativ,
              ),
              if (_normativi.isNotEmpty) ...[
                const SizedBox(height: 14),
                _NormativiTabela(
                  normativi: _normativi,
                  onObrisi: _cuvanje
                      ? null
                      : (n) => setState(() => _normativi.remove(n)),
                ),
              ],
              if (_prikaziGreskuNormativa) ...[
                const SizedBox(height: 12),
                _greskaTraka(
                  'Dodajte bar jednu stavku normativa prije čuvanja artikla.',
                ),
              ],
              if (greskaNormativa != null) ...[
                const SizedBox(height: 12),
                _greskaTraka(greskaNormativa),
              ],
            ],
          ),
        ],

        AnimatedSize(
          duration: hoverTrajanje,
          curve: hoverKriva,
          alignment: Alignment.topCenter,
          child: _greska != null && _greska!.fieldErrors.isEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _greskaTraka(_greska!.message),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = _temaTipa(widget.tip);
    final gotov = widget.tip == tipGotovProizvod;

    return _OkvirDijaloga(
      ikona: _izmjena ? Icons.edit_rounded : tema.ikona,
      boja: tema.boja,
      naslov: _izmjena
          ? 'Izmijeni artikal'
          : gotov
          ? 'Novi gotov proizvod'
          : 'Novi artikal repromaterijala',
      podnaslov: _izmjena
          ? nazivSaId(widget.artikal!.id, widget.artikal!.naziv)
          : gotov
          ? 'Unesite podatke o proizvodu i njegov normativ.'
          : 'Unesite naziv, jedinicu mjere i po potrebi šifru i minimalnu količinu.',
      maxSirina: _saNormativom ? 860 : 580,
      zakljucano: _cuvanje,
      onZatvori: () => Navigator.pop(context),
      sadrzaj: _sadrzaj,
      dugmad: _dugmadDijaloga(
        context,
        odustani: GlatkoDugme(
          tekst: 'Odustani',
          vrsta: VrstaDugmeta.sekundarno,
          onTap: _cuvanje ? null : () => Navigator.pop(context),
        ),
        potvrdi: GlatkoDugme(
          tekst: _izmjena ? 'Sačuvaj izmjene' : 'Dodaj artikal',
          ikona: Icons.check_rounded,
          ucitavanje: _cuvanje,
          onTap: _sacuvaj,
        ),
      ),
    );
  }
}

// ======================================================================
// POP UP: NORMATIVI GOTOVOG PROIZVODA
// Stavke se dodaju, mijenjaju i brišu odmah na serveru; obrisana stavka se
// može vratiti. Vraća true ako je normativ izmijenjen.
// ======================================================================
class _NormativiDialog extends StatefulWidget {
  final int firmaId;
  final Artikal artikal;

  const _NormativiDialog({required this.firmaId, required this.artikal});

  @override
  State<_NormativiDialog> createState() => _NormativiDialogState();
}

class _NormativiDialogState extends State<_NormativiDialog> {
  final ArticlesService _service = ArticlesService();

  List<Normativ> _normativi = [];
  Normativ? _zadnjaObrisana;

  bool _ucitavanje = true;
  bool _radi = false;
  bool _izmijenjeno = false;
  String? _greska;

  int get _artikalId => widget.artikal.id!;

  @override
  void initState() {
    super.initState();
    _ucitaj();
  }

  Future<void> _ucitaj() async {
    try {
      final normativi = await _service.fetchBomItems(
        widget.firmaId,
        _artikalId,
      );
      if (mounted) setState(() => _normativi = normativi);
    } on ApiException catch (e) {
      if (mounted) setState(() => _greska = e.message);
    } finally {
      if (mounted) setState(() => _ucitavanje = false);
    }
  }

  // Izvršava poziv ka serveru, pa ponovo učitava stavke (cijene i ukupno
  // računa server). Vraća true ako je poziv uspio.
  Future<bool> _izvrsi(Future<void> Function() poziv) async {
    setState(() {
      _radi = true;
      _greska = null;
    });

    try {
      await poziv();
      _izmijenjeno = true;
      await _ucitaj();
      return true;
    } on ApiException catch (e) {
      if (mounted) setState(() => _greska = e.message);
      return false;
    } finally {
      if (mounted) setState(() => _radi = false);
    }
  }

  Future<bool> _dodaj(Normativ normativ) {
    return _izvrsi(() async {
      await _service.addBomItem(
        widget.firmaId,
        _artikalId,
        materialId: normativ.materialId!,
        quantity: normativ.kolicina,
      );
      _zadnjaObrisana = null;
    });
  }

  // Izmjena sirovine i/ili količine; šalju se samo izmijenjena polja.
  // Nepovezana stavka se ovako veže za sirovinu.
  Future<void> _izmijeni(Normativ normativ) async {
    final izmjena = await showDialog<_IzmjenaStavke>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (_) => _IzmjenaStavkeDialog(
        firmaId: widget.firmaId,
        normativ: normativ,
        zauzete: _zauzete..remove(normativ.materialId),
      ),
    );

    if (izmjena == null || !mounted) return;

    final materialId = izmjena.sirovina?.id;
    final novaSirovina =
        materialId != null && materialId != normativ.materialId;
    final novaKolicina = izmjena.kolicina != normativ.kolicina;
    if (!novaSirovina && !novaKolicina) return;

    _izvrsi(
      () => _service.updateBomItem(
        widget.firmaId,
        _artikalId,
        normativ.id!,
        materialId: novaSirovina ? materialId : null,
        quantity: novaKolicina ? izmjena.kolicina : null,
      ),
    );
  }

  Set<int> get _zauzete => _normativi.map((n) => n.materialId).nonNulls.toSet();

  void _obrisi(Normativ normativ) {
    _izvrsi(() async {
      await _service.deleteBomItem(widget.firmaId, _artikalId, normativ.id!);
      _zadnjaObrisana = normativ;
    });
  }

  void _vratiObrisanu() {
    final normativ = _zadnjaObrisana!;

    _izvrsi(() async {
      await _service.restoreBomItem(widget.firmaId, _artikalId, normativ.id!);
      _zadnjaObrisana = null;
    });
  }

  Widget _sadrzaj(double sirina) {
    final uredjivanje = !_radi;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 3,
          child: _radi || _ucitavanje
              ? const LinearProgressIndicator(
                  color: _akcent,
                  backgroundColor: _akcentSvijetlo,
                )
              : null,
        ),
        const SizedBox(height: 10),
        if (_ucitavanje)
          Container(
            height: 160,
            decoration: BoxDecoration(
              color: MagacinBoje.zaglavlje,
              borderRadius: BorderRadius.circular(14),
            ),
          )
        else if (_normativi.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: MagacinBoje.zaglavlje,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MagacinBoje.linija),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  color: MagacinBoje.svijetlo,
                  size: 28,
                ),
                SizedBox(height: 8),
                Text(
                  'Normativ još nema stavki. Dodajte prvu sirovinu ispod.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MagacinBoje.priguseno),
                ),
              ],
            ),
          )
        else
          _NormativiTabela(
            normativi: _normativi,
            onIzmijeni: uredjivanje ? _izmijeni : null,
            onObrisi: uredjivanje ? _obrisi : null,
          ),

        if (!_ucitavanje && _normativi.any((n) => !n.jePovezan)) ...[
          const SizedBox(height: 12),
          _traka(
            'Neke stavke nisu povezane sa sirovinom. Kliknite ikonicu za '
            'povezivanje i izaberite sirovinu — dok se ne povežu, radni '
            'nalog za ovaj proizvod se ne može obraditi.',
            ikona: Icons.link_off_rounded,
            boja: _narandzasta,
            pozadina: _narandzastaSvijetlo,
          ),
        ],

        if (_zadnjaObrisana != null) ...[
          const SizedBox(height: 12),
          _traka(
            'Stavka ${_zadnjaObrisana!.naziv} je uklonjena.',
            ikona: Icons.delete_outline_rounded,
            boja: MagacinBoje.tekst,
            pozadina: MagacinBoje.zaglavlje,
            akcija: TextButton(
              onPressed: _radi ? null : _vratiObrisanu,
              style: TextButton.styleFrom(foregroundColor: _akcent),
              child: const Text('Poništi'),
            ),
          ),
        ],

        if (_greska != null) ...[
          const SizedBox(height: 12),
          _greskaTraka(_greska!),
        ],

        const SizedBox(height: 22),
        _sekcija('Dodaj stavku', Icons.add_circle_outline_rounded, [
          _NormativUnos(
            firmaId: widget.firmaId,
            zauzete: _zauzete,
            enabled: uredjivanje,
            onDodaj: _dodaj,
          ),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = _temaTipa(tipGotovProizvod);
    final zatvori = GlatkoDugme(
      tekst: 'Zatvori',
      onTap: () => Navigator.pop(context, _izmijenjeno),
    );

    return _OkvirDijaloga(
      ikona: Icons.account_tree_rounded,
      boja: tema.boja,
      naslov: 'Normativ',
      podnaslov: nazivSaId(widget.artikal.id, widget.artikal.naziv),
      maxSirina: 900,
      onZatvori: () => Navigator.pop(context, _izmijenjeno),
      sadrzaj: _sadrzaj,
      dugmad: MediaQuery.sizeOf(context).width < 600
          ? zatvori
          : Row(mainAxisAlignment: MainAxisAlignment.end, children: [zatvori]),
    );
  }
}

// Rezultat izmjene stavke normativa: izabrana sirovina (null = ista) i
// količina.
typedef _IzmjenaStavke = ({Artikal? sirovina, double kolicina});

// ======================================================================
// POP UP: IZMJENA STAVKE NORMATIVA
// Sirovina je preselektovana (material_id); stara stavka bez sirovine mora
// dobiti sirovinu prije čuvanja.
// ======================================================================
class _IzmjenaStavkeDialog extends StatefulWidget {
  final int firmaId;
  final Normativ normativ;
  final Set<int> zauzete;

  const _IzmjenaStavkeDialog({
    required this.firmaId,
    required this.normativ,
    this.zauzete = const {},
  });

  @override
  State<_IzmjenaStavkeDialog> createState() => _IzmjenaStavkeDialogState();
}

class _IzmjenaStavkeDialogState extends State<_IzmjenaStavkeDialog> {
  final _formKey = GlobalKey<FormState>();
  late final kolicinaController = TextEditingController(
    text: _formatKolicina(widget.normativ.kolicina),
  );
  Artikal? _sirovina;
  String? _greskaSirovine;

  Normativ get _normativ => widget.normativ;

  @override
  void dispose() {
    kolicinaController.dispose();
    super.dispose();
  }

  void _potvrdi() {
    setState(() {
      _greskaSirovine = !_normativ.jePovezan && _sirovina == null
          ? 'Izaberite sirovinu'
          : null;
    });
    if (!_formKey.currentState!.validate() || _greskaSirovine != null) return;

    Navigator.pop<_IzmjenaStavke>(context, (
      sirovina: _sirovina,
      kolicina: _parse(kolicinaController.text),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sirovina = _sirovina;
    final naziv = sirovina != null
        ? nazivSaId(sirovina.id, sirovina.naziv)
        : _normativ.jePovezan
        ? _normativ.naziv
        : null;

    return _OkvirDijaloga(
      ikona: _normativ.jePovezan ? Icons.edit_rounded : Icons.link_rounded,
      boja: _normativ.jePovezan ? _akcent : _narandzasta,
      naslov: _normativ.jePovezan
          ? 'Izmijeni stavku'
          : 'Poveži stavku sa sirovinom',
      podnaslov: _normativ.naziv.isEmpty ? null : _normativ.naziv,
      maxSirina: 480,
      onZatvori: () => Navigator.pop(context),
      sadrzaj: (_) => Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_normativ.jePovezan && _normativ.naziv.isNotEmpty) ...[
              _traka(
                'Stari naziv stavke: ${_normativ.naziv}',
                ikona: Icons.info_outline_rounded,
                boja: _narandzasta,
                pozadina: _narandzastaSvijetlo,
              ),
              const SizedBox(height: 16),
            ],
            _SirovinaPolje(
              firmaId: widget.firmaId,
              naziv: naziv,
              zauzete: widget.zauzete,
              errorText: _greskaSirovine,
              onIzaberi: (s) => setState(() {
                _sirovina = s;
                _greskaSirovine = null;
              }),
            ),
            const SizedBox(height: 16),
            const OznakaPolja('Količina', obavezno: true),
            TextFormField(
              controller: kolicinaController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_decimalFormatter],
              style: _stilUnosa,
              decoration: dekoracijaPolja(
                ikona: Icons.scale_outlined,
              ).copyWith(suffixText: sirovina?.jm ?? _normativ.jm),
              validator: _validirajKolicinu,
              onFieldSubmitted: (_) => _potvrdi(),
            ),
          ],
        ),
      ),
      dugmad: _dugmadDijaloga(
        context,
        odustani: GlatkoDugme(
          tekst: 'Odustani',
          vrsta: VrstaDugmeta.sekundarno,
          onTap: () => Navigator.pop(context),
        ),
        potvrdi: GlatkoDugme(
          tekst: 'Sačuvaj',
          ikona: Icons.check_rounded,
          onTap: _potvrdi,
        ),
      ),
    );
  }
}

// ======================================================================
// PREKIDAČ: Repromaterijal | Gotovi proizvodi
// Svaki tip je poseban ekran, pa se pokazivač animira od tipa koji je bio
// prikazan prije (pamti se statički), da prelaz izgleda kao klizanje.
// ======================================================================
class _PrekidacTipa extends StatelessWidget {
  final String tip;
  final bool puno;
  final ValueChanged<String> onIzaberi;

  const _PrekidacTipa({
    required this.tip,
    required this.puno,
    required this.onIzaberi,
  });

  static String? _prethodni;

  @override
  Widget build(BuildContext context) {
    final desno = tip == tipGotovProizvod;
    final odDesno = (_prethodni ?? tip) == tipGotovProizvod;
    _prethodni = tip;

    final tema = _temaTipa(tip);

    Widget opcija(String t, String naziv, IconData ikona) {
      final izabrana = t == tip;
      return Expanded(
        child: _OpcijaPrekidaca(
          naziv: naziv,
          ikona: ikona,
          izabrana: izabrana,
          boja: _temaTipa(t).boja,
          onTap: izabrana ? null : () => onIzaberi(t),
        ),
      );
    }

    final prekidac = Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: MagacinBoje.linijaSvijetla),
      ),
      child: Stack(
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: odDesno ? 1 : 0, end: desno ? 1 : 0),
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeInOutCubic,
            builder: (context, v, _) => Align(
              alignment: Alignment(v * 2 - 1, 0),
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: tema.boja.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                      const BoxShadow(
                        color: Color(0x140F172A),
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Opcije zauzimaju cijelu visinu i širinu prekidača, da tekst bude
          // tačno u sredini svake polovine (i ispod pokazivača).
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                opcija(
                  tipRepromaterijal,
                  'Repromaterijal',
                  Icons.inventory_2_rounded,
                ),
                opcija(
                  tipGotovProizvod,
                  'Gotovi proizvodi',
                  Icons.local_shipping_rounded,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return puno ? prekidac : SizedBox(width: 360, child: prekidac);
  }
}

class _OpcijaPrekidaca extends StatefulWidget {
  final String naziv;
  final IconData ikona;
  final bool izabrana;
  final Color boja;
  final VoidCallback? onTap;

  const _OpcijaPrekidaca({
    required this.naziv,
    required this.ikona,
    required this.izabrana,
    required this.boja,
    this.onTap,
  });

  @override
  State<_OpcijaPrekidaca> createState() => _OpcijaPrekidacaState();
}

class _OpcijaPrekidacaState extends State<_OpcijaPrekidaca> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final boja = widget.izabrana
        ? widget.boja
        : _hover
        ? MagacinBoje.naslov
        : MagacinBoje.priguseno;

    return Semantics(
      button: true,
      selected: widget.izabrana,
      child: MouseRegion(
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: TweenAnimationBuilder<Color?>(
            duration: hoverTrajanje,
            curve: hoverKriva,
            tween: ColorTween(end: boja),
            builder: (context, c, _) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.ikona, size: 16, color: c),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        widget.naziv,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        // Ravnomjeran razmak iznad i ispod slova, da tekst
                        // bude optički u sredini, poravnat sa ikonom.
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          leadingDistribution: TextLeadingDistribution.even,
                          fontWeight: widget.izabrana
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: c,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

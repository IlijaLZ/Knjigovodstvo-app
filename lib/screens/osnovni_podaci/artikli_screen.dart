import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../models/article.dart';
import '../../models/auth_models.dart';
import '../../services/articles_service.dart';

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

final _decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'));

void _poruka(BuildContext context, String tekst, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tekst), action: action));
}

InputDecoration _decoration(String label, {String? suffixText}) {
  return InputDecoration(
    labelText: label,
    suffixText: suffixText,
    filled: true,
    fillColor: Colors.grey.shade50,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Colors.blue, width: 2),
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

  final FirmaController _firmaController = Get.find<FirmaController>();
  final ArticlesService _service = ArticlesService();
  late final Worker _firmaWorker;

  List<Artikal> artikli = [];
  bool _ucitavanje = false;
  String? _greska;

  // Paginacija sa servera (meta iz odgovora); veličinu stranice zadaje server.
  int _stranica = 1;
  int _poStranici = 0;
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
        _poStranici = rezultat.poStranici;
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
      builder: (context) => _ArtikalDialog(tip: widget.tip, firmaId: firma.id),
    );

    if (noviArtikal == null || !mounted) return;

    _poruka(context, 'Artikal ${noviArtikal.naziv} je dodat.');
    _ucitaj(_stranica);
  }

  Future<void> _izmijeniArtikal(Artikal artikal) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final izmijenjen = await showDialog<Artikal>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ArtikalDialog(tip: widget.tip, firmaId: firma.id, artikal: artikal),
    );

    if (izmijenjen == null || !mounted) return;

    setState(() {
      final i = artikli.indexWhere((a) => a.id == izmijenjen.id);
      if (i != -1) artikli[i] = izmijenjen;
    });
  }

  Future<void> _prikaziNormative(Artikal artikal) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null || artikal.id == null) return;

    final izmijenjeno = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
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
      builder: (context) {
        return AlertDialog(
          title: const Text('Obriši artikal'),
          content: Text(
            'Da li ste sigurni da želite obrisati ${artikal.naziv}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Odustani'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Obriši'),
            ),
          ],
        );
      },
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

  Widget _paginacija() {
    final prva = _stranica > 1 && !_ucitavanje;
    final zadnja = _stranica < _zadnjaStranica && !_ucitavanje;

    return Row(
      children: [
        Text(
          _ukupno == 0
              ? 'Nema artikala'
              : 'Prikazano ${_od ?? 0}–${_do ?? 0} od $_ukupno',
          style: TextStyle(color: Colors.grey.shade700),
        ),
        if (_poStranici > 0) ...[
          const SizedBox(width: 24),
          Text(
            '$_poStranici po stranici',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
        const Spacer(),
        IconButton(
          tooltip: 'Prva stranica',
          onPressed: prva ? () => _ucitaj(1) : null,
          icon: const Icon(Icons.first_page),
        ),
        IconButton(
          tooltip: 'Prethodna stranica',
          onPressed: prva ? () => _ucitaj(_stranica - 1) : null,
          icon: const Icon(Icons.chevron_left),
        ),
        Text('Strana $_stranica od $_zadnjaStranica'),
        IconButton(
          tooltip: 'Sljedeća stranica',
          onPressed: zadnja ? () => _ucitaj(_stranica + 1) : null,
          icon: const Icon(Icons.chevron_right),
        ),
        IconButton(
          tooltip: 'Zadnja stranica',
          onPressed: zadnja ? () => _ucitaj(_zadnjaStranica) : null,
          icon: const Icon(Icons.last_page),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const boldText = TextStyle(fontWeight: FontWeight.bold);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _gotovProizvod
                ? 'Artikli gotovih proizvoda'
                : 'Artikli repromaterijala',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 24),

          if (_greska != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _greska!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => _ucitaj(_stranica),
                    child: const Text('Pokušaj ponovo'),
                  ),
                ],
              ),
            ),

          if (_ucitavanje)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: LinearProgressIndicator(),
            ),

          // --------------------------------------------------
          // PRETRAGA + DUGME "DODAJ NOVI ARTIKAL" + TABELA
          // --------------------------------------------------
          // Blok je centriran i dok se lista tek učitava; ako je širi od
          // ekrana, skroluje se horizontalno.
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: Center(
                  child: IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            SizedBox(
                              width: 350,
                              child: TextField(
                                controller: searchController,
                                decoration: _decoration('Pretraži artikle...')
                                    .copyWith(
                                      labelText: null,
                                      hintText: 'Pretraži artikle...',
                                      prefixIcon: const Icon(Icons.search),
                                      suffixIcon:
                                          searchController.text.isNotEmpty
                                          ? IconButton(
                                              onPressed: searchController.clear,
                                              icon: const Icon(Icons.clear),
                                            )
                                          : null,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                    ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            ElevatedButton.icon(
                              onPressed: _dodajNoviArtikal,
                              icon: const Icon(Icons.add),
                              label: const Text('Dodaj novi artikal'),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                Colors.grey.shade100,
                              ),
                              dataRowMinHeight: 55,
                              dataRowMaxHeight: 65,
                              columnSpacing: 35,
                              columns: [
                                const DataColumn(
                                  label: Text('Šifra', style: boldText),
                                ),
                                const DataColumn(
                                  label: Text('Naziv artikla', style: boldText),
                                ),
                                const DataColumn(
                                  label: Text(
                                    'Jedinica mjere',
                                    style: boldText,
                                  ),
                                ),
                                if (_gotovProizvod)
                                  const DataColumn(
                                    label: Text(
                                      'Br. normativa',
                                      style: boldText,
                                    ),
                                  ),
                                if (!_gotovProizvod)
                                  const DataColumn(
                                    label: Text(
                                      'Prosječna nabavna cijena',
                                      style: boldText,
                                    ),
                                  ),
                                const DataColumn(
                                  label: Text('Akcije', style: boldText),
                                ),
                              ],
                              rows: artikli.map((artikal) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(artikal.sifra)),
                                    DataCell(Text(artikal.naziv)),
                                    DataCell(Text(artikal.jm)),
                                    if (_gotovProizvod)
                                      DataCell(
                                        Text('${artikal.brojNormativa}'),
                                      ),
                                    if (!_gotovProizvod)
                                      DataCell(
                                        Text(
                                          artikal.cijena != null
                                              ? '${_format(artikal.cijenaNormativa)} €'
                                              : '-',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    DataCell(
                                      Row(
                                        children: [
                                          if (_gotovProizvod)
                                            IconButton(
                                              tooltip: 'Normativi',
                                              onPressed: () =>
                                                  _prikaziNormative(artikal),
                                              icon: const Icon(Icons.list_alt),
                                            ),
                                          IconButton(
                                            tooltip: 'Izmijeni',
                                            onPressed: () =>
                                                _izmijeniArtikal(artikal),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Obriši',
                                            onPressed: () =>
                                                _obrisiArtikal(artikal),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        _paginacija(),
                      ],
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
}

// ======================================================================
// TABELA NORMATIVA (prikaz u dijalogu)
// Ako je onIzmijeni/onObrisi != null, svaki red ima dugme za tu akciju.
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

  @override
  Widget build(BuildContext context) {
    const boldText = TextStyle(fontWeight: FontWeight.bold);
    final ukupno = normativi.fold<double>(0, (suma, n) => suma + n.iznos);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 24,
        columns: [
          const DataColumn(label: Text('Naziv', style: boldText)),
          const DataColumn(label: Text('Cijena', style: boldText)),
          const DataColumn(label: Text('Količina', style: boldText)),
          const DataColumn(label: Text('JM', style: boldText)),
          const DataColumn(label: Text('Iznos', style: boldText)),
          if (_akcije) const DataColumn(label: Text('')),
        ],
        rows: [
          ...normativi.map((n) {
            return DataRow(
              color: n.jePovezan
                  ? null
                  : WidgetStateProperty.all(Colors.orange.shade50),
              cells: [
                DataCell(
                  n.jePovezan
                      ? Text(n.naziv)
                      : Tooltip(
                          message:
                              'Stavka nije povezana sa sirovinom. '
                              'Izaberite sirovinu preko izmjene stavke.',
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.link_off,
                                size: 18,
                                color: Colors.orange.shade800,
                              ),
                              const SizedBox(width: 6),
                              Text(n.naziv.isEmpty ? '—' : n.naziv),
                              const SizedBox(width: 6),
                              Text(
                                '(nepovezano)',
                                style: TextStyle(
                                  color: Colors.orange.shade800,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                DataCell(Text('${_format(n.cijena)} €')),
                DataCell(Text(_formatKolicina(n.kolicina))),
                DataCell(Text(n.jm)),
                DataCell(Text('${_format(n.iznos)} €')),
                if (_akcije)
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onIzmijeni != null)
                          IconButton(
                            tooltip: n.jePovezan
                                ? 'Izmijeni stavku'
                                : 'Poveži sa sirovinom',
                            onPressed: () => onIzmijeni!(n),
                            icon: Icon(
                              n.jePovezan ? Icons.edit_outlined : Icons.link,
                              color: n.jePovezan
                                  ? null
                                  : Colors.orange.shade800,
                            ),
                          ),
                        if (onObrisi != null)
                          IconButton(
                            tooltip: 'Ukloni normativ',
                            onPressed: () => onObrisi!(n),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          }),
          DataRow(
            cells: [
              const DataCell(Text('Ukupno', style: boldText)),
              const DataCell(Text('')),
              const DataCell(Text('')),
              const DataCell(Text('')),
              DataCell(Text('${_format(ukupno)} €', style: boldText)),
              if (_akcije) const DataCell(Text('')),
            ],
          ),
        ],
      ),
    );
  }
}

// ======================================================================
// POLJE ZA IZBOR SIROVINE: prikazuje izabranu sirovinu, a klik otvara
// pretragu repromaterijala (_IzborSirovineDialog).
// ======================================================================
class _SirovinaPolje extends StatelessWidget {
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

  Future<void> _otvori(BuildContext context) async {
    final sirovina = await showDialog<Artikal>(
      context: context,
      builder: (_) => _IzborSirovineDialog(firmaId: firmaId, zauzete: zauzete),
    );
    if (sirovina != null) onIzaberi(sirovina);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _otvori(context) : null,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        isEmpty: naziv == null,
        decoration: _decoration('Sirovina').copyWith(
          errorText: errorText,
          enabled: enabled,
          suffixIcon: const Icon(Icons.search),
        ),
        child: Text(naziv ?? '', overflow: TextOverflow.ellipsis),
      ),
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

  Widget _lista() {
    if (_greska != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_greska!, style: TextStyle(color: Colors.grey.shade700)),
      );
    }
    if (!_ucitavanje && _rezultati.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Nema sirovina.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _rezultati.length,
      itemBuilder: (context, index) {
        final sirovina = _rezultati[index];
        final zauzeta = widget.zauzete.contains(sirovina.id);

        return ListTile(
          dense: true,
          enabled: !zauzeta,
          title: Text('${sirovina.sifra} — ${sirovina.naziv}'),
          subtitle: Text(
            [
              if (sirovina.cijena != null)
                '${_format(sirovina.cijena!)} € / ${sirovina.jm}'
              else
                sirovina.jm,
              if (zauzeta) 'već u normativu',
            ].join(' · '),
          ),
          onTap: () => Navigator.of(context).pop(sirovina),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Izaberi sirovinu'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pretragaController,
              autofocus: true,
              onChanged: _promjenaPretrage,
              decoration: const InputDecoration(
                labelText: 'Pretraga sirovina (šifra ili naziv)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 4,
              child: _ucitavanje ? const LinearProgressIndicator() : null,
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: _lista(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Odustani'),
        ),
      ],
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
  final String dugme;
  final Future<bool> Function(Normativ) onDodaj;

  const _NormativUnos({
    required this.firmaId,
    required this.onDodaj,
    this.zauzete = const {},
    this.enabled = true,
    this.dugme = 'Dodaj normativ',
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

    return Form(
      key: _formKey,
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 300,
            child: _SirovinaPolje(
              firmaId: widget.firmaId,
              naziv: sirovina == null
                  ? null
                  : '${sirovina.sifra} — ${sirovina.naziv}',
              zauzete: widget.zauzete,
              enabled: widget.enabled,
              errorText: _greskaSirovine,
              onIzaberi: (s) => setState(() {
                _sirovina = s;
                _greskaSirovine = null;
              }),
            ),
          ),
          SizedBox(
            width: 140,
            child: TextFormField(
              controller: kolicinaController,
              enabled: widget.enabled,
              keyboardType: broj,
              inputFormatters: [_decimalFormatter],
              decoration: _decoration('Količina', suffixText: sirovina?.jm),
              validator: _validirajKolicinu,
              onFieldSubmitted: (_) => _dodaj(),
            ),
          ),
          SizedBox(
            width: 130,
            child: InputDecorator(
              decoration: _decoration(
                'Cijena',
                suffixText: '€',
              ).copyWith(fillColor: Colors.grey.shade200),
              child: Text(
                sirovina?.cijena == null ? '—' : _format(sirovina!.cijena!),
              ),
            ),
          ),
          SizedBox(
            width: 130,
            child: InputDecorator(
              decoration: _decoration(
                'Iznos',
                suffixText: '€',
              ).copyWith(fillColor: Colors.grey.shade200),
              child: Text(_format(_iznos)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: widget.enabled ? _dodaj : null,
            icon: const Icon(Icons.add),
            label: Text(widget.dugme),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ],
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

  final List<Normativ> _normativi = [];
  bool _prikaziGreskuNormativa = false;

  bool _cuvanje = false;
  ApiException? _greska;

  bool get _izmjena => widget.artikal != null;

  bool get _saNormativom => !_izmjena && widget.tip == tipGotovProizvod;

  @override
  void dispose() {
    sifraController.dispose();
    nazivController.dispose();
    super.dispose();
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
          code: sifra,
          name: naziv,
          unitOfMeasure: _jm,
          bomItems: _normativi,
        );
      } else {
        // Šalju se samo izmijenjena polja.
        sacuvan = await _service.updateArticle(
          widget.firmaId,
          stari.id!,
          code: sifra != stari.sifra ? sifra : null,
          name: naziv != stari.naziv ? naziv : null,
          unitOfMeasure: _jm != stari.jm ? _jm : null,
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

  Widget _jmDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _jm,
      decoration: _decoration('Jedinica mjere'),
      items: _jediniceMjere
          .map((jm) => DropdownMenuItem(value: jm, child: Text(jm)))
          .toList(),
      forceErrorText: _greska?.fieldError('unit_of_measure'),
      onChanged: (v) {
        if (v != null) setState(() => _jm = v);
      },
    );
  }

  Widget _redGreske(String tekst) {
    final boja = Theme.of(context).colorScheme.error;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: boja, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(tekst, style: TextStyle(color: boja)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const polje = 200.0;

    final greskaNormativa = _greska?.fieldErrors.entries
        .where((e) => e.key.startsWith('bom_items'))
        .firstOrNull
        ?.value
        .first;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _izmjena ? 'Izmijeni artikal' : 'Dodaj novi artikal',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --------------------------------------------------
                      // PODACI O ARTIKLU
                      // --------------------------------------------------
                      Form(
                        key: _artikalFormKey,
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            SizedBox(
                              width: polje,
                              child: TextFormField(
                                controller: sifraController,
                                maxLength: 50,
                                decoration: _decoration(
                                  'Šifra',
                                ).copyWith(counterText: ''),
                                forceErrorText: _greska?.fieldError('code'),
                                validator: _validirajObavezno,
                              ),
                            ),
                            SizedBox(
                              width: polje * 2 + 16,
                              child: TextFormField(
                                controller: nazivController,
                                maxLength: 255,
                                decoration: _decoration(
                                  'Naziv artikla',
                                ).copyWith(counterText: ''),
                                forceErrorText: _greska?.fieldError('name'),
                                validator: _validirajObavezno,
                              ),
                            ),
                            SizedBox(width: polje, child: _jmDropdown()),
                          ],
                        ),
                      ),

                      // --------------------------------------------------
                      // NORMATIVI (samo novi gotov proizvod)
                      // --------------------------------------------------
                      if (_saNormativom) ...[
                        const SizedBox(height: 28),
                        const Text(
                          'Normativi',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Artikal mora imati bar jedan normativ.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),

                        const SizedBox(height: 16),

                        _NormativUnos(
                          firmaId: widget.firmaId,
                          zauzete: _normativi.map((n) => n.materialId!).toSet(),
                          onDodaj: _dodajNormativ,
                        ),

                        const SizedBox(height: 16),

                        if (_normativi.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _NormativiTabela(
                                normativi: _normativi,
                                onObrisi: (n) =>
                                    setState(() => _normativi.remove(n)),
                              ),
                            ),
                          ),

                        if (_prikaziGreskuNormativa)
                          _redGreske(
                            'Dodajte bar jedan normativ prije čuvanja artikla.',
                          ),
                        if (greskaNormativa != null)
                          _redGreske(greskaNormativa),
                      ],

                      if (_greska != null && _greska!.fieldErrors.isEmpty)
                        _redGreske(_greska!.message),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // DUGMAD
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _cuvanje ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                    child: const Text('Odustani'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _cuvanje ? null : _sacuvaj,
                    icon: _cuvanje
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_izmjena ? 'Sačuvaj izmjene' : 'Dodaj artikal'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
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

  @override
  Widget build(BuildContext context) {
    final uredjivanje = !_radi;
    final boja = Theme.of(context).colorScheme.error;

    return AlertDialog(
      title: Text('Normativi: ${widget.artikal.naziv}'),
      content: SizedBox(
        width: 900,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_ucitavanje || _radi)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(),
                ),

              if (!_ucitavanje)
                _NormativiTabela(
                  normativi: _normativi,
                  onIzmijeni: uredjivanje ? _izmijeni : null,
                  onObrisi: uredjivanje ? _obrisi : null,
                ),

              if (!_ucitavanje && _normativi.any((n) => !n.jePovezan))
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    border: Border.all(color: Colors.orange.shade200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.link_off, color: Colors.orange.shade800),
                      const SizedBox(width: 10),
                      const Flexible(
                        child: Text(
                          'Neke stavke nisu povezane sa sirovinom. Kliknite '
                          'ikonicu za povezivanje i izaberite sirovinu — dok '
                          'se ne povežu, radni nalog za ovaj proizvod se ne '
                          'može obraditi.',
                        ),
                      ),
                    ],
                  ),
                ),

              if (_zadnjaObrisana != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Text('Stavka ${_zadnjaObrisana!.naziv} je uklonjena.'),
                      TextButton(
                        onPressed: _radi ? null : _vratiObrisanu,
                        child: const Text('Poništi'),
                      ),
                    ],
                  ),
                ),

              if (_greska != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: boja, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(_greska!, style: TextStyle(color: boja)),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),
              _NormativUnos(
                firmaId: widget.firmaId,
                zauzete: _zauzete,
                enabled: uredjivanje,
                dugme: 'Dodaj stavku',
                onDodaj: _dodaj,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _izmijenjeno),
          child: const Text('Zatvori'),
        ),
      ],
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
        ? '${sirovina.sifra} — ${sirovina.naziv}'
        : _normativ.jePovezan
        ? _normativ.naziv
        : null;

    return AlertDialog(
      title: Text(
        _normativ.jePovezan ? 'Izmijeni stavku' : 'Poveži stavku sa sirovinom',
      ),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_normativ.jePovezan && _normativ.naziv.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Stari naziv stavke: ${_normativ.naziv}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
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
              TextFormField(
                controller: kolicinaController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_decimalFormatter],
                decoration: _decoration(
                  'Količina',
                  suffixText: sirovina?.jm ?? _normativ.jm,
                ),
                validator: _validirajKolicinu,
                onFieldSubmitted: (_) => _potvrdi(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Odustani'),
        ),
        ElevatedButton(onPressed: _potvrdi, child: const Text('Sačuvaj')),
      ],
    );
  }
}

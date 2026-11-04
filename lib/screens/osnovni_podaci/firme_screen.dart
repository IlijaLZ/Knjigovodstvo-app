import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../models/auth_models.dart';
import '../../models/company.dart';
import '../../services/companies_service.dart';
import '../../widgets/paginacija_widget.dart';

String? _validirajObavezno(String? value) {
  if (value == null || value.trim().isEmpty) return 'Obavezno polje';
  return null;
}

// JIB: 8–13 cifara; crtice i razmaci se ignorišu (server ih uklanja).
String? _validirajJib(String? value) {
  final jib = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
  if (jib.isEmpty) return 'Obavezno polje';
  if (!RegExp(r'^\d{8,13}$').hasMatch(jib)) return 'JIB mora imati 8–13 cifara';
  return null;
}

void _poruka(BuildContext context, String tekst, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tekst), action: action));
}

InputDecoration _decoration(String label) {
  return InputDecoration(
    labelText: label,
    counterText: '',
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

// Lista firmi prijavljenog korisnika, sa API-ja: GET /companies.
// Nakon svake promjene osvježava se i lista firmi u gornjem desnom uglu.
class FirmeScreen extends StatefulWidget {
  const FirmeScreen({super.key});

  @override
  State<FirmeScreen> createState() => _FirmeScreenState();
}

class _FirmeScreenState extends State<FirmeScreen> {
  final searchController = TextEditingController();

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

  Future<void> _dodaj() async {
    final nova = await showDialog<Company>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _FirmaDialog(),
    );

    if (nova == null || !mounted) return;

    _poruka(context, 'Firma ${nova.name} je dodata.');
    _firmaController.ucitajFirme();
    _ucitaj(_stranica);
  }

  Future<void> _izmijeni(Company firma) async {
    final izmijenjena = await showDialog<Company>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FirmaDialog(firma: firma),
    );

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
      builder: (context) {
        return AlertDialog(
          title: const Text('Obriši firmu'),
          content: Text('Da li ste sigurni da želite obrisati ${firma.name}?'),
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
      action: SnackBarAction(label: 'Poništi', onPressed: () => _vrati(firma)),
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

  @override
  Widget build(BuildContext context) {
    const boldText = TextStyle(fontWeight: FontWeight.bold);

    DataColumn kolona(String naziv, {bool numeric = false}) => DataColumn(
      label: Text(naziv, style: boldText),
      numeric: numeric,
    );

    DataCell celija(String? tekst) => DataCell(Text(tekst ?? '-'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Firme',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
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
          // PRETRAGA + DUGME "DODAJ" + TABELA
          // --------------------------------------------------
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
                          children: [
                            SizedBox(
                              width: 350,
                              child: TextField(
                                controller: searchController,
                                decoration: _decoration('').copyWith(
                                  labelText: null,
                                  hintText: 'Pretraži po nazivu ili JIB-u...',
                                  prefixIcon: const Icon(Icons.search),
                                  suffixIcon: searchController.text.isNotEmpty
                                      ? IconButton(
                                          onPressed: searchController.clear,
                                          icon: const Icon(Icons.clear),
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(width: 24),
                            ElevatedButton.icon(
                              onPressed: _dodaj,
                              icon: const Icon(Icons.add),
                              label: const Text('Dodaj firmu'),
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
                            child: Obx(() {
                              final izabrana =
                                  _firmaController.izabranaFirma.value;

                              return DataTable(
                                headingRowColor: WidgetStateProperty.all(
                                  Colors.grey.shade100,
                                ),
                                dataRowMinHeight: 55,
                                dataRowMaxHeight: 65,
                                columnSpacing: 35,
                                columns: [
                                  kolona('Naziv'),
                                  kolona('JIB'),
                                  kolona('PDV broj'),
                                  kolona('Adresa'),
                                  kolona('Ovlašteno lice'),
                                  kolona('Artikala', numeric: true),
                                  kolona('Akcije'),
                                ],
                                rows: firme.map((firma) {
                                  final jeIzabrana = firma == izabrana;

                                  return DataRow(
                                    color: jeIzabrana
                                        ? WidgetStateProperty.all(
                                            Colors.blue.shade50,
                                          )
                                        : null,
                                    cells: [
                                      DataCell(
                                        Text(
                                          firma.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      celija(firma.taxId),
                                      celija(firma.vatNumber),
                                      celija(firma.address),
                                      celija(firma.authorizedPerson),
                                      celija('${firma.articlesCount}'),
                                      DataCell(
                                        Row(
                                          children: [
                                            IconButton(
                                              tooltip: jeIzabrana
                                                  ? 'Trenutna firma'
                                                  : 'Radi u ovoj firmi',
                                              onPressed: jeIzabrana
                                                  ? null
                                                  : () => _izaberi(firma),
                                              icon: Icon(
                                                jeIzabrana
                                                    ? Icons.check_circle
                                                    : Icons
                                                          .check_circle_outline,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Izmijeni',
                                              onPressed: () => _izmijeni(firma),
                                              icon: const Icon(
                                                Icons.edit_outlined,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: 'Obriši',
                                              onPressed: () => _obrisi(firma),
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
                              );
                            }),
                          ),
                        ),

                        const SizedBox(height: 8),

                        Paginacija(
                          stranica: _stranica,
                          zadnjaStranica: _zadnjaStranica,
                          ukupno: _ukupno,
                          od: _od,
                          doBroja: _do,
                          zakljucano: _ucitavanje,
                          prazno: 'Nema firmi',
                          onStranica: _ucitaj,
                        ),
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
// DIJALOG ZA DODAVANJE / IZMJENU FIRME
// ======================================================================
class _FirmaDialog extends StatefulWidget {
  final Company? firma;

  const _FirmaDialog({this.firma});

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
  late final jibController = TextEditingController(text: widget.firma?.taxId);
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
    jibController.dispose();
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
      taxId: _vrijednost(jibController),
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
    required double sirina,
    required int maxLength,
    FormFieldValidator<String>? validator,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
  }) {
    return SizedBox(
      width: sirina,
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        decoration: _decoration(label),
        forceErrorText: _greska?.fieldError(apiPolje),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const polje = 240.0;
    const siroko = polje * 2 + 16;
    final boja = Theme.of(context).colorScheme.error;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: siroko + 48),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _izmjena ? 'Izmijeni firmu' : 'Dodaj firmu',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),

              if (!_izmjena)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Uz firmu se automatski prave tri skladišta: '
                    'repromaterijal, proizvodnja u toku i gotovi proizvodi.',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),

              const SizedBox(height: 20),

              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        _polje(
                          'Naziv firme',
                          nazivController,
                          'name',
                          sirina: siroko,
                          maxLength: 255,
                          validator: _validirajObavezno,
                        ),
                        _polje(
                          'Adresa',
                          adresaController,
                          'address',
                          sirina: siroko,
                          maxLength: 255,
                          validator: _validirajObavezno,
                        ),
                        _polje(
                          'JIB',
                          jibController,
                          'tax_id',
                          sirina: polje,
                          maxLength: 20,
                          validator: _validirajJib,
                          keyboardType: TextInputType.number,
                        ),
                        _polje(
                          'PDV broj (opciono)',
                          pdvController,
                          'vat_number',
                          sirina: polje,
                          maxLength: 20,
                        ),
                        _polje(
                          'Ovlašteno lice',
                          ovlastenoLiceController,
                          'authorized_person',
                          sirina: siroko,
                          maxLength: 255,
                          validator: _validirajObavezno,
                          textCapitalization: TextCapitalization.words,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              if (_greska != null && _greska!.fieldErrors.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: boja, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _greska!.message,
                          style: TextStyle(color: boja),
                        ),
                      ),
                    ],
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
                    label: Text(_izmjena ? 'Sačuvaj izmjene' : 'Dodaj firmu'),
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

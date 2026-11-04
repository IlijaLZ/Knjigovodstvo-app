import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../models/auth_models.dart';
import '../../models/partner.dart';
import '../../services/partners_service.dart';
import '../../widgets/paginacija_widget.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _validirajObavezno(String? value) {
  if (value == null || value.trim().isEmpty) return 'Obavezno polje';
  return null;
}

// JIB: 8–13 cifara; crtice i razmaci se ignorišu (server ih uklanja).
String? _validirajJib(String? value) {
  final jib = (value ?? '').replaceAll(RegExp(r'[\s-]'), '');
  if (jib.isEmpty) return null;
  if (!RegExp(r'^\d{8,13}$').hasMatch(jib)) return 'JIB mora imati 8–13 cifara';
  return null;
}

String? _validirajEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return null;
  if (!_emailRegex.hasMatch(email)) return 'Neispravan email';
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

// Lista dobavljača ili kupaca izabrane firme, sa API-ja:
// GET /companies/{company}/suppliers|customers
class PartneriScreen extends StatefulWidget {
  final VrstaPartnera vrsta;

  const PartneriScreen({super.key, required this.vrsta});

  @override
  State<PartneriScreen> createState() => _PartneriScreenState();
}

class _PartneriScreenState extends State<PartneriScreen> {
  final searchController = TextEditingController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final PartnersService _service = PartnersService();
  late final Worker _firmaWorker;

  List<Partner> partneri = [];
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

  VrstaPartnera get _vrsta => widget.vrsta;

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

  Future<void> _ucitaj([int stranica = 1]) async {
    final firma = _firmaController.izabranaFirma.value;
    final zahtjev = ++_zahtjev;

    if (firma == null) {
      setState(() {
        partneri = [];
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
      final rezultat = await _service.fetchPartners(
        firma.id,
        _vrsta,
        page: stranica,
        search: _pretraga,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        partneri = rezultat.partneri;
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
    final stranica = partneri.length == 1 && _stranica > 1
        ? _stranica - 1
        : _stranica;
    _ucitaj(stranica);
  }

  Future<void> _dodaj() async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final novi = await showDialog<Partner>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PartnerDialog(vrsta: _vrsta, firmaId: firma.id),
    );

    if (novi == null || !mounted) return;

    _poruka(context, '${_vrsta.jednina} ${novi.naziv} je dodat.');
    _ucitaj(_stranica);
  }

  Future<void> _izmijeni(Partner partner) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final izmijenjen = await showDialog<Partner>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _PartnerDialog(vrsta: _vrsta, firmaId: firma.id, partner: partner),
    );

    if (izmijenjen == null || !mounted) return;

    setState(() {
      final i = partneri.indexWhere((p) => p.id == izmijenjen.id);
      if (i != -1) partneri[i] = izmijenjen;
    });
  }

  Future<void> _obrisi(Partner partner) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Obriši ${_vrsta.akuzativ}'),
          content: Text(
            'Da li ste sigurni da želite obrisati ${partner.naziv}?\n'
            'Ostaje vidljiv na postojećim dokumentima, ali se ne može '
            'izabrati na novim.',
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
      await _service.deletePartner(firma.id, _vrsta, partner.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _osvjeziNakonUklanjanja();
    _poruka(
      context,
      '${_vrsta.jednina} ${partner.naziv} je obrisan.',
      action: SnackBarAction(
        label: 'Poništi',
        onPressed: () => _vrati(partner),
      ),
    );
  }

  Future<void> _vrati(Partner partner) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    try {
      await _service.restorePartner(firma.id, _vrsta, partner.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    _ucitaj(_stranica);
    _poruka(context, '${_vrsta.jednina} ${partner.naziv} je vraćen.');
  }

  @override
  Widget build(BuildContext context) {
    const boldText = TextStyle(fontWeight: FontWeight.bold);

    DataColumn kolona(String naziv) =>
        DataColumn(label: Text(naziv, style: boldText));

    DataCell celija(String? tekst) => DataCell(Text(tekst ?? '-'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _vrsta.mnozina,
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
                              label: Text('Dodaj ${_vrsta.akuzativ}'),
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
                                kolona('Naziv'),
                                kolona('JIB'),
                                kolona('PDV broj'),
                                kolona('Adresa'),
                                kolona('Grad'),
                                kolona('Telefon'),
                                kolona('Email'),
                                kolona('Akcije'),
                              ],
                              rows: partneri.map((partner) {
                                return DataRow(
                                  cells: [
                                    DataCell(
                                      Text(
                                        partner.naziv,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    celija(partner.jib),
                                    celija(partner.pdvBroj),
                                    celija(partner.adresa),
                                    celija(partner.grad),
                                    celija(partner.telefon),
                                    celija(partner.email),
                                    DataCell(
                                      Row(
                                        children: [
                                          IconButton(
                                            tooltip: 'Izmijeni',
                                            onPressed: () => _izmijeni(partner),
                                            icon: const Icon(
                                              Icons.edit_outlined,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Obriši',
                                            onPressed: () => _obrisi(partner),
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

                        Paginacija(
                          stranica: _stranica,
                          zadnjaStranica: _zadnjaStranica,
                          ukupno: _ukupno,
                          od: _od,
                          doBroja: _do,
                          zakljucano: _ucitavanje,
                          prazno: 'Nema unosa',
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
// DIJALOG ZA DODAVANJE / IZMJENU PARTNERA
// ======================================================================
class _PartnerDialog extends StatefulWidget {
  final VrstaPartnera vrsta;
  final int firmaId;
  final Partner? partner;

  const _PartnerDialog({
    required this.vrsta,
    required this.firmaId,
    this.partner,
  });

  @override
  State<_PartnerDialog> createState() => _PartnerDialogState();
}

class _PartnerDialogState extends State<_PartnerDialog> {
  final _formKey = GlobalKey<FormState>();
  final PartnersService _service = PartnersService();

  late final nazivController = TextEditingController(
    text: widget.partner?.naziv,
  );
  late final jibController = TextEditingController(text: widget.partner?.jib);
  late final pdvController = TextEditingController(
    text: widget.partner?.pdvBroj,
  );
  late final adresaController = TextEditingController(
    text: widget.partner?.adresa,
  );
  late final gradController = TextEditingController(text: widget.partner?.grad);
  late final telefonController = TextEditingController(
    text: widget.partner?.telefon,
  );
  late final emailController = TextEditingController(
    text: widget.partner?.email,
  );

  bool _cuvanje = false;
  ApiException? _greska;

  bool get _izmjena => widget.partner != null;

  @override
  void dispose() {
    nazivController.dispose();
    jibController.dispose();
    pdvController.dispose();
    adresaController.dispose();
    gradController.dispose();
    telefonController.dispose();
    emailController.dispose();
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

    final unos = Partner(
      id: widget.partner?.id ?? 0,
      naziv: nazivController.text.trim(),
      jib: _vrijednost(jibController),
      pdvBroj: _vrijednost(pdvController),
      adresa: _vrijednost(adresaController),
      grad: _vrijednost(gradController),
      telefon: _vrijednost(telefonController),
      email: _vrijednost(emailController),
    );

    try {
      final Partner sacuvan;
      final stari = widget.partner;

      if (stari == null) {
        sacuvan = await _service.createPartner(
          widget.firmaId,
          widget.vrsta,
          unos,
        );
      } else {
        // Šalju se samo izmijenjena polja; obrisana vrijednost ide kao null.
        final staro = stari.toJson();
        final izmjene = unos.toJson()
          ..removeWhere((kljuc, vrijednost) => staro[kljuc] == vrijednost);

        sacuvan = izmjene.isEmpty
            ? stari
            : await _service.updatePartner(
                widget.firmaId,
                widget.vrsta,
                stari.id,
                izmjene,
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

  Widget _polje(
    String label,
    TextEditingController controller,
    String apiPolje, {
    required double sirina,
    required int maxLength,
    FormFieldValidator<String>? validator,
    TextInputType? keyboardType,
  }) {
    return SizedBox(
      width: sirina,
      child: TextFormField(
        controller: controller,
        maxLength: maxLength,
        keyboardType: keyboardType,
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
                _izmjena
                    ? 'Izmijeni ${widget.vrsta.akuzativ}'
                    : 'Dodaj ${widget.vrsta.akuzativ}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
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
                          'Naziv',
                          nazivController,
                          'name',
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
                          'PDV broj',
                          pdvController,
                          'vat_number',
                          sirina: polje,
                          maxLength: 20,
                        ),
                        _polje(
                          'Adresa',
                          adresaController,
                          'address',
                          sirina: polje,
                          maxLength: 255,
                        ),
                        _polje(
                          'Grad',
                          gradController,
                          'city',
                          sirina: polje,
                          maxLength: 100,
                        ),
                        _polje(
                          'Telefon',
                          telefonController,
                          'phone',
                          sirina: polje,
                          maxLength: 50,
                          keyboardType: TextInputType.phone,
                        ),
                        _polje(
                          'Email',
                          emailController,
                          'email',
                          sirina: polje,
                          maxLength: 255,
                          validator: _validirajEmail,
                          keyboardType: TextInputType.emailAddress,
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
                    label: Text(
                      _izmjena
                          ? 'Sačuvaj izmjene'
                          : 'Dodaj ${widget.vrsta.akuzativ}',
                    ),
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

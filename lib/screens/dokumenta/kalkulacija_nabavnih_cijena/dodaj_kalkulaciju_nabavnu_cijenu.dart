import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/models/article.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/partner.dart';
import 'package:knjigovodstvo_app/models/purchase_calculation.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/screens/analiticka_kartica.dart';
import 'package:knjigovodstvo_app/services/purchase_calculations_service.dart';
import 'package:knjigovodstvo_app/widgets/input_widget.dart';

double _parse(String text) {
  return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
}

double _zaokruzi(double value, int decimale) {
  return double.parse(value.toStringAsFixed(decimale));
}

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

// Količine i jedinične cijene API vraća sa 4 decimale.
String _format4(double value) {
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text.replaceAll('.', ',');
}

String _formatDatum(DateTime datum) {
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}';
}

void _poruka(BuildContext context, String tekst) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tekst)));
}

final _decimalFormatter = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

// Jedna stavka kalkulacije u formi. Zavisni trošak i nabavna cijena se
// računaju lokalno (isto kao na serveru) samo za prikaz; konačne vrijednosti
// vraća server pri snimanju.
class _Stavka {
  final int articleId;
  final String sifra;
  final String naziv;
  final String jm;
  final String dokument;
  final double kolicina;
  final double fakturnaCijena;

  double zavisniTrosak = 0;

  _Stavka({
    required this.articleId,
    required this.sifra,
    required this.naziv,
    required this.jm,
    required this.dokument,
    required this.kolicina,
    required this.fakturnaCijena,
  });

  factory _Stavka.izApi(StavkaKalkulacije s) => _Stavka(
    articleId: s.articleId,
    sifra: s.sifra,
    naziv: s.naziv,
    jm: s.jm,
    dokument: s.dokument ?? '',
    kolicina: s.kolicina,
    fakturnaCijena: s.fakturnaCijena,
  )..zavisniTrosak = s.zavisniTrosak;

  double get fakturnaVrijednost => _zaokruzi(kolicina * fakturnaCijena, 2);

  double get nabavnaVrijednost => fakturnaVrijednost + zavisniTrosak;

  double get nabavnaCijena => kolicina > 0
      ? _zaokruzi(fakturnaCijena + zavisniTrosak / kolicina, 4)
      : fakturnaCijena;

  StavkaKalkulacijeZahtjev zaApi() => StavkaKalkulacijeZahtjev(
    articleId: articleId,
    dokument: dokument,
    kolicina: kolicina,
    fakturnaCijena: fakturnaCijena,
  );
}

// Raspodjela zavisnih troškova kao na serveru: srazmjerno fakturnoj
// vrijednosti (po količini ako je faktura 0); razlika zaokruživanja ide na
// najveću stavku, pa zbir uvijek odgovara ukupnim zavisnim troškovima.
void _rasporediTroskove(List<_Stavka> stavke, double zavisniTroskovi) {
  if (stavke.isEmpty) return;

  final ukupnaFaktura = stavke.fold<double>(
    0,
    (s, x) => s + x.fakturnaVrijednost,
  );
  final poKolicini = ukupnaFaktura <= 0;
  double osnovica(_Stavka s) => poKolicini ? s.kolicina : s.fakturnaVrijednost;
  final ukupnaOsnovica = stavke.fold<double>(0, (s, x) => s + osnovica(x));

  var raspodijeljeno = 0.0;
  for (final s in stavke) {
    s.zavisniTrosak = ukupnaOsnovica > 0
        ? _zaokruzi(zavisniTroskovi * osnovica(s) / ukupnaOsnovica, 2)
        : 0;
    raspodijeljeno += s.zavisniTrosak;
  }

  final razlika = _zaokruzi(zavisniTroskovi - raspodijeljeno, 2);
  if (razlika != 0) {
    final najveca = stavke.reduce((a, b) => osnovica(b) > osnovica(a) ? b : a);
    najveca.zavisniTrosak = _zaokruzi(najveca.zavisniTrosak + razlika, 2);
  }
}

// Nova kalkulacija (bez argumenta) ili izmjena postojeće: Get.arguments je
// id kalkulacije. Proknjižena kalkulacija se samo pregleda.
class DodajKalkulacijuScreen extends StatefulWidget {
  const DodajKalkulacijuScreen({super.key});

  @override
  State<DodajKalkulacijuScreen> createState() => _DodajKalkulacijuScreenState();
}

class _DodajKalkulacijuScreenState extends State<DodajKalkulacijuScreen> {
  final FirmaController _firmaController = Get.find<FirmaController>();
  final PurchaseCalculationsService _service = PurchaseCalculationsService();

  final datumController = TextEditingController();
  final rcBrController = TextEditingController();
  final prijemnicaBrController = TextEditingController();
  final kalkulisaoController = TextEditingController();
  final robuPrimioController = TextEditingController();
  final prevozController = TextEditingController();
  final spedicijaController = TextEditingController();
  final carinaController = TextEditingController();
  final searchController = TextEditingController();

  final List<_Stavka> stavke = [];

  int? _firmaId;
  int? _kalkulacijaId;
  Kalkulacija? _kalkulacija;

  DateTime _datum = DateTime.now();
  List<Partner> _dobavljaci = [];
  int? _dobavljacId;
  List<Skladiste> _skladista = [];
  int? _skladisteId;

  bool _ucitavanje = true;
  String? _greskaUcitavanja;
  bool _cuvanje = false;
  ApiException? _greska;

  // Da li je nešto snimljeno, da lista zna da se osvježi.
  bool _promijenjeno = false;

  bool get _samoPregled => _kalkulacija?.jeProknjizena ?? false;

  @override
  void initState() {
    super.initState();
    _firmaId = _firmaController.izabranaFirma.value?.id;
    final argument = Get.arguments;
    _kalkulacijaId = argument is int ? argument : null;
    datumController.text = _formatDatum(_datum);
    searchController.addListener(() => setState(() {}));
    _ucitaj();
  }

  @override
  void dispose() {
    datumController.dispose();
    rcBrController.dispose();
    prijemnicaBrController.dispose();
    kalkulisaoController.dispose();
    robuPrimioController.dispose();
    prevozController.dispose();
    spedicijaController.dispose();
    carinaController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> _ucitaj() async {
    final firmaId = _firmaId;
    if (firmaId == null) {
      setState(() {
        _ucitavanje = false;
        _greskaUcitavanja = 'Nije izabrana firma.';
      });
      return;
    }

    setState(() {
      _ucitavanje = true;
      _greskaUcitavanja = null;
    });

    try {
      final dobavljaci = _service.fetchSuppliers(firmaId);
      final skladista = _service.fetchWarehouses(firmaId);
      final kalkulacija = _kalkulacijaId == null
          ? null
          : await _service.fetchCalculation(firmaId, _kalkulacijaId!);

      final listaDobavljaca = await dobavljaci;
      final listaSkladista = await skladista;
      if (!mounted) return;

      setState(() {
        _dobavljaci = listaDobavljaca.where((d) => !d.jeObrisan).toList();
        _skladista = listaSkladista;
        // Nova kalkulacija: roba se po defaultu prima u magacin sirovina.
        _skladisteId ??= listaSkladista
            .where((s) => s.tip == 'raw_materials')
            .firstOrNull
            ?.id;
        if (kalkulacija != null) _postaviKalkulaciju(kalkulacija);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _greskaUcitavanja = e.message);
    } finally {
      if (mounted) setState(() => _ucitavanje = false);
    }
  }

  void _postaviKalkulaciju(Kalkulacija k) {
    _kalkulacija = k;
    _kalkulacijaId = k.id;
    _datum = k.datum ?? _datum;
    datumController.text = _formatDatum(_datum);
    rcBrController.text = k.brojFakture;
    prijemnicaBrController.text = k.brojPrijemnice;
    final r = k.rekapitulacija;
    prevozController.text = r.prevoz == 0 ? '' : _format(r.prevoz);
    spedicijaController.text = r.spedicija == 0 ? '' : _format(r.spedicija);
    carinaController.text = r.carina == 0 ? '' : _format(r.carina);
    kalkulisaoController.text = r.kalkulisao ?? '';
    robuPrimioController.text = r.robuPrimio ?? '';
    _dobavljacId = k.supplierId;
    _skladisteId = k.skladiste?.id ?? _skladisteId;

    // Obrisan dobavljač se ne vraća u listi, ali ostaje vidljiv na kalkulaciji.
    if (_dobavljacId != null && !_dobavljaci.any((d) => d.id == _dobavljacId)) {
      _dobavljaci = [
        Partner(
          id: _dobavljacId!,
          naziv: k.dobavljac ?? 'Dobavljač #$_dobavljacId',
        ),
        ..._dobavljaci,
      ];
    }

    stavke
      ..clear()
      ..addAll(k.stavke.map(_Stavka.izApi));
  }

  // ------------------------------------------------------------------
  // Rekapitulacija
  // ------------------------------------------------------------------

  double get _prevoz => _parse(prevozController.text);
  double get _spedicija => _parse(spedicijaController.text);
  double get _carina => _parse(carinaController.text);
  double get _zavisniTroskovi => _zaokruzi(_prevoz + _spedicija + _carina, 2);
  double get _fakturnaVrijednost =>
      stavke.fold<double>(0, (s, x) => s + x.fakturnaVrijednost);

  void _preracunaj() {
    _rasporediTroskove(stavke, _zavisniTroskovi);
  }

  // ------------------------------------------------------------------
  // Akcije
  // ------------------------------------------------------------------

  Future<void> _izaberiDatum() async {
    if (_samoPregled) return;

    final izabran = await showDatePicker(
      context: context,
      initialDate: _datum,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (izabran == null) return;

    setState(() {
      _datum = izabran;
      datumController.text = _formatDatum(izabran);
    });
  }

  Future<void> _dodajIliIzmijeniArtikal([_Stavka? postojeca]) async {
    final firmaId = _firmaId;
    if (firmaId == null) return;

    final nova = await showDialog<_Stavka>(
      context: context,
      builder: (context) => _ArtikalDialog(
        firmaId: firmaId,
        dokument: rcBrController.text.trim(),
        stavka: postojeca,
      ),
    );
    if (nova == null || !mounted) return;

    setState(() {
      if (postojeca != null) {
        stavke[stavke.indexOf(postojeca)] = nova;
      } else {
        stavke.add(nova);
      }
      _preracunaj();
    });
  }

  // Kartica artikla na skladištu ove kalkulacije.
  void _otvoriKarticu(_Stavka stavka) {
    final skladiste = _skladista.where((s) => s.id == _skladisteId).firstOrNull;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalitickaKarticaScreen(
          articleId: stavka.articleId,
          sifra: stavka.sifra,
          naziv: stavka.naziv,
          jm: stavka.jm,
          warehouseId: skladiste?.id,
          skladiste: skladiste?.naziv,
        ),
      ),
    );
  }

  Future<void> _obrisiArtikal(_Stavka stavka) async {
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Obriši artikal'),
        content: Text('Da li ste sigurni da želite obrisati ${stavka.naziv}?'),
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
      ),
    );
    if (potvrda != true || !mounted) return;

    setState(() {
      stavke.remove(stavka);
      _preracunaj();
    });
  }

  // Lokalna provjera prije slanja; ostalo provjerava server (422).
  String? _provjeri() {
    if (_dobavljacId == null) return 'Izaberite dobavljača.';
    if (_skladisteId == null) return 'Izaberite objekat (skladište).';
    if (rcBrController.text.trim().isEmpty) return 'Unesite broj fakture.';
    if (prijemnicaBrController.text.trim().isEmpty) {
      return 'Unesite broj prijemnice.';
    }
    if (stavke.isEmpty) return 'Dodajte bar jedan artikal.';
    return null;
  }

  // Snima kalkulaciju (kreira ili mijenja) i vraća je; null ako nije uspjelo.
  Future<Kalkulacija?> _sacuvaj() async {
    final firmaId = _firmaId;
    if (firmaId == null) return null;

    final greska = _provjeri();
    if (greska != null) {
      _poruka(context, greska);
      return null;
    }

    setState(() {
      _cuvanje = true;
      _greska = null;
    });

    try {
      final items = stavke.map((s) => s.zaApi()).toList();
      final kalkulacija = _kalkulacijaId == null
          ? await _service.createCalculation(
              firmaId,
              warehouseId: _skladisteId!,
              supplierId: _dobavljacId!,
              date: _datum,
              invoiceNumber: rcBrController.text.trim(),
              receiptNumber: prijemnicaBrController.text.trim(),
              transportCost: _prevoz,
              forwardingCost: _spedicija,
              customsCost: _carina,
              calculatedBy: kalkulisaoController.text,
              receivedBy: robuPrimioController.text,
              items: items,
            )
          : await _service.updateCalculation(
              firmaId,
              _kalkulacijaId!,
              warehouseId: _skladisteId,
              supplierId: _dobavljacId,
              date: _datum,
              invoiceNumber: rcBrController.text.trim(),
              receiptNumber: prijemnicaBrController.text.trim(),
              transportCost: _prevoz,
              forwardingCost: _spedicija,
              customsCost: _carina,
              calculatedBy: kalkulisaoController.text,
              receivedBy: robuPrimioController.text,
              items: items,
            );

      _promijenjeno = true;
      if (mounted) setState(() => _postaviKalkulaciju(kalkulacija));
      return kalkulacija;
    } on ApiException catch (e) {
      if (mounted) setState(() => _greska = e);
      return null;
    } finally {
      if (mounted) setState(() => _cuvanje = false);
    }
  }

  Future<void> _sacuvajIZatvori() async {
    final kalkulacija = await _sacuvaj();
    if (kalkulacija == null || !mounted) return;

    Get.back(result: true);
  }

  Future<void> _sacuvajIProknjizi() async {
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Proknjiži kalkulaciju'),
        content: const Text(
          'Kalkulacija se snima i knjiži: roba ulazi na zalihu izabranog '
          'skladišta po nabavnoj vrijednosti i upisuje se na karticu artikla. '
          'Poslije knjiženja kalkulacija se ne može mijenjati ni brisati. '
          'Nastaviti?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proknjiži'),
          ),
        ],
      ),
    );
    if (potvrda != true || !mounted) return;

    final kalkulacija = await _sacuvaj();
    if (kalkulacija == null || !mounted) return;

    setState(() {
      _cuvanje = true;
      _greska = null;
    });

    try {
      final proknjizena = await _service.bookCalculation(
        _firmaId!,
        kalkulacija.id,
      );
      if (!mounted) return;
      setState(() => _postaviKalkulaciju(proknjizena));
      _poruka(context, 'Kalkulacija je proknjižena.');
    } on ApiException catch (e) {
      // Kalkulacija je sačuvana, ali nije proknjižena.
      if (mounted) setState(() => _greska = e);
    } finally {
      if (mounted) setState(() => _cuvanje = false);
    }
  }

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  InputDecoration _dekoracija(String label, {String? greska}) {
    return InputDecoration(
      labelText: label,
      errorText: greska,
      filled: true,
      fillColor: _samoPregled ? Colors.grey.shade200 : Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
    );
  }

  Widget _tekstPolje(
    String label,
    TextEditingController controller, {
    String? poljeApi,
    bool broj = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      readOnly: _samoPregled,
      onChanged: onChanged,
      keyboardType: broj
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      inputFormatters: broj ? [_decimalFormatter] : null,
      decoration: _dekoracija(
        label,
        greska: poljeApi == null ? null : _greska?.fieldError(poljeApi),
      ),
    );
  }

  Widget _buildDobavljac() {
    return DropdownButtonFormField<int>(
      key: ValueKey('dobavljac-$_dobavljacId-${_dobavljaci.length}'),
      initialValue: _dobavljacId,
      isExpanded: true,
      forceErrorText: _greska?.fieldError('supplier_id'),
      decoration: _dekoracija('Dobavljač'),
      hint: Text(
        _dobavljaci.isEmpty ? 'Nema unesenih dobavljača' : 'Izaberite',
      ),
      items: _dobavljaci
          .map(
            (d) => DropdownMenuItem(
              value: d.id,
              child: Text(
                d.grad == null ? d.naziv : '${d.naziv} (${d.grad})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _samoPregled
          ? null
          : (id) => setState(() => _dobavljacId = id),
    );
  }

  Widget _buildSkladiste() {
    return DropdownButtonFormField<int>(
      key: ValueKey('skladiste-$_skladisteId-${_skladista.length}'),
      initialValue: _skladisteId,
      isExpanded: true,
      forceErrorText: _greska?.fieldError('warehouse_id'),
      decoration: _dekoracija('Objekat'),
      items: _skladista
          .map(
            (s) => DropdownMenuItem(
              value: s.id,
              child: Text(s.naziv, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: _samoPregled
          ? null
          : (id) => setState(() => _skladisteId = id),
    );
  }

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTabelaArtikala() {
    final pretraga = searchController.text.trim().toLowerCase();
    final indeksi = [
      for (var i = 0; i < stavke.length; i++)
        if (pretraga.isEmpty ||
            stavke[i].sifra.toLowerCase().contains(pretraga) ||
            stavke[i].naziv.toLowerCase().contains(pretraga) ||
            stavke[i].dokument.toLowerCase().contains(pretraga))
          i,
    ];

    if (stavke.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          'Nema dodatih artikala. Klikni "Dodaj novi artikal".',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    const bold = TextStyle(fontWeight: FontWeight.w600);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 56,
          columnSpacing: 30,
          columns: [
            _kolona('Rb'),
            _kolona('Šifra'),
            _kolona('Naziv artikla'),
            _kolona('Dokument'),
            _kolona('JM'),
            _kolona('Količina', numeric: true),
            _kolona('Fakturna cijena', numeric: true),
            _kolona('Fakturna vrijednost', numeric: true),
            _kolona('Zavisni trošak', numeric: true),
            _kolona('Nabavna cijena', numeric: true),
            _kolona('Nabavna vrijednost', numeric: true),
            _kolona('Akcije'),
          ],
          rows: [
            for (final i in indeksi)
              DataRow(
                cells: [
                  DataCell(Text('${i + 1}')),
                  DataCell(Text(stavke[i].sifra)),
                  DataCell(Text(stavke[i].naziv)),
                  DataCell(Text(stavke[i].dokument)),
                  DataCell(Text(stavke[i].jm)),
                  DataCell(Text(_format4(stavke[i].kolicina))),
                  DataCell(Text('${_format4(stavke[i].fakturnaCijena)} €')),
                  DataCell(Text('${_format(stavke[i].fakturnaVrijednost)} €')),
                  DataCell(Text('${_format(stavke[i].zavisniTrosak)} €')),
                  DataCell(
                    Text('${_format4(stavke[i].nabavnaCijena)} €', style: bold),
                  ),
                  DataCell(Text('${_format(stavke[i].nabavnaVrijednost)} €')),
                  DataCell(
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Analitička kartica',
                          onPressed: () => _otvoriKarticu(stavke[i]),
                          icon: const Icon(Icons.visibility_outlined),
                        ),
                        if (!_samoPregled) ...[
                          IconButton(
                            tooltip: 'Izmijeni',
                            onPressed: _cuvanje
                                ? null
                                : () => _dodajIliIzmijeniArtikal(stavke[i]),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'Obriši',
                            onPressed: _cuvanje
                                ? null
                                : () => _obrisiArtikal(stavke[i]),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _red(String naziv, String vrijednost, {bool istaknuto = false}) {
    final stil = TextStyle(
      fontSize: istaknuto ? 16 : 14,
      fontWeight: istaknuto ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(naziv, style: stil)),
          Text(vrijednost, style: stil),
        ],
      ),
    );
  }

  Widget _buildRekapitulacija() {
    final fv = _fakturnaVrijednost;
    final zt = _zavisniTroskovi;
    final ztn = fv > 0 ? zt / fv * 100 : 0.0;

    void promjena(String _) => setState(_preracunaj);

    return Wrap(
      spacing: 32,
      runSpacing: 24,
      children: [
        SizedBox(
          width: 320,
          child: Column(
            children: [
              _tekstPolje(
                'Prevoz',
                prevozController,
                poljeApi: 'transport_cost',
                broj: true,
                onChanged: promjena,
              ),
              const SizedBox(height: 12),
              _tekstPolje(
                'Špedicija',
                spedicijaController,
                poljeApi: 'forwarding_cost',
                broj: true,
                onChanged: promjena,
              ),
              const SizedBox(height: 12),
              _tekstPolje(
                'Carina',
                carinaController,
                poljeApi: 'customs_cost',
                broj: true,
                onChanged: promjena,
              ),
            ],
          ),
        ),
        Container(
          width: 360,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _red('Fakturna vrijednost (FV)', '${_format(fv)} €'),
              _red('Zavisni troškovi (svega)', '${_format(zt)} €'),
              _red('ZTN (zavisni troškovi / FV)', '${_format(ztn)}%'),
              const Divider(),
              _red(
                'Nabavna vrijednost',
                '${_format(fv + zt)} €',
                istaknuto: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Greške servera koje nisu vezane za polje forme (stavke, status...).
  Widget? _buildGreske() {
    final greska = _greska;
    if (greska == null) return null;

    const poljaForme = {
      'supplier_id',
      'warehouse_id',
      'invoice_number',
      'receipt_number',
      'transport_cost',
      'forwarding_cost',
      'customs_cost',
      'calculated_by',
      'received_by',
      'date',
    };
    final poruke = greska.fieldErrors.entries
        .where((e) => !poljaForme.contains(e.key))
        .expand((e) => e.value)
        .toList();
    if (poruke.isEmpty && greska.fieldErrors.isEmpty) {
      poruke.add(greska.message);
    }
    if (poruke.isEmpty) return null;

    final boja = Theme.of(context).colorScheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: boja.withValues(alpha: 0.06),
        border: Border.all(color: boja.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final poruka in poruke)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, color: boja, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(poruka, style: TextStyle(color: boja)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dugme({
    required VoidCallback? onPressed,
    required Widget label,
    Widget? icon,
    bool outlined = false,
  }) {
    final style = ButtonStyle(
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      ),
      minimumSize: WidgetStateProperty.all(const Size(0, 56)),
      textStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );

    if (outlined) {
      return OutlinedButton(onPressed: onPressed, style: style, child: label);
    }
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: icon,
      label: label,
      style: style,
    );
  }

  Widget _buildForma() {
    final greske = _buildGreske();
    final zakljucano = _cuvanje || _samoPregled;
    final k = _kalkulacija;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k == null
              ? 'Dodaj novu kalkulaciju nabavnih cijena'
              : 'Kalkulacija ${k.brojPrijemnice}',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        if (_samoPregled) ...[
          const SizedBox(height: 8),
          Text(
            'Kalkulacija je proknjižena i više se ne može mijenjati.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
        const SizedBox(height: 24),

        // Red 1: Datum, Dobavljač, Objekat
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _izaberiDatum,
                child: AbsorbPointer(
                  child: buildInput(
                    label: 'Datum',
                    controller: datumController,
                    width: null,
                    readOnly: _samoPregled,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: _buildDobavljac()),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: _buildSkladiste()),
          ],
        ),
        const SizedBox(height: 16),

        // Red 2: RC.BR, Prijemnica br
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _tekstPolje(
                'RC.BR (broj fakture)',
                rcBrController,
                poljeApi: 'invoice_number',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _tekstPolje(
                'Prijemnica br',
                prijemnicaBrController,
                poljeApi: 'receipt_number',
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        // Artikli
        Row(
          children: [
            const Text(
              'Artikli',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 320,
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Pretraži artikle...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: searchController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: searchController.clear,
                          icon: const Icon(Icons.clear),
                        ),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const Spacer(),
            if (!_samoPregled)
              ElevatedButton.icon(
                onPressed: _cuvanje ? null : () => _dodajIliIzmijeniArtikal(),
                icon: const Icon(Icons.add),
                label: const Text('Dodaj novi artikal'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Prazna poruka ima punu širinu, pa ne smije biti u horizontalnom
        // scrollu (beskonačna širina ruši layout).
        if (stavke.isEmpty)
          _buildTabelaArtikala()
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _buildTabelaArtikala(),
          ),
        if (!_samoPregled && stavke.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Zavisni troškovi se raspoređuju srazmjerno fakturnoj vrijednosti. '
            'Konačne vrijednosti računa server pri snimanju.',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],

        const SizedBox(height: 32),

        const Text(
          'Rekapitulacija',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        _buildRekapitulacija(),

        const SizedBox(height: 32),

        // Kalkulisao + Robu primio
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 320,
              child: _tekstPolje(
                'Kalkulisao',
                kalkulisaoController,
                poljeApi: 'calculated_by',
              ),
            ),
            SizedBox(
              width: 320,
              child: _tekstPolje(
                'Robu primio',
                robuPrimioController,
                poljeApi: 'received_by',
              ),
            ),
          ],
        ),

        const SizedBox(height: 32),

        if (greske != null) ...[greske, const SizedBox(height: 16)],

        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (!_samoPregled) ...[
              _dugme(
                onPressed: zakljucano ? null : _sacuvajIZatvori,
                icon: _cuvanje
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 24),
                label: const Text('Sačuvaj dokument'),
              ),
              _dugme(
                onPressed: zakljucano ? null : _sacuvajIProknjizi,
                icon: const Icon(Icons.inventory_2_outlined, size: 24),
                label: const Text('Sačuvaj i proknjiži'),
              ),
            ],
            _dugme(
              onPressed: () {},
              icon: const Icon(Icons.print),
              label: const Text('Štampaj'),
            ),
            _dugme(
              onPressed: _cuvanje
                  ? null
                  : () => Get.back(result: _promijenjeno),
              label: Text(_samoPregled ? 'Zatvori' : 'Odustani'),
              outlined: true,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget sadrzaj;
    if (_ucitavanje) {
      sadrzaj = const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_greskaUcitavanja != null) {
      sadrzaj = Padding(
        padding: const EdgeInsets.all(48),
        child: Center(
          child: Column(
            children: [
              Text(
                _greskaUcitavanja!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _ucitaj,
                child: const Text('Pokušaj ponovo'),
              ),
            ],
          ),
        ),
      );
    } else {
      sadrzaj = _buildForma();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_cuvanje) Get.back(result: _promijenjeno);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _kalkulacijaId == null
                ? 'Dodaj novu kalkulaciju nabavnih cijena'
                : 'Kalkulacija nabavnih cijena',
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: sadrzaj,
        ),
      ),
    );
  }
}

// ======================================================================
// DIJALOG: izbor artikla, dokument, količina i fakturna cijena
// GET /companies/{company}/purchase-calculations/articles?search=...
// ======================================================================
class _ArtikalDialog extends StatefulWidget {
  final int firmaId;
  final String dokument;
  final _Stavka? stavka;

  const _ArtikalDialog({
    required this.firmaId,
    required this.dokument,
    this.stavka,
  });

  @override
  State<_ArtikalDialog> createState() => _ArtikalDialogState();
}

class _ArtikalDialogState extends State<_ArtikalDialog> {
  final PurchaseCalculationsService _service = PurchaseCalculationsService();
  final _formKey = GlobalKey<FormState>();

  final pretragaController = TextEditingController();
  late final TextEditingController dokumentController;
  late final TextEditingController kolicinaController;
  late final TextEditingController fakturnaController;

  List<Artikal> _rezultati = [];
  Artikal? _artikal;
  bool _ucitavanje = false;
  String? _greska;
  Timer? _timer;
  int _zahtjev = 0;

  @override
  void initState() {
    super.initState();
    final s = widget.stavka;
    dokumentController = TextEditingController(
      text: s?.dokument ?? widget.dokument,
    );
    kolicinaController = TextEditingController(
      text: s == null ? '' : _format4(s.kolicina),
    );
    fakturnaController = TextEditingController(
      text: s == null ? '' : _format4(s.fakturnaCijena),
    );
    if (s != null) {
      _artikal = Artikal(
        id: s.articleId,
        sifra: s.sifra,
        naziv: s.naziv,
        jm: s.jm,
      );
    }
    kolicinaController.addListener(() => setState(() {}));
    fakturnaController.addListener(() => setState(() {}));
    _trazi();
  }

  @override
  void dispose() {
    _timer?.cancel();
    pretragaController.dispose();
    dokumentController.dispose();
    kolicinaController.dispose();
    fakturnaController.dispose();
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
      final artikli = await _service.searchArticles(
        widget.firmaId,
        search: pretragaController.text,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _rezultati = artikli);
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

  String? _kolicinaValidator(String? value) {
    final v = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (v == null) return 'Unesite ispravan broj';
    if (v <= 0) return 'Mora biti veće od 0';
    return null;
  }

  String? _cijenaValidator(String? value) {
    final v = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (v == null) return 'Unesite ispravan broj';
    if (v < 0) return 'Ne može biti negativna';
    return null;
  }

  void _potvrdi() {
    final artikal = _artikal;
    if (artikal == null) return;
    if (!_formKey.currentState!.validate()) return;

    Navigator.of(context).pop(
      _Stavka(
        articleId: artikal.id!,
        sifra: artikal.sifra,
        naziv: artikal.naziv,
        jm: artikal.jm,
        dokument: dokumentController.text.trim(),
        kolicina: _parse(kolicinaController.text),
        fakturnaCijena: _parse(fakturnaController.text),
      ),
    );
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
          'Nema artikala.',
          style: TextStyle(color: Colors.grey.shade700),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _rezultati.length,
      itemBuilder: (context, index) {
        final artikal = _rezultati[index];
        final izabran = artikal.id == _artikal?.id;

        return ListTile(
          dense: true,
          selected: izabran,
          selectedTileColor: Colors.blue.shade50,
          title: Text('${artikal.sifra} — ${artikal.naziv}'),
          subtitle: Text(
            [
              artikal.tip == tipGotovProizvod
                  ? 'Gotov proizvod'
                  : 'Repromaterijal',
              artikal.jm,
              if (artikal.cijena != null)
                'prosj. ${_format4(artikal.cijena!)} €',
            ].join(' · '),
          ),
          onTap: () => setState(() => _artikal = artikal),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fv =
        _parse(kolicinaController.text) * _parse(fakturnaController.text);

    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text(
        widget.stavka == null ? 'Dodaj novi artikal' : 'Izmijeni artikal',
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: pretragaController,
                autofocus: widget.stavka == null,
                onChanged: _promjenaPretrage,
                decoration: const InputDecoration(
                  labelText: 'Pretraga artikala (šifra ili naziv)',
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
                constraints: const BoxConstraints(maxHeight: 220),
                child: _lista(),
              ),
              const SizedBox(height: 12),
              Text(
                _artikal == null
                    ? 'Izaberite artikal iz liste.'
                    : 'Izabran: ${_artikal!.sifra} — ${_artikal!.naziv}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: _artikal == null ? Colors.grey.shade600 : null,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: dokumentController,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Dokument',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: kolicinaController,
                      inputFormatters: [_decimalFormatter],
                      validator: _kolicinaValidator,
                      decoration: InputDecoration(
                        labelText: 'Količina',
                        suffixText: _artikal?.jm,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: fakturnaController,
                      inputFormatters: [_decimalFormatter],
                      validator: _cijenaValidator,
                      onFieldSubmitted: (_) => _potvrdi(),
                      decoration: const InputDecoration(
                        labelText: 'Fakturna cijena',
                        suffixText: '€',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Fakturna vrijednost: ${_format(fv)} €',
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Odustani'),
        ),
        ElevatedButton(
          onPressed: _artikal == null ? null : _potvrdi,
          child: Text(widget.stavka == null ? 'Dodaj artikal' : 'Sačuvaj'),
        ),
      ],
    );
  }
}

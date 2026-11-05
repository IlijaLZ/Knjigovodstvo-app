import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/purchase_calculation.dart';
import 'package:knjigovodstvo_app/routes/app_routes.dart';
import 'package:knjigovodstvo_app/services/purchase_calculations_service.dart';
import 'package:knjigovodstvo_app/widgets/paginacija_widget.dart';

String _formatDatum(DateTime? datum) {
  if (datum == null) return '';
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}';
}

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

void _poruka(BuildContext context, String tekst, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tekst), action: action));
}

// Lista kalkulacija izabrane firme: GET /companies/{company}/purchase-calculations
class KalkulacijaNabavnihCijenaScreen extends StatefulWidget {
  const KalkulacijaNabavnihCijenaScreen({super.key});

  @override
  State<KalkulacijaNabavnihCijenaScreen> createState() =>
      _KalkulacijaNabavnihCijenaScreenState();
}

class _KalkulacijaNabavnihCijenaScreenState
    extends State<KalkulacijaNabavnihCijenaScreen> {
  final searchController = TextEditingController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final PurchaseCalculationsService _service = PurchaseCalculationsService();
  late final Worker _firmaWorker;

  List<Kalkulacija> kalkulacije = [];
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
        kalkulacije = [];
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
      final rezultat = await _service.fetchCalculations(
        firma.id,
        page: stranica,
        search: _pretraga,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        kalkulacije = rezultat.kalkulacije;
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

  Future<void> _otvori([Kalkulacija? kalkulacija]) async {
    final sacuvano = await Get.toNamed(
      AppRoutes.dodajKalkulacijuNabavnuCijenu,
      arguments: kalkulacija?.id,
    );
    if (sacuvano != true || !mounted) return;
    _ucitaj(kalkulacija == null ? 1 : _stranica);
    _poruka(context, 'Kalkulacija je sačuvana.');
  }

  Future<bool> _potvrdi(String naslov, String tekst, String dugme) async {
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(naslov),
        content: Text(tekst),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(dugme),
          ),
        ],
      ),
    );
    return potvrda == true;
  }

  String _oznaka(Kalkulacija k) =>
      k.brojPrijemnice.isNotEmpty ? k.brojPrijemnice : k.brojFakture;

  Future<void> _proknjizi(Kalkulacija kalkulacija) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      'Proknjiži kalkulaciju',
      'Knjiženjem kalkulacije ${_oznaka(kalkulacija)} roba ulazi na zalihu '
          'skladišta i upisuje se na karticu artikla. Kalkulacija se poslije '
          'ne može mijenjati ni brisati. Nastaviti?',
      'Proknjiži',
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.bookCalculation(firma.id, kalkulacija.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _poruka(context, 'Kalkulacija ${_oznaka(kalkulacija)} je proknjižena.');
    _ucitaj(_stranica);
  }

  Future<void> _obrisi(Kalkulacija kalkulacija) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      'Obriši kalkulaciju',
      'Da li ste sigurni da želite obrisati kalkulaciju '
          '${_oznaka(kalkulacija)}?',
      'Obriši',
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.deleteCalculation(firma.id, kalkulacija.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    // Nakon brisanja zadnjeg reda na stranici vraća se na prethodnu.
    _ucitaj(
      kalkulacije.length == 1 && _stranica > 1 ? _stranica - 1 : _stranica,
    );
    _poruka(
      context,
      'Kalkulacija ${_oznaka(kalkulacija)} je obrisana.',
      action: SnackBarAction(
        label: 'Poništi',
        onPressed: () => _vrati(firma.id, kalkulacija),
      ),
    );
  }

  Future<void> _vrati(int firmaId, Kalkulacija kalkulacija) async {
    try {
      await _service.restoreCalculation(firmaId, kalkulacija.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _ucitaj(_stranica);
    _poruka(context, 'Kalkulacija ${_oznaka(kalkulacija)} je vraćena.');
  }

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _filteri() {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 360,
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Pretraga po dobavljaču, fakturi ili prijemnici',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Obriši pretragu',
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close),
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tabela() {
    if (!_ucitavanje && kalkulacije.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            _firmaController.izabranaFirma.value == null
                ? 'Izaberite firmu.'
                : 'Nema kalkulacija.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return DataTable(
      headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
      columnSpacing: 32,
      showCheckboxColumn: false,
      columns: [
        _kolona('RB'),
        _kolona('Datum'),
        _kolona('Dobavljač'),
        _kolona('RC.BR'),
        _kolona('Prijemnica br'),
        _kolona('Objekat'),
        _kolona('Nabavna vrijednost', numeric: true),
        _kolona('Kalkulisao'),
        _kolona('Robu primio'),
        _kolona('Akcije'),
      ],
      rows: List.generate(kalkulacije.length, (index) {
        final k = kalkulacije[index];

        return DataRow(
          onSelectChanged: (_) => _otvori(k),
          cells: [
            DataCell(Text('${(_od ?? 1) + index}')),
            DataCell(Text(_formatDatum(k.datum))),
            DataCell(Text(k.dobavljac ?? '')),
            DataCell(Text(k.brojFakture)),
            DataCell(Text(k.brojPrijemnice)),
            DataCell(Text(k.skladiste?.naziv ?? '')),
            DataCell(Text('${_format(k.rekapitulacija.nabavnaVrijednost)} €')),
            DataCell(Text(k.rekapitulacija.kalkulisao ?? '')),
            DataCell(Text(k.rekapitulacija.robuPrimio ?? '')),
            DataCell(
              Row(
                children: [
                  IconButton(
                    tooltip: k.jeProknjizena ? 'Pregled' : 'Izmijeni',
                    onPressed: () => _otvori(k),
                    icon: Icon(
                      k.jeProknjizena
                          ? Icons.visibility_outlined
                          : Icons.edit_outlined,
                    ),
                  ),
                  if (!k.jeProknjizena) ...[
                    IconButton(
                      tooltip: 'Proknjiži',
                      onPressed: () => _proknjizi(k),
                      icon: const Icon(Icons.inventory_2_outlined),
                    ),
                    IconButton(
                      tooltip: 'Obriši',
                      onPressed: () => _obrisi(k),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boja = Theme.of(context).colorScheme.error;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Kalkulacija nabavnih cijena',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _firmaController.izabranaFirma.value == null
                      ? null
                      : () => _otvori(),
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj novi dokument'),
                ),
              ],
            ),

            const SizedBox(height: 24),
            _filteri(),
            const SizedBox(height: 16),

            if (_greska != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: boja),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(_greska!, style: TextStyle(color: boja)),
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

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(child: _tabela()),
                ),
              ),
            ),

            const SizedBox(height: 16),

            Paginacija(
              stranica: _stranica,
              zadnjaStranica: _zadnjaStranica,
              ukupno: _ukupno,
              od: _od,
              doBroja: _do,
              zakljucano: _ucitavanje,
              prazno: 'Nema kalkulacija',
              onStranica: _ucitaj,
            ),
          ],
        ),
      ),
    );
  }
}

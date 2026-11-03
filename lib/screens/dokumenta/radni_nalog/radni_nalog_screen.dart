import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/routes/app_routes.dart';
import 'package:knjigovodstvo_app/services/work_orders_service.dart';
import 'package:knjigovodstvo_app/widgets/paginacija_widget.dart';

String _formatDatum(DateTime? datum) {
  if (datum == null) return '';
  final d = datum.day.toString().padLeft(2, '0');
  final m = datum.month.toString().padLeft(2, '0');
  return '$d.$m.${datum.year}';
}

void _poruka(BuildContext context, String tekst, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(tekst), action: action));
}

// Oznaka statusa naloga (u pripremi / izdat).
Widget statusNaloga(RadniNalog nalog) {
  final izdat = nalog.jeIzdat;
  final boja = izdat ? Colors.green : Colors.orange;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: boja.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: boja.shade200),
    ),
    child: Text(
      nazivStatusa(nalog.status),
      style: TextStyle(color: boja.shade800, fontWeight: FontWeight.w600),
    ),
  );
}

// Lista radnih naloga izabrane firme: GET /companies/{company}/work-orders
class RadniNalogScreen extends StatefulWidget {
  const RadniNalogScreen({super.key});

  @override
  State<RadniNalogScreen> createState() => _RadniNalogScreenState();
}

class _RadniNalogScreenState extends State<RadniNalogScreen> {
  final searchController = TextEditingController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final WorkOrdersService _service = WorkOrdersService();
  late final Worker _firmaWorker;

  List<RadniNalog> nalozi = [];
  bool _ucitavanje = false;
  String? _greska;

  // null = svi statusi.
  String? _status;

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

  Future<void> _otvori([RadniNalog? nalog]) async {
    final sacuvano = await Get.toNamed(
      AppRoutes.dodajRadniNalog,
      arguments: nalog?.id,
    );
    if (sacuvano != true || !mounted) return;
    _ucitaj(nalog == null ? 1 : _stranica);
    _poruka(context, 'Radni nalog je sačuvan.');
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

  Future<void> _izdaj(RadniNalog nalog) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      'Izdaj radni nalog',
      'Izdavanjem naloga ${nalog.broj} materijal se skida sa skladišta '
          'sirovina i prenosi u proizvodnju. Nalog se poslije ne može '
          'mijenjati ni brisati. Nastaviti?',
      'Izdaj',
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.issueWorkOrder(firma.id, nalog.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _poruka(context, 'Radni nalog ${nalog.broj} je izdat.');
    _ucitaj(_stranica);
  }

  Future<void> _obrisi(RadniNalog nalog) async {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    final potvrda = await _potvrdi(
      'Obriši radni nalog',
      'Da li ste sigurni da želite obrisati radni nalog ${nalog.broj}?',
      'Obriši',
    );
    if (!potvrda || !mounted) return;

    try {
      await _service.deleteWorkOrder(firma.id, nalog.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;

    // Nakon brisanja zadnjeg reda na stranici vraća se na prethodnu.
    _ucitaj(nalozi.length == 1 && _stranica > 1 ? _stranica - 1 : _stranica);
    _poruka(
      context,
      'Radni nalog ${nalog.broj} je obrisan.',
      action: SnackBarAction(
        label: 'Poništi',
        onPressed: () => _vrati(firma.id, nalog),
      ),
    );
  }

  Future<void> _vrati(int firmaId, RadniNalog nalog) async {
    try {
      await _service.restoreWorkOrder(firmaId, nalog.id);
    } on ApiException catch (e) {
      if (mounted) _poruka(context, e.message);
      return;
    }

    if (!mounted) return;
    _ucitaj(_stranica);
    _poruka(context, 'Radni nalog ${nalog.broj} je vraćen.');
  }

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _filteri() {
    return Row(
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Pretraga po kupcu ili broju naloga',
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
        const SizedBox(width: 16),
        SegmentedButton<String?>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: null, label: Text('Svi')),
            ButtonSegment(value: statusNacrt, label: Text('U pripremi')),
            ButtonSegment(value: statusIzdat, label: Text('Izdati')),
          ],
          selected: {_status},
          onSelectionChanged: (izbor) {
            setState(() => _status = izbor.first);
            _ucitaj();
          },
        ),
      ],
    );
  }

  Widget _tabela() {
    if (!_ucitavanje && nalozi.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            _firmaController.izabranaFirma.value == null
                ? 'Izaberite firmu.'
                : 'Nema radnih naloga.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ),
      );
    }

    return DataTable(
      headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
      columnSpacing: 40,
      showCheckboxColumn: false,
      columns: [
        _kolona('RB'),
        _kolona('Broj naloga'),
        _kolona('Datum'),
        _kolona('Kupac'),
        _kolona('Izdao'),
        _kolona('Potpisao'),
        _kolona('Broj stavki', numeric: true),
        _kolona('Status'),
        _kolona('Akcije'),
      ],
      rows: List.generate(nalozi.length, (index) {
        final nalog = nalozi[index];

        return DataRow(
          onSelectChanged: (_) => _otvori(nalog),
          cells: [
            DataCell(Text('${(_od ?? 1) + index}')),
            DataCell(Text(nalog.broj)),
            DataCell(Text(_formatDatum(nalog.datum))),
            DataCell(Text(nalog.kupac ?? '')),
            DataCell(Text(nalog.izdao ?? '')),
            DataCell(Text(nalog.potpisao ?? '')),
            DataCell(Text('${nalog.brojStavki}')),
            DataCell(statusNaloga(nalog)),
            DataCell(
              Row(
                children: [
                  IconButton(
                    tooltip: nalog.jeIzdat ? 'Pregled' : 'Izmijeni',
                    onPressed: () => _otvori(nalog),
                    icon: Icon(
                      nalog.jeIzdat
                          ? Icons.visibility_outlined
                          : Icons.edit_outlined,
                    ),
                  ),
                  if (!nalog.jeIzdat) ...[
                    IconButton(
                      tooltip: 'Izdaj nalog',
                      onPressed: () => _izdaj(nalog),
                      icon: const Icon(Icons.outbox_outlined),
                    ),
                    IconButton(
                      tooltip: 'Obriši',
                      onPressed: () => _obrisi(nalog),
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
                  'Radni nalog',
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
              prazno: 'Nema radnih naloga',
              onStranica: _ucitaj,
            ),
          ],
        ),
      ),
    );
  }
}

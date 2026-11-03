import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/radni_nalog/radni_nalog_screen.dart';
import 'package:knjigovodstvo_app/services/work_orders_service.dart';
import 'package:knjigovodstvo_app/widgets/paginacija_widget.dart';

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

// Količine normativa znaju biti male (0,007 kg) pa prikazujemo do 4 decimale.
String _formatKolicina(double value) {
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

// Svaki radni nalog ima tačno jedno trebovanje (pravi se pri snimanju
// naloga), pa se lista trebovanja čita iz liste naloga, a sadržaj sa
// GET /companies/{company}/work-orders/{workOrder}/requisition.
class TrebovanjeScreen extends StatefulWidget {
  const TrebovanjeScreen({super.key});

  @override
  State<TrebovanjeScreen> createState() => _TrebovanjeScreenState();
}

class _TrebovanjeScreenState extends State<TrebovanjeScreen> {
  final searchController = TextEditingController();

  final FirmaController _firmaController = Get.find<FirmaController>();
  final WorkOrdersService _service = WorkOrdersService();
  late final Worker _firmaWorker;

  List<RadniNalog> nalozi = [];
  bool _ucitavanje = false;
  String? _greska;

  String? _status;

  int _stranica = 1;
  int _zadnjaStranica = 1;
  int _ukupno = 0;
  int? _od;
  int? _do;

  Timer? _pretragaTimer;
  String _pretraga = '';
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

  void _prikaziTrebovanje(RadniNalog nalog) {
    final firma = _firmaController.izabranaFirma.value;
    if (firma == null) return;

    showDialog(
      context: context,
      builder: (context) => _TrebovanjeDialog(firmaId: firma.id, nalog: nalog),
    );
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
            ButtonSegment(value: null, label: Text('Sva')),
            ButtonSegment(value: statusNacrt, label: Text('U pripremi')),
            ButtonSegment(value: statusIzdat, label: Text('Izdata')),
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
                : 'Nema trebovanja.',
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
        _kolona('Radni nalog'),
        _kolona('Datum'),
        _kolona('Kupac'),
        _kolona('Izdaje'),
        _kolona('Prima'),
        _kolona('Broj stavki', numeric: true),
        _kolona('Status'),
        _kolona('Akcije'),
      ],
      rows: List.generate(nalozi.length, (index) {
        final nalog = nalozi[index];

        return DataRow(
          // Klik bilo gdje na red otvara pregled trebovanja.
          onSelectChanged: (_) => _prikaziTrebovanje(nalog),
          cells: [
            DataCell(Text('${(_od ?? 1) + index}')),
            DataCell(Text(nalog.broj)),
            DataCell(Text(_formatDatum(nalog.datum))),
            DataCell(Text(nalog.kupac ?? '')),
            DataCell(Text(nalog.izvor?.naziv ?? '')),
            DataCell(Text(nalog.odrediste?.naziv ?? '')),
            DataCell(Text('${nalog.brojStavki}')),
            DataCell(statusNaloga(nalog)),
            DataCell(
              IconButton(
                tooltip: 'Pregled',
                onPressed: () => _prikaziTrebovanje(nalog),
                icon: const Icon(Icons.visibility_outlined),
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
            const Text(
              'Trebovanje',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
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
              prazno: 'Nema trebovanja',
              onStranica: _ucitaj,
            ),
          ],
        ),
      ),
    );
  }
}

// Pop-up sa trebovanjem jednog naloga: zaglavlje, artikli i materijali.
class _TrebovanjeDialog extends StatefulWidget {
  final int firmaId;
  final RadniNalog nalog;

  const _TrebovanjeDialog({required this.firmaId, required this.nalog});

  @override
  State<_TrebovanjeDialog> createState() => _TrebovanjeDialogState();
}

class _TrebovanjeDialogState extends State<_TrebovanjeDialog> {
  final WorkOrdersService _service = WorkOrdersService();

  Trebovanje? _trebovanje;
  String? _greska;

  static const _bold = TextStyle(fontWeight: FontWeight.bold);

  @override
  void initState() {
    super.initState();
    _ucitaj();
  }

  Future<void> _ucitaj() async {
    setState(() {
      _greska = null;
      _trebovanje = null;
    });

    try {
      final trebovanje = await _service.fetchRequisition(
        widget.firmaId,
        widget.nalog.id,
      );
      if (mounted) setState(() => _trebovanje = trebovanje);
    } on ApiException catch (e) {
      if (mounted) setState(() => _greska = e.message);
    }
  }

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: _bold),
    );
  }

  Widget _okvir(Widget tabela) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: tabela,
      ),
    );
  }

  Widget _sekcija(String naslov) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 12),
      child: Text(
        naslov,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _podatak(String label, String vrijednost) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 4),
        Text(vrijednost, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildTabelaArtikala(Trebovanje trebovanje) {
    return _okvir(
      DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 32,
        columns: [
          _kolona('Rb'),
          _kolona('Šifra artikla'),
          _kolona('Naziv artikla'),
          _kolona('Jedinica mjere'),
          _kolona('Količina', numeric: true),
        ],
        rows: List.generate(trebovanje.stavke.length, (index) {
          final stavka = trebovanje.stavke[index];

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(stavka.sifra)),
              DataCell(Text(stavka.naziv)),
              DataCell(Text(stavka.jm)),
              DataCell(Text(_formatKolicina(stavka.kolicina))),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTabelaMaterijala(Trebovanje trebovanje) {
    final redovi = <DataRow>[];

    for (final stavka in trebovanje.stavke) {
      for (final m in stavka.materijali) {
        // Bez ručno unesene količine materijal se izdaje kako je traženo.
        final izdato = m.izdato ?? m.trazeno;
        final razlika = izdato != m.trazeno;

        redovi.add(
          DataRow(
            cells: [
              DataCell(Text('${redovi.length + 1}')),
              DataCell(Text(stavka.sifra)),
              DataCell(Text(m.naziv)),
              DataCell(Text(m.jm)),
              DataCell(Text(_formatKolicina(m.norma))),
              DataCell(Text(_formatKolicina(m.trazeno))),
              DataCell(
                Text(
                  _formatKolicina(izdato),
                  style: razlika
                      ? TextStyle(
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        )
                      : null,
                ),
              ),
              DataCell(
                Text(
                  m.vrijednost == null ? '—' : '${_format(m.vrijednost!)} €',
                ),
              ),
            ],
          ),
        );
      }
    }

    final ukupno = trebovanje.vrijednost;
    redovi.add(
      DataRow(
        color: WidgetStateProperty.all(Colors.grey.shade100),
        cells: [
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('Ukupno', style: _bold)),
          for (var i = 0; i < 4; i++) const DataCell(Text('')),
          DataCell(
            Text(ukupno == null ? '—' : '${_format(ukupno)} €', style: _bold),
          ),
        ],
      ),
    );

    return _okvir(
      DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
        columnSpacing: 32,
        columns: [
          _kolona('Rb'),
          _kolona('Artikal'),
          _kolona('Materijal'),
          _kolona('Jed. mjere'),
          _kolona('Norma', numeric: true),
          _kolona('Trebovano', numeric: true),
          _kolona('Izdato', numeric: true),
          _kolona('Vrijednost', numeric: true),
        ],
        rows: redovi,
      ),
    );
  }

  Widget _sadrzaj() {
    final trebovanje = _trebovanje;

    if (_greska != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Text(
              _greska!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _ucitaj, child: const Text('Pokušaj ponovo')),
          ],
        ),
      );
    }

    if (trebovanje == null) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final nalog = widget.nalog;
    final vrijednost = trebovanje.vrijednost;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 48,
            runSpacing: 16,
            children: [
              _podatak('Datum', _formatDatum(trebovanje.datum)),
              _podatak('Radni nalog', trebovanje.brojNaloga ?? nalog.broj),
              _podatak('Kupac', trebovanje.kupac ?? nalog.kupac ?? ''),
              _podatak('Izdaje', nalog.izvor?.naziv ?? ''),
              _podatak('Prima', nalog.odrediste?.naziv ?? ''),
              _podatak('Status', nazivStatusa(nalog.status)),
              _podatak(
                'Vrijednost',
                vrijednost == null
                    ? 'obračunava se pri izdavanju'
                    : '${_format(vrijednost)} €',
              ),
            ],
          ),

          _sekcija('Artikli'),
          _buildTabelaArtikala(trebovanje),

          _sekcija('Materijali'),
          _buildTabelaMaterijala(trebovanje),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 8),
              child: Row(
                children: [
                  Text(
                    'Trebovanje — ${widget.nalog.broj}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Zatvori',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            Flexible(child: _sadrzaj()),

            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Zatvori'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

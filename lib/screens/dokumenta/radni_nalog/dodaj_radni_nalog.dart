import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/models/article.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/radni_nalog/radni_nalog_screen.dart';
import 'package:knjigovodstvo_app/services/articles_service.dart';
import 'package:knjigovodstvo_app/services/work_orders_service.dart';
import 'package:knjigovodstvo_app/widgets/input_widget.dart';

double _parse(String text) {
  return double.tryParse(text.trim().replaceAll(',', '.')) ?? 0;
}

String _format(double value) {
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

// Količine normativa znaju biti male (0,007 kg) pa prikazujemo do 4 decimale
// (koliko ih vraća i API).
String _formatKolicina(double value) {
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

// Jedan gotov proizvod na nalogu sa svojim materijalima (normativ × količina).
// Izdato prati traženu količinu dok ga korisnik ručno ne promijeni; samo
// ručno unesene količine se šalju serveru.
class _StavkaArtikla {
  final Artikal artikal;
  final TextEditingController kolicina;

  // Ključ = id stavke normativa (bom_item_id).
  final Map<int, TextEditingController> izdato = {};
  final Set<int> rucno = {};

  // Vrijednost po prosječnoj cijeni koju je server obračunao pri izdavanju.
  final Map<int, double> izdataVrijednost;

  _StavkaArtikla({
    required this.artikal,
    required double kolicina,
    Map<int, double> izdatoRucno = const {},
    this.izdataVrijednost = const {},
  }) : kolicina = TextEditingController(text: _formatKolicina(kolicina)) {
    for (final normativ in materijali) {
      izdato[normativ.id!] = TextEditingController();
    }
    izdatoRucno.forEach((bomItemId, vrijednost) {
      final controller = izdato[bomItemId];
      if (controller == null) return;
      rucno.add(bomItemId);
      controller.text = _formatKolicina(vrijednost);
    });
    osvjeziIzdato();
  }

  Iterable<Normativ> get materijali =>
      artikal.normativi.where((n) => n.id != null);

  double get kol => _parse(kolicina.text);

  double trazeno(Normativ normativ) => normativ.kolicina * kol;

  void osvjeziIzdato() {
    for (final normativ in materijali) {
      if (!rucno.contains(normativ.id)) {
        izdato[normativ.id]!.text = _formatKolicina(trazeno(normativ));
      }
    }
  }

  double vrijednost(Normativ normativ) =>
      izdataVrijednost[normativ.id] ??
      _parse(izdato[normativ.id]!.text) * normativ.cijena;

  StavkaNaloga zaApi() => StavkaNaloga(
    articleId: artikal.id!,
    kolicina: kol,
    izdato: {for (final id in rucno) id: _parse(izdato[id]!.text)},
  );

  void dispose() {
    kolicina.dispose();
    for (final controller in izdato.values) {
      controller.dispose();
    }
  }
}

// Novi radni nalog (bez argumenta) ili izmjena postojećeg: Get.arguments je
// id naloga. Izdat nalog se samo pregleda.
class DodajRadniNalog extends StatefulWidget {
  const DodajRadniNalog({super.key});

  @override
  State<DodajRadniNalog> createState() => _DodajRadniNalogState();
}

class _DodajRadniNalogState extends State<DodajRadniNalog> {
  final FirmaController _firmaController = Get.find<FirmaController>();
  final WorkOrdersService _service = WorkOrdersService();
  final ArticlesService _articlesService = ArticlesService();

  final datumController = TextEditingController();
  final brojController = TextEditingController();
  final izdaoController = TextEditingController();
  final potpisaoController = TextEditingController();

  final List<_StavkaArtikla> stavke = [];

  int? _firmaId;
  int? _nalogId;
  RadniNalog? _nalog;

  DateTime _datum = DateTime.now();
  List<Kupac> _kupci = [];
  int? _kupacId;

  bool _ucitavanje = true;
  String? _greskaUcitavanja;
  bool _cuvanje = false;
  ApiException? _greska;

  // Da li je nešto snimljeno, da lista zna da se osvježi.
  bool _promijenjeno = false;

  bool get _samoPregled => _nalog?.jeIzdat ?? false;

  @override
  void initState() {
    super.initState();
    _firmaId = _firmaController.izabranaFirma.value?.id;
    final argument = Get.arguments;
    _nalogId = argument is int ? argument : null;
    datumController.text = _formatDatum(_datum);
    _ucitaj();
  }

  @override
  void dispose() {
    datumController.dispose();
    brojController.dispose();
    izdaoController.dispose();
    potpisaoController.dispose();
    for (final stavka in stavke) {
      stavka.dispose();
    }
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
      final kupci = _service.fetchCustomers(firmaId);
      final nalog = _nalogId == null
          ? null
          : await _service.fetchWorkOrder(firmaId, _nalogId!);
      final noveStavke = nalog == null
          ? <_StavkaArtikla>[]
          : await _stavkeIz(firmaId, nalog);

      final listaKupaca = await kupci;
      if (!mounted) {
        for (final s in noveStavke) {
          s.dispose();
        }
        return;
      }

      setState(() {
        _kupci = listaKupaca;
        if (nalog != null) _postaviNalog(nalog, noveStavke);
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _greskaUcitavanja = e.message);
    } finally {
      if (mounted) setState(() => _ucitavanje = false);
    }
  }

  void _postaviNalog(RadniNalog nalog, List<_StavkaArtikla> noveStavke) {
    _nalog = nalog;
    _nalogId = nalog.id;
    _datum = nalog.datum ?? _datum;
    datumController.text = _formatDatum(_datum);
    brojController.text = nalog.broj;
    izdaoController.text = nalog.izdao ?? '';
    potpisaoController.text = nalog.potpisao ?? '';
    _kupacId = nalog.customerId;

    // Obrisan kupac se ne vraća u listi, ali ostaje vidljiv na nalogu.
    if (_kupacId != null && !_kupci.any((k) => k.id == _kupacId)) {
      _kupci = [
        Kupac(id: _kupacId!, naziv: nalog.kupac ?? 'Kupac #$_kupacId'),
        ..._kupci,
      ];
    }

    for (final stavka in stavke) {
      stavka.dispose();
    }
    stavke
      ..clear()
      ..addAll(noveStavke);
  }

  // Stavke naloga iz trebovanja. Artikli se učitavaju zbog cijena i aktuelnog
  // normativa; ako artikal više ne postoji, normativ se gradi iz trebovanja.
  Future<List<_StavkaArtikla>> _stavkeIz(int firmaId, RadniNalog nalog) async {
    final stavkeTrebovanja = nalog.trebovanje?.stavke ?? const [];
    final izdat = nalog.jeIzdat;

    final artikli = await Future.wait(
      stavkeTrebovanja.map((s) async {
        // Za izdat nalog važi normativ kako je bio pri izdavanju.
        if (izdat) return null;
        try {
          return await _articlesService.fetchArticle(firmaId, s.articleId);
        } on ApiException {
          return null;
        }
      }),
    );

    return List.generate(stavkeTrebovanja.length, (i) {
      final s = stavkeTrebovanja[i];
      final artikal =
          artikli[i] ??
          Artikal(
            id: s.articleId,
            tip: tipGotovProizvod,
            sifra: s.sifra,
            naziv: s.naziv,
            jm: s.jm,
            normativi: s.materijali
                .map(
                  (m) => Normativ(
                    id: m.bomItemId,
                    materialId: m.materialId,
                    naziv: m.naziv,
                    // Kod izdatog naloga: stvarna prosječna cijena izdavanja.
                    cijena: (m.vrijednost != null && (m.izdato ?? 0) > 0)
                        ? m.vrijednost! / m.izdato!
                        : 0,
                    kolicina: m.norma,
                    jm: m.jm,
                  ),
                )
                .toList(),
          );

      return _StavkaArtikla(
        artikal: artikal,
        kolicina: s.kolicina,
        izdatoRucno: {
          for (final m in s.materijali)
            if (m.izdato != null) m.bomItemId: m.izdato!,
        },
        izdataVrijednost: {
          for (final m in s.materijali)
            if (m.vrijednost != null) m.bomItemId: m.vrijednost!,
        },
      );
    });
  }

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

  Future<void> _dodajArtikal() async {
    final firmaId = _firmaId;
    if (firmaId == null) return;

    final rezultat = await showDialog<(Artikal, double)>(
      context: context,
      builder: (context) => _DodajArtikalDialog(firmaId: firmaId),
    );
    if (rezultat == null || !mounted) return;

    final (artikal, kolicina) = rezultat;

    setState(() {
      final postojeca = stavke
          .where((s) => s.artikal.id == artikal.id)
          .firstOrNull;

      // Isti artikal dodat ponovo -> samo se povećava količina
      // (API ne dozvoljava ponavljanje proizvoda na nalogu).
      if (postojeca != null) {
        postojeca.kolicina.text = _formatKolicina(postojeca.kol + kolicina);
        postojeca.osvjeziIzdato();
      } else {
        stavke.add(_StavkaArtikla(artikal: artikal, kolicina: kolicina));
      }
    });
  }

  void _obrisiArtikal(_StavkaArtikla stavka) {
    setState(() {
      stavke.remove(stavka);
      stavka.dispose();
    });
  }

  // Lokalna provjera prije slanja; ostalo provjerava server (422).
  String? _provjeri() {
    if (_kupacId == null) return 'Izaberite kupca.';
    if (brojController.text.trim().isEmpty) return 'Unesite broj naloga.';
    if (stavke.isEmpty) return 'Dodajte bar jedan artikal.';
    if (stavke.any((s) => s.kol <= 0)) {
      return 'Količina svakog artikla mora biti veća od 0.';
    }
    return null;
  }

  // Snima nalog (kreira ili mijenja) i vraća ga; null ako nije uspjelo.
  Future<RadniNalog?> _sacuvaj() async {
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
      final nalog = _nalogId == null
          ? await _service.createWorkOrder(
              firmaId,
              customerId: _kupacId!,
              date: _datum,
              orderNumber: brojController.text.trim(),
              issuedBy: izdaoController.text,
              signedBy: potpisaoController.text,
              items: items,
            )
          : await _service.updateWorkOrder(
              firmaId,
              _nalogId!,
              customerId: _kupacId,
              date: _datum,
              orderNumber: brojController.text.trim(),
              issuedBy: izdaoController.text,
              signedBy: potpisaoController.text,
              items: items,
            );

      _promijenjeno = true;
      _nalog = nalog;
      _nalogId = nalog.id;
      return nalog;
    } on ApiException catch (e) {
      if (mounted) setState(() => _greska = e);
      return null;
    } finally {
      if (mounted) setState(() => _cuvanje = false);
    }
  }

  Future<void> _sacuvajIZatvori() async {
    final nalog = await _sacuvaj();
    if (nalog == null || !mounted) return;

    Get.back(result: true);
  }

  Future<void> _sacuvajIIzdaj() async {
    final potvrda = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Izdaj radni nalog'),
        content: const Text(
          'Nalog se snima i izdaje: materijal se skida sa skladišta sirovina '
          'po prosječnoj cijeni i prenosi u proizvodnju. Poslije izdavanja '
          'nalog se ne može mijenjati ni brisati. Nastaviti?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Izdaj'),
          ),
        ],
      ),
    );
    if (potvrda != true || !mounted) return;

    final nalog = await _sacuvaj();
    if (nalog == null || !mounted) return;

    setState(() {
      _cuvanje = true;
      _greska = null;
    });

    try {
      final izdat = await _service.issueWorkOrder(_firmaId!, nalog.id);
      final noveStavke = await _stavkeIz(_firmaId!, izdat);
      if (!mounted) return;
      setState(() => _postaviNalog(izdat, noveStavke));
      _poruka(context, 'Radni nalog ${izdat.broj} je izdat.');
    } on ApiException catch (e) {
      // Nalog je sačuvan, ali nije izdat (npr. nema dovoljno zalihe).
      if (mounted) setState(() => _greska = e);
    } finally {
      if (mounted) setState(() => _cuvanje = false);
    }
  }

  DataColumn _kolona(String naslov, {bool numeric = false}) {
    return DataColumn(
      numeric: numeric,
      label: Text(naslov, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _celijaInput(
    TextEditingController controller, {
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: 100,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        readOnly: _samoPregled,
        textAlign: TextAlign.right,
        inputFormatters: [_decimalFormatter],
        decoration: const InputDecoration(isDense: true),
      ),
    );
  }

  Widget _sekcija(String naslov, {Widget? akcija}) {
    return Row(
      children: [
        Text(
          naslov,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        ?akcija,
      ],
    );
  }

  Widget _okvir(Widget child) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );
  }

  Widget _prazno(String poruka) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(poruka, style: TextStyle(color: Colors.grey.shade600)),
    );
  }

  Widget _buildKupac() {
    return DropdownButtonFormField<int>(
      // Key prati učitavanje da bi se prikazala vrijednost postojećeg naloga.
      key: ValueKey('kupac-$_kupacId-${_kupci.length}'),
      initialValue: _kupacId,
      isExpanded: true,
      forceErrorText: _greska?.fieldError('customer_id'),
      decoration: InputDecoration(
        labelText: 'Kupac',
        filled: true,
        fillColor: _samoPregled ? Colors.grey.shade200 : Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      hint: Text(_kupci.isEmpty ? 'Nema unesenih kupaca' : 'Izaberite kupca'),
      items: _kupci
          .map(
            (k) => DropdownMenuItem(
              value: k.id,
              child: Text(
                k.grad == null ? k.naziv : '${k.naziv} (${k.grad})',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _samoPregled ? null : (id) => setState(() => _kupacId = id),
    );
  }

  Widget _buildTabelaArtikala() {
    if (stavke.isEmpty) {
      return _prazno('Nema dodatih artikala. Klikni "Dodaj artikal".');
    }

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
          _kolona('Cijena koštanja', numeric: true),
          if (!_samoPregled) _kolona(''),
        ],
        rows: List.generate(stavke.length, (index) {
          final stavka = stavke[index];

          return DataRow(
            cells: [
              DataCell(Text('${index + 1}')),
              DataCell(Text(stavka.artikal.sifra)),
              DataCell(Text(stavka.artikal.naziv)),
              DataCell(Text(stavka.artikal.jm)),
              DataCell(
                _celijaInput(
                  stavka.kolicina,
                  onChanged: (_) => setState(stavka.osvjeziIzdato),
                ),
              ),
              DataCell(Text('${_format(stavka.artikal.cijenaNormativa)} €')),
              if (!_samoPregled)
                DataCell(
                  IconButton(
                    tooltip: 'Obriši',
                    onPressed: () => _obrisiArtikal(stavka),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTabelaMaterijala() {
    if (stavke.isEmpty) {
      return _prazno('Materijali se prikazuju automatski kad dodaš artikal.');
    }

    double ukupno = 0;
    final redovi = <DataRow>[];

    for (final stavka in stavke) {
      for (final normativ in stavka.materijali) {
        final id = normativ.id!;
        final vrijednost = stavka.vrijednost(normativ);
        ukupno += vrijednost;
        final rucno = stavka.rucno.contains(id);

        redovi.add(
          DataRow(
            cells: [
              DataCell(Text('${redovi.length + 1}')),
              DataCell(Text(stavka.artikal.sifra)),
              DataCell(Text(normativ.naziv)),
              DataCell(Text(normativ.jm)),
              DataCell(Text(_formatKolicina(normativ.kolicina))),
              DataCell(Text(_formatKolicina(stavka.trazeno(normativ)))),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _celijaInput(
                      stavka.izdato[id]!,
                      onChanged: (_) => setState(() => stavka.rucno.add(id)),
                    ),
                    if (rucno && !_samoPregled)
                      IconButton(
                        tooltip: 'Vrati na traženu količinu',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          stavka.rucno.remove(id);
                          stavka.osvjeziIzdato();
                        }),
                        icon: const Icon(Icons.undo, size: 18),
                      ),
                  ],
                ),
              ),
              DataCell(Text('${_format(normativ.cijena)} €')),
              DataCell(Text('${_format(vrijednost)} €')),
            ],
          ),
        );
      }
    }

    const bold = TextStyle(fontWeight: FontWeight.bold);
    redovi.add(
      DataRow(
        color: WidgetStateProperty.all(Colors.grey.shade100),
        cells: [
          const DataCell(Text('')),
          const DataCell(Text('')),
          const DataCell(Text('Ukupno', style: bold)),
          for (var i = 0; i < 5; i++) const DataCell(Text('')),
          DataCell(Text('${_format(ukupno)} €', style: bold)),
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
          _kolona('Cijena', numeric: true),
          _kolona('Vrijednost', numeric: true),
        ],
        rows: redovi,
      ),
    );
  }

  // Greške servera koje nisu vezane za polje forme (stavke, zaliha...).
  Widget? _buildGreske() {
    final greska = _greska;
    if (greska == null) return null;

    const poljaForme = {'customer_id', 'order_number', 'date'};
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _nalog == null ? 'Radni nalog' : 'Radni nalog ${_nalog!.broj}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 16),
            if (_nalog != null) statusNaloga(_nalog!),
          ],
        ),
        if (_samoPregled) ...[
          const SizedBox(height: 12),
          Text(
            'Nalog je izdat i više se ne može mijenjati.',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
        if (_nalog?.izvor != null && _nalog?.odrediste != null) ...[
          const SizedBox(height: 8),
          Text(
            'Izdaje: ${_nalog!.izvor!.naziv}  →  Prima: '
            '${_nalog!.odrediste!.naziv}',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
        const SizedBox(height: 30),

        // Red 1: Datum + Broj naloga
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _izaberiDatum,
                child: AbsorbPointer(
                  child: buildInput(
                    controller: datumController,
                    label: 'Datum',
                    width: null,
                    readOnly: _samoPregled,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                controller: brojController,
                readOnly: _samoPregled,
                decoration: InputDecoration(
                  labelText: 'Broj naloga',
                  errorText: _greska?.fieldError('order_number'),
                  filled: true,
                  fillColor: _samoPregled
                      ? Colors.grey.shade200
                      : Colors.grey.shade50,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Red 2: Kupac
        _buildKupac(),
        const SizedBox(height: 20),

        // Red 3: Izdao + Potpisao
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: buildInput(
                controller: izdaoController,
                label: 'Izdao',
                width: null,
                readOnly: _samoPregled,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: buildInput(
                controller: potpisaoController,
                label: 'Potpisao',
                width: null,
                readOnly: _samoPregled,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),

        _sekcija(
          'Artikli',
          akcija: _samoPregled
              ? null
              : ElevatedButton.icon(
                  onPressed: _cuvanje ? null : _dodajArtikal,
                  icon: const Icon(Icons.add),
                  label: const Text('Dodaj artikal'),
                ),
        ),
        const SizedBox(height: 12),
        _buildTabelaArtikala(),
        const SizedBox(height: 32),

        _sekcija('Trebovano materijala iz magacina repromaterijala'),
        const SizedBox(height: 12),
        _buildTabelaMaterijala(),
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
                onPressed: zakljucano ? null : _sacuvajIIzdaj,
                icon: const Icon(Icons.outbox_outlined, size: 24),
                label: const Text('Sačuvaj i izdaj'),
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
          title: Text(_nalogId == null ? 'Dodaj radni nalog' : 'Radni nalog'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: sadrzaj,
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// DIJALOG: izbor gotovog proizvoda (sa normativom) i količine
// GET /companies/{company}/work-orders/articles
// ======================================================================
class _DodajArtikalDialog extends StatefulWidget {
  final int firmaId;

  const _DodajArtikalDialog({required this.firmaId});

  @override
  State<_DodajArtikalDialog> createState() => _DodajArtikalDialogState();
}

class _DodajArtikalDialogState extends State<_DodajArtikalDialog> {
  final WorkOrdersService _service = WorkOrdersService();
  final pretragaController = TextEditingController();
  final kolicinaController = TextEditingController(text: '1');

  List<Artikal> _rezultati = [];
  Artikal? _artikal;
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
    kolicinaController.dispose();
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
      final rezultati = await _service.searchProducts(
        widget.firmaId,
        search: pretragaController.text,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() => _rezultati = rezultati);
    } on ApiException catch (e) {
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        _rezultati = [];
        // Server može tražiti pojam za pretragu.
        _greska = e.statusCode == 422 && pretragaController.text.trim().isEmpty
            ? 'Ukucajte šifru ili naziv proizvoda.'
            : e.message;
      });
    } finally {
      if (mounted && zahtjev == _zahtjev) {
        setState(() => _ucitavanje = false);
      }
    }
  }

  void _potvrdi() {
    final kolicina = _parse(kolicinaController.text);
    if (_artikal == null || kolicina <= 0) return;

    Navigator.of(context).pop((_artikal!, kolicina));
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
          'Nema gotovih proizvoda sa normativom.',
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
            '${artikal.brojNormativa} materijala · '
            '${_format(artikal.cijenaNormativa)} € / ${artikal.jm}',
          ),
          onTap: () => setState(() => _artikal = artikal),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Dodaj artikal'),
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
                labelText: 'Pretraga gotovih proizvoda',
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
              constraints: const BoxConstraints(maxHeight: 280),
              child: _lista(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: kolicinaController,
              inputFormatters: [_decimalFormatter],
              onSubmitted: (_) => _potvrdi(),
              decoration: InputDecoration(
                labelText: 'Količina',
                suffixText: _artikal?.jm,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Odustani'),
        ),
        ElevatedButton(
          onPressed: _artikal == null ? null : _potvrdi,
          child: const Text('Dodaj'),
        ),
      ],
    );
  }
}

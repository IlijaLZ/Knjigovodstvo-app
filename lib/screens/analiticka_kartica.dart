import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/stock_card.dart';
import 'package:knjigovodstvo_app/services/articles_service.dart';
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

// Analitička kartica artikla:
// GET /companies/{company}/articles/{article}/stock-card
// Ako je zadat warehouseId, prikazuju se samo promjene na tom skladištu.
class AnalitickaKarticaScreen extends StatefulWidget {
  final int articleId;
  final String sifra;
  final String naziv;
  final String? jm;
  final int? warehouseId;
  final String? skladiste;

  const AnalitickaKarticaScreen({
    super.key,
    required this.articleId,
    required this.sifra,
    required this.naziv,
    this.jm,
    this.warehouseId,
    this.skladiste,
  });

  static const Color headerColor = Color(0xFFE2E8F0);
  static const Color groupHeaderColor = Color(0xFFCBD5E1);
  static const Color borderColor = Color(0xFFCBD5E1);

  @override
  State<AnalitickaKarticaScreen> createState() =>
      _AnalitickaKarticaScreenState();
}

class _AnalitickaKarticaScreenState extends State<AnalitickaKarticaScreen> {
  final FirmaController _firmaController = Get.find<FirmaController>();
  final ArticlesService _service = ArticlesService();

  List<PromjenaKartice> _promjene = [];
  bool _ucitavanje = false;
  String? _greska;

  int _stranica = 1;
  int _zadnjaStranica = 1;
  int _ukupno = 0;
  int? _od;
  int? _do;
  int _zahtjev = 0;

  static const List<double> sirine = [
    55,
    100,
    115,
    200,
    100,
    100,
    100,
    150,
    120,
    120,
    120,
  ];

  static const List<String> zaglavlja = [
    'Rb',
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

  @override
  void initState() {
    super.initState();
    _ucitaj();
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
        page: stranica,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      setState(() {
        _promjene = rezultat.promjene;
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

  List<String> _celije(int index, PromjenaKartice p) => [
    '${(_od ?? 1) + index}',
    _formatDatum(p.datum),
    p.brojDokumenta ?? '',
    widget.warehouseId == null && p.skladiste != null
        ? '${p.nazivDokumenta} · ${p.skladiste!.naziv}'
        : p.nazivDokumenta,
    _format4(p.ulaz),
    _format4(p.izlaz),
    _format4(p.saldoKolicina),
    _format4(p.cijena),
    _format(p.vrijednostUlaz),
    _format(p.vrijednostIzlaz),
    _format(p.saldoVrijednost),
  ];

  Widget _celija(
    String tekst, {
    required double visina,
    Alignment poravnanje = Alignment.center,
    bool zaglavlje = false,
  }) {
    return Container(
      height: visina,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      alignment: poravnanje,
      child: Text(
        tekst,
        textAlign: zaglavlje ? TextAlign.center : null,
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
        style: TextStyle(
          fontSize: 12,
          fontWeight: zaglavlje ? FontWeight.bold : FontWeight.normal,
          color: zaglavlje ? const Color(0xFF0F172A) : const Color(0xFF334155),
        ),
      ),
    );
  }

  Widget _tabela() {
    final ukupnaSirina = sirine.reduce((a, b) => a + b);
    final kolone = {
      for (int i = 0; i < sirine.length; i++) i: FixedColumnWidth(sirine[i]),
    };
    final okvir = TableBorder.all(
      color: AnalitickaKarticaScreen.borderColor,
      width: 1,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: ukupnaSirina,
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Krovno zaglavlje (Količinski / Vrijednosno)
              Row(
                children: [
                  _blok(sirine[0] + sirine[1] + sirine[2] + sirine[3], null),
                  _blok(sirine[4] + sirine[5] + sirine[6], 'Količinski'),
                  _blok(sirine[7], null),
                  _blok(sirine[8] + sirine[9] + sirine[10], 'Vrijednosno'),
                ],
              ),
              Table(
                columnWidths: kolone,
                border: okvir,
                children: [
                  TableRow(
                    decoration: const BoxDecoration(
                      color: AnalitickaKarticaScreen.headerColor,
                    ),
                    children: [
                      for (final z in zaglavlja)
                        _celija(z, visina: 60, zaglavlje: true),
                    ],
                  ),
                ],
              ),
              if (_promjene.isEmpty && !_ucitavanje)
                Container(
                  width: ukupnaSirina,
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.center,
                  child: Text(
                    _greska ?? 'Artikal nema promjena na kartici.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              else
                Table(
                  columnWidths: kolone,
                  border: okvir,
                  children: List.generate(_promjene.length, (rowIndex) {
                    final celije = _celije(rowIndex, _promjene[rowIndex]);
                    return TableRow(
                      decoration: BoxDecoration(
                        color: rowIndex.isEven
                            ? Colors.white
                            : const Color(0xFFF8FAFC),
                      ),
                      children: List.generate(celije.length, (i) {
                        return _celija(
                          celije[i],
                          visina: 52,
                          poravnanje: i == 0
                              ? Alignment.center
                              : i >= 4
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                        );
                      }),
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podnaslov = [
      'Šifra: ${widget.sifra}',
      if (widget.jm != null) 'JM: ${widget.jm}',
      widget.skladiste ?? 'Sva skladišta',
    ].join('  ·  ');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Analitička kartica'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.naziv,
              style: const TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(podnaslov, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 16),
            if (_greska != null && _promjene.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _greska!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (_ucitavanje)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            Expanded(child: _tabela()),
            const SizedBox(height: 12),
            Paginacija(
              stranica: _stranica,
              zadnjaStranica: _zadnjaStranica,
              ukupno: _ukupno,
              od: _od,
              doBroja: _do,
              zakljucano: _ucitavanje,
              prazno: 'Nema promjena',
              onStranica: _ucitaj,
            ),
          ],
        ),
      ),
    );
  }

  Widget _blok(double sirina, String? naslov) {
    return Container(
      width: sirina,
      height: 42,
      decoration: BoxDecoration(
        color: naslov == null
            ? Colors.transparent
            : AnalitickaKarticaScreen.groupHeaderColor,
        border: naslov == null
            ? null
            : Border.all(color: AnalitickaKarticaScreen.borderColor, width: 1),
      ),
      alignment: Alignment.center,
      child: naslov == null
          ? null
          : Text(
              naslov,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Color(0xFF0F172A),
              ),
            ),
    );
  }
}

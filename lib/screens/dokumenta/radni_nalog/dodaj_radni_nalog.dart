import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/controllers/poslovne_godine_controller.dart';
import 'package:knjigovodstvo_app/models/article.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/stampa/pdf_zajednicko.dart';
import 'package:knjigovodstvo_app/stampa/pregled_stampe.dart';
import 'package:knjigovodstvo_app/stampa/radni_nalog_pdf.dart';
import 'package:knjigovodstvo_app/services/articles_service.dart';
import 'package:knjigovodstvo_app/services/work_orders_service.dart';
import 'package:knjigovodstvo_app/widgets/logo.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';

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
  final sirina = MediaQuery.sizeOf(context).width;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(tekst),
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
const Color _nacrt = Color(0xFFB45309);
const Color _nacrtSvijetlo = Color(0xFFFEF3C7);
const Color _izdat = Color(0xFF0369A1);
const Color _izdatSvijetlo = Color(0xFFE0F2FE);

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

  // Vrijednost svog materijala izdatog za ovaj proizvod.
  double get vrijednostMaterijala =>
      materijali.fold(0, (suma, n) => suma + vrijednost(n));

  // Cijena koštanja po komadu: izdati materijal / količina. Prati ručno
  // izdate količine (izdato 5 -> 3 smanjuje cijenu). Bez materijala ili
  // količine ostaje cijena iz šifarnika.
  double get cijenaKostanja {
    if (materijali.isEmpty || kol <= 0) return artikal.cijenaNormativa;
    return vrijednostMaterijala / kol;
  }

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

  // Nalog iz zaključene poslovne godine se ne može mijenjati.
  bool get _zakljucenaGodina =>
      _nalog != null && PoslovneGodineController.zakljucenDatum(_nalog!.datum);

  bool get _samoPregled => (_nalog?.jeIzdat ?? false) || _zakljucenaGodina;

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
      // Datumi iz zaključenih poslovnih godina se ne nude.
      initialDate: PoslovneGodineController.zakljucenDatum(_datum)
          ? DateTime.now()
          : _datum,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      selectableDayPredicate: (d) =>
          !PoslovneGodineController.zakljucenDatum(d),
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
      barrierColor: const Color(0x800F172A),
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
      barrierColor: const Color(0x800F172A),
      builder: (context) => const PotvrdaDijalog(
        naslov: 'Sačuvaj i izdaj nalog?',
        tekst:
            'Nalog se snima i izdaje: materijal se skida sa skladišta '
            'sirovina po prosječnoj cijeni i prenosi u proizvodnju. Poslije '
            'izdavanja nalog se ne može mijenjati ni brisati.',
        dugme: 'Izdaj',
        ikona: Icons.outbox_rounded,
        opasno: false,
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

  // ------------------------------------------------------------------
  // UI
  // ------------------------------------------------------------------

  static const _stilUnosa = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: MagacinBoje.naslov,
  );

  static const _brojStil = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: MagacinBoje.tekst,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  InputDecoration _dekoracija({
    String? hint,
    IconData? ikona,
    String? greska,
    Widget? suffix,
  }) {
    final d = dekoracijaPolja(
      hint: hint,
      ikona: ikona,
      errorText: greska,
      suffix: suffix,
    );
    // Izdat nalog: polja su samo za čitanje, malo tamnija.
    return _samoPregled ? d.copyWith(fillColor: const Color(0xFFF1F5F9)) : d;
  }

  Widget _polje(
    String oznaka,
    TextEditingController controller, {
    IconData? ikona,
    String? hint,
    String? poljeApi,
    bool obavezno = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OznakaPolja(oznaka, obavezno: obavezno && !_samoPregled),
        TextField(
          controller: controller,
          readOnly: _samoPregled,
          enabled: !_cuvanje || _samoPregled,
          onChanged: (_) {
            // Greška sa servera za ovo polje nestaje čim se ono mijenja.
            if (poljeApi != null && _greska?.fieldError(poljeApi) != null) {
              setState(() => _greska = null);
            }
          },
          style: _stilUnosa,
          decoration: _dekoracija(
            hint: _samoPregled ? null : hint,
            ikona: ikona,
            greska: poljeApi == null ? null : _greska?.fieldError(poljeApi),
          ),
        ),
      ],
    );
  }

  Widget _datumPolje() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OznakaPolja('Datum', obavezno: !_samoPregled),
        TextField(
          controller: datumController,
          readOnly: true,
          onTap: _samoPregled || _cuvanje ? null : _izaberiDatum,
          mouseCursor: _samoPregled ? null : SystemMouseCursors.click,
          style: _stilUnosa,
          decoration: _dekoracija(
            ikona: Icons.event_outlined,
            greska: _greska?.fieldError('date'),
            suffix: _samoPregled
                ? null
                : const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: MagacinBoje.priguseno,
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildKupac() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OznakaPolja('Kupac', obavezno: !_samoPregled),
        DropdownButtonFormField<int>(
          // Key prati učitavanje da bi se prikazala vrijednost postojećeg naloga.
          key: ValueKey('kupac-$_kupacId-${_kupci.length}'),
          initialValue: _kupacId,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          dropdownColor: Colors.white,
          style: _stilUnosa,
          icon: _samoPregled
              ? const SizedBox.shrink()
              : const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: MagacinBoje.priguseno,
                ),
          forceErrorText: _greska?.fieldError('customer_id'),
          decoration: _dekoracija(ikona: Icons.person_outline_rounded),
          hint: Text(
            _kupci.isEmpty ? 'Nema unesenih kupaca' : 'Izaberite kupca',
            style: const TextStyle(color: MagacinBoje.svijetlo),
          ),
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
          onChanged: _samoPregled || _cuvanje
              ? null
              : (id) => setState(() {
                  _kupacId = id;
                  _greska = null;
                }),
        ),
      ],
    );
  }

  // Malo polje za broj u redu tabele (količina, izdato).
  Widget _malaPolje(
    TextEditingController controller, {
    required ValueChanged<String> onChanged,
    String? jedinica,
    bool istaknuto = false,
  }) {
    if (_samoPregled) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: controller.text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: MagacinBoje.naslov,
              ),
            ),
            if (jedinica != null)
              TextSpan(
                text: ' $jedinica',
                style: const TextStyle(color: MagacinBoje.priguseno),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _brojStil.copyWith(fontSize: 13.5),
      );
    }
    return TextField(
      controller: controller,
      onChanged: onChanged,
      enabled: !_cuvanje,
      textAlign: TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_decimalFormatter],
      style: _brojStil.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
        color: istaknuto ? _nacrt : MagacinBoje.naslov,
      ),
      decoration: dekoracijaPolja().copyWith(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        suffixText: jedinica,
        suffixStyle: const TextStyle(
          fontSize: 12,
          color: MagacinBoje.priguseno,
        ),
        fillColor: istaknuto ? const Color(0xFFFFFBEB) : null,
        enabledBorder: istaknuto
            ? OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: hoverNijansa(_nacrt, 0.45)),
              )
            : OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: MagacinBoje.linija),
              ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _akcent, width: 1.6),
        ),
      ),
    );
  }

  // Bijela kartica sa naslovom sekcije.
  Widget _kartica({
    required String naslov,
    required IconData ikona,
    required Widget dijete,
    Widget? desno,
    String? opis,
    EdgeInsets padding = const EdgeInsets.all(20),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 16, opis == null ? 14 : 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _akcentSvijetlo,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(ikona, size: 17, color: _akcent),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        naslov,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: MagacinBoje.naslov,
                        ),
                      ),
                      if (opis != null)
                        Text(
                          opis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: MagacinBoje.priguseno,
                          ),
                        ),
                    ],
                  ),
                ),
                ?desno,
              ],
            ),
          ),
          const Divider(height: 1, color: MagacinBoje.linijaSvijetla),
          Padding(padding: padding, child: dijete),
        ],
      ),
    );
  }

  Widget _prazno(IconData ikona, String naslov, String opis, {Widget? akcija}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: _akcentSvijetlo,
              shape: BoxShape.circle,
            ),
            child: Icon(ikona, color: _akcent, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            naslov,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.naslov,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            opis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
          ),
          if (akcija != null) ...[const SizedBox(height: 16), akcija],
        ],
      ),
    );
  }

  Widget _zaglavljeKolona(List<(String, int)> kolone, double sirinaAkcija) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: MagacinBoje.zaglavlje,
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < kolone.length; i++)
            _celija(
              kolone,
              i,
              Text(
                kolone[i].$1.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ),
          if (sirinaAkcija > 0) SizedBox(width: sirinaAkcija),
        ],
      ),
    );
  }

  Widget _celija(List<(String, int)> kolone, int i, Widget dijete) {
    return Expanded(
      flex: kolone[i].$2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Align(
          alignment: i <= 1 ? Alignment.centerLeft : Alignment.centerRight,
          child: dijete,
        ),
      ),
    );
  }

  Widget _proizvodNaziv(Artikal a, {int maxLines = 1}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          a.naziv,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: MagacinBoje.naslov,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          idArtikla(a.id),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: MagacinBoje.priguseno,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // ---- Podaci o nalogu ----------------------------------------------

  Widget _buildPodaci() {
    return _kartica(
      naslov: 'Podaci o nalogu',
      ikona: Icons.assignment_outlined,
      dijete: LayoutBuilder(
        builder: (context, c) {
          final siroko = c.maxWidth >= 560;
          final datum = _datumPolje();
          final broj = _polje(
            'Broj naloga',
            brojController,
            ikona: Icons.tag_rounded,
            hint: 'npr. RN-001',
            poljeApi: 'order_number',
            obavezno: true,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (siroko)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: datum),
                    const SizedBox(width: 14),
                    Expanded(child: broj),
                  ],
                )
              else ...[
                datum,
                const SizedBox(height: 16),
                broj,
              ],
              const SizedBox(height: 16),
              _buildKupac(),
            ],
          );
        },
      ),
    );
  }

  // ---- Proizvodi ------------------------------------------------------

  static const List<(String, int)> _koloneProizvoda = [
    ('#', 4),
    ('Proizvod', 34),
    ('Količina', 18),
    ('Cijena koštanja', 16),
  ];

  Widget _buildProizvodi() {
    final dodaj = GlatkoDugme(
      tekst: 'Dodaj proizvod',
      ikona: Icons.add_rounded,
      visina: 40,
      onTap: _cuvanje ? null : _dodajArtikal,
    );

    Widget sadrzaj;
    if (stavke.isEmpty) {
      sadrzaj = _prazno(
        Icons.inventory_2_outlined,
        'Još nema proizvoda',
        _samoPregled
            ? 'Nalog nema proizvoda.'
            : 'Dodajte gotove proizvode koje treba napraviti. Materijal se '
                  'računa iz njihovog normativa.',
        akcija: _samoPregled ? null : dodaj,
      );
    } else {
      sadrzaj = LayoutBuilder(
        builder: (context, c) {
          final sirinaAkcija = _samoPregled ? 0.0 : 52.0;
          if (c.maxWidth >= 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _zaglavljeKolona(_koloneProizvoda, sirinaAkcija),
                for (int i = 0; i < stavke.length; i++)
                  _redProizvoda(i, sirinaAkcija),
              ],
            );
          }
          return Column(
            children: [
              for (int i = 0; i < stavke.length; i++) _karticaProizvoda(i),
            ],
          );
        },
      );
    }

    return _kartica(
      naslov: 'Proizvodi',
      ikona: Icons.inventory_2_outlined,
      opis: stavke.isEmpty ? null : 'Gotovi proizvodi koji se prave nalogom',
      desno: _samoPregled || stavke.isEmpty ? null : dodaj,
      padding: EdgeInsets.zero,
      dijete: sadrzaj,
    );
  }

  Widget _redProizvoda(int i, double sirinaAkcija) {
    final s = stavke[i];
    return HoverRed(
      akcent: _akcent,
      visina: 64,
      builder: (hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            _celija(
              _koloneProizvoda,
              0,
              Text(
                '${i + 1}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.svijetlo,
                ),
              ),
            ),
            _celija(_koloneProizvoda, 1, _proizvodNaziv(s.artikal)),
            _celija(
              _koloneProizvoda,
              2,
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _malaPolje(
                    s.kolicina,
                    jedinica: s.artikal.jm,
                    onChanged: (_) => setState(s.osvjeziIzdato),
                  ),
                ),
              ),
            ),
            _celija(
              _koloneProizvoda,
              3,
              Text(
                '${_format(s.cijenaKostanja)} €',
                style: _brojStil.copyWith(
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.naslov,
                ),
              ),
            ),
            if (sirinaAkcija > 0)
              SizedBox(
                width: sirinaAkcija,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: IkonaAkcija(
                    ikona: Icons.delete_outline_rounded,
                    poruka: 'Ukloni',
                    boja: MagacinBoje.crvena,
                    onTap: _cuvanje ? null : () => _obrisiArtikal(s),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _karticaProizvoda(int i) {
    final s = stavke[i];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _proizvodNaziv(s.artikal, maxLines: 2)),
              if (!_samoPregled) ...[
                const SizedBox(width: 8),
                IkonaAkcija(
                  ikona: Icons.delete_outline_rounded,
                  poruka: 'Ukloni',
                  boja: MagacinBoje.crvena,
                  onTap: _cuvanje ? null : () => _obrisiArtikal(s),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'KOLIČINA',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.svijetlo,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: 150,
                        child: _malaPolje(
                          s.kolicina,
                          jedinica: s.artikal.jm,
                          onChanged: (_) => setState(s.osvjeziIzdato),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'CIJENA KOŠTANJA',
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 0.7,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.svijetlo,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_format(s.cijenaKostanja)} €',
                    style: _brojStil.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Trebovani materijali ------------------------------------------

  static const List<(String, int)> _koloneMaterijala = [
    ('#', 4),
    ('Materijal', 30),
    ('Norma', 12),
    ('Trebovano', 14),
    ('Izdato', 22),
    ('Cijena', 12),
    ('Vrijednost', 14),
  ];

  double get _ukupnoMaterijal {
    double ukupno = 0;
    for (final s in stavke) {
      for (final n in s.materijali) {
        ukupno += s.vrijednost(n);
      }
    }
    return ukupno;
  }

  int get _brojMaterijala => stavke.fold(0, (z, s) => z + s.materijali.length);

  // Polje "izdato" sa dugmetom za vraćanje na traženu količinu.
  Widget _izdatoPolje(_StavkaArtikla s, Normativ n) {
    final id = n.id!;
    final rucno = s.rucno.contains(id);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _malaPolje(
            s.izdato[id]!,
            jedinica: _samoPregled ? n.jm : null,
            istaknuto: rucno && !_samoPregled,
            onChanged: (_) => setState(() => s.rucno.add(id)),
          ),
        ),
        if (!_samoPregled)
          SizedBox(
            width: 34,
            child: AnimatedOpacity(
              duration: hoverTrajanje,
              opacity: rucno ? 1 : 0,
              child: IgnorePointer(
                ignoring: !rucno,
                child: IconButton(
                  tooltip: 'Vrati na traženu količinu',
                  visualDensity: VisualDensity.compact,
                  color: _nacrt,
                  onPressed: () => setState(() {
                    s.rucno.remove(id);
                    s.osvjeziIzdato();
                  }),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMaterijali() {
    if (stavke.isEmpty) {
      return _kartica(
        naslov: 'Trebovani materijal',
        ikona: Icons.move_down_rounded,
        padding: EdgeInsets.zero,
        dijete: _prazno(
          Icons.category_outlined,
          'Nema materijala',
          'Materijal se prikazuje automatski kad dodate proizvod.',
        ),
      );
    }

    return _kartica(
      naslov: 'Trebovani materijal',
      ikona: Icons.move_down_rounded,
      opis: 'Iz magacina repromaterijala, po normativu proizvoda',
      padding: EdgeInsets.zero,
      dijete: LayoutBuilder(
        builder: (context, c) =>
            c.maxWidth >= 640 ? _tabelaMaterijala() : _karticeMaterijala(),
      ),
    );
  }

  Widget _tabelaMaterijala() {
    final redovi = <Widget>[];
    var rb = 0;

    for (final s in stavke) {
      // Red grupe: proizvod za koji je materijal.
      redovi.add(
        Container(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
          decoration: const BoxDecoration(
            color: Color(0xFFF4FAFA),
            border: Border(
              bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.subdirectory_arrow_right_rounded,
                size: 15,
                color: _akcent,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '${s.artikal.naziv}  ·  ${_formatKolicina(s.kol)} ${s.artikal.jm}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _akcentTamni,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      for (final n in s.materijali) {
        rb++;
        final broj = rb;
        redovi.add(
          HoverRed(
            akcent: _akcent,
            visina: 58,
            builder: (hover) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  _celija(
                    _koloneMaterijala,
                    0,
                    Text(
                      '$broj',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.svijetlo,
                      ),
                    ),
                  ),
                  _celija(
                    _koloneMaterijala,
                    1,
                    Text(
                      n.naziv,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                  ),
                  _celija(
                    _koloneMaterijala,
                    2,
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_formatKolicina(n.kolicina)} ${n.jm}',
                        style: _brojStil.copyWith(color: MagacinBoje.priguseno),
                      ),
                    ),
                  ),
                  _celija(
                    _koloneMaterijala,
                    3,
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_formatKolicina(s.trazeno(n))} ${n.jm}',
                        style: _brojStil.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  _celija(
                    _koloneMaterijala,
                    4,
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: _izdatoPolje(s, n),
                    ),
                  ),
                  _celija(
                    _koloneMaterijala,
                    5,
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('${_format(n.cijena)} €', style: _brojStil),
                    ),
                  ),
                  _celija(
                    _koloneMaterijala,
                    6,
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${_format(s.vrijednost(n))} €',
                        style: _brojStil.copyWith(
                          fontWeight: FontWeight.w800,
                          color: MagacinBoje.naslov,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _zaglavljeKolona(_koloneMaterijala, 0),
        ...redovi,
        _ukupnoRed(),
      ],
    );
  }

  Widget _ukupnoRed() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 18, 12),
      decoration: const BoxDecoration(
        color: _akcentSvijetlo,
        border: Border(top: BorderSide(color: MagacinBoje.linija)),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Ukupna vrijednost materijala',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _akcentTamni,
              ),
            ),
          ),
          Text(
            '${_format(_ukupnoMaterijal)} €',
            style: _brojStil.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _akcentTamni,
            ),
          ),
        ],
      ),
    );
  }

  Widget _karticeMaterijala() {
    Widget metrika(String naziv, String vrijednost, {bool jaka = false}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            naziv.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 9.5,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.svijetlo,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              vrijednost,
              style: _brojStil.copyWith(
                fontWeight: jaka ? FontWeight.w800 : FontWeight.w600,
                color: jaka ? MagacinBoje.naslov : MagacinBoje.tekst,
              ),
            ),
          ),
        ],
      );
    }

    final dijelovi = <Widget>[];
    for (final s in stavke) {
      dijelovi.add(
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          color: const Color(0xFFF4FAFA),
          child: Text(
            '${s.artikal.naziv}  ·  ${_formatKolicina(s.kol)} ${s.artikal.jm}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _akcentTamni,
            ),
          ),
        ),
      );
      for (final n in s.materijali) {
        dijelovi.add(
          Container(
            padding: const EdgeInsets.all(14),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  n.naziv,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: MagacinBoje.naslov,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: metrika(
                        'Norma',
                        '${_formatKolicina(n.kolicina)} ${n.jm}',
                      ),
                    ),
                    Expanded(
                      child: metrika(
                        'Trebovano',
                        '${_formatKolicina(s.trazeno(n))} ${n.jm}',
                      ),
                    ),
                    Expanded(
                      child: metrika(
                        'Vrijednost',
                        '${_format(s.vrijednost(n))} €',
                        jaka: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text(
                      'IZDATO',
                      style: TextStyle(
                        fontSize: 9.5,
                        letterSpacing: 0.7,
                        fontWeight: FontWeight.w800,
                        color: MagacinBoje.svijetlo,
                      ),
                    ),
                    const Spacer(),
                    SizedBox(width: 170, child: _izdatoPolje(s, n)),
                  ],
                ),
              ],
            ),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [...dijelovi, _ukupnoRed()],
    );
  }

  // ---- Desna kolona: tok materijala, potpisi, sažetak ----------------

  Widget _buildTok() {
    final izvor = _nalog?.izvor?.naziv ?? 'Magacin repromaterijala';
    final odrediste = _nalog?.odrediste?.naziv ?? 'Proizvodnja u toku';

    Widget mjesto(String oznaka, String naziv, String tip) {
      final tema = TemaSkladista.za(tip);
      return Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tema.svijetla,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(tema.ikona, color: tema.boja, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  oznaka.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 9.5,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w800,
                    color: MagacinBoje.svijetlo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  naziv,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: MagacinBoje.naslov,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _kartica(
      naslov: 'Tok materijala',
      ikona: Icons.swap_vert_rounded,
      dijete: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          mjesto('Izdaje', izvor, _nalog?.izvor?.tip ?? 'raw_materials'),
          Padding(
            padding: const EdgeInsets.only(left: 11, top: 4, bottom: 4),
            child: Row(
              children: [
                Container(width: 2, height: 22, color: MagacinBoje.linija),
                const SizedBox(width: 18),
                const Icon(
                  Icons.arrow_downward_rounded,
                  size: 15,
                  color: MagacinBoje.svijetlo,
                ),
              ],
            ),
          ),
          mjesto('Prima', odrediste, _nalog?.odrediste?.tip ?? 'production'),
        ],
      ),
    );
  }

  Widget _buildPotpisi() {
    return _kartica(
      naslov: 'Potpisi',
      ikona: Icons.draw_outlined,
      dijete: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _polje(
            'Izdao',
            izdaoController,
            ikona: Icons.edit_document,
            hint: 'Ime i prezime',
            poljeApi: 'issued_by',
          ),
          const SizedBox(height: 14),
          _polje(
            'Potpisao',
            potpisaoController,
            ikona: Icons.draw_outlined,
            hint: 'Ime i prezime',
            poljeApi: 'signed_by',
          ),
        ],
      ),
    );
  }

  Widget _buildSazetak() {
    Widget red(String naziv, String vrijednost) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                naziv,
                style: const TextStyle(fontSize: 13, color: MagacinBoje.tekst),
              ),
            ),
            Text(
              vrijednost,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: MagacinBoje.naslov,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      );
    }

    return _kartica(
      naslov: 'Sažetak',
      ikona: Icons.functions_rounded,
      dijete: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          red('Proizvoda', '${stavke.length}'),
          red('Stavki materijala', '$_brojMaterijala'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [akcentTamni, _akcent],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Vrijednost materijala',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '${_format(_ukupnoMaterijal)} €',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: mint,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Greške servera koje nisu vezane za polje forme (stavke, zaliha...).
  Widget? _buildGreske() {
    final greska = _greska;
    if (greska == null) return null;

    const poljaForme = {
      'customer_id',
      'order_number',
      'date',
      'issued_by',
      'signed_by',
    };
    final poruke = greska.fieldErrors.entries
        .where((e) => !poljaForme.contains(e.key))
        .expand((e) => e.value)
        .toList();
    if (poruke.isEmpty && greska.fieldErrors.isEmpty) {
      poruke.add(greska.message);
    }
    if (poruke.isEmpty) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MagacinBoje.crvenaSvijetlo,
        border: Border.all(color: hoverNijansa(MagacinBoje.crvena, 0.3)),
        borderRadius: BorderRadius.circular(14),
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
                  const Icon(
                    Icons.error_outline_rounded,
                    color: MagacinBoje.crvena,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      poruka,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: MagacinBoje.crvena,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---- Gornja traka i akcije -----------------------------------------

  void _nazad() {
    if (!_cuvanje) Get.back(result: _promijenjeno);
  }

  Widget _statusOznaka() {
    final n = _nalog;
    final (String tekst, Color boja, Color pozadina, IconData ikona) = n == null
        ? ('Novi', akcentTamni, mint, Icons.fiber_new_rounded)
        : n.jeIzdat
        ? ('Izdat', _izdat, _izdatSvijetlo, Icons.outbox_rounded)
        : ('Nacrt', _nacrt, _nacrtSvijetlo, Icons.edit_note_rounded);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 10, 4),
      decoration: BoxDecoration(
        color: pozadina,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ikona, size: 14, color: boja),
          const SizedBox(width: 5),
          Text(
            tekst,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: boja,
            ),
          ),
        ],
      ),
    );
  }

  // Štampa se snimljeno stanje sa servera; nacrt se prvo sačuva da bi
  // odštampani nalog odgovarao onome što je na ekranu.
  Future<void> _stampaj() async {
    final nalog = _samoPregled ? _nalog : await _sacuvaj();
    if (nalog == null || !mounted) return;

    final broj = nalog.broj.trim();
    final firma = _firmaController.izabranaFirma.value;
    await prikaziPregledStampe(
      context,
      naslov: 'Radni nalog $broj',
      nazivFajla: pdfNazivFajla(
        'radni_nalog_${broj.isEmpty ? nalog.id : broj}',
      ),
      napravi: (format) =>
          napraviRadniNalogPdf(nalog: nalog, firma: firma, format: format),
    );
  }

  List<Widget> _dugmadAkcija({required bool kompaktno}) {
    final stampaj = kompaktno
        ? IkonaAkcija(
            ikona: Icons.print_outlined,
            poruka: 'Štampaj',
            boja: _akcent,
            onTap: _cuvanje ? null : _stampaj,
          )
        : GlatkoDugme(
            tekst: 'Štampaj',
            ikona: Icons.print_outlined,
            vrsta: VrstaDugmeta.sekundarno,
            visina: 42,
            onTap: _cuvanje ? null : _stampaj,
          );
    if (_samoPregled || kompaktno) return [stampaj];
    return [
      stampaj,
      GlatkoDugme(
        tekst: 'Odustani',
        vrsta: VrstaDugmeta.sekundarno,
        visina: 42,
        onTap: _cuvanje ? null : _nazad,
      ),
      GlatkoDugme(
        tekst: 'Sačuvaj',
        ikona: Icons.save_outlined,
        vrsta: VrstaDugmeta.sekundarno,
        visina: 42,
        ucitavanje: _cuvanje,
        onTap: _cuvanje ? null : _sacuvajIZatvori,
      ),
      GlatkoDugme(
        tekst: 'Sačuvaj i izdaj',
        ikona: Icons.outbox_rounded,
        visina: 42,
        onTap: _cuvanje ? null : _sacuvajIIzdaj,
      ),
    ];
  }

  Widget _gornjaTraka({required bool siroko}) {
    final n = _nalog;
    final naslov = n == null ? 'Novi radni nalog' : 'Radni nalog ${n.broj}';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: MagacinBoje.linija)),
        boxShadow: [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: siroko ? 20 : 8,
            vertical: 10,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Nazad',
                onPressed: _cuvanje ? null : _nazad,
                style: IconButton.styleFrom(
                  foregroundColor: MagacinBoje.naslov,
                  hoverColor: const Color(0xFFF1F5F9),
                ),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'RADNI NALOG',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.3,
                        fontWeight: FontWeight.w800,
                        color: _akcent.withValues(alpha: 0.85),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            naslov,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: siroko ? 19 : 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.3,
                              color: MagacinBoje.naslov,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _statusOznaka(),
                      ],
                    ),
                  ],
                ),
              ),
              if (!_ucitavanje && _greskaUcitavanja == null)
                for (final d in _dugmadAkcija(kompaktno: !siroko)) ...[
                  const SizedBox(width: 8),
                  d,
                ],
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Traka sa dugmadima na dnu (uzak ekran).
  Widget _donjaTraka() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: MagacinBoje.linija)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: GlatkoDugme(
                tekst: 'Sačuvaj',
                ikona: Icons.save_outlined,
                vrsta: VrstaDugmeta.sekundarno,
                ucitavanje: _cuvanje,
                onTap: _cuvanje ? null : _sacuvajIZatvori,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GlatkoDugme(
                tekst: 'Izdaj',
                ikona: Icons.outbox_rounded,
                onTap: _cuvanje ? null : _sacuvajIIzdaj,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForma(double sirina) {
    final greske = _buildGreske();
    final dvijeKolone = sirina >= 1100;

    final glavno = [
      _buildPodaci(),
      const SizedBox(height: 20),
      _buildProizvodi(),
      const SizedBox(height: 20),
      _buildMaterijali(),
    ];
    final strana = [
      _buildTok(),
      const SizedBox(height: 20),
      _buildSazetak(),
      const SizedBox(height: 20),
      _buildPotpisi(),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_samoPregled) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _izdatSvijetlo,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hoverNijansa(_izdat, 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_outline_rounded, color: _izdat),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _zakljucenaGodina
                        ? 'Poslovna godina ${_nalog!.datum!.year} je '
                              'zaključena. Nalog se više ne može mijenjati.'
                        : 'Nalog je izdat i više se ne može mijenjati.',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF075985),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (greske != null) ...[greske, const SizedBox(height: 20)],
        if (dvijeKolone)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: glavno,
                ),
              ),
              const SizedBox(width: 20),
              SizedBox(
                width: 340,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: strana,
                ),
              ),
            ],
          )
        else ...[
          ...glavno,
          const SizedBox(height: 20),
          if (sirina >= 720)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildTok()),
                const SizedBox(width: 20),
                Expanded(child: _buildSazetak()),
              ],
            )
          else ...[
            _buildTok(),
            const SizedBox(height: 20),
            _buildSazetak(),
          ],
        ],
        if (!dvijeKolone) ...[const SizedBox(height: 20), _buildPotpisi()],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_cuvanje) Get.back(result: _promijenjeno);
      },
      child: Scaffold(
        backgroundColor: MagacinBoje.pozadina,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final siroko = w >= 1000;
            final razmak = w < 600 ? 12.0 : 24.0;

            final Widget sadrzaj;
            if (_ucitavanje) {
              sadrzaj = const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: ZecRacuna(tekst: 'Učitavam dokument…')),
              );
            } else if (_greskaUcitavanja != null) {
              sadrzaj = Padding(
                padding: const EdgeInsets.symmetric(vertical: 64),
                child: Column(
                  children: [
                    const ZecStanja(
                      poza: PozaZeca.lezi,
                      ikona: Icons.error_outline_rounded,
                      boja: MagacinBoje.crvena,
                      pozadina: MagacinBoje.crvenaSvijetlo,
                      visina: 60,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _greskaUcitavanja!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlatkoDugme(
                      tekst: 'Pokušaj ponovo',
                      ikona: Icons.refresh_rounded,
                      vrsta: VrstaDugmeta.sekundarno,
                      onTap: _ucitaj,
                    ),
                  ],
                ),
              );
            } else {
              sadrzaj = _buildForma(w - 2 * razmak);
            }

            final mozeCuvati =
                !_ucitavanje && _greskaUcitavanja == null && !_samoPregled;

            return Column(
              children: [
                _gornjaTraka(siroko: siroko),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(razmak),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1400),
                        child: sadrzaj,
                      ),
                    ),
                  ),
                ),
                if (!siroko && mozeCuvati) _donjaTraka(),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ======================================================================
// DIJALOG: izbor gotovog proizvoda (sa normativom) i količine
// GET /companies/{company}/articles?type=finished_product&search=...
// Normativ izabranog proizvoda: GET /companies/{company}/articles/{article}
// ======================================================================
class _DodajArtikalDialog extends StatefulWidget {
  final int firmaId;

  const _DodajArtikalDialog({required this.firmaId});

  @override
  State<_DodajArtikalDialog> createState() => _DodajArtikalDialogState();
}

class _DodajArtikalDialogState extends State<_DodajArtikalDialog> {
  final ArticlesService _service = ArticlesService();
  final pretragaController = TextEditingController();
  final kolicinaController = TextEditingController(text: '1');

  List<Artikal> _rezultati = [];
  Artikal? _artikal;
  bool _ucitavanje = false;
  bool _ucitavanjeNormativa = false;
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
      final stranica = await _service.fetchArticles(
        widget.firmaId,
        type: tipGotovProizvod,
        search: pretragaController.text,
        perPage: 20,
      );
      if (!mounted || zahtjev != _zahtjev) return;
      // Nalog se može otvoriti samo za proizvod koji ima normativ. Ako lista
      // ne vrati broj stavki, proizvod ostaje, a normativ se provjerava pri
      // izboru.
      setState(
        () => _rezultati = stranica.artikli
            .where(
              (a) =>
                  !a.jeObrisan &&
                  (!a.poznatBrojNormativa || a.brojNormativa > 0),
            )
            .toList(),
      );
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

  // Lista ne vraća stavke normativa, pa se izabrani proizvod učitava cio.
  Future<void> _izaberi(Artikal artikal) async {
    setState(() {
      _artikal = artikal;
      _ucitavanjeNormativa = artikal.normativi.isEmpty;
    });
    if (artikal.normativi.isNotEmpty) return;

    try {
      final pun = await _service.fetchArticle(widget.firmaId, artikal.id!);
      if (!mounted || _artikal?.id != artikal.id) return;
      if (pun.normativi.isEmpty) {
        setState(() {
          _artikal = null;
          _ucitavanjeNormativa = false;
          _rezultati.removeWhere((a) => a.id == artikal.id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izabrani proizvod nema normativ.')),
        );
        return;
      }
      // Stare stavke bez sirovine (material_id) server ne može obraditi.
      if (pun.imaNepovezanihNormativa) {
        setState(() {
          _artikal = null;
          _ucitavanjeNormativa = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Normativ proizvoda ima stavke koje nisu povezane sa '
              'sirovinom. Povežite ih u šifarniku artikala.',
            ),
          ),
        );
        return;
      }
      setState(() => _artikal = pun);
    } on ApiException catch (e) {
      if (!mounted || _artikal?.id != artikal.id) return;
      setState(() {
        _artikal = null;
        _ucitavanjeNormativa = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted && _artikal?.id == artikal.id) {
        setState(() => _ucitavanjeNormativa = false);
      }
    }
  }

  void _potvrdi() {
    final kolicina = _parse(kolicinaController.text);
    if (_artikal == null || _ucitavanjeNormativa || kolicina <= 0) return;

    Navigator.of(context).pop((_artikal!, kolicina));
  }

  Widget _lista() {
    if (_greska != null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          _greska!,
          style: const TextStyle(color: MagacinBoje.crvena),
        ),
      );
    }
    if (_ucitavanje && _rezultati.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(28),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: akcentAplikacije,
            ),
          ),
        ),
      );
    }
    if (_rezultati.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nema gotovih proizvoda sa normativom.',
            textAlign: TextAlign.center,
            style: TextStyle(color: MagacinBoje.priguseno),
          ),
        ),
      );
    }

    final tema = TemaSkladista.za('finished_goods');
    return AnimatedOpacity(
      duration: hoverTrajanje,
      opacity: _ucitavanje ? 0.55 : 1,
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(6),
        itemCount: _rezultati.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final artikal = _rezultati[index];
          final izabran = artikal.id == _artikal?.id;
          return _HoverIzbor(
            izabran: izabran,
            onTap: () => _izaberi(artikal),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: tema.svijetla,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(tema.ikona, size: 17, color: tema.tamna),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artikal.naziv,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: MagacinBoje.naslov,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          idArtikla(artikal.id),
                          if (artikal.poznatBrojNormativa)
                            '${artikal.brojNormativa} materijala',
                          if (artikal.cijena != null)
                            '${_format(artikal.cijena!)} € / ${artikal.jm}'
                          else
                            artikal.jm,
                        ].join('  ·  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: MagacinBoje.priguseno,
                        ),
                      ),
                    ],
                  ),
                ),
                if (izabran && _ucitavanjeNormativa)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: akcentAplikacije,
                    ),
                  )
                else
                  AnimatedOpacity(
                    duration: hoverTrajanje,
                    opacity: izabran ? 1 : 0,
                    child: const Icon(
                      Icons.check_circle_rounded,
                      color: akcentAplikacije,
                      size: 20,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sadrzaj() {
    final artikal = _artikal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: pretragaController,
          autofocus: true,
          onChanged: _promjenaPretrage,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MagacinBoje.naslov,
          ),
          decoration: dekoracijaPolja(
            hint: 'Pretraži gotove proizvode…',
            ikona: Icons.search_rounded,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: MagacinBoje.linija),
          ),
          child: _lista(),
        ),
        const SizedBox(height: 14),
        // Materijali izabranog proizvoda (normativ), kad se učitaju.
        AnimatedSize(
          duration: hoverTrajanje,
          curve: hoverKriva,
          alignment: Alignment.topCenter,
          child: artikal == null || _ucitavanjeNormativa
              ? const SizedBox(width: double.infinity)
              : Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F4F3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hoverNijansa(akcentAplikacije, 0.25),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 18,
                            color: akcentAplikacije,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              nazivSaId(artikal.id, artikal.naziv),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0B434B),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (artikal.normativi.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Normativ po ${artikal.jm}: ${artikal.normativi.map((n) => '${n.naziv} ${_formatKolicina(n.kolicina)} ${n.jm}').join(', ')}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Color(0xFF0C4D56),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        const OznakaPolja('Količina', obavezno: true),
        TextField(
          controller: kolicinaController,
          inputFormatters: [_decimalFormatter],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => _potvrdi(),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MagacinBoje.naslov,
          ),
          decoration: dekoracijaPolja(
            hint: '1',
            ikona: Icons.scale_outlined,
          ).copyWith(suffixText: _artikal?.jm),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final usko = MediaQuery.sizeOf(context).width < 600;
    final mozeDodati = _artikal != null && !_ucitavanjeNormativa;

    final naslov = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFE6F4F3),
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.add_box_outlined,
            color: akcentAplikacije,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dodaj proizvod',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Izaberite gotov proizvod sa normativom i unesite količinu.',
                style: TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Zatvori',
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(foregroundColor: MagacinBoje.priguseno),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );

    final odustani = GlatkoDugme(
      tekst: 'Odustani',
      vrsta: VrstaDugmeta.sekundarno,
      onTap: () => Navigator.of(context).pop(),
    );
    final dodaj = GlatkoDugme(
      tekst: 'Dodaj',
      ikona: Icons.check_rounded,
      onTap: mozeDodati ? _potvrdi : null,
    );

    if (usko) {
      return Dialog.fullscreen(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 14),
                child: naslov,
              ),
              const Divider(height: 1, color: MagacinBoje.linija),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                  child: _sadrzaj(),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: MagacinBoje.linija)),
                ),
                child: Row(
                  children: [
                    Expanded(child: odustani),
                    const SizedBox(width: 10),
                    Expanded(flex: 2, child: dodaj),
                  ],
                ),
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
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 14, 16),
              child: naslov,
            ),
            const Divider(height: 1, color: MagacinBoje.linija),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                child: _sadrzaj(),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              decoration: const BoxDecoration(
                color: MagacinBoje.zaglavlje,
                border: Border(top: BorderSide(color: MagacinBoje.linija)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [odustani, const SizedBox(width: 10), dodaj],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Stavka liste sa glatkim hoverom; izabrana ima ljubičast okvir.
class _HoverIzbor extends StatefulWidget {
  final bool izabran;
  final VoidCallback onTap;
  final Widget child;

  const _HoverIzbor({
    required this.izabran,
    required this.onTap,
    required this.child,
  });

  @override
  State<_HoverIzbor> createState() => _HoverIzborState();
}

class _HoverIzborState extends State<_HoverIzbor> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: hoverTrajanje,
          curve: hoverKriva,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: widget.izabran
                ? const Color(0xFFE6F4F3)
                : _hover
                ? const Color(0xFFF1F5F9)
                : Colors.white,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: widget.izabran
                  ? hoverNijansa(akcentAplikacije, 0.4)
                  : Colors.white,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:knjigovodstvo_app/controllers/firma_controller.dart';
import 'package:knjigovodstvo_app/controllers/poslovne_godine_controller.dart';
import 'package:knjigovodstvo_app/models/article.dart';
import 'package:knjigovodstvo_app/models/auth_models.dart';
import 'package:knjigovodstvo_app/models/partner.dart';
import 'package:knjigovodstvo_app/models/purchase_calculation.dart';
import 'package:knjigovodstvo_app/models/work_order.dart';
import 'package:knjigovodstvo_app/screens/analiticka_kartica.dart';
import 'package:knjigovodstvo_app/screens/dokumenta/kalkulacija_nabavnih_cijena/kopiraj_stavke_dialog.dart';
import 'package:knjigovodstvo_app/stampa/kalkulacija_nabavnih_cijena_pdf.dart';
import 'package:knjigovodstvo_app/stampa/pdf_zajednicko.dart';
import 'package:knjigovodstvo_app/stampa/pregled_stampe.dart';
import 'package:knjigovodstvo_app/services/purchase_calculations_service.dart';
import 'package:knjigovodstvo_app/widgets/logo.dart';
import 'package:knjigovodstvo_app/widgets/magacin_ui.dart';

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
  // Tip artikla (raw_material / finished_product); stavke učitane sa servera
  // ga nemaju, pa je null.
  final String? tip;

  double zavisniTrosak = 0;

  _Stavka({
    required this.articleId,
    required this.sifra,
    required this.naziv,
    required this.jm,
    required this.dokument,
    required this.kolicina,
    required this.fakturnaCijena,
    this.tip,
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

  // Kalkulacija iz zaključene poslovne godine se ne može mijenjati.
  bool get _zakljucenaGodina =>
      _kalkulacija != null &&
      PoslovneGodineController.zakljucenDatum(_kalkulacija!.datum);

  bool get _samoPregled =>
      (_kalkulacija?.jeProknjizena ?? false) || _zakljucenaGodina;

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

  Future<void> _dodajIliIzmijeniArtikal([_Stavka? postojeca]) async {
    final firmaId = _firmaId;
    if (firmaId == null) return;

    final nova = await showDialog<_Stavka>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => _ArtikalDialog(
        firmaId: firmaId,
        dokument: rcBrController.text.trim(),
        stavka: postojeca,
        tipArtikla: _tipArtiklaZaSkladiste,
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

  // Stavke iz ranije kalkulacije (zadnje od istog dobavljača ili bilo koje),
  // sa izmijenjenim količinama/cijenama. Dokument stavke je broj fakture
  // ove kalkulacije, ne one iz koje se kopira.
  Future<void> _kopirajStavke() async {
    final firmaId = _firmaId;
    if (firmaId == null) return;

    final dobavljac = _dobavljaci
        .where((d) => d.id == _dobavljacId)
        .firstOrNull;
    final tipSkladista = _skladista
        .where((s) => s.id == _skladisteId)
        .firstOrNull
        ?.tip;

    final rezultat = await showDialog<RezultatKopiranja>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => KopirajStavkeDialog(
        firmaId: firmaId,
        dobavljacId: dobavljac?.id,
        dobavljacNaziv: dobavljac?.naziv,
        trenutnaKalkulacijaId: _kalkulacijaId,
        postojeciArtikli: stavke.map((s) => s.articleId).toSet(),
        tipSkladista: tipSkladista,
      ),
    );
    if (rezultat == null || !mounted) return;

    final dokument = rcBrController.text.trim();
    final izvor = rezultat.kalkulacija;
    final r = izvor.rekapitulacija;

    setState(() {
      if (rezultat.kopirajTroskove) {
        prevozController.text = r.prevoz == 0 ? '' : _format(r.prevoz);
        spedicijaController.text = r.spedicija == 0 ? '' : _format(r.spedicija);
        carinaController.text = r.carina == 0 ? '' : _format(r.carina);
      }
      if (rezultat.kopirajPotpise) {
        if ((r.kalkulisao ?? '').trim().isNotEmpty) {
          kalkulisaoController.text = r.kalkulisao!.trim();
        }
        if ((r.robuPrimio ?? '').trim().isNotEmpty) {
          robuPrimioController.text = r.robuPrimio!.trim();
        }
      }
      stavke.addAll(
        rezultat.stavke.map(
          (k) => _Stavka(
            articleId: k.izvor.articleId,
            sifra: k.izvor.sifra,
            naziv: k.izvor.naziv,
            jm: k.izvor.jm,
            dokument: dokument,
            kolicina: k.kolicina,
            fakturnaCijena: k.fakturnaCijena,
          ),
        ),
      );
      // Nova kalkulacija bez dobavljača preuzima dobavljača izvora.
      if (_dobavljacId == null &&
          izvor.supplierId != null &&
          _dobavljaci.any((d) => d.id == izvor.supplierId)) {
        _dobavljacId = izvor.supplierId;
      }
      _greska = null;
      _preracunaj();
    });

    final n = rezultat.stavke.length;
    final dijelovi = [
      if (n == 1) '1 stavka',
      if (n > 1) '$n stavki',
      if (rezultat.kopirajTroskove) 'zavisni troškovi',
      if (rezultat.kopirajPotpise) 'potpisi',
    ];
    _poruka(
      context,
      'Kopirano iz kalkulacije (faktura ${izvor.brojFakture}): '
      '${dijelovi.join(', ')}.',
    );
  }

  // Kartica artikla na skladištu ove kalkulacije.
  void _otvoriKarticu(_Stavka stavka) {
    final skladiste = _skladista.where((s) => s.id == _skladisteId).firstOrNull;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AnalitickaKarticaScreen(
          articleId: stavka.articleId,
          naziv: stavka.naziv,
          jm: stavka.jm,
          warehouseId: skladiste?.id,
          skladiste: skladiste?.naziv,
          tipSkladista: skladiste?.tip,
        ),
      ),
    );
  }

  Future<void> _obrisiArtikal(_Stavka stavka) async {
    final potvrda = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => PotvrdaDijalog(
        naslov: 'Ukloni artikal?',
        tekst:
            'Artikal ${stavka.naziv} će biti uklonjen iz kalkulacije. '
            'Promjena se snima tek kad sačuvate dokument.',
        dugme: 'Ukloni',
        ikona: Icons.delete_outline_rounded,
        opasno: true,
      ),
    );
    if (potvrda != true || !mounted) return;

    setState(() {
      stavke.remove(stavka);
      _preracunaj();
    });
  }

  // Koji tip artikla smije ući u izabrano skladište: repromaterijal u magacin
  // repromaterijala, gotov proizvod u magacin gotovih proizvoda.
  String? get _tipArtiklaZaSkladiste {
    final tip = _skladista.where((s) => s.id == _skladisteId).firstOrNull?.tip;
    return switch (tip) {
      'raw_materials' => tipRepromaterijal,
      'finished_goods' => tipGotovProizvod,
      _ => null,
    };
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
    final dozvoljen = _tipArtiklaZaSkladiste;
    if (dozvoljen != null) {
      final pogresna = stavke
          .where((s) => s.tip != null && s.tip != dozvoljen)
          .firstOrNull;
      if (pogresna != null) {
        final skladiste = dozvoljen == tipRepromaterijal
            ? 'magacin repromaterijala'
            : 'magacin gotovih proizvoda';
        return 'Artikal ${pogresna.naziv} ne može ući u $skladiste.';
      }
    }
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
      barrierColor: const Color(0x800F172A),
      builder: (context) => const PotvrdaDijalog(
        naslov: 'Sačuvaj i proknjiži?',
        tekst:
            'Kalkulacija se snima i knjiži: roba ulazi na zalihu izabranog '
            'skladišta po nabavnoj vrijednosti i upisuje se na karticu '
            'artikla. Poslije knjiženja kalkulacija se ne može mijenjati ni '
            'brisati.',
        dugme: 'Proknjiži',
        ikona: Icons.inventory_2_rounded,
        opasno: false,
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

  static const _stilUnosa = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: MagacinBoje.naslov,
  );

  InputDecoration _dekoracija({
    String? hint,
    IconData? ikona,
    String? greska,
    Widget? suffix,
    String? suffixText,
  }) {
    final d = dekoracijaPolja(
      hint: hint,
      ikona: ikona,
      errorText: greska,
      suffix: suffix,
    ).copyWith(suffixText: suffixText);
    // Proknjižena kalkulacija: polja su samo za čitanje, malo tamnija.
    return _samoPregled ? d.copyWith(fillColor: const Color(0xFFF1F5F9)) : d;
  }

  Widget _polje(
    String oznaka,
    TextEditingController controller, {
    IconData? ikona,
    String? hint,
    String? poljeApi,
    bool broj = false,
    bool obavezno = false,
    ValueChanged<String>? onChanged,
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
          onChanged: (v) {
            // Greška sa servera za ovo polje nestaje čim se ono mijenja.
            if (poljeApi != null && _greska?.fieldError(poljeApi) != null) {
              setState(() => _greska = null);
            }
            onChanged?.call(v);
          },
          keyboardType: broj
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          inputFormatters: broj ? [_decimalFormatter] : null,
          style: _stilUnosa,
          decoration: _dekoracija(
            hint: _samoPregled ? null : hint,
            ikona: ikona,
            suffixText: broj ? '€' : null,
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

  Widget _padajuce<T>({
    required String oznaka,
    required Key key,
    required T? vrijednost,
    required List<DropdownMenuItem<T>> stavke,
    required IconData ikona,
    required ValueChanged<T?> onChanged,
    String? greska,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OznakaPolja(oznaka, obavezno: !_samoPregled),
        DropdownButtonFormField<T>(
          key: key,
          initialValue: vrijednost,
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
          forceErrorText: greska,
          decoration: _dekoracija(ikona: ikona),
          hint: hint == null
              ? null
              : Text(hint, style: const TextStyle(color: MagacinBoje.svijetlo)),
          items: stavke,
          onChanged: _samoPregled || _cuvanje ? null : onChanged,
        ),
      ],
    );
  }

  Widget _buildDobavljac() {
    return _padajuce<int>(
      oznaka: 'Dobavljač',
      key: ValueKey('dobavljac-$_dobavljacId-${_dobavljaci.length}'),
      vrijednost: _dobavljacId,
      ikona: Icons.storefront_outlined,
      greska: _greska?.fieldError('supplier_id'),
      hint: _dobavljaci.isEmpty ? 'Nema unesenih dobavljača' : 'Izaberite',
      stavke: _dobavljaci
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
      onChanged: (id) => setState(() {
        _dobavljacId = id;
        _greska = null;
      }),
    );
  }

  Widget _buildSkladiste() {
    return _padajuce<int>(
      oznaka: 'Objekat',
      key: ValueKey('skladiste-$_skladisteId-${_skladista.length}'),
      vrijednost: _skladisteId,
      ikona: Icons.warehouse_outlined,
      greska: _greska?.fieldError('warehouse_id'),
      stavke: _skladista
          .map(
            (s) => DropdownMenuItem(
              value: s.id,
              child: Text(s.naziv, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (id) => setState(() {
        _skladisteId = id;
        _greska = null;
      }),
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
            // Zaglavlje kartice uvijek ima isti razmak, i kad sadržaj (npr.
            // tabela artikala) ide od ivice do ivice.
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
          Padding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              padding.top,
              padding.right,
              padding.bottom,
            ),
            child: dijete,
          ),
        ],
      ),
    );
  }

  // Polja u mreži: broj kolona zavisi od širine.
  Widget _mreza(List<Widget> polja, {required int kolone}) {
    const razmak = 14.0;
    return LayoutBuilder(
      builder: (context, c) {
        final sirina = (c.maxWidth - (kolone - 1) * razmak) / kolone;
        return Wrap(
          spacing: razmak,
          runSpacing: 16,
          children: [for (final p in polja) SizedBox(width: sirina, child: p)],
        );
      },
    );
  }

  Widget _buildZaglavljeDokumenta() {
    return _kartica(
      naslov: 'Podaci o dokumentu',
      ikona: Icons.description_outlined,
      dijete: LayoutBuilder(
        builder: (context, c) {
          final kolone = c.maxWidth >= 640 ? 3 : (c.maxWidth >= 400 ? 2 : 1);
          return _mreza(kolone: kolone, [
            _datumPolje(),
            _buildDobavljac(),
            _buildSkladiste(),
            _polje(
              'RC.BR (broj fakture)',
              rcBrController,
              ikona: Icons.receipt_outlined,
              hint: 'npr. 123/2026',
              poljeApi: 'invoice_number',
              obavezno: true,
            ),
            _polje(
              'Prijemnica br',
              prijemnicaBrController,
              ikona: Icons.move_to_inbox_outlined,
              hint: 'npr. PR-001',
              poljeApi: 'receipt_number',
              obavezno: true,
            ),
          ]);
        },
      ),
    );
  }

  // ---- Artikli --------------------------------------------------------

  List<int> get _vidljiveStavke {
    final pretraga = searchController.text.trim().toLowerCase();
    return [
      for (var i = 0; i < stavke.length; i++)
        if (pretraga.isEmpty ||
            idArtikla(stavke[i].articleId).contains(pretraga) ||
            stavke[i].naziv.toLowerCase().contains(pretraga) ||
            stavke[i].dokument.toLowerCase().contains(pretraga))
          i,
    ];
  }

  Widget _akcijeStavke(_Stavka s) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IkonaAkcija(
          ikona: Icons.timeline_rounded,
          poruka: 'Analitička kartica',
          boja: MagacinBoje.zelena,
          onTap: () => _otvoriKarticu(s),
        ),
        if (!_samoPregled) ...[
          const SizedBox(width: 6),
          IkonaAkcija(
            ikona: Icons.edit_rounded,
            poruka: 'Izmijeni',
            boja: _akcent,
            onTap: _cuvanje ? null : () => _dodajIliIzmijeniArtikal(s),
          ),
          const SizedBox(width: 6),
          IkonaAkcija(
            ikona: Icons.delete_outline_rounded,
            poruka: 'Ukloni',
            boja: MagacinBoje.crvena,
            onTap: _cuvanje ? null : () => _obrisiArtikal(s),
          ),
        ],
      ],
    );
  }

  static const _brojStil = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: MagacinBoje.tekst,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // Kolone tabele artikala: (naziv, flex); akcije imaju fiksnu širinu.
  // Cijena i vrijednost su u istoj ćeliji, pa tabela staje bez skrolovanja.
  static const List<(String, int)> _koloneArtikala = [
    ('#', 4),
    ('Artikal', 30),
    ('Količina', 13),
    ('Fakturno', 16),
    ('Zavisni trošak', 13),
    ('Nabavno', 17),
  ];

  double get _sirinaAkcija => _samoPregled ? 58 : 138;

  Widget _celija(int i, Widget dijete) {
    return Expanded(
      flex: _koloneArtikala[i].$2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Align(
          alignment: i <= 1 ? Alignment.centerLeft : Alignment.centerRight,
          child: dijete,
        ),
      ),
    );
  }

  // Vrijednost krupno, a ispod nje sitno "× jedinična cijena".
  Widget _iznos(
    String vrijednost, {
    String? ispod,
    Color boja = MagacinBoje.naslov,
    FontWeight tezina = FontWeight.w700,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            vrijednost,
            style: _brojStil.copyWith(
              fontSize: 13.5,
              fontWeight: tezina,
              color: boja,
            ),
          ),
        ),
        if (ispod != null) ...[
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              ispod,
              style: _brojStil.copyWith(
                fontSize: 11.5,
                color: MagacinBoje.svijetlo,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _tabelaArtikala(List<int> indeksi) {
    final zaglavlje = Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: MagacinBoje.zaglavlje,
        border: Border(bottom: BorderSide(color: MagacinBoje.linijaSvijetla)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _koloneArtikala.length; i++)
            _celija(
              i,
              Text(
                _koloneArtikala[i].$1.toUpperCase(),
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
          SizedBox(width: _sirinaAkcija),
        ],
      ),
    );

    Widget red(int i) {
      final s = stavke[i];
      return HoverRed(
        akcent: _akcent,
        visina: 64,
        builder: (hover) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              _celija(
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
              _celija(
                1,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.naziv,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: MagacinBoje.naslov,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            idArtikla(s.articleId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: MagacinBoje.priguseno,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        if (s.dokument.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: MagacinBoje.zaglavlje,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: MagacinBoje.linijaSvijetla,
                                ),
                              ),
                              child: Text(
                                s.dokument,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: MagacinBoje.priguseno,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              _celija(
                2,
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _format4(s.kolicina),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: MagacinBoje.naslov,
                        ),
                      ),
                      TextSpan(
                        text: ' ${s.jm}',
                        style: const TextStyle(color: MagacinBoje.priguseno),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _brojStil.copyWith(fontSize: 13.5),
                ),
              ),
              _celija(
                3,
                _iznos(
                  '${_format(s.fakturnaVrijednost)} €',
                  ispod: '× ${_format4(s.fakturnaCijena)} €',
                  tezina: FontWeight.w600,
                  boja: MagacinBoje.tekst,
                ),
              ),
              _celija(
                4,
                _iznos(
                  s.zavisniTrosak == 0
                      ? '—'
                      : '+ ${_format(s.zavisniTrosak)} €',
                  tezina: FontWeight.w600,
                  boja: s.zavisniTrosak == 0
                      ? MagacinBoje.svijetlo
                      : MagacinBoje.tekst,
                ),
              ),
              _celija(
                5,
                _iznos(
                  '${_format(s.nabavnaVrijednost)} €',
                  ispod: '× ${_format4(s.nabavnaCijena)} €',
                  tezina: FontWeight.w800,
                ),
              ),
              SizedBox(
                width: _sirinaAkcija,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _akcijeStavke(s),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Zbir svih stavki (ne samo onih koje odgovaraju pretrazi).
    final ukupnoFakturno = stavke.fold<double>(
      0,
      (z, s) => z + s.fakturnaVrijednost,
    );
    final ukupnoZavisno = stavke.fold<double>(0, (z, s) => z + s.zavisniTrosak);
    final ukupnoNabavno = stavke.fold<double>(
      0,
      (z, s) => z + s.nabavnaVrijednost,
    );

    final ukupno = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: const BoxDecoration(
        color: _akcentSvijetlo,
        border: Border(top: BorderSide(color: MagacinBoje.linija)),
      ),
      child: Row(
        children: [
          _celija(0, const SizedBox()),
          _celija(
            1,
            const Text(
              'Ukupno',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _akcentTamni,
              ),
            ),
          ),
          _celija(2, const SizedBox()),
          _celija(
            3,
            _iznos(
              '${_format(ukupnoFakturno)} €',
              boja: _akcentTamni,
              tezina: FontWeight.w700,
            ),
          ),
          _celija(
            4,
            _iznos(
              ukupnoZavisno == 0 ? '—' : '+ ${_format(ukupnoZavisno)} €',
              boja: _akcentTamni,
              tezina: FontWeight.w700,
            ),
          ),
          _celija(
            5,
            _iznos(
              '${_format(ukupnoNabavno)} €',
              boja: _akcentTamni,
              tezina: FontWeight.w800,
            ),
          ),
          SizedBox(width: _sirinaAkcija),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [zaglavlje, for (final i in indeksi) red(i), ukupno],
    );
  }

  Widget _karticeArtikala(List<int> indeksi) {
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

    return Column(
      children: [
        for (final i in indeksi)
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _akcentSvijetlo,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _akcentTamni,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stavke[i].naziv,
                            maxLines: 2,
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
                              idArtikla(stavke[i].articleId),
                              if (stavke[i].dokument.isNotEmpty)
                                'dok. ${stavke[i].dokument}',
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
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: MagacinBoje.zaglavlje,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: metrika(
                              'Količina',
                              '${_format4(stavke[i].kolicina)} ${stavke[i].jm}',
                            ),
                          ),
                          Expanded(
                            child: metrika(
                              'Fakt. cijena',
                              '${_format4(stavke[i].fakturnaCijena)} €',
                            ),
                          ),
                          Expanded(
                            child: metrika(
                              'Fakt. vrijednost',
                              '${_format(stavke[i].fakturnaVrijednost)} €',
                            ),
                          ),
                        ],
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Divider(height: 1, color: MagacinBoje.linija),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: metrika(
                              'Zavisni trošak',
                              '${_format(stavke[i].zavisniTrosak)} €',
                            ),
                          ),
                          Expanded(
                            child: metrika(
                              'Nab. cijena',
                              '${_format4(stavke[i].nabavnaCijena)} €',
                            ),
                          ),
                          Expanded(
                            child: metrika(
                              'Nab. vrijednost',
                              '${_format(stavke[i].nabavnaVrijednost)} €',
                              jaka: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: _akcijeStavke(stavke[i]),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildArtikli() {
    final indeksi = _vidljiveStavke;

    final pretraga = TextField(
      controller: searchController,
      style: _stilUnosa,
      decoration: dekoracijaPolja(
        hint: 'Pretraži artikle…',
        ikona: Icons.search_rounded,
        suffix: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Obriši pretragu',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: MagacinBoje.priguseno,
                onPressed: searchController.clear,
              ),
      ),
    );

    final dodaj = GlatkoDugme(
      tekst: 'Dodaj artikal',
      ikona: Icons.add_rounded,
      onTap: _cuvanje ? null : () => _dodajIliIzmijeniArtikal(),
    );

    final kopiraj = GlatkoDugme(
      tekst: 'Kopiraj iz kalkulacije',
      ikona: Icons.content_copy_rounded,
      vrsta: VrstaDugmeta.sekundarno,
      onTap: _cuvanje ? null : _kopirajStavke,
    );

    Widget sadrzaj;
    if (stavke.isEmpty) {
      sadrzaj = Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: _akcentSvijetlo,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_shopping_cart_rounded,
                color: _akcent,
                size: 26,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Još nema artikala',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: MagacinBoje.naslov,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _samoPregled
                  ? 'Kalkulacija nema stavki.'
                  : 'Dodajte artikle koje primate ovom kalkulacijom.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: MagacinBoje.priguseno,
              ),
            ),
            if (!_samoPregled) ...[
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [dodaj, kopiraj],
              ),
            ],
          ],
        ),
      );
    } else if (indeksi.isEmpty) {
      sadrzaj = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Nijedan artikal ne odgovara pretrazi.',
            style: TextStyle(color: MagacinBoje.priguseno),
          ),
        ),
      );
    } else {
      sadrzaj = LayoutBuilder(
        builder: (context, c) => c.maxWidth >= 680
            ? _tabelaArtikala(indeksi)
            : _karticeArtikala(indeksi),
      );
    }

    return _kartica(
      naslov: 'Artikli',
      ikona: Icons.inventory_2_outlined,
      opis: stavke.isEmpty
          ? null
          : '${stavke.length} ${stavke.length == 1 ? 'stavka' : (stavke.length < 5 ? 'stavke' : 'stavki')}',
      padding: EdgeInsets.zero,
      dijete: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stavke.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth >= 760) {
                    return Row(
                      children: [
                        Expanded(child: pretraga),
                        if (!_samoPregled) ...[
                          const SizedBox(width: 10),
                          kopiraj,
                          const SizedBox(width: 10),
                          dodaj,
                        ],
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      pretraga,
                      if (!_samoPregled) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: kopiraj),
                            const SizedBox(width: 10),
                            Expanded(child: dodaj),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          if (stavke.isNotEmpty)
            const Divider(height: 1, color: MagacinBoje.linijaSvijetla),
          sadrzaj,
          if (!_samoPregled && stavke.isNotEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              decoration: const BoxDecoration(
                color: MagacinBoje.zaglavlje,
                border: Border(
                  top: BorderSide(color: MagacinBoje.linijaSvijetla),
                ),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: MagacinBoje.svijetlo,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Zavisni troškovi se raspoređuju srazmjerno fakturnoj '
                      'vrijednosti. Konačne vrijednosti računa server pri '
                      'snimanju.',
                      style: TextStyle(
                        fontSize: 12,
                        color: MagacinBoje.priguseno,
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

  // ---- Troškovi, rekapitulacija, potpisi ------------------------------

  Widget _buildTroskovi() {
    void promjena(String _) => setState(_preracunaj);

    return _kartica(
      naslov: 'Zavisni troškovi',
      ikona: Icons.local_shipping_outlined,
      dijete: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _polje(
            'Prevoz',
            prevozController,
            ikona: Icons.local_shipping_outlined,
            hint: '0,00',
            poljeApi: 'transport_cost',
            broj: true,
            onChanged: promjena,
          ),
          const SizedBox(height: 14),
          _polje(
            'Špedicija',
            spedicijaController,
            ikona: Icons.assignment_outlined,
            hint: '0,00',
            poljeApi: 'forwarding_cost',
            broj: true,
            onChanged: promjena,
          ),
          const SizedBox(height: 14),
          _polje(
            'Carina',
            carinaController,
            ikona: Icons.account_balance_outlined,
            hint: '0,00',
            poljeApi: 'customs_cost',
            broj: true,
            onChanged: promjena,
          ),
        ],
      ),
    );
  }

  Widget _buildRekapitulacija() {
    final fv = _fakturnaVrijednost;
    final zt = _zavisniTroskovi;
    final ztn = fv > 0 ? zt / fv * 100 : 0.0;

    Widget red(String naziv, String vrijednost, {String? opis}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    naziv,
                    style: const TextStyle(
                      fontSize: 13,
                      color: MagacinBoje.tekst,
                    ),
                  ),
                  if (opis != null)
                    Text(
                      opis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: MagacinBoje.svijetlo,
                      ),
                    ),
                ],
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
      naslov: 'Rekapitulacija',
      ikona: Icons.functions_rounded,
      dijete: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          red('Fakturna vrijednost', '${_format(fv)} €', opis: 'FV'),
          red('Zavisni troškovi', '${_format(zt)} €', opis: 'svega'),
          red('ZTN', '${_format(ztn)} %', opis: 'zavisni troškovi / FV'),
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
                    'Nabavna vrijednost',
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
                      '${_format(fv + zt)} €',
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

  Widget _buildPotpisi() {
    return _kartica(
      naslov: 'Potpisi',
      ikona: Icons.draw_outlined,
      dijete: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _polje(
            'Kalkulisao',
            kalkulisaoController,
            ikona: Icons.calculate_outlined,
            hint: 'Ime i prezime',
            poljeApi: 'calculated_by',
          ),
          const SizedBox(height: 14),
          _polje(
            'Robu primio',
            robuPrimioController,
            ikona: Icons.inventory_outlined,
            hint: 'Ime i prezime',
            poljeApi: 'received_by',
          ),
        ],
      ),
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
    final k = _kalkulacija;
    final (String tekst, Color boja, Color pozadina, IconData ikona) = k == null
        ? ('Nova', akcentTamni, mint, Icons.fiber_new_rounded)
        : k.jeProknjizena
        ? (
            'Proknjižena',
            MagacinBoje.zelena,
            MagacinBoje.zelenaSvijetlo,
            Icons.check_circle_rounded,
          )
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

  // Štampa se snimljeno stanje sa servera (vrijednosti računa server);
  // nacrt se prvo sačuva da bi odštampana kalkulacija odgovarala ekranu.
  Future<void> _stampaj() async {
    final kalkulacija = _samoPregled ? _kalkulacija : await _sacuvaj();
    if (kalkulacija == null || !mounted) return;

    final broj = kalkulacija.brojPrijemnice.trim();
    final firma = _firmaController.izabranaFirma.value;
    await prikaziPregledStampe(
      context,
      naslov: 'Kalkulacija nabavnih cijena $broj',
      nazivFajla: pdfNazivFajla(
        'kalkulacija_${broj.isEmpty ? kalkulacija.id : broj}',
      ),
      format: PdfPageFormat.a4.landscape,
      napravi: (format) => napraviKalkulacijuNabavnihCijenaPdf(
        kalkulacija: kalkulacija,
        firma: firma,
        format: format,
      ),
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
        tekst: 'Sačuvaj i proknjiži',
        ikona: Icons.inventory_2_outlined,
        visina: 42,
        onTap: _cuvanje ? null : _sacuvajIProknjizi,
      ),
    ];
  }

  Widget _gornjaTraka({required bool siroko}) {
    final k = _kalkulacija;
    final naslov = k == null
        ? 'Nova kalkulacija'
        : 'Kalkulacija ${k.brojPrijemnice.isNotEmpty ? k.brojPrijemnice : k.brojFakture}';

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
                      'KALKULACIJA NABAVNIH CIJENA',
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
                tekst: 'Proknjiži',
                ikona: Icons.inventory_2_outlined,
                onTap: _cuvanje ? null : _sacuvajIProknjizi,
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
      _buildZaglavljeDokumenta(),
      const SizedBox(height: 20),
      _buildArtikli(),
    ];
    final strana = [
      _buildTroskovi(),
      const SizedBox(height: 20),
      _buildRekapitulacija(),
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
              color: MagacinBoje.zelenaSvijetlo,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: hoverNijansa(MagacinBoje.zelena, 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: MagacinBoje.zelena,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _zakljucenaGodina
                        ? 'Poslovna godina ${_kalkulacija!.datum!.year} je '
                              'zaključena. Kalkulacija se više ne može '
                              'mijenjati.'
                        : 'Kalkulacija je proknjižena i više se ne može '
                              'mijenjati.',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF065F46),
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
          // Srednja širina: troškovi i rekapitulacija jedno pored drugog.
          if (sirina >= 720)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildTroskovi()),
                const SizedBox(width: 20),
                Expanded(child: _buildRekapitulacija()),
              ],
            )
          else ...[
            _buildTroskovi(),
            const SizedBox(height: 20),
            _buildRekapitulacija(),
          ],
          const SizedBox(height: 20),
          _buildPotpisi(),
        ],
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
// DIJALOG: izbor artikla, dokument, količina i fakturna cijena
// GET /companies/{company}/purchase-calculations/articles?search=...
// ======================================================================
class _ArtikalDialog extends StatefulWidget {
  final int firmaId;
  final String dokument;
  final _Stavka? stavka;
  // Ako je zadat, nude se samo artikli tog tipa (prema skladištu kalkulacije).
  final String? tipArtikla;

  const _ArtikalDialog({
    required this.firmaId,
    required this.dokument,
    this.stavka,
    this.tipArtikla,
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
      final tip = widget.tipArtikla;
      setState(
        () => _rezultati = tip == null
            ? artikli
            : artikli.where((a) => a.tip == null || a.tip == tip).toList(),
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
        tip: artikal.tip ?? widget.stavka?.tip,
      ),
    );
  }

  Widget _stavkaListe(Artikal artikal) {
    final izabran = artikal.id == _artikal?.id;
    final gotov = artikal.tip == tipGotovProizvod;
    final tema = TemaSkladista.za(gotov ? 'finished_goods' : 'raw_materials');
    return _HoverIzbor(
      izabran: izabran,
      onTap: () => setState(() => _artikal = artikal),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
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
                    gotov ? 'Gotov proizvod' : 'Repromaterijal',
                    artikal.jm,
                    if (artikal.cijena != null)
                      'prosj. ${_format4(artikal.cijena!)} €',
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
            'Nema artikala za ovu pretragu.',
            style: TextStyle(color: MagacinBoje.priguseno),
          ),
        ),
      );
    }

    return AnimatedOpacity(
      duration: hoverTrajanje,
      opacity: _ucitavanje ? 0.55 : 1,
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.all(6),
        itemCount: _rezultati.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, index) => _stavkaListe(_rezultati[index]),
      ),
    );
  }

  Widget _brojPolje(
    String oznaka,
    TextEditingController controller, {
    required FormFieldValidator<String> validator,
    String? suffix,
    bool zadnje = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        OznakaPolja(oznaka, obavezno: true),
        TextFormField(
          controller: controller,
          inputFormatters: [_decimalFormatter],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: validator,
          textInputAction: zadnje ? TextInputAction.done : TextInputAction.next,
          onFieldSubmitted: zadnje ? (_) => _potvrdi() : null,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MagacinBoje.naslov,
          ),
          decoration: dekoracijaPolja(hint: '0').copyWith(suffixText: suffix),
        ),
      ],
    );
  }

  Widget _sadrzaj(double sirina) {
    final fv =
        _parse(kolicinaController.text) * _parse(fakturnaController.text);
    final artikal = _artikal;

    final dokument = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const OznakaPolja('Dokument'),
        TextFormField(
          controller: dokumentController,
          maxLength: 100,
          textInputAction: TextInputAction.next,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MagacinBoje.naslov,
          ),
          decoration: dekoracijaPolja(
            hint: 'Broj fakture',
            ikona: Icons.receipt_outlined,
          ),
        ),
      ],
    );
    final kolicina = _brojPolje(
      'Količina',
      kolicinaController,
      validator: _kolicinaValidator,
      suffix: artikal?.jm,
    );
    final cijena = _brojPolje(
      'Fakturna cijena',
      fakturnaController,
      validator: _cijenaValidator,
      suffix: '€',
      zadnje: true,
    );

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: pretragaController,
            autofocus: widget.stavka == null,
            onChanged: _promjenaPretrage,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: MagacinBoje.naslov,
            ),
            decoration: dekoracijaPolja(
              hint: 'Pretraži po nazivu…',
              ikona: Icons.search_rounded,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MagacinBoje.linija),
            ),
            child: _lista(),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: hoverTrajanje,
            child: artikal == null
                ? Container(
                    key: const ValueKey('nema'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MagacinBoje.zaglavlje,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MagacinBoje.linijaSvijetla),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 18,
                          color: MagacinBoje.svijetlo,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Izaberite artikal iz liste.',
                            style: TextStyle(color: MagacinBoje.priguseno),
                          ),
                        ),
                      ],
                    ),
                  )
                : Container(
                    key: ValueKey(artikal.id),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE6F4F3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: hoverNijansa(akcentAplikacije, 0.25),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: akcentAplikacije,
                        ),
                        const SizedBox(width: 10),
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
                  ),
          ),
          const SizedBox(height: 18),
          if (sirina >= 480)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: dokument),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: kolicina),
                const SizedBox(width: 12),
                Expanded(flex: 3, child: cijena),
              ],
            )
          else ...[
            dokument,
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: kolicina),
                const SizedBox(width: 12),
                Expanded(child: cijena),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: MagacinBoje.zaglavlje,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Fakturna vrijednost',
                    style: TextStyle(
                      fontSize: 13,
                      color: MagacinBoje.priguseno,
                    ),
                  ),
                ),
                Text(
                  '${_format(fv)} €',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: MagacinBoje.naslov,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usko = MediaQuery.sizeOf(context).width < 600;
    final novi = widget.stavka == null;

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
          child: Icon(
            novi ? Icons.add_shopping_cart_rounded : Icons.edit_rounded,
            color: akcentAplikacije,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                novi ? 'Dodaj artikal' : 'Izmijeni artikal',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.naslov,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'Izaberite artikal, pa unesite količinu i fakturnu cijenu.',
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
    final potvrdi = GlatkoDugme(
      tekst: novi ? 'Dodaj artikal' : 'Sačuvaj',
      ikona: Icons.check_rounded,
      onTap: _artikal == null ? null : _potvrdi,
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
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                    child: _sadrzaj(c.maxWidth - 36),
                  ),
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
                    Expanded(flex: 2, child: potvrdi),
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
        constraints: const BoxConstraints(maxWidth: 600),
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
              child: LayoutBuilder(
                builder: (context, c) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
                  child: _sadrzaj(c.maxWidth - 48),
                ),
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
                children: [odustani, const SizedBox(width: 10), potvrdi],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Stavka liste artikala sa glatkim hoverom; izabrana ima ljubičast okvir.
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

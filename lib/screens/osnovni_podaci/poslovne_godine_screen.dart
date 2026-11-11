import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/firma_controller.dart';
import '../../controllers/poslovne_godine_controller.dart';
import '../../models/auth_models.dart';
import '../../models/fiscal_year.dart';
import '../../widgets/logo.dart';
import '../../widgets/magacin_ui.dart';

// Poslovne godine firme: zaključivanje i ponovno otvaranje.
// GET/POST /companies/{company}/fiscal-years[/{year}/close|reopen]

const Color _akcent = akcentAplikacije;
const Color _akcentSvijetlo = Color(0xFFE6F4F3);
const Color _zakljucena = Color(0xFF475569);
const Color _zakljucenaSvijetlo = Color(0xFFE2E8F0);
const Color _otvorena = MagacinBoje.zelena;
const Color _otvorenaSvijetlo = MagacinBoje.zelenaSvijetlo;

const double _sirinaTabele = 860;
const double _visinaReda = 72;

// Kolone tabele: (naziv, flex).
const List<(String, int)> _kolone = [
  ('Godina', 10),
  ('Status', 13),
  ('Zaključeno', 20),
  ('Nacrta', 9),
  ('', 22),
];

String _formatDatumVrijeme(DateTime? d) {
  if (d == null) return '';
  String dva(int n) => n.toString().padLeft(2, '0');
  return '${dva(d.day)}.${dva(d.month)}.${d.year}. ${dva(d.hour)}:${dva(d.minute)}';
}

String _nacrta(int n) => switch (n) {
  1 => '1 dokument u nacrtu',
  _ => '$n dokumenata u nacrtu',
};

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

class PoslovneGodineScreen extends StatefulWidget {
  const PoslovneGodineScreen({super.key});

  @override
  State<PoslovneGodineScreen> createState() => _PoslovneGodineScreenState();
}

class _PoslovneGodineScreenState extends State<PoslovneGodineScreen> {
  final FirmaController _firmaController = Get.find<FirmaController>();
  final PoslovneGodineController _controller =
      Get.find<PoslovneGodineController>();

  // Godina na kojoj je akcija u toku (dugme pokazuje učitavanje).
  int? _uToku;

  bool get _imaFirmu => _firmaController.izabranaFirma.value != null;

  @override
  void initState() {
    super.initState();
    // Broj nacrta se mijenja dok se radi s dokumentima; osvježi pri otvaranju.
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.ucitaj());
  }

  PoslovnaGodina? _godina(int godina) =>
      _controller.godine.firstWhereOrNull((g) => g.godina == godina);

  // Razlog zašto se godina ne može zaključiti (null = može).
  // Server ima zadnju riječ; ovo je samo da dugme ne nudi nemoguće.
  String? _razlogZaZakljucenje(PoslovnaGodina g) {
    if (g.zakljucena) return 'Godina je već zaključena.';
    if (!g.zavrsena) {
      return 'Godina ${g.godina} se može zaključiti tek od 1.1.${g.godina + 1}.';
    }
    final prethodna = _godina(g.godina - 1);
    if (prethodna != null && !prethodna.zakljucena) {
      return 'Prvo zaključite ${prethodna.godina}. godinu.';
    }
    if (g.brojNacrta > 0) {
      return 'U godini ima još ${_nacrta(g.brojNacrta)}. '
          'Proknjižite, izdajte ili obrišite ih.';
    }
    return null;
  }

  Future<void> _zakljuci(PoslovnaGodina g) async {
    final potvrda = await _potvrdi(
      naslov: 'Zaključi ${g.godina}. godinu?',
      tekst:
          'Kalkulacije i radni nalozi sa datumom u ${g.godina}. godini se '
          'više neće moći kreirati, mijenjati, knjižiti, izdavati ni brisati.',
      dugme: 'Zaključi',
      ikona: Icons.lock_rounded,
      opasno: false,
    );
    if (!potvrda || !mounted) return;
    await _izvrsi(
      g,
      () => _controller.zakljuci(g.godina),
      'Godina ${g.godina} je zaključena.',
    );
  }

  Future<void> _izvrsi(
    PoslovnaGodina g,
    Future<PoslovnaGodina> Function() poziv,
    String uspjeh,
  ) async {
    setState(() => _uToku = g.godina);
    try {
      await poziv();
      if (mounted) _poruka(context, uspjeh);
    } on ApiException catch (e) {
      if (!mounted) return;
      _poruka(context, e.fieldError('year') ?? e.message);
      // Stanje na serveru se možda promijenilo (npr. novi nacrt).
      _controller.ucitaj();
    } finally {
      if (mounted) setState(() => _uToku = null);
    }
  }

  Future<bool> _potvrdi({
    required String naslov,
    required String tekst,
    required String dugme,
    required IconData ikona,
    required bool opasno,
  }) async {
    final potvrda = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x800F172A),
      builder: (context) => PotvrdaDijalog(
        naslov: naslov,
        tekst: tekst,
        dugme: dugme,
        ikona: ikona,
        opasno: opasno,
      ),
    );
    return potvrda == true;
  }

  // ---------------------------------------------------------------------------
  // Sitni elementi
  // ---------------------------------------------------------------------------

  Widget _statusOznaka(PoslovnaGodina g) {
    final z = g.zakljucena;
    final boja = z ? _zakljucena : _otvorena;
    return Container(
      width: 112,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: z ? _zakljucenaSvijetlo : _otvorenaSvijetlo,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            z ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 12,
            color: boja,
          ),
          const SizedBox(width: 5),
          Text(
            z ? 'Zaključena' : 'Otvorena',
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

  Widget _tekst(String? tekst, {bool jaci = false}) {
    final prazno = (tekst ?? '').isEmpty;
    return Text(
      prazno ? '—' : tekst!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 13,
        fontWeight: jaci ? FontWeight.w600 : FontWeight.w500,
        color: prazno
            ? MagacinBoje.svijetlo
            : jaci
            ? MagacinBoje.naslov
            : MagacinBoje.priguseno,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _brojNacrta(PoslovnaGodina g) {
    final ima = g.brojNacrta > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: ima ? MagacinBoje.narandzastaSvijetlo : MagacinBoje.zaglavlje,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: ima ? Colors.transparent : MagacinBoje.linija,
        ),
      ),
      child: Text(
        '${g.brojNacrta}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: ima ? const Color(0xFF92400E) : MagacinBoje.tekst,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  // Zaključena godina nema akciju (ponovno otvaranje nije u aplikaciji).
  Widget _akcija(PoslovnaGodina g) {
    if (g.zakljucena) {
      // Umjesto dugmeta: tiha oznaka da su dokumenti godine zaključani.
      return Tooltip(
        message:
            'Dokumenti iz ${g.godina}. godine se ne mogu mijenjati, '
            'knjižiti, izdavati ni brisati.',
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: MagacinBoje.zaglavlje,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MagacinBoje.linija),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_outlined,
                size: 16,
                color: MagacinBoje.zelena,
              ),
              SizedBox(width: 7),
              Text(
                'Dokumenti zaključani',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final razlog = _razlogZaZakljucenje(g);
    final uToku = _uToku == g.godina;
    final zauzeto = _uToku != null;

    final dugme = GlatkoDugme(
      tekst: 'Zaključi',
      ikona: Icons.lock_rounded,
      visina: 38,
      ucitavanje: uToku,
      onTap: razlog != null || zauzeto ? null : () => _zakljuci(g),
    );

    return razlog == null ? dugme : Tooltip(message: razlog, child: dugme);
  }

  // Kratka napomena ispod godine kad se ne može zaključiti (npr. nacrti).
  String? _napomena(PoslovnaGodina g) {
    if (g.zakljucena) return null;
    if (!g.zavrsena) return 'Tekuća godina';
    return _razlogZaZakljucenje(g);
  }

  // ---------------------------------------------------------------------------
  // Tabela (širok ekran)
  // ---------------------------------------------------------------------------

  Widget _celija(int i, Widget dijete) {
    final desno = i == _kolone.length - 1;
    return Expanded(
      flex: _kolone[i].$2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: desno ? Alignment.centerRight : Alignment.centerLeft,
          child: dijete,
        ),
      ),
    );
  }

  Widget _zaglavljeTabele() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: MagacinBoje.zaglavlje,
        border: Border(bottom: BorderSide(color: MagacinBoje.linija)),
      ),
      child: Row(
        children: [
          for (int i = 0; i < _kolone.length; i++)
            _celija(
              i,
              Text(
                _kolone[i].$1.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  letterSpacing: 0.9,
                  fontWeight: FontWeight.w800,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _godinaTekst(PoslovnaGodina g, {bool velik = false}) {
    final napomena = _napomena(g);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${g.godina}',
          style: TextStyle(
            fontSize: velik ? 20 : 16,
            fontWeight: FontWeight.w800,
            color: MagacinBoje.naslov,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (napomena != null && velik) ...[
          const SizedBox(height: 2),
          Text(
            napomena,
            style: const TextStyle(fontSize: 12, color: MagacinBoje.priguseno),
          ),
        ],
      ],
    );
  }

  Widget _red(PoslovnaGodina g) {
    return HoverRed(
      akcent: _akcent,
      visina: _visinaReda,
      builder: (hover) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            _celija(0, _godinaTekst(g)),
            _celija(1, _statusOznaka(g)),
            _celija(2, _tekst(_formatDatumVrijeme(g.zakljucenaU))),
            _celija(3, _brojNacrta(g)),
            _celija(4, _akcija(g)),
          ],
        ),
      ),
    );
  }

  Widget _tabela(List<PoslovnaGodina> godine) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MagacinBoje.linija),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 3,
            child: _controller.isLoading.value
                ? const LinearProgressIndicator(
                    color: _akcent,
                    backgroundColor: _akcentSvijetlo,
                  )
                : null,
          ),
          _zaglavljeTabele(),
          if (godine.isEmpty)
            _praznoStanje()
          else
            for (final g in godine)
              Container(
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: MagacinBoje.linijaSvijetla),
                  ),
                ),
                child: _red(g),
              ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Kartice (uzak ekran)
  // ---------------------------------------------------------------------------

  Widget _kartica(PoslovnaGodina g) {
    Widget podatak(IconData ikona, String naziv, Widget vrijednost) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(ikona, size: 15, color: MagacinBoje.svijetlo),
            const SizedBox(width: 8),
            SizedBox(
              width: 86,
              child: Text(
                naziv,
                style: const TextStyle(
                  fontSize: 12,
                  color: MagacinBoje.priguseno,
                ),
              ),
            ),
            Expanded(child: vrijednost),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MagacinBoje.linija),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _godinaTekst(g, velik: true)),
              const SizedBox(width: 8),
              _statusOznaka(g),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MagacinBoje.zaglavlje,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                podatak(
                  Icons.event_rounded,
                  'Zaključeno',
                  _tekst(_formatDatumVrijeme(g.zakljucenaU)),
                ),
                podatak(
                  Icons.edit_note_rounded,
                  'U nacrtu',
                  Align(alignment: Alignment.centerLeft, child: _brojNacrta(g)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: _akcija(g)),
        ],
      ),
    );
  }

  Widget _kartice(List<PoslovnaGodina> godine) {
    if (godine.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MagacinBoje.linija),
        ),
        child: _praznoStanje(),
      );
    }
    return Column(
      children: [
        for (final g in godine)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _kartica(g),
          ),
      ],
    );
  }

  Widget _praznoStanje() {
    final greska = _controller.errorMessage.value;
    final ucitava = _controller.isLoading.value;

    if (ucitava && greska == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: _akcent),
          ),
        ),
      );
    }

    final (IconData ikona, String naslov, String opis) = !_imaFirmu
        ? (
            Icons.business_rounded,
            'Nije izabrana firma',
            'Izaberite firmu u gornjem desnom uglu da vidite poslovne godine.',
          )
        : greska != null
        ? (
            Icons.error_outline_rounded,
            'Poslovne godine se ne mogu učitati',
            greska,
          )
        : (
            Icons.event_note_rounded,
            'Još nema poslovnih godina',
            'Godine se pojavljuju od prvog dokumenta firme.',
          );

    final jeGreska = greska != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZecStanja(
            poza: jeGreska ? PozaZeca.lezi : PozaZeca.stoji,
            ikona: ikona,
            boja: jeGreska ? MagacinBoje.crvena : _akcent,
            pozadina: jeGreska ? MagacinBoje.crvenaSvijetlo : _akcentSvijetlo,
            visina: jeGreska ? 60 : 128,
          ),
          const SizedBox(height: 16),
          Text(
            naslov,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: MagacinBoje.naslov,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            opis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: MagacinBoje.priguseno),
          ),
          if (jeGreska) ...[
            const SizedBox(height: 18),
            GlatkoDugme(
              tekst: 'Pokušaj ponovo',
              ikona: Icons.refresh_rounded,
              vrsta: VrstaDugmeta.sekundarno,
              onTap: ucitava ? null : _controller.ucitaj,
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Zaglavlje
  // ---------------------------------------------------------------------------

  Widget _zaglavlje() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final malo = constraints.maxWidth < 600;

        final naslov = Row(
          children: [
            ZnakDokumenta(ikona: Icons.event_available_rounded, malo: malo),
            SizedBox(width: malo ? 14 : 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OSNOVNI PODACI',
                    style: TextStyle(
                      fontSize: 10.5,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w800,
                      color: _akcent.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Poslovne godine',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: malo ? 22 : 28,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: MagacinBoje.naslov,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final osvjezi = GlatkoDugme(
          tekst: 'Osvježi',
          ikona: Icons.refresh_rounded,
          vrsta: VrstaDugmeta.sekundarno,
          visina: 48,
          onTap: _imaFirmu && !_controller.isLoading.value
              ? _controller.ucitaj
              : null,
        );

        const opis = Text(
          'Godine se zaključuju redom, od najstarije. Dokumenti iz zaključene '
          'godine se ne mogu mijenjati, knjižiti, izdavati ni brisati.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: MagacinBoje.priguseno,
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (constraints.maxWidth >= 640)
              Row(
                children: [
                  Expanded(child: naslov),
                  const SizedBox(width: 20),
                  osvjezi,
                ],
              )
            else ...[
              naslov,
              const SizedBox(height: 16),
              osvjezi,
            ],
            const SizedBox(height: 14),
            opis,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: MagacinBoje.pozadina,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final razmak = w < 600 ? 12.0 : 24.0;

          return SingleChildScrollView(
            padding: EdgeInsets.all(razmak),
            child: Obx(() {
              _firmaController.izabranaFirma.value;
              _controller.isLoading.value;
              final godine = _controller.godine.toList();
              final greska = _controller.errorMessage.value;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _zaglavlje(),
                  const SizedBox(height: 20),
                  if (greska != null && godine.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Text(
                        greska,
                        style: const TextStyle(
                          color: MagacinBoje.crvena,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (w >= _sirinaTabele) _tabela(godine) else _kartice(godine),
                ],
              );
            }),
          );
        },
      ),
    );
  }
}

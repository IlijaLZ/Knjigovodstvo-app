import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../controllers/firma_controller.dart';
import '../controllers/navigation_controller.dart';
import '../controllers/niske_zalihe_controller.dart';
import '../models/company.dart';
import 'logo.dart';
import 'magacin_ui.dart';

// Gornja traka aplikacije: meni, izbor firme i korisnik.
// Široko: horizontalni meni sa padajućim listama. Srednje: isti meni,
// zbijeniji. Usko: dugme koje otvara bočni meni (GlavniMeniDrawer).

const Color _akcent = Color(0xFF0F5C66);
const Color _akcentSvijetlo = Color(0xFFE6F4F3);
const Color _hoverPozadina = Color(0xFFF1F5F9);

// Granice širine za header (i bočni meni u MainScreen).
const double sirinaUskogHeadera = 800;
const double _sirinaPunogHeadera = 1180;
const double _sirinaSaNazivom = 1400;

class _Stavka {
  final String naziv;
  final IconData ikona;
  final int? index;
  final void Function(NavigationController c)? otvori;

  // Stavka dobija crveni kružić kad ima repromaterijala ispod minimuma.
  final bool niskeZalihe;

  const _Stavka(
    this.naziv,
    this.ikona, {
    this.index,
    this.otvori,
    this.niskeZalihe = false,
  });

  bool sadrzi(int i) => index == i;

  // Broj upozorenja za ovu stavku (0 = bez kružića).
  int upozorenja(int niske) => niskeZalihe ? niske : 0;
}

class _Sekcija {
  final String naziv;
  final IconData ikona;
  final List<_Stavka> stavke;

  // Sekcija bez padajuće liste (jedna stranica).
  final _Stavka? direktno;

  const _Sekcija(this.naziv, this.ikona, this.stavke, {this.direktno});

  bool sadrzi(int i) =>
      (direktno?.sadrzi(i) ?? false) || stavke.any((s) => s.sadrzi(i));

  int upozorenja(int niske) =>
      (direktno?.upozorenja(niske) ?? 0) +
      stavke.fold(0, (suma, s) => suma + s.upozorenja(niske));
}

String _porukaUpozorenja(int broj) => broj == 1
    ? '1 artikal ispod minimalne količine'
    : '$broj artikala ispod minimalne količine';

// Crveni kružić upozorenja; sa brojem ako je zadat, inače mala tačka.
class _CrveniKruzic extends StatelessWidget {
  final int? broj;

  const _CrveniKruzic({this.broj});

  @override
  Widget build(BuildContext context) {
    if (broj == null) {
      return Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: MagacinBoje.crvena,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      height: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4.5),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: MagacinBoje.crvena,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      child: Text(
        broj! > 99 ? '99+' : '$broj',
        style: const TextStyle(
          fontSize: 9.5,
          height: 1,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

final List<_Sekcija> _sekcije = [
  _Sekcija(
    'Početna',
    Icons.home_rounded,
    const [],
    direktno: _Stavka(
      'Početna',
      Icons.home_rounded,
      index: 0,
      otvori: (c) => c.openPocetna(),
    ),
  ),
  _Sekcija('Osnovni podaci', Icons.folder_open_rounded, [
    _Stavka(
      'Firme',
      Icons.business_rounded,
      index: 19,
      otvori: (c) => c.openFirme(),
    ),
    _Stavka(
      'Poslovne godine',
      Icons.event_available_rounded,
      index: 22,
      otvori: (c) => c.openPoslovneGodine(),
    ),

    _Stavka(
      'Artikli repromaterijala',
      Icons.category_rounded,
      index: 3,
      otvori: (c) => c.openArtikliRepromaterijala(),
    ),
    _Stavka(
      'Artikli gotovih proizvoda',
      Icons.widgets_rounded,
      index: 16,
      otvori: (c) => c.openArtikliGotovihProizvoda(),
    ),
    _Stavka(
      'Glavna knjiga',
      Icons.menu_book_rounded,
      index: 1,
      otvori: (c) => c.openOFirmi(),
    ),
    _Stavka(
      'Dobavljači',
      Icons.storefront_rounded,
      index: 17,
      otvori: (c) => c.openDobavljaci(),
    ),
    _Stavka(
      'Kupci',
      Icons.people_alt_rounded,
      index: 18,
      otvori: (c) => c.openKupci(),
    ),
  ]),
  _Sekcija('Dokumenta', Icons.description_rounded, [
    _Stavka(
      'Kalkulacija nabavnih cijena',
      Icons.calculate_rounded,
      index: 4,
      otvori: (c) => c.openKalkulacijaNabavnihCijena(),
    ),
    _Stavka(
      'Radni nalog',
      Icons.assignment_rounded,
      index: 5,
      otvori: (c) => c.openRadniNalog(),
    ),
    _Stavka(
      'Trebovanje',
      Icons.outbox_rounded,
      index: 6,
      otvori: (c) => c.openTrebovanje(),
    ),
    _Stavka(
      'Kalk. cijene koštanja',
      Icons.price_change_rounded,
      index: 7,
      otvori: (c) => c.openKalkulacijaCijeneKostanja(),
    ),
    _Stavka(
      'Otpremnica',
      Icons.local_shipping_outlined,
      index: 8,
      otvori: (c) => c.openOtpremnica(),
    ),
  ]),
  _Sekcija(
    'Knjiženje naloga',
    Icons.edit_note_rounded,
    const [],
    direktno: _Stavka(
      'Knjiženje naloga',
      Icons.edit_note_rounded,
      index: 9,
      otvori: (c) => c.openKnjizenjeNaloga(),
    ),
  ),
  _Sekcija('Stanja', Icons.inventory_rounded, [
    _Stavka(
      'Magacin repromaterijala',
      Icons.inventory_2_rounded,
      index: 12,
      otvori: (c) => c.openStanjeMagacina(),
      niskeZalihe: true,
    ),
    _Stavka(
      'Magacin proizvodnje u toku',
      Icons.precision_manufacturing_rounded,
      index: 20,
      otvori: (c) => c.openStanjeProizvodnje(),
    ),
    _Stavka(
      'Magacin gotovih proizvoda',
      Icons.local_shipping_rounded,
      index: 21,
      otvori: (c) => c.openStanjeGotovihProizvoda(),
    ),
  ]),
];

// Naziv trenutne stranice (za uski header).
String _nazivStranice(int index) {
  if (index == 0) return 'Početna';
  for (final s in _sekcije) {
    if (s.direktno?.index == index) return s.direktno!.naziv;
    for (final st in s.stavke) {
      if (st.index == index) return st.naziv;
    }
  }
  return 'Kalkulino';
}

String _inicijali(String ime) {
  final dijelovi = ime.trim().split(RegExp(r'\s+')).where((d) => d.isNotEmpty);
  final slova = dijelovi.take(2).map((d) => d.characters.first.toUpperCase());
  return slova.isEmpty ? '?' : slova.join();
}

const _oblikMenija = RoundedRectangleBorder(
  borderRadius: BorderRadius.all(Radius.circular(14)),
  side: BorderSide(color: MagacinBoje.linija),
);

MenuStyle get _stilMenija => MenuStyle(
  backgroundColor: const WidgetStatePropertyAll(Colors.white),
  surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
  elevation: const WidgetStatePropertyAll(10),
  shadowColor: const WidgetStatePropertyAll(Color(0x330F172A)),
  shape: const WidgetStatePropertyAll(_oblikMenija),
  padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
);

ButtonStyle _stilStavke(bool aktivna) => ButtonStyle(
  minimumSize: const WidgetStatePropertyAll(Size(240, 42)),
  padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
  shape: const WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
  ),
  backgroundColor: WidgetStateProperty.resolveWith(
    (s) => aktivna
        ? _akcentSvijetlo
        : s.contains(WidgetState.hovered) || s.contains(WidgetState.focused)
        ? _hoverPozadina
        : Colors.transparent,
  ),
  overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  foregroundColor: WidgetStatePropertyAll(
    aktivna ? _akcent : MagacinBoje.tekst,
  ),
  iconColor: WidgetStatePropertyAll(aktivna ? _akcent : MagacinBoje.priguseno),
  textStyle: WidgetStatePropertyAll(
    TextStyle(
      fontSize: 13.5,
      fontWeight: aktivna ? FontWeight.w700 : FontWeight.w500,
    ),
  ),
);

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class GlavniHeader extends StatelessWidget {
  // Otvara bočni meni (samo na uskom ekranu).
  final VoidCallback onMeni;

  const GlavniHeader({super.key, required this.onMeni});

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavigationController>();
    final niske = Get.find<NiskeZaliheController>();

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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final usko = w < sirinaUskogHeadera;
            final puno = w >= _sirinaPunogHeadera;

            return SizedBox(
              height: usko ? 60 : 66,
              child: Obx(() {
                final index = nav.selectedIndex.value;
                final brojNiskih = niske.stavke.length;

                if (usko) {
                  return Row(
                    children: [
                      const SizedBox(width: 8),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _IkonaDugme(
                            ikona: Icons.menu_rounded,
                            poruka: brojNiskih > 0
                                ? 'Meni — ${_porukaUpozorenja(brojNiskih)}'
                                : 'Meni',
                            onTap: onMeni,
                          ),
                          if (brojNiskih > 0)
                            const Positioned(
                              right: 7,
                              top: 7,
                              child: IgnorePointer(child: _CrveniKruzic()),
                            ),
                        ],
                      ),
                      const SizedBox(width: 4),
                      _LogoDugme(onTap: nav.openPocetna, velicina: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _nazivStranice(index),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: MagacinBoje.naslov,
                          ),
                        ),
                      ),
                      const _FirmaIzbor(kompaktno: true),
                      const SizedBox(width: 4),
                      const _OdjavaDugme(kompaktno: true),
                      const SizedBox(width: 8),
                    ],
                  );
                }

                return Row(
                  children: [
                    SizedBox(width: puno ? 20 : 14),
                    _LogoDugme(
                      onTap: nav.openPocetna,
                      velicina: 40,
                      // Naziv samo kad ima mjesta pored punog menija.
                      saNazivom: w >= _sirinaSaNazivom,
                    ),
                    Container(
                      width: 1,
                      height: 28,
                      margin: EdgeInsets.symmetric(horizontal: puno ? 16 : 12),
                      color: MagacinBoje.linija,
                    ),
                    // Meni se skroluje ako ipak ne stane (npr. veliki font).
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            // Početna se otvara klikom na logo.
                            for (final s in _sekcije.where(
                              (s) => s.direktno?.index != 0,
                            ))
                              Padding(
                                padding: const EdgeInsets.only(right: 2),
                                child: s.direktno != null
                                    ? _NavDugme(
                                        naziv: s.naziv,
                                        ikona: puno ? s.ikona : null,
                                        aktivno: s.sadrzi(index),
                                        upozorenja: s.upozorenja(brojNiskih),
                                        onTap: () => s.direktno!.otvori!(nav),
                                      )
                                    : _NavMeni(
                                        sekcija: s,
                                        index: index,
                                        saIkonom: puno,
                                        brojNiskih: brojNiskih,
                                      ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: puno ? 260 : 180),
                      child: const _FirmaIzbor(kompaktno: false),
                    ),
                    const SizedBox(width: 8),
                    _OdjavaDugme(kompaktno: !puno),
                    SizedBox(width: puno ? 20 : 14),
                  ],
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

// Logo u headeru; klik vodi na početnu. Na hover se pločica blago podigne.
class _LogoDugme extends StatefulWidget {
  final VoidCallback onTap;
  final double velicina;
  final bool saNazivom;

  const _LogoDugme({
    required this.onTap,
    required this.velicina,
    this.saNazivom = false,
  });

  @override
  State<_LogoDugme> createState() => _LogoDugmeState();
}

class _LogoDugmeState extends State<_LogoDugme> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Početna',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: hoverTrajanje,
                curve: hoverKriva,
                scale: _hover ? 1.06 : 1,
                child: AnimatedRotation(
                  duration: hoverTrajanje,
                  curve: hoverKriva,
                  turns: _hover ? -0.012 : 0,
                  child: LogoZnak(velicina: widget.velicina),
                ),
              ),
              if (widget.saNazivom) ...[
                const SizedBox(width: 10),
                const LogoNaziv(velicina: 16.5, boja: MagacinBoje.naslov),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Dugme u meniju sa glatkim hoverom (neprozirne boje, bez bljeska).
class _NavDugme extends StatefulWidget {
  final String naziv;
  final IconData? ikona;
  final bool aktivno;
  final bool otvoreno;
  final bool saStrelicom;
  final VoidCallback onTap;

  // > 0: crveni kružić u gornjem desnom uglu.
  final int upozorenja;

  const _NavDugme({
    required this.naziv,
    required this.aktivno,
    required this.onTap,
    this.ikona,
    this.otvoreno = false,
    this.saStrelicom = false,
    this.upozorenja = 0,
  });

  @override
  State<_NavDugme> createState() => _NavDugmeState();
}

class _NavDugmeState extends State<_NavDugme> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final istaknuto = _hover || widget.otvoreno;
    final pozadina = widget.aktivno
        ? _akcentSvijetlo
        : istaknuto
        ? _hoverPozadina
        : Colors.white;
    final boja = widget.aktivno
        ? _akcent
        : istaknuto
        ? MagacinBoje.naslov
        : MagacinBoje.tekst;

    final dugme = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: hoverTrajanje,
          curve: hoverKriva,
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: pozadina,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TweenAnimationBuilder<Color?>(
            duration: hoverTrajanje,
            curve: hoverKriva,
            tween: ColorTween(end: boja),
            builder: (context, c, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.ikona != null) ...[
                  Icon(widget.ikona, size: 17, color: c),
                  const SizedBox(width: 7),
                ],
                Text(
                  widget.naziv,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: widget.aktivno
                        ? FontWeight.w700
                        : FontWeight.w600,
                    color: c,
                  ),
                ),
                if (widget.saStrelicom) ...[
                  const SizedBox(width: 3),
                  AnimatedRotation(
                    duration: hoverTrajanje,
                    curve: hoverKriva,
                    turns: widget.otvoreno ? 0.5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: c,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.upozorenja <= 0) return dugme;

    return Tooltip(
      message: _porukaUpozorenja(widget.upozorenja),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          dugme,
          const Positioned(
            right: 2,
            top: 2,
            child: IgnorePointer(child: _CrveniKruzic()),
          ),
        ],
      ),
    );
  }
}

class _NavMeni extends StatefulWidget {
  final _Sekcija sekcija;
  final int index;
  final bool saIkonom;
  final int brojNiskih;

  const _NavMeni({
    required this.sekcija,
    required this.index,
    required this.saIkonom,
    required this.brojNiskih,
  });

  @override
  State<_NavMeni> createState() => _NavMeniState();
}

class _NavMeniState extends State<_NavMeni> {
  bool _otvoren = false;

  List<Widget> _stavke(NavigationController nav, List<_Stavka> stavke) {
    return [
      for (final s in stavke)
        MenuItemButton(
          style: _stilStavke(s.sadrzi(widget.index)),
          leadingIcon: Icon(s.ikona, size: 18),
          trailingIcon: s.upozorenja(widget.brojNiskih) > 0
              ? Tooltip(
                  message: _porukaUpozorenja(s.upozorenja(widget.brojNiskih)),
                  child: _CrveniKruzic(broj: s.upozorenja(widget.brojNiskih)),
                )
              : s.sadrzi(widget.index)
              ? const Icon(Icons.check_rounded, size: 16)
              : null,
          onPressed: () => s.otvori!(nav),
          child: Text(s.naziv),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavigationController>();
    return MenuAnchor(
      style: _stilMenija,
      alignmentOffset: const Offset(0, 8),
      onOpen: () => setState(() => _otvoren = true),
      onClose: () => setState(() => _otvoren = false),
      menuChildren: _stavke(nav, widget.sekcija.stavke),
      builder: (context, kontroler, _) => _NavDugme(
        naziv: widget.sekcija.naziv,
        ikona: widget.saIkonom ? widget.sekcija.ikona : null,
        aktivno: widget.sekcija.sadrzi(widget.index),
        otvoreno: _otvoren,
        saStrelicom: true,
        upozorenja: widget.sekcija.upozorenja(widget.brojNiskih),
        onTap: () => kontroler.isOpen ? kontroler.close() : kontroler.open(),
      ),
    );
  }
}

class _IkonaDugme extends StatelessWidget {
  final IconData ikona;
  final String poruka;
  final VoidCallback onTap;

  const _IkonaDugme({
    required this.ikona,
    required this.poruka,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: poruka,
      onPressed: onTap,
      style: IconButton.styleFrom(
        foregroundColor: MagacinBoje.naslov,
        hoverColor: _hoverPozadina,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: Icon(ikona),
    );
  }
}

// ---------------------------------------------------------------------------
// Firma i korisnik
// ---------------------------------------------------------------------------

List<PopupMenuEntry<Company>> _stavkeFirme(
  FirmaController firme,
  NavigationController nav,
) {
  final izabrana = firme.izabranaFirma.value;
  final ostale = firme.firme.where((f) => f != izabrana).toList();
  return [
    const PopupMenuItem<Company>(
      enabled: false,
      height: 32,
      child: Text(
        'PROMIJENI FIRMU',
        style: TextStyle(
          fontSize: 10.5,
          letterSpacing: 1,
          fontWeight: FontWeight.w800,
          color: MagacinBoje.svijetlo,
        ),
      ),
    ),
    if (ostale.isEmpty)
      const PopupMenuItem<Company>(
        enabled: false,
        child: Text(
          'Nema drugih firmi',
          style: TextStyle(color: MagacinBoje.priguseno),
        ),
      ),
    for (final firma in ostale)
      PopupMenuItem<Company>(
        value: firma,
        child: Row(
          children: [
            _FirmaZnak(naziv: firma.name, velicina: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                firma.name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ],
        ),
      ),
    const PopupMenuDivider(),
    PopupMenuItem<Company>(
      onTap: nav.openFirme,
      child: const Row(
        children: [
          Icon(Icons.settings_outlined, size: 18, color: MagacinBoje.priguseno),
          SizedBox(width: 10),
          Text('Upravljanje firmama', style: TextStyle(fontSize: 13.5)),
        ],
      ),
    ),
  ];
}

class _FirmaZnak extends StatelessWidget {
  final String naziv;
  final double velicina;

  const _FirmaZnak({required this.naziv, this.velicina = 30});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: velicina,
      height: velicina,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_akcent, akcentTamni],
        ),
        borderRadius: BorderRadius.circular(velicina * 0.3),
      ),
      child: Text(
        _inicijali(naziv),
        style: TextStyle(
          fontSize: velicina * 0.36,
          fontWeight: FontWeight.w800,
          color: mint,
        ),
      ),
    );
  }
}

class _FirmaIzbor extends StatefulWidget {
  final bool kompaktno;

  const _FirmaIzbor({required this.kompaktno});

  @override
  State<_FirmaIzbor> createState() => _FirmaIzborState();
}

class _FirmaIzborState extends State<_FirmaIzbor> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final firme = Get.find<FirmaController>();
    final nav = Get.find<NavigationController>();

    return Obx(() {
      final izabrana = firme.izabranaFirma.value;
      final naziv =
          izabrana?.name ??
          (firme.isLoading.value
              ? 'Učitavanje firmi…'
              : firme.errorMessage.value ?? 'Nema firmi');

      return PopupMenuButton<Company>(
        tooltip: 'Promijeni firmu',
        position: PopupMenuPosition.under,
        offset: const Offset(0, 8),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: const Color(0x330F172A),
        shape: _oblikMenija,
        constraints: const BoxConstraints(minWidth: 240, maxWidth: 320),
        onSelected: firme.izaberiFirmu,
        itemBuilder: (_) => _stavkeFirme(firme, nav),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: hoverTrajanje,
            curve: hoverKriva,
            height: 42,
            padding: EdgeInsets.fromLTRB(5, 5, widget.kompaktno ? 5 : 10, 5),
            decoration: BoxDecoration(
              color: _hover ? _hoverPozadina : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MagacinBoje.linija),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _FirmaZnak(naziv: izabrana?.name ?? '?'),
                if (!widget.kompaktno) ...[
                  const SizedBox(width: 9),
                  Flexible(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'FIRMA',
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.1,
                            letterSpacing: 0.9,
                            fontWeight: FontWeight.w800,
                            color: MagacinBoje.svijetlo,
                          ),
                        ),
                        Text(
                          naziv,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            color: MagacinBoje.naslov,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.unfold_more_rounded,
                    size: 17,
                    color: MagacinBoje.priguseno,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    });
  }
}

// Dugme za odjavu; kompaktno je samo ikona.
class _OdjavaDugme extends StatefulWidget {
  final bool kompaktno;

  const _OdjavaDugme({required this.kompaktno});

  @override
  State<_OdjavaDugme> createState() => _OdjavaDugmeState();
}

class _OdjavaDugmeState extends State<_OdjavaDugme> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    return Tooltip(
      message: 'Odjava',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: auth.logout,
          child: AnimatedContainer(
            duration: hoverTrajanje,
            curve: hoverKriva,
            height: 42,
            padding: EdgeInsets.symmetric(
              horizontal: widget.kompaktno ? 11 : 14,
            ),
            decoration: BoxDecoration(
              color: _hover ? MagacinBoje.crvenaSvijetlo : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hover
                    ? hoverNijansa(MagacinBoje.crvena, 0.35)
                    : MagacinBoje.linija,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.logout_rounded,
                  size: 18,
                  color: MagacinBoje.crvena,
                ),
                if (!widget.kompaktno) ...[
                  const SizedBox(width: 8),
                  const Text(
                    'Odjava',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: MagacinBoje.crvena,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bočni meni (usko)
// ---------------------------------------------------------------------------

class GlavniMeniDrawer extends StatelessWidget {
  const GlavniMeniDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavigationController>();
    final niske = Get.find<NiskeZaliheController>();
    final sirina = MediaQuery.sizeOf(context).width;
    var brojNiskih = 0;

    void otvori(_Stavka s) {
      Navigator.of(context).pop();
      s.otvori!(nav);
    }

    Widget stavka(_Stavka s, int index, {double uvlaka = 0}) {
      final aktivna = s.sadrzi(index);
      return Padding(
        padding: EdgeInsets.fromLTRB(10 + uvlaka, 1, 10, 1),
        child: ListTile(
          dense: true,
          selected: aktivna,
          selectedColor: Colors.white,
          selectedTileColor: _akcent,
          iconColor: MagacinBoje.priguseno,
          textColor: MagacinBoje.tekst,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: Icon(s.ikona, size: 19, color: aktivna ? mint : null),
          minLeadingWidth: 20,
          title: Text(
            s.naziv,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: aktivna ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          trailing: s.upozorenja(brojNiskih) > 0
              ? _CrveniKruzic(broj: s.upozorenja(brojNiskih))
              : null,
          onTap: () => otvori(s),
        ),
      );
    }

    return Drawer(
      width: sirina * 0.86 > 320 ? 320 : sirina * 0.86,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Obx(() {
          final index = nav.selectedIndex.value;
          brojNiskih = niske.stavke.length;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [Expanded(child: _FirmaIzbor(kompaktno: false))],
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1, color: MagacinBoje.linija),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    for (final s in _sekcije)
                      if (s.direktno != null)
                        stavka(s.direktno!, index)
                      else
                        Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            initiallyExpanded: s.sadrzi(index),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 26,
                            ),
                            iconColor: _akcent,
                            collapsedIconColor: MagacinBoje.priguseno,
                            leading: Icon(
                              s.ikona,
                              size: 19,
                              color: s.sadrzi(index)
                                  ? _akcent
                                  : MagacinBoje.priguseno,
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    s.naziv,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: s.sadrzi(index)
                                          ? _akcent
                                          : MagacinBoje.naslov,
                                    ),
                                  ),
                                ),
                                if (s.upozorenja(brojNiskih) > 0) ...[
                                  const SizedBox(width: 8),
                                  const _CrveniKruzic(),
                                ],
                              ],
                            ),
                            children: [
                              for (final st in s.stavke)
                                stavka(st, index, uvlaka: 14),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
              const Divider(height: 1, color: MagacinBoje.linija),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [Expanded(child: _OdjavaDugme(kompaktno: false))],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

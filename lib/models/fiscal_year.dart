// Poslovna godina firme: GET /companies/{company}/fiscal-years.
// Dokumenti (kalkulacije, radni nalozi) sa datumom u zaključenoj godini se
// više ne mogu kreirati, mijenjati, knjižiti, izdavati, brisati ni vraćati.

class PoslovnaGodina {
  final int godina;
  final bool zakljucena;
  final DateTime? zakljucenaU;
  final String? zakljucio;

  // Broj kalkulacija i radnih naloga u statusu draft u toj godini.
  // Dok je veći od 0, godina se ne može zaključiti.
  final int brojNacrta;

  const PoslovnaGodina({
    required this.godina,
    required this.zakljucena,
    this.zakljucenaU,
    this.zakljucio,
    required this.brojNacrta,
  });

  factory PoslovnaGodina.fromJson(Map<String, dynamic> json) {
    final zakljucio = json['closed_by'] as Map<String, dynamic>?;
    return PoslovnaGodina(
      godina: json['year'] as int,
      zakljucena: json['is_closed'] as bool? ?? false,
      zakljucenaU: DateTime.tryParse(
        json['closed_at'] as String? ?? '',
      )?.toLocal(),
      zakljucio: zakljucio?['name'] as String?,
      brojNacrta: json['drafts_count'] as int? ?? 0,
    );
  }

  // Godina je završena tek od 1.1. sljedeće godine.
  bool get zavrsena => DateTime.now().year > godina;
}

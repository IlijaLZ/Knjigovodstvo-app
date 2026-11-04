// Dobavljač ili kupac firme. API ih drži u dvije tabele sa istim poljima
// i istim rutama (/suppliers i /customers).

class VrstaPartnera {
  final String ruta;
  final String jednina;
  final String mnozina;
  final String akuzativ;

  const VrstaPartnera._(this.ruta, this.jednina, this.mnozina, this.akuzativ);

  static const dobavljac = VrstaPartnera._(
    'suppliers',
    'Dobavljač',
    'Dobavljači',
    'dobavljača',
  );

  static const kupac = VrstaPartnera._('customers', 'Kupac', 'Kupci', 'kupca');
}

class Partner {
  final int id;
  final String naziv;
  final String? jib;
  final String? pdvBroj;
  final String? adresa;
  final String? grad;
  final String? telefon;
  final String? email;
  final DateTime? obrisan;

  const Partner({
    required this.id,
    required this.naziv,
    this.jib,
    this.pdvBroj,
    this.adresa,
    this.grad,
    this.telefon,
    this.email,
    this.obrisan,
  });

  bool get jeObrisan => obrisan != null;

  factory Partner.fromJson(Map<String, dynamic> json) {
    final deletedAt = json['deleted_at'] as String?;

    return Partner(
      id: json['id'] as int,
      naziv: json['name'] as String,
      jib: json['tax_id'] as String?,
      pdvBroj: json['vat_number'] as String?,
      adresa: json['address'] as String?,
      grad: json['city'] as String?,
      telefon: json['phone'] as String?,
      email: json['email'] as String?,
      obrisan: deletedAt == null ? null : DateTime.tryParse(deletedAt),
    );
  }

  // Polja za POST/PATCH; prazna opciona polja se šalju kao null.
  Map<String, dynamic> toJson() => {
    'name': naziv,
    'tax_id': jib,
    'vat_number': pdvBroj,
    'address': adresa,
    'city': grad,
    'phone': telefon,
    'email': email,
  };
}

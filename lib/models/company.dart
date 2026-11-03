class Company {
  final int id;
  final String name;

  Company({required this.id, required this.name});

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(id: json['id'] as int, name: json['name'] as String);
  }

  @override
  bool operator ==(Object other) => other is Company && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class Country {
  final String name;
  final String dialCode;
  final String flagPng;

  const Country({
    required this.name,
    required this.dialCode,
    required this.flagPng,
  });

  @override
  String toString() => name;
}

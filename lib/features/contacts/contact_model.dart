/// A saved contact in the user's address book — identified by UID only,
/// never by phone number.
class ContactModel {
  final String uid;
  final String displayName;
  final DateTime addedAt;
  bool isFavorite;

  ContactModel({
    required this.uid,
    required this.displayName,
    required this.addedAt,
    this.isFavorite = false,
  });

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'displayName': displayName,
        'addedAt': addedAt.toIso8601String(),
        'isFavorite': isFavorite,
      };

  factory ContactModel.fromJson(Map<String, dynamic> json) => ContactModel(
        uid: json['uid'],
        displayName: json['displayName'],
        addedAt: DateTime.parse(json['addedAt']),
        isFavorite: json['isFavorite'] ?? false,
      );
}
import 'package:cloud_firestore/cloud_firestore.dart';

class Client {
  final int? id;             // Local SQLite ID
  final String name;
  final String phone;
  final String address;
  final String? docId;       // Firestore document ID
  final DateTime? updatedAt; // Last update time
  final bool isSynced;       // ✅ For offline queueing (0/1 in SQLite)

  const Client({
    this.id,
    required this.name,
    required this.phone,
    required this.address,
    this.docId,
    this.updatedAt,
    this.isSynced = false,
  });

  /// Map for local SQLite
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'updatedAt': updatedAt?.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
  };

  /// Map for Firestore writes
  Map<String, dynamic> toFirestore() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// From Firestore document
  factory Client.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Client(
      docId: doc.id,
      id: data['id'] as int?,
      name: (data['name'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      isSynced: true, // Already in the cloud
    );
  }

  /// From local SQLite row
  factory Client.fromMap(Map<String, dynamic> map) => Client(
    id: map['id'] as int?,
    name: (map['name'] ?? '') as String,
    phone: (map['phone'] ?? '') as String,
    address: (map['address'] ?? '') as String,
    updatedAt: map['updatedAt'] != null
        ? DateTime.tryParse(map['updatedAt'].toString())
        : null,
    isSynced: (map['isSynced'] ?? 0) == 1,
  );

  /// Create a modified copy
  Client copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    String? docId,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return Client(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      docId: docId ?? this.docId,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Client &&
              id == other.id &&
              name == other.name &&
              phone == other.phone &&
              address == other.address &&
              docId == other.docId;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      phone.hashCode ^
      address.hashCode ^
      (docId?.hashCode ?? 0);
}

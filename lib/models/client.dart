import 'package:cloud_firestore/cloud_firestore.dart';

class Client {
  final int? id;               // Local SQLite ID
  final String name;
  final String phone;
  final String address;
  final String? firestoreId;   // Firestore document ID
  final DateTime? updatedAt;   // Last update time
  final bool isSynced;         // Tracks if this record is synced to cloud

  const Client({
    this.id,
    required this.name,
    required this.phone,
    required this.address,
    this.firestoreId,
    this.updatedAt,
    this.isSynced = false,
  });

  /* ------------ Conversions ------------ */

  /// Local SQLite representation
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'updatedAt': updatedAt?.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'firestoreId': firestoreId,
  };

  /// Firestore representation
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
      firestoreId: doc.id,
      id: data['id'] as int?,
      name: (data['name'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
      isSynced: true,
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
    firestoreId: map['firestoreId'] as String?,
    isSynced: (map['isSynced'] ?? 0) == 1,
  );

  /* ------------ Utilities ------------ */

  /// Create a modified copy
  Client copyWith({
    int? id,
    String? name,
    String? phone,
    String? address,
    String? firestoreId,
    DateTime? updatedAt,
    bool? isSynced,
  }) {
    return Client(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      firestoreId: firestoreId ?? this.firestoreId,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Client &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              name == other.name &&
              phone == other.phone &&
              address == other.address &&
              firestoreId == other.firestoreId;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      phone.hashCode ^
      address.hashCode ^
      (firestoreId?.hashCode ?? 0);
}

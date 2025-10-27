import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class Client {
  final int? id;
  final String firestoreId;
  final String name;
  final String phone;
  final String address;
  final double balance;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  Client({
    this.id,
    String? firestoreId,
    required this.name,
    required this.phone,
    required this.address,
    this.balance = 0.0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : firestoreId = firestoreId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'firestoreId': firestoreId,
    'name': name,
    'phone': phone,
    'address': address,
    'balance': balance,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'phone': phone,
    'address': address,
    'balance': balance,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    'isSynced': isSynced,
    'isDeleted': isDeleted,
  };

  factory Client.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return Client(
      firestoreId: doc.id,
      id: data['id'] as int?,
      name: (data['name'] ?? '') as String,
      phone: (data['phone'] ?? '') as String,
      address: (data['address'] ?? '') as String,
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      isSynced: (data['isSynced'] as bool?) ?? true,
      isDeleted: (data['isDeleted'] as bool?) ?? false,
    );
  }

  factory Client.fromMap(Map<String, dynamic> map) {
    // ✅ FIXED: Proper createdAt handling with safe fallback
    final createdAt = map['createdAt'] != null
        ? DateTime.parse(map['createdAt'] as String)
        : DateTime.now();

    final updatedAt = map['updatedAt'] != null
        ? DateTime.parse(map['updatedAt'] as String)
        : DateTime.now();

    return Client(
      id: map['id'] as int?,
      firestoreId: (map['firestoreId'] ?? '') as String,
      name: (map['name'] ?? '') as String,
      phone: (map['phone'] ?? '') as String,
      address: (map['address'] ?? '') as String,
      balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
      createdAt: createdAt,
      updatedAt: updatedAt,
      isSynced: (map['isSynced'] ?? 0) == 1,
      isDeleted: (map['isDeleted'] ?? 0) == 1,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  Client copyWith({
    int? id,
    String? firestoreId,
    String? name,
    String? phone,
    String? address,
    double? balance,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Client(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      balance: balance ?? this.balance,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Client &&
              runtimeType == other.runtimeType &&
              firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;

  @override
  String toString() {
    return 'Client{id: $id, name: $name, phone: $phone, balance: $balance, isSynced: $isSynced}';
  }
}
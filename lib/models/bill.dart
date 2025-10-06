import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class Bill {
  final int? id;
  final String firestoreId;
  final int clientId;
  final double totalAmount;
  final double paidAmount;
  final double carryForward;
  final DateTime date;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  Bill({
    this.id,
    String? firestoreId,
    required this.clientId,
    required this.totalAmount,
    required this.paidAmount,
    required this.carryForward,
    required this.date,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : firestoreId = firestoreId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // FOR LOCAL SQLITE - NO createdAt
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'firestoreId': firestoreId,
    'clientId': clientId,
    'totalAmount': totalAmount,
    'paidAmount': paidAmount,
    'carryForward': carryForward,
    'date': date.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),  // REMOVED createdAt
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  // FOR FIREBASE - includes createdAt
  Map<String, dynamic> toFirestore() => {
    'clientId': clientId,
    'totalAmount': totalAmount,
    'paidAmount': paidAmount,
    'carryForward': carryForward,
    'date': Timestamp.fromDate(date),
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory Bill.fromFirestore(String docId, Map<String, dynamic> data) {
    return Bill(
      firestoreId: docId,
      id: data['id'] as int?,
      clientId: (data['clientId'] ?? 0) as int,
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      paidAmount: (data['paidAmount'] ?? 0).toDouble(),
      carryForward: (data['carryForward'] ?? 0).toDouble(),
      date: _parseTimestamp(data['date']),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      isSynced: true,
      isDeleted: false,
    );
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'] as int?,
      firestoreId: map['firestoreId'] as String?,
      clientId: (map['clientId'] ?? 0) as int,
      totalAmount: (map['totalAmount'] ?? 0).toDouble(),
      paidAmount: (map['paidAmount'] ?? 0).toDouble(),
      carryForward: (map['carryForward'] ?? 0).toDouble(),
      date: DateTime.parse(map['date'] as String),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.parse(map['updatedAt'] as String), // Fallback to updatedAt
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isSynced: (map['isSynced'] ?? 0) == 1,
      isDeleted: (map['isDeleted'] ?? 0) == 1,
    );
  }

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  Bill copyWith({
    int? id,
    String? firestoreId,
    int? clientId,
    double? totalAmount,
    double? paidAmount,
    double? carryForward,
    DateTime? date,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return Bill(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      clientId: clientId ?? this.clientId,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      carryForward: carryForward ?? this.carryForward,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Bill && runtimeType == other.runtimeType && firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;
}
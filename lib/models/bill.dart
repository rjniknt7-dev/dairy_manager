import 'package:cloud_firestore/cloud_firestore.dart';

class Bill {
  final int? id;               // Local SQLite id
  final String? firestoreId;   // Firestore document ID
  final int clientId;
  final double totalAmount;
  final double paidAmount;
  final double carryForward;
  final DateTime date;
  final bool isSynced;         // Track sync status
  final DateTime? updatedAt;   // Track last update

  const Bill({
    this.id,
    this.firestoreId,
    required this.clientId,
    required this.totalAmount,
    required this.paidAmount,
    required this.carryForward,
    required this.date,
    this.isSynced = false,
    this.updatedAt,
  });

  /* ------------ Conversions ------------ */

  /// Save for local DB (SQLite)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'clientId': clientId,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'carryForward': carryForward,
      'date': date.toIso8601String(),
      'isSynced': isSynced ? 1 : 0,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  /// Save for Firestore
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'clientId': clientId,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'carryForward': carryForward,
      'date': Timestamp.fromDate(date),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  factory Bill.fromMap(Map<String, dynamic> map) {
    return Bill(
      id: map['id'] as int?,
      firestoreId: map['firestoreId'] as String?,
      clientId: (map['clientId'] ?? 0) as int,
      totalAmount: (map['totalAmount'] ?? 0).toDouble(),
      paidAmount: (map['paidAmount'] ?? 0).toDouble(),
      carryForward: (map['carryForward'] ?? 0).toDouble(),
      date: DateTime.tryParse(map['date']?.toString() ?? '') ?? DateTime.now(),
      isSynced: (map['isSynced'] ?? 0) == 1,
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String)
          : null,
    );
  }

  factory Bill.fromFirestore(String docId, Map<String, dynamic> data) {
    final rawDate = data['date'];
    final parsedDate = rawDate is Timestamp
        ? rawDate.toDate()
        : DateTime.tryParse(rawDate?.toString() ?? '') ?? DateTime.now();

    final rawUpdated = data['updatedAt'];
    final parsedUpdated = rawUpdated is Timestamp
        ? rawUpdated.toDate()
        : DateTime.tryParse(rawUpdated?.toString() ?? '');

    return Bill(
      id: data['id'] as int?,
      firestoreId: docId,
      clientId: (data['clientId'] ?? 0) as int,
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      paidAmount: (data['paidAmount'] ?? 0).toDouble(),
      carryForward: (data['carryForward'] ?? 0).toDouble(),
      date: parsedDate,
      isSynced: true,
      updatedAt: parsedUpdated,
    );
  }

  /* ------------ Utilities ------------ */

  Bill copyWith({
    int? id,
    String? firestoreId,
    int? clientId,
    double? totalAmount,
    double? paidAmount,
    double? carryForward,
    DateTime? date,
    bool? isSynced,
    DateTime? updatedAt,
  }) {
    return Bill(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      clientId: clientId ?? this.clientId,
      totalAmount: totalAmount ?? this.totalAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      carryForward: carryForward ?? this.carryForward,
      date: date ?? this.date,
      isSynced: isSynced ?? this.isSynced,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is Bill &&
              runtimeType == other.runtimeType &&
              id == other.id &&
              firestoreId == other.firestoreId &&
              clientId == other.clientId &&
              date == other.date;

  @override
  int get hashCode =>
      id.hashCode ^ firestoreId.hashCode ^ clientId.hashCode ^ date.hashCode;
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class LedgerEntry {
  final int? id;
  final String firestoreId;
  final int clientId;
  final int? billId;
  final String type;
  final double amount;
  final DateTime date;
  final String? note;
  final String? paymentMethod;
  final String? referenceNumber;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  LedgerEntry({
    this.id,
    String? firestoreId,
    required this.clientId,
    this.billId,
    required this.type,
    required this.amount,
    required this.date,
    this.note,
    this.paymentMethod,
    this.referenceNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : firestoreId = firestoreId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// FOR LOCAL SQLITE
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'firestoreId': firestoreId,
    'clientId': clientId,
    'billId': billId,
    'type': type,
    'amount': amount,
    'date': date.toIso8601String(),
    'note': note,
    'paymentMethod': paymentMethod,
    'referenceNumber': referenceNumber,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  /// FOR FIREBASE - Uses Timestamps
  Map<String, dynamic> toFirestore() => {
    'type': type,
    'amount': amount,
    'date': Timestamp.fromDate(date),
    'note': note,
    'paymentMethod': paymentMethod,
    'referenceNumber': referenceNumber,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    // Don't include clientId/billId - added as FirestoreIds in sync service
  };

  /// FROM FIRESTORE DOCUMENT
  factory LedgerEntry.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;

    return LedgerEntry(
      id: null,
      firestoreId: doc.id,
      clientId: 0, // Will be resolved during sync
      billId: null,
      type: data['type'] as String? ?? 'debit',
      amount: _parseAmount(data['amount']),
      date: _parseDate(data['date']),
      note: data['note'] as String?,
      paymentMethod: data['paymentMethod'] as String?,
      referenceNumber: data['referenceNumber'] as String?,
      createdAt: _parseDate(data['createdAt']),
      updatedAt: _parseDate(data['updatedAt']),
      isSynced: true,
      isDeleted: false,
    );
  }

  /// FROM LOCAL DATABASE MAP
  factory LedgerEntry.fromMap(Map<String, dynamic> m) {
    return LedgerEntry(
      id: m['id'] as int?,
      firestoreId: m['firestoreId'] as String?,
      clientId: m['clientId'] as int? ?? 0,
      billId: m['billId'] as int?,
      type: (m['type'] ?? 'debit') as String,
      amount: _parseAmount(m['amount']),
      date: _parseDate(m['date']),
      note: m['note'] as String?,
      paymentMethod: m['paymentMethod'] as String?,
      referenceNumber: m['referenceNumber'] as String?,
      createdAt: _parseDate(m['createdAt'] ?? m['updatedAt']),
      updatedAt: _parseDate(m['updatedAt']),
      isSynced: (m['isSynced'] ?? 0) == 1,
      isDeleted: (m['isDeleted'] ?? 0) == 1,
    );
  }

  /// Safe amount parsing
  static double _parseAmount(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Safe date parsing
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    return DateTime.now();
  }

  LedgerEntry copyWith({
    int? id,
    String? firestoreId,
    int? clientId,
    int? billId,
    String? type,
    double? amount,
    DateTime? date,
    String? note,
    String? paymentMethod,
    String? referenceNumber,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return LedgerEntry(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      clientId: clientId ?? this.clientId,
      billId: billId ?? this.billId,
      type: type ?? this.type,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is LedgerEntry &&
              runtimeType == other.runtimeType &&
              firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;

  @override
  String toString() {
    return 'LedgerEntry(id: $id, firestoreId: $firestoreId, type: $type, '
        'amount: $amount, clientId: $clientId, billId: $billId, '
        'date: ${date.toIso8601String()}, isSynced: $isSynced)';
  }
}
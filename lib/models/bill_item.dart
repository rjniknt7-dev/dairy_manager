import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class BillItem {
  final int? id;
  final String firestoreId;
  final int? billId;
  final int productId;
  final double quantity;
  final double price;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSynced;
  final bool isDeleted;

  BillItem({
    this.id,
    String? firestoreId,
    this.billId,
    required this.productId,
    required this.quantity,
    required this.price,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isSynced = false,
    this.isDeleted = false,
  })  : firestoreId = firestoreId ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  // FOR LOCAL SQLITE - REMOVED createdAt
  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'firestoreId': firestoreId,
    'billId': billId,
    'productId': productId,
    'quantity': quantity,
    'price': price,
    'updatedAt': updatedAt.toIso8601String(),  // REMOVED createdAt line
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  // FOR FIREBASE - keeps createdAt
  Map<String, dynamic> toFirestore() => {
    'billId': billId,
    'productId': productId,
    'quantity': quantity,
    'price': price,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory BillItem.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return BillItem(
      firestoreId: doc.id,
      id: data['id'] as int?,
      billId: data['billId'] as int?,
      productId: (data['productId'] ?? 0) as int,
      quantity: (data['quantity'] ?? 0).toDouble(),
      price: (data['price'] ?? 0).toDouble(),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      isSynced: true,
      isDeleted: false,
    );
  }

  factory BillItem.fromMap(Map<String, dynamic> map) => BillItem(
    id: map['id'] as int?,
    firestoreId: map['firestoreId'] as String?,
    billId: map['billId'] as int?,
    productId: (map['productId'] ?? 0) as int,
    quantity: (map['quantity'] ?? 0).toDouble(),
    price: (map['price'] ?? 0).toDouble(),
    createdAt: map['createdAt'] != null
        ? DateTime.parse(map['createdAt'] as String)
        : DateTime.parse(map['updatedAt'] as String), // Fallback
    updatedAt: DateTime.parse(map['updatedAt'] as String),
    isSynced: (map['isSynced'] ?? 0) == 1,
    isDeleted: (map['isDeleted'] ?? 0) == 1,
  );

  static DateTime _parseTimestamp(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  BillItem copyWith({
    int? id,
    String? firestoreId,
    int? billId,
    int? productId,
    double? quantity,
    double? price,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isSynced,
    bool? isDeleted,
  }) {
    return BillItem(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      billId: billId ?? this.billId,
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is BillItem && runtimeType == other.runtimeType && firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;
}
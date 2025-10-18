import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

class BillItem {
  final int? id;
  final String firestoreId;
  final int? billId;
  final int productId;
  final double quantity;
  final double price;
  final double? discount;
  final double? tax;
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
    this.discount,
    this.tax,
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
    'billId': billId,
    'productId': productId,
    'quantity': quantity,
    'price': price,
    'discount': discount ?? 0.0,
    'tax': tax ?? 0.0,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isSynced': isSynced ? 1 : 0,
    'isDeleted': isDeleted ? 1 : 0,
  };

  /// FOR FIREBASE - Uses Timestamps
  Map<String, dynamic> toFirestore() => {
    'quantity': quantity,
    'price': price,
    'discount': discount ?? 0.0,
    'tax': tax ?? 0.0,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
    // Don't include billId/productId - added as FirestoreIds in sync service
  };

  /// FROM FIRESTORE DOCUMENT
  factory BillItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    return BillItem(
      firestoreId: doc.id,
      id: null,
      billId: null, // Will be resolved during sync
      productId: 0, // Will be resolved during sync
      quantity: _parseDouble(data['quantity']),
      price: _parseDouble(data['price']),
      discount: _parseDouble(data['discount']),
      tax: _parseDouble(data['tax']),
      createdAt: _parseTimestamp(data['createdAt']),
      updatedAt: _parseTimestamp(data['updatedAt']),
      isSynced: true,
      isDeleted: false,
    );
  }

  /// FROM LOCAL DATABASE MAP
  factory BillItem.fromMap(Map<String, dynamic> map) {
    return BillItem(
      id: map['id'] as int?,
      firestoreId: map['firestoreId'] as String?,
      billId: map['billId'] as int?,
      productId: (map['productId'] ?? 0) as int,
      quantity: _parseDouble(map['quantity']),
      price: _parseDouble(map['price']),
      discount: _parseDouble(map['discount']),
      tax: _parseDouble(map['tax']),
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.parse(map['updatedAt'] as String),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isSynced: (map['isSynced'] ?? 0) == 1,
      isDeleted: (map['isDeleted'] ?? 0) == 1,
    );
  }

  /// Safe double parsing
  static double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  /// Safe timestamp parsing
  static DateTime _parseTimestamp(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  BillItem copyWith({
    int? id,
    String? firestoreId,
    int? billId,
    int? productId,
    double? quantity,
    double? price,
    double? discount,
    double? tax,
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
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isSynced: isSynced ?? this.isSynced,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  /// Calculate total amount for this item
  double get totalAmount {
    final baseAmount = quantity * price;
    final discountAmount = discount ?? 0.0;
    final taxAmount = tax ?? 0.0;
    return baseAmount - discountAmount + taxAmount;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          other is BillItem &&
              runtimeType == other.runtimeType &&
              firestoreId == other.firestoreId;

  @override
  int get hashCode => firestoreId.hashCode;

  @override
  String toString() {
    return 'BillItem(id: $id, firestoreId: $firestoreId, billId: $billId, '
        'productId: $productId, quantity: $quantity, price: $price, '
        'total: $totalAmount)';
  }
}
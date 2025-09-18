import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/client.dart';

/// Handles all Firestore reads/writes for the authenticated user.
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Returns users/{uid}, throws if no user is signed in.
  String _userPath() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'NO_USER',
        message: 'User is not authenticated.',
      );
    }
    return 'users/${user.uid}';
  }

  CollectionReference<Map<String, dynamic>> _clientCollection() =>
      _db.collection('${_userPath()}/clients/items');

  /// Create or update a client document.
  /// If client.id is null, a new Firestore ID is generated.
  Future<void> saveClient(Client client) async {
    final docId = client.id?.toString() ?? _db.collection('tmp').doc().id;
    await _clientCollection().doc(docId).set(
      {
        ...client.toMap(),
        'updatedAt': FieldValue.serverTimestamp(), // ✅ Track updates
      },
      SetOptions(merge: true), // ✅ Merge to avoid overwriting unintended fields
    );
  }

  /// Add a client with a random Firestore ID.
  Future<void> addClientAutoId(Client client) async {
    await _clientCollection().add({
      ...client.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Listen to all clients as a stream of List<Client>, ordered by name.
  Stream<List<Client>> streamClients() {
    return _clientCollection()
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map((d) {
      final data = d.data();
      // Make sure ID is present for Client.fromMap
      data['id'] ??= d.id;
      return Client.fromMap(data);
    }).toList());
  }

  /// Delete by Firestore document ID (string).
  Future<void> deleteClient(String clientDocId) async {
    await _clientCollection().doc(clientDocId).delete();
  }

  /// Save many clients in a single batch.
  Future<void> saveMultipleClients(List<Client> clients) async {
    final batch = _db.batch();
    final col = _clientCollection();
    for (final c in clients) {
      final docId = c.id?.toString() ?? _db.collection('tmp').doc().id;
      batch.set(
        col.doc(docId),
        {
          ...c.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }
}

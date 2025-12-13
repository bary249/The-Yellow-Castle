import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/campaign_state.dart';

class CampaignFirestoreService {
  static const String _collection = 'campaigns';
  static const String _currentCampaignDoc = 'current';

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  bool _disableCloudOps = false;

  CampaignFirestoreService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  String? get _userId => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>>? get _campaignRef {
    final uid = _userId;
    if (uid == null) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection(_collection)
        .doc(_currentCampaignDoc);
  }

  DocumentReference<Map<String, dynamic>>? get _progressionRef {
    final uid = _userId;
    if (uid == null) return null;
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('progression')
        .doc('napoleon');
  }

  /// Save campaign to Firestore
  Future<bool> saveCampaign(CampaignState campaign) async {
    if (_disableCloudOps) return false;
    final ref = _campaignRef;
    if (ref == null) {
      debugPrint('Cannot save to Firestore: No user logged in');
      return false;
    }

    try {
      await ref.set(campaign.toJson());
      debugPrint('Campaign saved to Firestore');
      return true;
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _disableCloudOps = true;
        debugPrint(
          'Error saving campaign to Firestore: permission-denied (cloud sync disabled for this session). Update Firestore rules to allow users/{uid}/campaigns/current writes.',
        );
        return false;
      }
      debugPrint('Error saving campaign to Firestore: $e');
      return false;
    }
  }

  /// Load campaign from Firestore
  Future<CampaignState?> loadCampaign() async {
    if (_disableCloudOps) return null;
    final ref = _campaignRef;
    if (ref == null) return null;

    try {
      final doc = await ref.get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('No campaign found in Firestore');
        return null;
      }

      return CampaignState.fromJson(doc.data()!);
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _disableCloudOps = true;
        debugPrint(
          'Error loading campaign from Firestore: permission-denied (cloud sync disabled for this session). Update Firestore rules to allow users/{uid}/campaigns/current reads.',
        );
        return null;
      }
      debugPrint('Error loading campaign from Firestore: $e');
      return null;
    }
  }

  /// Save progression to Firestore
  Future<bool> saveProgression(Map<String, dynamic> progressionJson) async {
    if (_disableCloudOps) return false;
    final ref = _progressionRef;
    if (ref == null) return false;

    try {
      await ref.set(progressionJson);
      debugPrint('Progression saved to Firestore');
      return true;
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _disableCloudOps = true;
        debugPrint(
          'Error saving progression to Firestore: permission-denied (cloud sync disabled for this session). Update Firestore rules to allow users/{uid}/progression/napoleon writes.',
        );
        return false;
      }
      debugPrint('Error saving progression to Firestore: $e');
      return false;
    }
  }

  /// Load progression from Firestore
  Future<Map<String, dynamic>?> loadProgression() async {
    if (_disableCloudOps) return null;
    final ref = _progressionRef;
    if (ref == null) return null;

    try {
      final doc = await ref.get();
      if (!doc.exists || doc.data() == null) {
        return null;
      }
      return doc.data();
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _disableCloudOps = true;
        debugPrint(
          'Error loading progression from Firestore: permission-denied (cloud sync disabled for this session). Update Firestore rules to allow users/{uid}/progression/napoleon reads.',
        );
        return null;
      }
      debugPrint('Error loading progression from Firestore: $e');
      return null;
    }
  }

  /// Delete campaign from Firestore
  Future<bool> deleteCampaign() async {
    if (_disableCloudOps) return false;
    final ref = _campaignRef;
    if (ref == null) return false;

    try {
      await ref.delete();
      debugPrint('Campaign deleted from Firestore');
      return true;
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _disableCloudOps = true;
        debugPrint(
          'Error deleting campaign from Firestore: permission-denied (cloud sync disabled for this session). Update Firestore rules to allow users/{uid}/campaigns/current deletes.',
        );
        return false;
      }
      debugPrint('Error deleting campaign from Firestore: $e');
      return false;
    }
  }

  /// Check if a campaign exists in Firestore
  Future<bool> hasSavedCampaign() async {
    if (_disableCloudOps) return false;
    final ref = _campaignRef;
    if (ref == null) return false;

    try {
      final doc = await ref.get();
      return doc.exists;
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        _disableCloudOps = true;
        debugPrint(
          'Error checking campaign in Firestore: permission-denied (cloud sync disabled for this session). Update Firestore rules to allow users/{uid}/campaigns/current reads.',
        );
      }
      return false;
    }
  }
}

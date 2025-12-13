import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/campaign_state.dart';
import 'campaign_firestore_service.dart';

class CampaignPersistenceService {
  static const String _campaignKey = 'current_campaign_state';
  static const String _progressionKey = 'napoleon_progression_state';

  // Singleton instance
  static final CampaignPersistenceService _instance =
      CampaignPersistenceService._internal();

  factory CampaignPersistenceService() => _instance;

  final CampaignFirestoreService _firestoreService = CampaignFirestoreService();

  CampaignPersistenceService._internal();

  /// Save the current campaign state to local storage and Firestore
  Future<bool> saveCampaign(CampaignState campaign) async {
    // Update timestamp before saving
    campaign.lastUpdated = DateTime.now();
    bool localSuccess = false;
    bool cloudSuccess = false;

    // 1. Save locally
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(campaign.toJson());
      await prefs.setString(_campaignKey, jsonString);
      debugPrint(
        'Campaign saved locally: Act ${campaign.act}, Encounter ${campaign.encounterNumber}',
      );
      localSuccess = true;
    } catch (e) {
      debugPrint('Error saving campaign locally: $e');
    }

    // 2. Save to cloud (fire and forget, don't block UI strictly, but await for status)
    try {
      cloudSuccess = await _firestoreService.saveCampaign(campaign);
    } catch (e) {
      debugPrint('Error saving campaign to cloud: $e');
    }

    return localSuccess || cloudSuccess;
  }

  /// Load the saved campaign state, preferring the most recent version
  Future<CampaignState?> loadCampaign() async {
    CampaignState? localCampaign;
    CampaignState? cloudCampaign;

    // 1. Load local
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_campaignKey);

      if (jsonString != null) {
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
        localCampaign = CampaignState.fromJson(jsonMap);
        debugPrint('Local campaign found: ${localCampaign.lastUpdated}');
      }
    } catch (e) {
      debugPrint('Error loading local campaign: $e');
    }

    // 2. Load cloud
    try {
      cloudCampaign = await _firestoreService.loadCampaign();
      if (cloudCampaign != null) {
        debugPrint('Cloud campaign found: ${cloudCampaign.lastUpdated}');
      }
    } catch (e) {
      debugPrint('Error loading cloud campaign: $e');
    }

    // 3. Compare and return newer
    if (localCampaign == null && cloudCampaign == null) {
      return null;
    }

    if (localCampaign != null && cloudCampaign != null) {
      if (cloudCampaign.lastUpdated.isAfter(localCampaign.lastUpdated)) {
        debugPrint('Using Cloud campaign (newer)');
        // Update local cache with newer cloud data
        _saveToLocalOnly(cloudCampaign);
        return cloudCampaign;
      } else {
        debugPrint('Using Local campaign (newer or equal)');
        // Optional: Push local to cloud if local is significantly newer?
        // For now, next save will handle it.
        return localCampaign;
      }
    }

    return cloudCampaign ?? localCampaign;
  }

  /// Save progression state to local storage and Firestore
  Future<bool> saveProgression(Map<String, dynamic> progressionJson) async {
    bool localSuccess = false;
    bool cloudSuccess = false;

    // 1. Save locally
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(progressionJson);
      await prefs.setString(_progressionKey, jsonString);
      debugPrint('Progression saved locally');
      localSuccess = true;
    } catch (e) {
      debugPrint('Error saving progression locally: $e');
    }

    // 2. Save to cloud
    try {
      cloudSuccess = await _firestoreService.saveProgression(progressionJson);
    } catch (e) {
      debugPrint('Error saving progression to cloud: $e');
    }

    return localSuccess || cloudSuccess;
  }

  /// Load progression state
  Future<Map<String, dynamic>?> loadProgression() async {
    Map<String, dynamic>? localProgression;
    Map<String, dynamic>? cloudProgression;

    // 1. Load local
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_progressionKey);
      if (jsonString != null) {
        localProgression = jsonDecode(jsonString) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error loading local progression: $e');
    }

    // 2. Load cloud
    try {
      cloudProgression = await _firestoreService.loadProgression();
    } catch (e) {
      debugPrint('Error loading cloud progression: $e');
    }

    // 3. Return merged/best (simplified: prefer cloud if available as it might have cross-device progress)
    // Ideally we'd merge or check timestamps, but for now we'll assume cloud is authority if present.
    // Actually, simple max points strategy is safer if we don't have timestamps on progression.
    if (cloudProgression != null) {
      // Sync to local
      await _saveToLocalProgressionOnly(cloudProgression);
      return cloudProgression;
    }

    return localProgression;
  }

  Future<void> _saveToLocalProgressionOnly(
    Map<String, dynamic> progressionJson,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(progressionJson);
      await prefs.setString(_progressionKey, jsonString);
    } catch (e) {
      debugPrint('Error syncing cloud progression to local: $e');
    }
  }

  /// Helper to update local storage only (used when syncing from cloud)
  Future<void> _saveToLocalOnly(CampaignState campaign) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(campaign.toJson());
      await prefs.setString(_campaignKey, jsonString);
    } catch (e) {
      debugPrint('Error syncing cloud data to local storage: $e');
    }
  }

  /// Check if a saved campaign exists (local or cloud)
  Future<bool> hasSavedCampaign() async {
    bool hasLocal = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      hasLocal = prefs.containsKey(_campaignKey);
    } catch (e) {
      // ignore
    }

    if (hasLocal) return true;

    // If no local, check cloud (slower, but necessary for fresh installs)
    return await _firestoreService.hasSavedCampaign();
  }

  /// Delete the saved campaign
  Future<bool> clearCampaign() async {
    bool localCleared = false;
    bool cloudCleared = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_campaignKey);
      localCleared = true;
      debugPrint('Local campaign cleared');
    } catch (e) {
      debugPrint('Error clearing local campaign: $e');
    }

    try {
      cloudCleared = await _firestoreService.deleteCampaign();
    } catch (e) {
      debugPrint('Error clearing cloud campaign: $e');
    }

    return localCleared || cloudCleared;
  }
}

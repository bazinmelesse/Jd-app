import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/playlist.dart';
import '../models/track.dart';

/// Everything the app remembers between launches: playlists, recent
/// searches and recently played songs. Stored as JSON on the device.
class LibraryController extends ChangeNotifier {
  static const _playlistsKey = 'playlists';
  static const _searchesKey = 'recent_searches';
  static const _recentTracksKey = 'recent_tracks';
  static const maxRecentSearches = 10;
  static const maxRecentTracks = 20;

  final List<Playlist> playlists = [];
  final List<String> recentSearches = [];
  final List<Track> recentTracks = [];

  SharedPreferences? _prefs;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    try {
      final raw = prefs.getString(_playlistsKey);
      if (raw != null) {
        playlists.addAll((jsonDecode(raw) as List)
            .map((p) => Playlist.fromJson(p as Map<String, dynamic>)));
      }
      recentSearches.addAll(prefs.getStringList(_searchesKey) ?? []);
      final rawTracks = prefs.getString(_recentTracksKey);
      if (rawTracks != null) {
        recentTracks.addAll((jsonDecode(rawTracks) as List)
            .map((t) => Track.fromJson(t as Map<String, dynamic>)));
      }
    } catch (e) {
      // Corrupt data shouldn't stop the app from opening.
      debugPrint('Could not read saved library: $e');
    }
    notifyListeners();
  }

  void _save() {
    final prefs = _prefs;
    if (prefs == null) return;
    prefs.setString(
        _playlistsKey, jsonEncode(playlists.map((p) => p.toJson()).toList()));
    prefs.setStringList(_searchesKey, recentSearches);
    prefs.setString(_recentTracksKey,
        jsonEncode(recentTracks.map((t) => t.toJson()).toList()));
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  // ---- Search history ----

  /// Moves the query to the front of the history (no duplicates).
  void addSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    recentSearches.removeWhere((s) => s.toLowerCase() == q.toLowerCase());
    recentSearches.insert(0, q);
    if (recentSearches.length > maxRecentSearches) {
      recentSearches.removeRange(maxRecentSearches, recentSearches.length);
    }
    _changed();
  }

  void removeSearch(String query) {
    recentSearches.remove(query);
    _changed();
  }

  void clearSearches() {
    recentSearches.clear();
    _changed();
  }

  // ---- Recently played ----

  void addRecentTrack(Track track) {
    recentTracks.removeWhere((t) => t.videoId == track.videoId);
    recentTracks.insert(0, track);
    if (recentTracks.length > maxRecentTracks) {
      recentTracks.removeRange(maxRecentTracks, recentTracks.length);
    }
    _changed();
  }

  // ---- Playlists ----

  Playlist createPlaylist(String name) {
    final playlist = Playlist(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim().isEmpty ? 'New playlist' : name.trim(),
    );
    playlists.add(playlist);
    _changed();
    return playlist;
  }

  void renamePlaylist(Playlist playlist, String name) {
    if (name.trim().isEmpty) return;
    playlist.name = name.trim();
    _changed();
  }

  void deletePlaylist(Playlist playlist) {
    playlists.remove(playlist);
    _changed();
  }

  /// Returns false if the song was already in the playlist.
  bool addToPlaylist(Playlist playlist, Track track) {
    if (playlist.tracks.any((t) => t.videoId == track.videoId)) return false;
    playlist.tracks.add(track);
    _changed();
    return true;
  }

  void removeFromPlaylist(Playlist playlist, int index) {
    playlist.tracks.removeAt(index);
    _changed();
  }

  /// [newIndex] is the final position (already adjusted for the removal).
  void reorderPlaylist(Playlist playlist, int oldIndex, int newIndex) {
    final track = playlist.tracks.removeAt(oldIndex);
    playlist.tracks.insert(newIndex, track);
    _changed();
  }
}

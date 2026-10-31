import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';

/// Wraps youtube_explode_dart to (1) search YouTube for tracks and
/// (2) resolve a video ID down to a direct, playable audio-only stream URL.
///
/// NOTE: This pulls audio directly from YouTube without going through
/// YouTube's official Data API licensing terms for commercial redistribution.
/// That's a gray area under YouTube's ToS. Fine for personal, non-commercial
/// use like this project - just don't publish or monetize this app.
class YoutubeService {
  final YoutubeExplode _yt = YoutubeExplode();

  /// Search YouTube and return a list of candidate tracks.
  Future<List<Track>> search(String query) async {
    final searchResults = await _yt.search.search(query);

    return searchResults.whereType<Video>().map((video) {
      return Track(
        videoId: video.id.value,
        title: video.title,
        author: video.author,
        thumbnailUrl: video.thumbnails.mediumResUrl,
        duration: video.duration ?? Duration.zero,
      );
    }).toList();
  }

  /// Songs YouTube suggests after this one ("up next" on YouTube).
  Future<List<Track>> related(String videoId) async {
    final video = await _yt.videos.get(videoId);
    final list = await _yt.videos.getRelatedVideos(video);
    if (list == null) return [];
    return list
        .map((video) => Track(
              videoId: video.id.value,
              title: video.title,
              author: video.author,
              thumbnailUrl: video.thumbnails.mediumResUrl,
              duration: video.duration ?? Duration.zero,
            ))
        .toList();
  }

  /// Resolve a video ID to a direct audio-stream URL.
  /// Picks the highest-bitrate audio-only stream available.
  ///
  /// Asks as the "Android VR" and default Android clients: their stream URLs
  /// play in a normal media player without extra signatures or tokens.
  Future<String> getAudioStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId,
        ytClients: [
          YoutubeApiClient.androidVr,
          YoutubeApiClient.androidSdkless
        ]);
    // Prefer MP4/AAC audio: every Android device can decode it.
    final mp4Audio =
        manifest.audioOnly.where((s) => s.container == StreamContainer.mp4);
    final audioStream = mp4Audio.isNotEmpty
        ? mp4Audio.withHighestBitrate()
        : manifest.audioOnly.withHighestBitrate();
    return audioStream.url.toString();
  }

  /// Resolve a video ID to a direct muxed (video+audio combined) stream URL
  /// for the Stream/Watch tab, so people can actually watch the video rather
  /// than just hear it. Falls back to the highest quality progressive stream.
  Future<String> getMuxedStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final muxedStream = manifest.muxed.withHighestBitrate();
    return muxedStream.url.toString();
  }

  /// Downloads a song's audio into [folder] and returns the file, so the
  /// deck plays from the tablet's storage: seeking and scratching are then
  /// instant instead of waiting on the network. Reuses an earlier download.
  ///
  /// Uses the combined video+audio stream first: it's the one confirmed to
  /// play with sound on Baz's tablet. Audio-only is the fallback.
  Future<File> downloadAudio(String videoId, Directory folder) async {
    final done = File('${folder.path}/$videoId.mp4');
    if (await done.exists() && await done.length() > 0) return done;

    final manifest = await _yt.videos.streamsClient.getManifest(videoId);
    final mp4Audio =
        manifest.audioOnly.where((s) => s.container == StreamContainer.mp4);
    final candidates = <StreamInfo>[
      if (manifest.muxed.isNotEmpty) manifest.muxed.withHighestBitrate(),
      if (mp4Audio.isNotEmpty) mp4Audio.withHighestBitrate(),
    ];
    if (candidates.isEmpty) {
      throw Exception('YouTube offered no playable audio for this song');
    }

    Object? lastError;
    for (final info in candidates) {
      // Write to a temp name first so a half-finished download is never
      // mistaken for a complete one.
      final partial = File('${done.path}.part');
      try {
        final sink = partial.openWrite();
        await sink.addStream(_yt.videos.streamsClient.get(info));
        await sink.close();
        if (await partial.length() == 0) throw Exception('empty download');
        return await partial.rename(done.path);
      } catch (e) {
        lastError = e;
        if (await partial.exists()) await partial.delete();
      }
    }
    throw Exception('Download failed: $lastError');
  }

  void dispose() {
    _yt.close();
  }
}

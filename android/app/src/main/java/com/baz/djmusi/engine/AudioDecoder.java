package com.baz.djmusi.engine;

import android.media.AudioFormat;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.nio.ShortBuffer;

/**
 * Decodes a whole song (MP4/AAC, MP3, Opus... anything Android can play)
 * into 16-bit stereo PCM in native memory, so a deck can jump anywhere and
 * play backwards without waiting on a decoder.
 */
public final class AudioDecoder {
    public static final class Result {
        public final ShortBuffer pcm;
        public final int frames;
        public final int sampleRate;
        Result(ShortBuffer pcm, int frames, int sampleRate) {
            this.pcm = pcm; this.frames = frames; this.sampleRate = sampleRate;
        }
    }

    public static Result decode(String path) throws IOException {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        try {
            extractor.setDataSource(path);
            int track = -1;
            MediaFormat format = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat f = extractor.getTrackFormat(i);
                String mime = f.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) { track = i; format = f; break; }
            }
            if (track < 0) throw new IOException("No audio track in file");
            extractor.selectTrack(track);

            int sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE);
            int channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
            long durationUs = format.containsKey(MediaFormat.KEY_DURATION)
                    ? format.getLong(MediaFormat.KEY_DURATION) : 0;

            // Room for the whole song (+5%); grows if the estimate is short.
            int capacityFrames = (int) Math.max(sampleRate * 10L,
                    durationUs * sampleRate / 1_000_000L * 105 / 100);
            ShortBuffer out = allocate(capacityFrames);
            int frames = 0;

            codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME));
            codec.configure(format, null, null, 0);
            codec.start();

            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            boolean inputDone = false, outputDone = false;
            boolean floatOutput = false;
            int outChannels = channels;
            while (!outputDone) {
                if (!inputDone) {
                    int in = codec.dequeueInputBuffer(10_000);
                    if (in >= 0) {
                        ByteBuffer buf = codec.getInputBuffer(in);
                        int size = extractor.readSampleData(buf, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(in, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputDone = true;
                        } else {
                            codec.queueInputBuffer(in, 0, size, extractor.getSampleTime(), 0);
                            extractor.advance();
                        }
                    }
                }
                int outIdx = codec.dequeueOutputBuffer(info, 10_000);
                if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    MediaFormat of = codec.getOutputFormat();
                    outChannels = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT);
                    sampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE);
                    floatOutput = of.containsKey(MediaFormat.KEY_PCM_ENCODING)
                            && of.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT;
                } else if (outIdx >= 0) {
                    ByteBuffer buf = codec.getOutputBuffer(outIdx);
                    if (buf != null && info.size > 0) {
                        buf.position(info.offset);
                        buf.limit(info.offset + info.size);
                        buf.order(ByteOrder.nativeOrder());
                        int bytesPerSample = floatOutput ? 4 : 2;
                        int newFrames = info.size / (bytesPerSample * outChannels);
                        if (frames + newFrames > capacityFrames) {
                            capacityFrames = (frames + newFrames) * 3 / 2;
                            out = grow(out, frames, capacityFrames);
                        }
                        for (int f = 0; f < newFrames; f++) {
                            short l, r;
                            if (floatOutput) {
                                float lf = buf.getFloat();
                                float rf = outChannels > 1 ? buf.getFloat() : lf;
                                for (int c = 2; c < outChannels; c++) buf.getFloat();
                                l = toShort(lf); r = toShort(rf);
                            } else {
                                l = buf.getShort();
                                r = outChannels > 1 ? buf.getShort() : l;
                                for (int c = 2; c < outChannels; c++) buf.getShort();
                            }
                            out.put((frames + f) * 2, l);
                            out.put((frames + f) * 2 + 1, r);
                        }
                        frames += newFrames;
                    }
                    codec.releaseOutputBuffer(outIdx, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) outputDone = true;
                }
            }
            if (frames == 0) throw new IOException("Song decoded to silence");
            return new Result(out, frames, sampleRate);
        } finally {
            if (codec != null) {
                try { codec.stop(); } catch (Exception ignored) { }
                codec.release();
            }
            extractor.release();
        }
    }

    private static short toShort(float f) {
        float c = Math.max(-1f, Math.min(1f, f));
        return (short) (c * 32767);
    }

    private static ShortBuffer allocate(int frames) {
        return ByteBuffer.allocateDirect(frames * 4).order(ByteOrder.nativeOrder()).asShortBuffer();
    }

    private static ShortBuffer grow(ShortBuffer old, int usedFrames, int newCapacity) {
        ShortBuffer bigger = allocate(newCapacity);
        for (int i = 0; i < usedFrames * 2; i++) bigger.put(i, old.get(i));
        return bigger;
    }
}

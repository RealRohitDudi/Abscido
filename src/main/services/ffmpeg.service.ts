import ffmpeg from 'fluent-ffmpeg';
// eslint-disable-next-line @typescript-eslint/no-require-imports
const ffmpegInstaller = require('@ffmpeg-installer/ffmpeg') as { path: string; version: string };
// eslint-disable-next-line @typescript-eslint/no-require-imports
const ffprobeInstaller = require('@ffprobe-installer/ffprobe') as { path: string; version: string };
import { app } from 'electron';
import fs from 'fs';
import path from 'path';
import os from 'os';
import { execFileSync } from 'child_process';
import type { MediaInfo, EditDecisionList, ExportPreset } from '../../shared/types';

/**
 * Ensure a binary is executable and not quarantined by macOS Gatekeeper.
 */
function prepBinary(binPath: string): string {
  try {
    fs.chmodSync(binPath, 0o755);
    if (process.platform === 'darwin') {
      try {
        execFileSync('xattr', ['-dr', 'com.apple.quarantine', binPath], { stdio: 'ignore' });
      } catch { /* attribute may not exist */ }
    }
  } catch (err) {
    console.warn(`[FFmpeg] prepBinary warning for ${binPath}:`, err);
  }
  return binPath;
}

// Use arch-correct binaries from @ffmpeg-installer / @ffprobe-installer
// These correctly ship arm64 binaries for Apple Silicon (unlike ffmpeg-static/ffprobe-static)
const ffmpegBin = prepBinary(ffmpegInstaller.path);
const ffprobeBin = prepBinary(ffprobeInstaller.path);

ffmpeg.setFfmpegPath(ffmpegBin);
ffmpeg.setFfprobePath(ffprobeBin);
console.log(`[FFmpeg] ffmpeg  ${ffmpegInstaller.version} @ ${ffmpegBin}`);
console.log(`[FFmpeg] ffprobe ${ffprobeInstaller.version} @ ${ffprobeBin}`);


function getTempDir(): string {
  const dir = path.join(app.getPath('temp'), 'abscido');
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  return dir;
}

function getThumbnailsDir(): string {
  const dir = path.join(app.getPath('userData'), 'thumbnails');
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  return dir;
}

export const ffmpegService = {
  /**
   * Extract audio track as 16kHz mono WAV for Whisper transcription
   */
  extractAudio(
    inputPath: string,
    outputWavPath: string,
    opts: { sampleRate?: number } = {},
  ): Promise<void> {
    const sampleRate = opts.sampleRate ?? 16000;

    return new Promise((resolve, reject) => {
      ffmpeg(inputPath)
        .noVideo()
        .audioCodec('pcm_s16le')
        .audioFrequency(sampleRate)
        .audioChannels(1)
        .format('wav')
        .output(outputWavPath)
        .on('start', (cmd) => console.log('[FFmpeg] extractAudio:', cmd))
        .on('error', (err, _stdout, stderr) => {
          reject(new Error(`FFmpeg extractAudio failed: ${err.message}\nStderr: ${stderr}`));
        })
        .on('end', () => resolve())
        .run();
    });
  },

  /**
   * Probe a media file and return its metadata
   */
  probeMedia(filePath: string): Promise<MediaInfo> {
    return new Promise((resolve, reject) => {
      ffmpeg.ffprobe(filePath, (err, metadata) => {
        if (err) {
          reject(new Error(`FFprobe failed: ${err.message}`));
          return;
        }

        const videoStream = metadata.streams.find((s) => s.codec_type === 'video');
        const audioStream = metadata.streams.find((s) => s.codec_type === 'audio');

        const durationMs = Math.round((metadata.format.duration ?? 0) * 1000);
        const width = videoStream?.width ?? 0;
        const height = videoStream?.height ?? 0;
        const codec = videoStream?.codec_name ?? audioStream?.codec_name ?? 'unknown';

        // Parse FPS from r_frame_rate string (e.g. "30000/1001" or "30/1")
        let fps = 0;
        const rFrameRate = videoStream?.r_frame_rate;
        if (rFrameRate) {
          const parts = rFrameRate.split('/');
          if (parts.length === 2) {
            const num = parseFloat(parts[0]);
            const den = parseFloat(parts[1]);
            fps = den !== 0 ? num / den : 0;
          }
        }

        resolve({
          filePath,
          durationMs,
          width,
          height,
          fps: Math.round(fps * 100) / 100,
          codec,
          bitrate: metadata.format.bit_rate ? parseInt(metadata.format.bit_rate.toString()) : 0,
          size: metadata.format.size ?? 0,
          streams: metadata.streams.map((s) => ({
            codecType: s.codec_type ?? '',
            codecName: s.codec_name ?? '',
            width: s.width,
            height: s.height,
            fps: (() => {
              if (!s.r_frame_rate) return undefined;
              const parts = s.r_frame_rate.split('/');
              if (parts.length === 2) {
                const n = parseFloat(parts[0]);
                const d = parseFloat(parts[1]);
                return d !== 0 ? n / d : undefined;
              }
              return undefined;
            })(),
            sampleRate: s.sample_rate ? parseInt(s.sample_rate.toString()) : undefined,
            channels: s.channels,
          })),
        });
      });
    });
  },

  /**
   * Generate a thumbnail PNG at a given timestamp
   */
  generateThumbnail(filePath: string, timeMs: number, outputPath?: string): Promise<string> {
    const timeSecs = timeMs / 1000;
    const thumbDir = getThumbnailsDir();
    const filename = outputPath ?? path.join(thumbDir, `thumb_${Date.now()}.png`);

    return new Promise((resolve, reject) => {
      ffmpeg(filePath)
        .screenshots({
          timestamps: [timeSecs],
          filename: path.basename(filename),
          folder: path.dirname(filename),
          size: '320x?',
        })
        .on('error', (err, _stdout, stderr) => {
          reject(new Error(`FFmpeg thumbnail failed: ${err.message}\nStderr: ${stderr}`));
        })
        .on('end', () => resolve(filename));
    });
  },

  /**
   * Compile an Edit Decision List into a single output video.
   * Uses stream copy when possible; falls back to re-encode.
   */
  async compileEdl(
    edl: EditDecisionList,
    outputPath: string,
    onProgress: (progress: number) => void,
  ): Promise<void> {
    const tempDir = getTempDir();
    const tempFiles: string[] = [];

    try {
      let segmentIndex = 0;
      const totalSegments = edl.clips.reduce((acc, c) => acc + c.segments.length, 0);

      // Step 1: Trim each segment to a temp file
      for (const clip of edl.clips) {
        for (const segment of clip.segments) {
          const startSecs = segment.startMs / 1000;
          const durationSecs = (segment.endMs - segment.startMs) / 1000;
          const tempFile = path.join(tempDir, `seg_${segmentIndex}_${Date.now()}.mp4`);
          tempFiles.push(tempFile);

          await new Promise<void>((resolve, reject) => {
            ffmpeg(clip.mediaFilePath)
              .seekInput(startSecs)
              .duration(durationSecs)
              .outputOptions(['-c copy', '-avoid_negative_ts make_zero'])
              .output(tempFile)
              .on('error', (err, _stdout, stderr) => {
                // If stream copy fails, try re-encode
                ffmpeg(clip.mediaFilePath)
                  .seekInput(startSecs)
                  .duration(durationSecs)
                  .videoCodec('libx264')
                  .audioCodec('aac')
                  .output(tempFile)
                  .on('error', (err2, _s, se2) => {
                    reject(
                      new Error(
                        `Segment trim failed: ${err.message} / ${err2.message}\n${stderr}\n${se2}`,
                      ),
                    );
                  })
                  .on('end', () => resolve())
                  .run();
              })
              .on('end', () => {
                segmentIndex++;
                onProgress(Math.round((segmentIndex / totalSegments) * 80));
                resolve();
              })
              .run();
          });
        }
      }

      // Step 2: Create concat list file
      const concatListPath = path.join(tempDir, `concat_${Date.now()}.txt`);
      const concatContent = tempFiles.map((f) => `file '${f}'`).join('\n');
      fs.writeFileSync(concatListPath, concatContent, 'utf-8');

      // Step 3: Concat all segments
      await new Promise<void>((resolve, reject) => {
        ffmpeg()
          .input(concatListPath)
          .inputOptions(['-f concat', '-safe 0'])
          .outputOptions(['-c copy'])
          .output(outputPath)
          .on('progress', (progress) => {
            const pct = 80 + Math.round((progress.percent ?? 0) * 0.2);
            onProgress(Math.min(99, pct));
          })
          .on('error', (err, _stdout, stderr) => {
            reject(new Error(`FFmpeg concat failed: ${err.message}\nStderr: ${stderr}`));
          })
          .on('end', () => {
            onProgress(100);
            resolve();
          })
          .run();
      });

      // Clean up concat list
      fs.unlinkSync(concatListPath);
    } finally {
      // Clean up temp segment files
      for (const f of tempFiles) {
        try {
          if (fs.existsSync(f)) fs.unlinkSync(f);
        } catch {
          // Ignore cleanup errors
        }
      }
    }
  },

  /**
   * Render a full export from the project's compiled output
   */
  renderExport(
    inputPath: string,
    outputPath: string,
    preset: ExportPreset,
    onProgress: (progress: number, eta: number) => void,
  ): Promise<void> {
    return new Promise((resolve, reject) => {
      const cmd = ffmpeg(inputPath);

      if (preset.width && preset.height) {
        cmd.size(`${preset.width}x${preset.height}`);
      }
      if (preset.fps) {
        cmd.fps(preset.fps);
      }

      switch (preset.quality) {
        case 'lossless':
          cmd.videoCodec('libx264').outputOptions(['-crf 0', '-preset ultrafast']);
          break;
        case 'high':
          cmd.videoCodec('libx264').outputOptions(['-crf 18', '-preset slow']);
          break;
        case 'medium':
          cmd.videoCodec('libx264').outputOptions(['-crf 23', '-preset medium']);
          break;
        case 'low':
          cmd.videoCodec('libx264').outputOptions(['-crf 28', '-preset fast']);
          break;
      }

      if (preset.bitrate) {
        cmd.videoBitrate(preset.bitrate);
      }

      cmd
        .audioCodec('aac')
        .audioBitrate('192k')
        .format(preset.format)
        .output(outputPath)
        .on('progress', (progress) => {
          const pct = progress.percent ?? 0;
          const eta = progress.currentKbps
            ? Math.round((100 - pct) / (pct || 1)) * 10
            : 0;
          onProgress(Math.round(pct), eta);
        })
        .on('error', (err, _stdout, stderr) => {
          reject(new Error(`FFmpeg export failed: ${err.message}\nStderr: ${stderr}`));
        })
        .on('end', () => resolve())
        .run();
    });
  },

  /**
   * Clean up orphaned temp files from previous sessions
   */
  cleanupTempFiles(): void {
    const tempDir = path.join(os.tmpdir(), 'abscido');
    if (!fs.existsSync(tempDir)) return;

    try {
      const files = fs.readdirSync(tempDir);
      const cutoff = Date.now() - 24 * 60 * 60 * 1000; // 24 hours

      for (const file of files) {
        const filePath = path.join(tempDir, file);
        const stat = fs.statSync(filePath);
        if (stat.mtimeMs < cutoff) {
          fs.unlinkSync(filePath);
          console.log(`[FFmpeg] Cleaned up orphaned temp file: ${filePath}`);
        }
      }
    } catch (err) {
      console.warn('[FFmpeg] Temp cleanup error:', err);
    }
  },
};

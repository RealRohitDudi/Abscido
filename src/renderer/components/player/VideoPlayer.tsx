import React, { useRef, useEffect, useCallback, useState } from 'react';
import { usePlayer, useTimeline, useStore } from '../../store';

function formatTime(ms: number): string {
  const totalSecs = Math.floor(ms / 1000);
  const hours = Math.floor(totalSecs / 3600);
  const mins = Math.floor((totalSecs % 3600) / 60);
  const secs = totalSecs % 60;
  const centisecs = Math.floor((ms % 1000) / 10);
  if (hours > 0) {
    return `${hours}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  return `${mins}:${secs.toString().padStart(2, '0')}.${centisecs.toString().padStart(2, '0')}`;
}

export const VideoPlayer: React.FC = () => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const progressRef = useRef<HTMLDivElement>(null);
  const animFrameRef = useRef<number>(0);

  const {
    currentTimeMs,
    durationMs,
    isPlaying,
    volume,
    isMuted,
    playbackRate,
    setCurrentTime,
    setDuration,
    setIsPlaying,
    setVideoRef,
    togglePlay,
    seek,
    setVolume,
    toggleMute,
    setPlaybackRate,
  } = usePlayer();

  const { clips } = useTimeline();
  const addToast = useStore((s) => s.addToast);

  // Current video source — use the first clip's media file for now
  const [videoSrc, setVideoSrc] = useState<string | null>(null);

  // Register video element ref in store
  useEffect(() => {
    if (videoRef.current) {
      setVideoRef(videoRef.current);
    }
    return () => setVideoRef(null);
  }, [setVideoRef]);

  // Load first clip when clips change
  useEffect(() => {
    if (clips.length === 0) {
      setVideoSrc(null);
      return;
    }
    // In a full implementation, we'd get the media file path from the clip.
    // We store the path in mediaFiles in the project store.
    // For now, we'll use a dummy approach and let the parent handle it.
  }, [clips]);

  // rAF loop for currentTime sync
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;

    const tick = (): void => {
      const ms = video.currentTime * 1000;
      setCurrentTime(ms);
      animFrameRef.current = requestAnimationFrame(tick);
    };

    if (isPlaying) {
      animFrameRef.current = requestAnimationFrame(tick);
    } else {
      cancelAnimationFrame(animFrameRef.current);
    }

    return () => cancelAnimationFrame(animFrameRef.current);
  }, [isPlaying, setCurrentTime]);

  const handleVideoEvents = useCallback((): void => {
    const video = videoRef.current;
    if (!video) return;

    video.onloadedmetadata = () => {
      setDuration(video.duration * 1000);
    };
    video.onplay = () => setIsPlaying(true);
    video.onpause = () => setIsPlaying(false);
    video.onended = () => setIsPlaying(false);
    video.ontimeupdate = () => {
      if (!isPlaying) setCurrentTime(video.currentTime * 1000);
    };
    video.onerror = () => {
      addToast({ type: 'error', message: 'Failed to load video' });
    };
  }, [setDuration, setIsPlaying, setCurrentTime, isPlaying, addToast]);

  useEffect(() => {
    handleVideoEvents();
  }, [handleVideoEvents, videoSrc]);

  // Sync volume/mute/rate changes
  useEffect(() => {
    const video = videoRef.current;
    if (!video) return;
    video.volume = volume;
    video.muted = isMuted;
    video.playbackRate = playbackRate;
  }, [volume, isMuted, playbackRate]);

  // Progress bar click to seek
  const handleProgressClick = useCallback(
    (e: React.MouseEvent<HTMLDivElement>): void => {
      if (!progressRef.current || durationMs === 0) return;
      const rect = progressRef.current.getBoundingClientRect();
      const fraction = (e.clientX - rect.left) / rect.width;
      seek(Math.round(fraction * durationMs));
    },
    [durationMs, seek],
  );

  const progress = durationMs > 0 ? (currentTimeMs / durationMs) * 100 : 0;

  const playbackRates = [0.5, 0.75, 1, 1.25, 1.5, 2];

  return (
    <div className="relative w-full h-full bg-black flex flex-col">
      {/* Video element */}
      <div className="flex-1 flex items-center justify-center overflow-hidden relative">
        {videoSrc ? (
          <video
            ref={videoRef}
            src={videoSrc}
            className="max-w-full max-h-full object-contain"
            playsInline
            preload="metadata"
          />
        ) : (
          <div className="flex flex-col items-center gap-3 text-center">
            <div className="w-16 h-16 rounded-full bg-white/5 flex items-center justify-center">
              <svg className="w-8 h-8 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
            <div>
              <p className="text-sm text-text-muted">No clip selected</p>
              <p className="text-xs text-text-muted/60 mt-0.5">
                Add a clip to the timeline to preview
              </p>
            </div>
          </div>
        )}

        {/* Playhead time overlay */}
        {videoSrc && (
          <div className="absolute top-2 left-2">
            <span className="timecode bg-black/60 px-2 py-1 rounded text-xs text-white">
              {formatTime(currentTimeMs)}
            </span>
          </div>
        )}
      </div>

      {/* Controls bar */}
      <div className="player-controls px-4 py-2 flex flex-col gap-1.5 flex-shrink-0" style={{ background: 'rgba(0,0,0,0.85)' }}>
        {/* Progress bar */}
        <div
          ref={progressRef}
          className="w-full h-1.5 rounded-full cursor-pointer group"
          style={{ background: '#2e2e2e' }}
          onClick={handleProgressClick}
          role="slider"
          aria-label="Playback progress"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(progress)}
        >
          <div
            className="h-full rounded-full relative transition-none"
            style={{
              width: `${progress}%`,
              background: 'linear-gradient(90deg, #7c6cfa, #9b8efb)',
            }}
          >
            <div className="absolute right-0 top-1/2 -translate-y-1/2 w-3 h-3 rounded-full bg-white opacity-0 group-hover:opacity-100 transition-opacity shadow" />
          </div>
        </div>

        {/* Buttons row */}
        <div className="flex items-center gap-2">
          {/* Shuttle: J */}
          <button
            onClick={() => setPlaybackRate(Math.max(0.25, playbackRate - 0.25))}
            className="w-7 h-7 flex items-center justify-center rounded text-text-secondary hover:text-text-primary hover:bg-white/10 transition-colors"
            title="Slower (J)"
            aria-label="Slow down playback"
          >
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" />
            </svg>
          </button>

          {/* Play/Pause */}
          <button
            id="player-play-pause"
            onClick={togglePlay}
            className="w-9 h-9 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors"
            title="Play/Pause (Space)"
            aria-label={isPlaying ? 'Pause' : 'Play'}
          >
            {isPlaying ? (
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" />
              </svg>
            ) : (
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z" />
              </svg>
            )}
          </button>

          {/* Shuttle: L */}
          <button
            onClick={() => setPlaybackRate(Math.min(4, playbackRate + 0.25))}
            className="w-7 h-7 flex items-center justify-center rounded text-text-secondary hover:text-text-primary hover:bg-white/10 transition-colors"
            title="Faster (L)"
            aria-label="Speed up playback"
          >
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
              <path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z" />
            </svg>
          </button>

          {/* Time display */}
          <div className="flex-1 flex items-center gap-1">
            <span className="timecode text-white">{formatTime(currentTimeMs)}</span>
            <span className="text-text-muted timecode">/</span>
            <span className="timecode text-text-muted">{formatTime(durationMs)}</span>
          </div>

          {/* Speed indicator */}
          {playbackRate !== 1 && (
            <span className="text-[10px] text-accent font-mono bg-accent/10 px-1.5 py-0.5 rounded">
              {playbackRate}×
            </span>
          )}

          {/* Mute */}
          <button
            onClick={toggleMute}
            className="w-7 h-7 flex items-center justify-center rounded text-text-secondary hover:text-text-primary hover:bg-white/10 transition-colors"
            title={isMuted ? 'Unmute' : 'Mute'}
            aria-label={isMuted ? 'Unmute' : 'Mute'}
          >
            {isMuted ? (
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z" />
              </svg>
            ) : (
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24">
                <path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z" />
              </svg>
            )}
          </button>

          {/* Volume slider */}
          <input
            type="range"
            min={0}
            max={1}
            step={0.05}
            value={isMuted ? 0 : volume}
            onChange={(e) => setVolume(parseFloat(e.target.value))}
            className="w-16 h-1 accent-[#7c6cfa] cursor-pointer"
            aria-label="Volume"
          />
        </div>
      </div>
    </div>
  );
};

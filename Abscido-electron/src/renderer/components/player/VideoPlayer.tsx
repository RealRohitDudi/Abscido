import React, { useRef, useEffect, useState, useCallback } from 'react';
import { usePlayer, useStore, useProject, useTimeline } from '../../store';

function formatTime(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const cs = Math.floor((ms % 1000) / 10);
  return `${m}:${(s % 60).toString().padStart(2, '0')}.${cs.toString().padStart(2, '0')}`;
}

export const VideoPlayer: React.FC = () => {
  const videoRef = useRef<HTMLVideoElement>(null);
  const progressRef = useRef<HTMLDivElement>(null);

  const {
    currentTimeMs, durationMs, isPlaying,
    volume, isMuted, playbackRate,
    setCurrentTime, setDuration, setIsPlaying,
    setVideoRef, seek, setVolume, toggleMute, setPlaybackRate,
  } = usePlayer();

  const { clips } = useTimeline();
  const { mediaFiles } = useProject();
  const addToast = useStore((s) => s.addToast);
  const [videoSrc, setVideoSrc] = useState<string | null>(null);
  const [debugError, setDebugError] = useState<string>('');

  // ── 1. Register video element in store (always-mounted, so ref is immediately valid) ──
  useEffect(() => {
    setVideoRef(videoRef.current);
    return () => setVideoRef(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── 2. Resolve file path from timeline clips ─────────────────────────────────
  useEffect(() => {
    const videoClips = clips.filter((c) => c.clipType === 'video');
    const target = videoClips[0] ?? clips[0] ?? null;
    if (!target || mediaFiles.length === 0) { setVideoSrc(null); return; }
    const mf = mediaFiles.find((f) => f.id === target.mediaFileId);
    if (!mf) { setVideoSrc(null); return; }
    // Use media://localhost/?p=<encoded-path> to pass file path without triggering
    // Electron's standard-protocol host normalization (which lowercases the path).
    setVideoSrc('media://localhost/?p=' + encodeURIComponent(mf.filePath));
  }, [clips, mediaFiles]);

  // ── 3. Play/Pause — button calls video directly; onPlay/onPause sync the icon ─
  const handlePlayPause = useCallback(() => {
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const v = videoRef.current as any;
    if (!v) { setDebugError('no videoRef'); return; }
    setDebugError(`src=${v.src?.slice(0,60)} ready=${v.readyState}`);
    if (v.paused || v.ended) {
      v.play().catch((err: unknown) => {
        const msg = err instanceof Error ? err.message : String(err);
        setDebugError('play failed: ' + msg);
        console.warn('[Player] play rejected:', err);
      });
    } else {
      v.pause();
    }
  }, []);

  // Space-bar also needs to work via store.togglePlay — patch it here
  useEffect(() => {
    const store = useStore.getState();
    const originalToggle = store.togglePlay;
    store.togglePlay = handlePlayPause;
    return () => { store.togglePlay = originalToggle; };
  }, [handlePlayPause]);

  // ── 5. Seek sync — subscribe to playheadMs and drive video.currentTime directly ─
  // This is more reliable than relying on store.videoRef (which may be stale).
  // The 500ms threshold distinguishes user seeks from normal playback updates.
  useEffect(() => {
    let lastPlayheadMs = -1;
    const unsubscribe = useStore.subscribe((state) => {
      const playheadMs = state.playheadMs;
      if (playheadMs === lastPlayheadMs) return;
      lastPlayheadMs = playheadMs;
      const video = videoRef.current;
      if (!video) return;
      const diff = Math.abs(video.currentTime * 1000 - playheadMs);
      // Only seek if the jump is > 500ms (user-initiated seek, not playback tick)
      if (diff > 500) {
        video.currentTime = playheadMs / 1000;
      }
    });
    return unsubscribe;
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── 4. Sync volume/mute/rate to video element ────────────────────────────────
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    v.volume = volume;
    v.muted = isMuted;
    v.playbackRate = playbackRate;
  }, [volume, isMuted, playbackRate]);

  const handleProgressClick = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (!progressRef.current || durationMs === 0) return;
    const rect = progressRef.current.getBoundingClientRect();
    const ms = Math.round(((e.clientX - rect.left) / rect.width) * durationMs);
    // Seek video directly via ref (guaranteed valid) and update store state
    const video = videoRef.current as HTMLVideoElement | null;
    if (video) video.currentTime = ms / 1000;
    useStore.getState().setPlayhead(ms);
    useStore.getState().setCurrentTime(ms);
  }, [durationMs, seek]);

  const progress = durationMs > 0 ? (currentTimeMs / durationMs) * 100 : 0;

  return (
    <div className="relative w-full h-full bg-black flex flex-col">
      <div className="flex-1 flex items-center justify-center overflow-hidden relative">

        {/* Always in DOM — never unmounted so videoRef stays valid */}
        <video
          ref={videoRef}
          src={videoSrc ?? undefined}
          playsInline
          preload="auto"
          style={{ display: videoSrc ? 'block' : 'none', maxWidth: '100%', maxHeight: '100%', objectFit: 'contain' }}
          onLoadedMetadata={(e) => setDuration(e.currentTarget.duration * 1000)}
          onTimeUpdate={(e) => {
            const ms = e.currentTarget.currentTime * 1000;
            setCurrentTime(ms);
            useStore.getState().setPlayhead(ms);
          }}
          onPlay={() => setIsPlaying(true)}
          onPause={() => setIsPlaying(false)}
          onEnded={() => setIsPlaying(false)}
          onError={(e) => {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const vid = e.currentTarget as any;
            const code = vid.error?.code ?? '?';
            const msg = vid.error?.message ?? 'unknown';
            const errStr = `MediaError ${code}: ${msg}`;
            setDebugError(errStr);
            addToast({ type: 'error', message: 'Cannot load video: ' + errStr });
          }}
        />

        {!videoSrc && (
          <div className="flex flex-col items-center gap-3 text-center pointer-events-none">
            <div className="w-16 h-16 rounded-full bg-white/5 flex items-center justify-center">
              <svg className="w-8 h-8 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M15 10l4.553-2.069A1 1 0 0121 8.87v6.26a1 1 0 01-1.447.894L15 14M5 18h8a2 2 0 002-2V8a2 2 0 00-2-2H5a2 2 0 00-2 2v8a2 2 0 002 2z" />
              </svg>
            </div>
            <p className="text-sm text-text-muted">Add a clip to preview</p>
          </div>
        )}

        {videoSrc && (
          <div className="absolute top-2 left-2 pointer-events-none">
            <span className="timecode bg-black/70 px-2 py-0.5 rounded text-xs text-white">{formatTime(currentTimeMs)}</span>
          </div>
        )}

        {/* Debug bar — remove after fixing */}
        <div className="absolute bottom-0 left-0 right-0 bg-black/80 px-2 py-0.5 text-[9px] font-mono pointer-events-none" style={{ zIndex: 99 }}>
          <span className="text-yellow-400">src: </span>
          <span className="text-white/70">{videoSrc ?? 'null'}</span>
          {debugError && <><br /><span className="text-red-400">{debugError}</span></>}
        </div>
      </div>

      {/* Controls */}
      <div className="px-4 py-2 flex flex-col gap-1.5 flex-shrink-0" style={{ background: 'rgba(0,0,0,0.85)' }}>
        {/* Progress */}
        <div
          ref={progressRef}
          className="w-full h-1.5 rounded-full cursor-pointer group"
          style={{ background: '#2e2e2e' }}
          onClick={handleProgressClick}
          role="slider" aria-label="Playback progress"
          aria-valuemin={0} aria-valuemax={100} aria-valuenow={Math.round(progress)}
        >
          <div className="h-full rounded-full relative" style={{ width: `${progress}%`, background: 'linear-gradient(90deg,#7c6cfa,#9b8efb)', transition: 'width 0.08s linear' }}>
            <div className="absolute right-0 top-1/2 -translate-y-1/2 w-3 h-3 rounded-full bg-white opacity-0 group-hover:opacity-100 transition-opacity" />
          </div>
        </div>

        {/* Buttons */}
        <div className="flex items-center gap-2">
          <button onClick={() => setPlaybackRate(Math.max(0.25, playbackRate - 0.25))}
            className="w-7 h-7 flex items-center justify-center rounded text-text-secondary hover:text-text-primary hover:bg-white/10 transition-colors" title="Slower">
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M6 6h2v12H6zm3.5 6l8.5 6V6z" /></svg>
          </button>

          <button id="player-play-pause" onClick={handlePlayPause}
            className="w-9 h-9 flex items-center justify-center rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors"
            title="Play/Pause (Space)" aria-label={isPlaying ? 'Pause' : 'Play'}>
            {isPlaying ? (
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" /></svg>
            ) : (
              <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M8 5v14l11-7z" /></svg>
            )}
          </button>

          <button onClick={() => setPlaybackRate(Math.min(4, playbackRate + 0.25))}
            className="w-7 h-7 flex items-center justify-center rounded text-text-secondary hover:text-text-primary hover:bg-white/10 transition-colors" title="Faster">
            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z" /></svg>
          </button>

          <div className="flex-1 flex items-center gap-1">
            <span className="timecode text-white">{formatTime(currentTimeMs)}</span>
            <span className="text-text-muted timecode">/</span>
            <span className="timecode text-text-muted">{formatTime(durationMs)}</span>
          </div>

          {playbackRate !== 1 && (
            <span className="text-[10px] text-accent font-mono bg-accent/10 px-1.5 py-0.5 rounded">{playbackRate}×</span>
          )}

          <button onClick={toggleMute}
            className="w-7 h-7 flex items-center justify-center rounded text-text-secondary hover:text-text-primary hover:bg-white/10 transition-colors"
            title={isMuted ? 'Unmute' : 'Mute'}>
            {isMuted
              ? <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z" /></svg>
              : <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 24 24"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z" /></svg>
            }
          </button>

          <input type="range" min={0} max={1} step={0.05}
            value={isMuted ? 0 : volume}
            onChange={(e) => setVolume(parseFloat(e.target.value))}
            className="w-16 h-1 accent-[#7c6cfa] cursor-pointer" aria-label="Volume" />
        </div>
      </div>
    </div>
  );
};

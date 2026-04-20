import React, { useRef, useCallback, useState, useEffect } from 'react';
import { useTimeline, usePlayer, useStore, useProject, useModal } from '../../store';
import { useIpc } from '../../hooks/useIpc';
import { TimelineClipComponent } from './TimelineClip';
import { PlayheadMarker } from './PlayheadMarker';
import { Button } from '../ui/Button';
import type { IpcResult, TimelineClip } from '../../types';

const BASE_PIXELS_PER_SEC = 50;           // px/s at zoom=1
const MIN_ZOOM = 0.25;
const MAX_ZOOM = 16;
const MIN_TRACK_HEIGHT = 32;
const MAX_TRACK_HEIGHT = 200;

function formatTime(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const secs = s % 60;
  return `${m}:${secs.toString().padStart(2, '0')}`;
}

function getTickInterval(pixelsPerSec: number): number {
  // Show a tick every N seconds such that there's roughly 80-200px between ticks
  const candidates = [1, 2, 5, 10, 15, 30, 60, 120, 300, 600];
  for (const s of candidates) {
    if (pixelsPerSec * s >= 80) return s * 1000; // return ms
  }
  return 600_000;
}

// ─── Drag-resize handle between two tracks ──────────────────────────────────
const TrackResizeHandle: React.FC<{
  onDrag: (dy: number) => void;
}> = ({ onDrag }) => {
  const handleMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      const startY = e.clientY;
      const handleMove = (moveEvent: MouseEvent) => {
        onDrag(moveEvent.clientY - startY);
      };
      const handleUp = () => {
        window.removeEventListener('mousemove', handleMove);
        window.removeEventListener('mouseup', handleUp);
        document.body.style.cursor = '';
      };
      document.body.style.cursor = 'ns-resize';
      window.addEventListener('mousemove', handleMove);
      window.addEventListener('mouseup', handleUp);
    },
    [onDrag],
  );

  return (
    <div
      className="flex-shrink-0 flex items-center justify-center cursor-ns-resize group"
      style={{ height: 6, background: '#111' }}
      onMouseDown={handleMouseDown}
      title="Drag to resize tracks"
    >
      <div
        className="w-8 h-0.5 rounded-full bg-white/20 group-hover:bg-accent/60 transition-colors"
      />
    </div>
  );
};

export const Timeline: React.FC = () => {
  const {
    clips,
    playheadMs,
    totalDurationMs,
    selectedClipIds,
    setSelectedClip,
    setSelectedClipIds,
    setPlayhead,
    addClips,
    removeClips,
  } = useTimeline();
  const { seek } = usePlayer();
  const { currentProject } = useProject();
  const { openModal } = useModal();
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();

  const rulerRef = useRef<HTMLDivElement>(null);
  const tracksRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // ── Zoom state (pinch-to-zoom) ──────────────────────────────────────────
  const [zoom, setZoom] = useState(1); // multiplier applied to BASE_PIXELS_PER_SEC
  const pixelsPerMs = (BASE_PIXELS_PER_SEC * zoom) / 1000; // px per ms

  // ── Track heights (resizable) ────────────────────────────────────────────
  const [videoTrackHeight, setVideoTrackHeight] = useState(56);
  const [audioTrackHeight, setAudioTrackHeight] = useState(48);

  // ── Compile state ────────────────────────────────────────────────────────
  const [isCompiling, setIsCompiling] = useState(false);
  const [compileProgress, setCompileProgress] = useState(0);
  const [isDragOver, setIsDragOver] = useState(false);

  // ── Ruler ticks ─────────────────────────────────────────────────────────
  const pixelsPerSec = BASE_PIXELS_PER_SEC * zoom;
  const tickIntervalMs = getTickInterval(pixelsPerSec);
  const totalMs = Math.max(totalDurationMs, 30_000);
  const totalWidthPx = totalMs * pixelsPerMs;

  const ticks: number[] = [];
  for (let ms = 0; ms <= totalMs + tickIntervalMs; ms += tickIntervalMs) {
    ticks.push(ms);
  }

  // ── Pinch-to-zoom ────────────────────────────────────────────────────────
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;

    const handleWheel = (e: WheelEvent) => {
      // On Mac, trackpad pinch fires as wheel with ctrlKey = true
      if (!e.ctrlKey) return;
      e.preventDefault();
      setZoom((z) => {
        const delta = e.deltaY > 0 ? 0.9 : 1.1;
        return Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, z * delta));
      });
    };

    el.addEventListener('wheel', handleWheel, { passive: false });
    return () => el.removeEventListener('wheel', handleWheel);
  }, []);

  // ── Playhead scrub ────────────────────────────────────────────────────────
  const handleRulerMouseDown = useCallback(
    (e: React.MouseEvent<HTMLDivElement>) => {
      if (!rulerRef.current) return;
      const rect = rulerRef.current.getBoundingClientRect();

      const updatePlayhead = (clientX: number) => {
        const ms = (clientX - rect.left) / pixelsPerMs;
        const clamped = Math.max(0, Math.min(ms, totalDurationMs || totalMs));
        setPlayhead(clamped);
        seek(clamped);
      };

      updatePlayhead(e.clientX);

      const onMove = (me: MouseEvent) => updatePlayhead(me.clientX);
      const onUp = () => {
        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onUp);
      };
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
    },
    [pixelsPerMs, totalDurationMs, totalMs, setPlayhead, seek],
  );

  // ── Drag-and-drop from bin ─────────────────────────────────────────────
  const handleDrop = async (e: React.DragEvent): Promise<void> => {
    e.preventDefault();
    setIsDragOver(false);
    try {
      const data = e.dataTransfer.getData('application/json');
      if (!data) return;
      const { type, file } = JSON.parse(data);
      if (type !== 'mediaFile' || !file || !currentProject) return;

      if (!rulerRef.current) return;
      const rect = rulerRef.current.getBoundingClientRect();
      const ms = Math.max(0, (e.clientX - rect.left) / pixelsPerMs);

      const result = await invoke<IpcResult<TimelineClip[]>>(
        window.electronAPI.channels.CLIP_ADD,
        {
          projectId: currentProject.id,
          mediaFileId: file.id,
          positionMs: ms,
          inPointMs: 0,
          outPointMs: file.durationMs,
          track: 0,
        },
      );

      if (!result.success) { addToast({ type: 'error', message: result.error }); return; }
      addClips(result.data);
      addToast({ type: 'success', message: `Added "${file.filePath.split('/').pop()}"` });
    } catch { /* ignore */ }
  };

  // ── Compile ───────────────────────────────────────────────────────────────
  const handleCompileEdit = async () => {
    if (!currentProject) { addToast({ type: 'warning', message: 'No active project' }); return; }
    if (clips.length === 0) { addToast({ type: 'warning', message: 'No clips in timeline' }); return; }

    const saveResult = await invoke<IpcResult<string | null>>(
      window.electronAPI.channels.APP_OPEN_SAVE_DIALOG,
      { defaultPath: `${currentProject.name}_compiled.mp4`, filters: [{ name: 'Video', extensions: ['mp4'] }] },
    );
    if (!saveResult.success || !saveResult.data) return;

    setIsCompiling(true);
    setCompileProgress(0);
    const cleanup = window.electronAPI.on(
      window.electronAPI.channels.EXPORT_PROGRESS,
      (data: unknown) => setCompileProgress((data as { progress: number }).progress),
    );

    try {
      const result = await invoke<IpcResult<{ outputPath: string }>>(
        window.electronAPI.channels.EDIT_COMPILE,
        { projectId: currentProject.id, outputPath: saveResult.data },
      );
      if (result.success) {
        addToast({ type: 'success', message: `Compiled!`, duration: 6000 });
      } else {
        addToast({ type: 'error', message: result.error });
      }
    } finally {
      cleanup();
      setIsCompiling(false);
      setCompileProgress(0);
    }
  };

  // ── Track resize helpers ──────────────────────────────────────────────────
  const handleResizeV1 = useCallback((dy: number) => {
    setVideoTrackHeight((h) =>
      Math.max(MIN_TRACK_HEIGHT, Math.min(MAX_TRACK_HEIGHT, h + dy)),
    );
  }, []);

  const handleResizeA1 = useCallback((dy: number) => {
    setAudioTrackHeight((h) =>
      Math.max(MIN_TRACK_HEIGHT, Math.min(MAX_TRACK_HEIGHT, h + dy)),
    );
  }, []);

  // ── Clip data by track ────────────────────────────────────────────────────
  const videoClips = clips.filter((c) => c.clipType === 'video');
  const audioClips = clips.filter((c) => c.clipType === 'audio');
  const totalTracksHeight = videoTrackHeight + audioTrackHeight + 12; // +handle height

  const handleDeleteClip = useCallback(
    async (clipId: number) => {
      const clip = clips.find((c) => c.id === clipId);
      const idsToRemove = [clipId, ...(clip?.linkedClipId ? [clip.linkedClipId] : [])];
      await invoke('clip:delete', { clipId });
      removeClips(idsToRemove);
    },
    [clips, invoke, removeClips],
  );

  const handleUnlink = useCallback(
    async (clipId: number) => {
      const clip = clips.find((c) => c.id === clipId);
      if (!clip?.linkedClipId) return;
      await invoke('clip:updateLink', { clipId, linkedClipId: null });
      await invoke('clip:updateLink', { clipId: clip.linkedClipId, linkedClipId: null });
      const { updateClip } = useStore.getState();
      updateClip(clipId, { linkedClipId: null });
      updateClip(clip.linkedClipId, { linkedClipId: null });
    },
    [clips, invoke],
  );

  return (
    <div className="flex flex-col h-full bg-[#161618]">
      {/* ── Header ─────────────────────────────────────────────────────────── */}
      <div className="px-3 pt-2 pb-2 flex-shrink-0 border-b border-border flex items-center gap-2">
        <h2 className="text-xs font-semibold text-text-muted uppercase tracking-wider mr-auto">
          Timeline
        </h2>
        {/* Zoom indicator */}
        <span className="text-[10px] text-text-muted/50 tabular-nums">{zoom.toFixed(1)}×</span>
        <Button
          variant="primary"
          size="xs"
          onClick={handleCompileEdit}
          loading={isCompiling}
          icon={
            <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14 10l-2 1m0 0l-2-1m2 1v2.5M20 7l-2 1m2-1l-2-1m2 1v2.5" />
            </svg>
          }
        >
          Compile
        </Button>
        <Button variant="secondary" size="xs" onClick={() => openModal('export')}>
          Export
        </Button>
      </div>

      {isCompiling && (
        <div className="px-3 py-1 flex-shrink-0 border-b border-border">
          <div className="progress-bar">
            <div className="progress-bar-fill" style={{ width: `${compileProgress}%` }} />
          </div>
          <p className="text-[10px] text-text-muted mt-0.5">{compileProgress}% — compiling…</p>
        </div>
      )}

      {/* ── Body ───────────────────────────────────────────────────────────── */}
      <div
        className="flex flex-1 overflow-hidden"
        onDragOver={(e) => {
          if (e.dataTransfer.types.includes('application/json')) {
            e.preventDefault();
            setIsDragOver(true);
          }
        }}
        onDragLeave={() => setIsDragOver(false)}
        onDrop={handleDrop}
      >
        {/* Track labels column — draggable to resize */}
        <div className="flex-shrink-0 border-r border-border flex flex-col" style={{ width: 48 }}>
          {/* Ruler spacer */}
          <div style={{ height: 24, borderBottom: '1px solid #2e2e2e' }} />

          {/* V1 label — drag bottom edge to resize */}
          <div
            className="relative flex items-center justify-center text-[11px] font-bold text-white/70 select-none"
            style={{
              height: videoTrackHeight,
              borderBottom: '1px solid #2a2a2a',
              background: '#1c2033',
            }}
          >
            V1
            {/* Resize handle at bottom of V1 */}
            <div
              className="absolute bottom-0 left-0 right-0 cursor-ns-resize flex items-center justify-center group"
              style={{ height: 8 }}
              onMouseDown={(e) => {
                e.preventDefault();
                const startY = e.clientY;
                let lastY = startY;
                const onMove = (me: MouseEvent) => {
                  handleResizeV1(me.clientY - lastY);
                  lastY = me.clientY;
                };
                const onUp = () => {
                  window.removeEventListener('mousemove', onMove);
                  window.removeEventListener('mouseup', onUp);
                  document.body.style.cursor = '';
                };
                document.body.style.cursor = 'ns-resize';
                window.addEventListener('mousemove', onMove);
                window.addEventListener('mouseup', onUp);
              }}
            >
              <div className="w-5 h-px bg-white/20 group-hover:bg-accent/70 transition-colors" />
            </div>
          </div>

          {/* A1 label — drag bottom edge to resize */}
          <div
            className="relative flex items-center justify-center text-[11px] font-bold text-white/70 select-none"
            style={{
              height: audioTrackHeight,
              borderBottom: '1px solid #2a2a2a',
              background: '#1c2a1c',
            }}
          >
            A1
            {/* Resize handle at bottom of A1 */}
            <div
              className="absolute bottom-0 left-0 right-0 cursor-ns-resize flex items-center justify-center group"
              style={{ height: 8 }}
              onMouseDown={(e) => {
                e.preventDefault();
                let lastY = e.clientY;
                const onMove = (me: MouseEvent) => {
                  handleResizeA1(me.clientY - lastY);
                  lastY = me.clientY;
                };
                const onUp = () => {
                  window.removeEventListener('mousemove', onMove);
                  window.removeEventListener('mouseup', onUp);
                  document.body.style.cursor = '';
                };
                document.body.style.cursor = 'ns-resize';
                window.addEventListener('mousemove', onMove);
                window.addEventListener('mouseup', onUp);
              }}
            >
              <div className="w-5 h-px bg-white/20 group-hover:bg-accent/70 transition-colors" />
            </div>
          </div>
        </div>

        {/* ── Scrollable track area ─────────────────────────────────────── */}
        <div ref={scrollRef} className="flex-1 overflow-auto">
          <div style={{ width: Math.max(totalWidthPx + 128, 400), minWidth: '100%' }}>

            {/* Ruler */}
            <div
              ref={rulerRef}
              className="relative flex-shrink-0 cursor-col-resize select-none"
              style={{ height: 24, background: '#1a1a1c', borderBottom: '1px solid #2e2e2e' }}
              onMouseDown={handleRulerMouseDown}
              role="slider"
              aria-label="Timeline ruler"
            >
              {ticks.map((ms) => {
                const leftPx = ms * pixelsPerMs;
                const isMajor = ms % (tickIntervalMs * 2) === 0 || tickIntervalMs >= 10_000;
                return (
                  <div key={ms} className="absolute top-0 bottom-0" style={{ left: leftPx }}>
                    <div
                      className="w-px bg-white/20"
                      style={{ height: isMajor ? '100%' : '40%', marginTop: isMajor ? 0 : '60%' }}
                    />
                    {isMajor && (
                      <span
                        className="timecode absolute text-[9px] text-text-muted/60"
                        style={{ left: 3, top: 3 }}
                      >
                        {formatTime(ms)}
                      </span>
                    )}
                  </div>
                );
              })}
              {/* Playhead on ruler */}
              <div
                className="absolute top-0 bottom-0 w-px bg-[#e85757] pointer-events-none"
                style={{ left: playheadMs * pixelsPerMs, zIndex: 10 }}
              />
            </div>

            {/* Tracks container */}
            <div
              ref={tracksRef}
              className={`relative transition-colors ${isDragOver ? 'bg-accent/5' : ''}`}
              style={{ minHeight: totalTracksHeight + 40 }}
              onClick={(e) => {
                // Deselect if click is directly on the container (not a clip)
                if (e.target === tracksRef.current) setSelectedClip(null);
              }}
            >
              {/* V1 — Video track */}
              <div
                className="relative"
                style={{
                  height: videoTrackHeight,
                  borderBottom: '1px solid #2a2a2a',
                  background: 'linear-gradient(180deg, #1a1f35 0%, #161820 100%)',
                }}
                onClick={(e) => {
                  if ((e.target as HTMLElement).closest('.timeline-clip') === null) {
                    setSelectedClip(null);
                  }
                }}
              >
                {videoClips.length === 0 && clips.length === 0 && (
                  <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                    <p className="text-[10px] text-text-muted/40">
                      {isDragOver ? '↓ Drop here' : 'Drag clips from Media Bin'}
                    </p>
                  </div>
                )}
                {videoClips.map((clip) => (
                  <TimelineClipComponent
                    key={clip.id}
                    clip={clip}
                    pixelsPerMs={pixelsPerMs}
                    isSelected={selectedClipIds.includes(clip.id)}
                    onClick={() => setSelectedClip(clip.id)}
                    allClips={clips}
                    selectedClipIds={selectedClipIds}
                    trackHeight={videoTrackHeight}
                    onDelete={handleDeleteClip}
                    onUnlink={handleUnlink}
                  />
                ))}
              </div>

              {/* A1 — Audio track */}
              <div
                className="relative"
                style={{
                  height: audioTrackHeight,
                  borderBottom: '1px solid #2a2a2a',
                  background: 'linear-gradient(180deg, #1a2a1a 0%, #161e16 100%)',
                }}
                onClick={(e) => {
                  if ((e.target as HTMLElement).closest('.timeline-clip') === null) {
                    setSelectedClip(null);
                  }
                }}
              >
                {audioClips.map((clip) => (
                  <TimelineClipComponent
                    key={clip.id}
                    clip={clip}
                    pixelsPerMs={pixelsPerMs}
                    isSelected={selectedClipIds.includes(clip.id)}
                    onClick={() => setSelectedClip(clip.id)}
                    allClips={clips}
                    selectedClipIds={selectedClipIds}
                    trackHeight={audioTrackHeight}
                    onDelete={handleDeleteClip}
                    onUnlink={handleUnlink}
                  />
                ))}
              </div>

              {/* Playhead across all tracks */}
              <PlayheadMarker
                positionPx={playheadMs * pixelsPerMs}
                totalHeightPx={totalTracksHeight}
              />
            </div>
          </div>
        </div>
      </div>

      {/* ── Zoom hint ──────────────────────────────────────────────────────── */}
      <div className="px-3 py-1 flex-shrink-0 border-t border-border flex items-center gap-2">
        <svg className="w-3 h-3 text-text-muted/40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v3m0 0v3m0-3h3m-3 0H7" />
        </svg>
        <span className="text-[9px] text-text-muted/40">Pinch to zoom · Drag V1/A1 edge to resize</span>
      </div>
    </div>
  );
};

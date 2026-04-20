import React, { useEffect, useRef, useState, useCallback } from 'react';
import { useProject, useStore } from '../../store';
import { useTimelineSync } from '../../hooks/useTimelineSync';
import type { TimelineClip, IpcResult } from '../../types';

interface TimelineClipProps {
  clip: TimelineClip;
  pixelsPerMs: number;
  isSelected: boolean;
  onClick: () => void;
  allClips: TimelineClip[];
  selectedClipIds: number[];
  onDelete: (clipId: number) => void;
  onUnlink: (clipId: number) => void;
  trackHeight: number;
}

function formatDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const secs = s % 60;
  return `${m}:${secs.toString().padStart(2, '0')}`;
}

// ─── Waveform hook ──────────────────────────────────────────────────────────
// The backend writes peaks at 50 samples/second as Float32LE binary.
function useWaveform(filePath: string, mediaFileId: number) {
  const [peaks, setPeaks] = useState<Float32Array | null>(null);

  useEffect(() => {
    if (!filePath || mediaFileId === -1) {
      setPeaks(null);
      return;
    }
    let active = true;
    console.log('[Waveform] requesting for', filePath, 'id=', mediaFileId);

    window.electronAPI
      .invoke<IpcResult<string>>(window.electronAPI.channels.MEDIA_WAVEFORM_DATA, {
        filePath,
        mediaFileId,
      })
      .then((res) => {
        if (!active) return;
        if (!res.success) {
          console.error('[Waveform] IPC failed:', res.error);
          return;
        }
        if (!res.data) {
          console.warn('[Waveform] empty data returned');
          return;
        }
        try {
          // Decode base64 → binary → Float32Array
          const binStr = atob(res.data);
          const bytes = new Uint8Array(binStr.length);
          for (let i = 0; i < binStr.length; i++) bytes[i] = binStr.charCodeAt(i);
          const floats = new Float32Array(bytes.buffer);
          console.log('[Waveform] loaded', floats.length, 'peaks for mediaFileId=', mediaFileId);
          if (active) setPeaks(floats);
        } catch (err) {
          console.error('[Waveform] parse error:', err);
        }
      })
      .catch((err) => console.error('[Waveform] invoke error:', err));

    return () => {
      active = false;
    };
  }, [filePath, mediaFileId]);

  return peaks;
}

// ─── Single waveform canvas chunk ───────────────────────────────────────────
const WaveformCanvas: React.FC<{
  peaks: Float32Array;
  startSampleIndex: number;
  widthPx: number;
  heightPx: number;
  pixelsPerSample: number;
}> = ({ peaks, startSampleIndex, widthPx, heightPx, pixelsPerSample }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || widthPx <= 0 || heightPx <= 0) return;

    const dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(widthPx * dpr);
    canvas.height = Math.round(heightPx * dpr);

    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.scale(dpr, dpr);
    ctx.clearRect(0, 0, widthPx, heightPx);
    ctx.fillStyle = 'rgba(255,255,255,0.9)';

    for (let px = 0; px < widthPx; px++) {
      const sampleIdx = startSampleIndex + Math.floor(px / pixelsPerSample);
      const peak = peaks[sampleIdx] ?? 0;
      const h = Math.max(1, peak * heightPx * 0.85);
      const y = (heightPx - h) / 2;
      ctx.fillRect(px, y, 1, h);
    }
  }, [peaks, startSampleIndex, widthPx, heightPx, pixelsPerSample]);

  return (
    <canvas
      ref={canvasRef}
      style={{ width: widthPx, height: heightPx, display: 'block', flexShrink: 0 }}
    />
  );
};

// ─── Waveform renderer (chunked for canvas size limits) ────────────────────
const WaveformRender: React.FC<{
  peaks: Float32Array;
  clipWidthPx: number;
  heightPx: number;
  inPointMs: number;
  pixelsPerMs: number;
}> = ({ peaks, clipWidthPx, heightPx, inPointMs, pixelsPerMs }) => {
  const MAX_CANVAS_WIDTH = 4096; // stay well under browser limit
  const SAMPLES_PER_SEC = 50;   // must match backend ffmpeg -ar 50
  const pixelsPerSample = (pixelsPerMs * 1000) / SAMPLES_PER_SEC;

  // First sample index in the peaks array for the clip's in-point
  const inPointSampleOffset = Math.floor((inPointMs / 1000) * SAMPLES_PER_SEC);

  if (clipWidthPx <= 0 || heightPx <= 0 || peaks.length === 0) return null;

  const numChunks = Math.ceil(clipWidthPx / MAX_CANVAS_WIDTH);

  return (
    <div
      style={{
        position: 'absolute',
        top: 0,
        left: 0,
        width: clipWidthPx,
        height: heightPx,
        pointerEvents: 'none',
        zIndex: 1,
        display: 'flex',
        overflow: 'hidden',
      }}
    >
      {Array.from({ length: numChunks }).map((_, i) => {
        const chunkStartPx = i * MAX_CANVAS_WIDTH;
        const chunkWidthPx = Math.min(MAX_CANVAS_WIDTH, clipWidthPx - chunkStartPx);
        // Convert the chunk's pixel start to a sample index
        const chunkStartSample = inPointSampleOffset + Math.floor(chunkStartPx / pixelsPerSample);

        return (
          <WaveformCanvas
            key={i}
            peaks={peaks}
            startSampleIndex={chunkStartSample}
            widthPx={chunkWidthPx}
            heightPx={heightPx}
            pixelsPerSample={pixelsPerSample}
          />
        );
      })}
    </div>
  );
};

// ─── Context Menu ───────────────────────────────────────────────────────────
interface ContextMenuProps {
  x: number;
  y: number;
  clip: TimelineClip;
  selectedClipIds: number[];
  allClips: TimelineClip[];
  onClose: () => void;
  onDelete: (clipId: number) => void;
  onUnlink: (clipId: number) => void;
  onLink: (clipId1: number, clipId2: number) => void;
}

const ContextMenu: React.FC<ContextMenuProps> = ({
  x,
  y,
  clip,
  selectedClipIds,
  allClips,
  onClose,
  onDelete,
  onUnlink,
  onLink,
}) => {
  const menuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(e.target as Node)) onClose();
    };
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('mousedown', handleClick);
    window.addEventListener('keydown', handleKey);
    return () => {
      window.removeEventListener('mousedown', handleClick);
      window.removeEventListener('keydown', handleKey);
    };
  }, [onClose]);

  const canLink =
    selectedClipIds.length === 2 &&
    selectedClipIds.every((id) => {
      const c = allClips.find((cl) => cl.id === id);
      return c && !c.linkedClipId;
    }) &&
    (() => {
      const types = selectedClipIds.map((id) => allClips.find((cl) => cl.id === id)?.clipType);
      return types.includes('video') && types.includes('audio');
    })();

  const isLinked = !!clip.linkedClipId;

  return (
    <div
      ref={menuRef}
      className="context-menu"
      style={{ left: x, top: y }}
      onContextMenu={(e) => e.preventDefault()}
    >
      <button className="context-menu-item" onClick={() => { onDelete(clip.id); onClose(); }}>
        <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
        </svg>
        Delete{isLinked ? ' (+ linked)' : ''}
      </button>

      {isLinked && (
        <button className="context-menu-item" onClick={() => { onUnlink(clip.id); onClose(); }}>
          <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
          </svg>
          Unlink Audio/Video
        </button>
      )}

      {canLink && (
        <button
          className="context-menu-item"
          onClick={() => { onLink(selectedClipIds[0], selectedClipIds[1]); onClose(); }}
        >
          <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" />
          </svg>
          Link Audio/Video
        </button>
      )}

      <div className="context-menu-separator" />

      <button className="context-menu-item text-text-muted" onClick={onClose}>
        <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 16H6a2 2 0 01-2-2V6a2 2 0 012-2h8a2 2 0 012 2v2m-6 12h8a2 2 0 002-2v-8a2 2 0 00-2-2h-8a2 2 0 00-2 2v8a2 2 0 002 2z" />
        </svg>
        Copy
      </button>
    </div>
  );
};

// ─── Main TimelineClip component ─────────────────────────────────────────────
export const TimelineClipComponent: React.FC<TimelineClipProps> = ({
  clip,
  pixelsPerMs,
  isSelected,
  onClick,
  allClips,
  selectedClipIds,
  onDelete,
  onUnlink,
  trackHeight,
}) => {
  const { mediaFiles } = useProject();
  const { getDeletedRangesForClip, getSavedDurationMs } = useTimelineSync();
  const [contextMenu, setContextMenu] = useState<{ x: number; y: number } | null>(null);

  const mediaFile = mediaFiles.find((f) => f.id === clip.mediaFileId);
  const filename = mediaFile?.filePath.split('/').pop() ?? 'Unknown';

  const clipDurationMs = clip.outPointMs - clip.inPointMs;
  const clipWidthPx = clipDurationMs * pixelsPerMs;
  const clipLeftPx = clip.positionMs * pixelsPerMs;

  const deletedRanges = getDeletedRangesForClip(clip.id);
  const savedMs = getSavedDurationMs(clip.id);

  const isAudio = clip.clipType === 'audio';
  const isLinked = !!clip.linkedClipId;

  // Load waveform for audio clips
  const peaks = useWaveform(
    isAudio && mediaFile ? mediaFile.filePath : '',
    isAudio && mediaFile ? mediaFile.id : -1,
  );

  const handleContextMenu = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault();
      e.stopPropagation();
      setContextMenu({ x: e.clientX, y: e.clientY });
      onClick();
    },
    [onClick],
  );

  const handleLink = useCallback(
    async (id1: number, id2: number) => {
      await window.electronAPI.invoke('clip:updateLink', { clipId: id1, linkedClipId: id2 });
      await window.electronAPI.invoke('clip:updateLink', { clipId: id2, linkedClipId: id1 });
      const { updateClip } = useStore.getState();
      updateClip(id1, { linkedClipId: id2 });
      updateClip(id2, { linkedClipId: id1 });
    },
    [],
  );

  const innerHeight = trackHeight - 8; // 4px top + 4px bottom padding

  return (
    <>
      <div
        className={`timeline-clip ${isAudio ? 'audio-clip' : 'video-clip'} ${isSelected ? 'selected' : ''}`}
        style={{
          left: clipLeftPx,
          width: Math.max(4, clipWidthPx),
          height: innerHeight,
          top: 4,
          position: 'absolute',
          overflow: 'hidden',
          cursor: 'pointer',
          userSelect: 'none',
        }}
        onClick={onClick}
        onContextMenu={handleContextMenu}
        title={`${filename} · ${formatDuration(clipDurationMs)}`}
      >
        {/* Waveform for audio clips */}
        {isAudio && peaks && (
          <WaveformRender
            peaks={peaks}
            clipWidthPx={Math.max(4, clipWidthPx)}
            heightPx={innerHeight}
            inPointMs={clip.inPointMs}
            pixelsPerMs={pixelsPerMs}
          />
        )}

        {/* Clip label bar */}
        <div
          className="absolute bottom-0 left-0 right-0 px-1.5 py-0.5 flex items-center gap-1 min-w-0"
          style={{ zIndex: 2, background: 'rgba(0,0,0,0.25)' }}
        >
          {isLinked && (
            <svg
              className="w-2.5 h-2.5 opacity-80 shrink-0"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2.5}
                d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"
              />
            </svg>
          )}
          <span className="text-[10px] text-white/90 truncate font-medium drop-shadow">
            {filename}
          </span>
          {savedMs > 0 && (
            <span className="ml-auto text-[9px] text-red-300/90 shrink-0 font-medium">
              -{formatDuration(savedMs)}
            </span>
          )}
        </div>

        {/* Deleted regions */}
        {deletedRanges.map((range, i) => {
          const rangeLeft = (range.startMs - clip.inPointMs) * pixelsPerMs;
          const rangeWidth = (range.endMs - range.startMs) * pixelsPerMs;
          return (
            <div
              key={i}
              className="timeline-deleted-region"
              style={{ left: Math.max(0, rangeLeft), width: Math.max(2, rangeWidth) }}
              title={`Cut: ${formatDuration(range.endMs - range.startMs)}`}
            />
          );
        })}
      </div>

      {contextMenu && (
        <ContextMenu
          x={contextMenu.x}
          y={contextMenu.y}
          clip={clip}
          selectedClipIds={selectedClipIds}
          allClips={allClips}
          onClose={() => setContextMenu(null)}
          onDelete={onDelete}
          onUnlink={onUnlink}
          onLink={handleLink}
        />
      )}
    </>
  );
};

import React, { useRef, useCallback, useState } from 'react';
import { useTimeline, usePlayer, useStore, useProject, useModal } from '../../store';
import { useIpc } from '../../hooks/useIpc';
import { TimelineClipComponent } from './TimelineClip';
import { PlayheadMarker } from './PlayheadMarker';
import { Button } from '../ui/Button';
import type { IpcResult, ExportPreset } from '../../types';

const PIXELS_PER_MS = 0.05; // 50px per second
const TRACK_HEIGHT = 64;

function formatTime(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const secs = s % 60;
  return `${m}:${secs.toString().padStart(2, '0')}`;
}

export const Timeline: React.FC = () => {
  const {
    clips,
    playheadMs,
    totalDurationMs,
    selectedClipId,
    setSelectedClip,
    setPlayhead,
    removeClip,
  } = useTimeline();
  const { seek } = usePlayer();
  const { currentProject } = useProject();
  const { openModal } = useModal();
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();
  const rulerRef = useRef<HTMLDivElement>(null);

  const [isCompiling, setIsCompiling] = useState(false);
  const [compileProgress, setCompileProgress] = useState(0);

  // Generate ruler ticks (every 5s)
  const tickIntervalMs = 5000;
  const totalMs = Math.max(totalDurationMs, 30000);
  const totalWidthPx = totalMs * PIXELS_PER_MS;

  const ticks: number[] = [];
  for (let ms = 0; ms <= totalMs; ms += tickIntervalMs) {
    ticks.push(ms);
  }

  const handleRulerClick = useCallback(
    (e: React.MouseEvent<HTMLDivElement>): void => {
      if (!rulerRef.current) return;
      const rect = rulerRef.current.getBoundingClientRect();
      const ms = (e.clientX - rect.left) / PIXELS_PER_MS;
      const clampedMs = Math.max(0, Math.min(ms, totalDurationMs));
      setPlayhead(clampedMs);
      seek(clampedMs);
    },
    [totalDurationMs, setPlayhead, seek],
  );

  const handleCompileEdit = async (): Promise<void> => {
    if (!currentProject) {
      addToast({ type: 'warning', message: 'No active project' });
      return;
    }
    if (clips.length === 0) {
      addToast({ type: 'warning', message: 'No clips in timeline' });
      return;
    }

    // Ask for output path
    const saveResult = await invoke<IpcResult<string | null>>(
      window.electronAPI.channels.APP_OPEN_SAVE_DIALOG,
      {
        defaultPath: `${currentProject.name}_compiled.mp4`,
        filters: [{ name: 'Video', extensions: ['mp4'] }],
      },
    );

    if (!saveResult.success || !saveResult.data) return;
    const outputPath = saveResult.data;

    setIsCompiling(true);
    setCompileProgress(0);

    // Listen for progress
    const cleanup = window.electronAPI.on(
      window.electronAPI.channels.EXPORT_PROGRESS,
      (data: unknown) => {
        const ev = data as { progress: number };
        setCompileProgress(ev.progress);
      },
    );

    try {
      const result = await invoke<IpcResult<{ outputPath: string }>>(
        window.electronAPI.channels.EDIT_COMPILE,
        { projectId: currentProject.id, outputPath },
      );

      if (result.success) {
        addToast({
          type: 'success',
          message: `Compiled to ${outputPath.split('/').pop()}`,
          duration: 6000,
        });
        // Show in finder
        invoke(window.electronAPI.channels.APP_SHOW_IN_FINDER, { filePath: outputPath }).catch(
          () => {},
        );
      } else {
        addToast({ type: 'error', message: result.error });
      }
    } finally {
      cleanup();
      setIsCompiling(false);
      setCompileProgress(0);
    }
  };

  const handleExport = (): void => {
    openModal('export');
  };

  // Group clips by track
  const tracks = [...new Set(clips.map((c) => c.track))].sort();

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-3 pt-3 pb-2 flex-shrink-0 border-b border-border">
        <h2 className="text-xs font-semibold text-text-muted uppercase tracking-wider mb-2">
          Timeline
        </h2>
        <div className="flex gap-2">
          <Button
            variant="primary"
            size="xs"
            onClick={handleCompileEdit}
            loading={isCompiling}
            className="flex-1"
            icon={
              <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M14 10l-2 1m0 0l-2-1m2 1v2.5M20 7l-2 1m2-1l-2-1m2 1v2.5M14 4l-2-1-2 1M4 7l2-1M4 7l2 1M4 7v2.5M12 21l-2-1m2 1l2-1m-2 1v-2.5M6 18l-2-1v-2.5M18 18l2-1v-2.5" />
              </svg>
            }
          >
            Compile Edit
          </Button>
          <Button
            variant="secondary"
            size="xs"
            onClick={handleExport}
            title="Export (⌘E)"
          >
            Export
          </Button>
        </div>

        {/* Compile progress */}
        {isCompiling && (
          <div className="mt-2">
            <div className="progress-bar">
              <div
                className="progress-bar-fill"
                style={{ width: `${compileProgress}%` }}
              />
            </div>
            <p className="text-[10px] text-text-muted mt-1">{compileProgress}% — compiling…</p>
          </div>
        )}
      </div>

      {/* Timeline ruler + tracks */}
      <div className="flex-1 overflow-auto">
        <div style={{ width: Math.max(totalWidthPx + 32, 280), minWidth: '100%' }}>
          {/* Ruler */}
          <div
            ref={rulerRef}
            className="relative flex-shrink-0 cursor-pointer"
            style={{ height: 24, background: '#161616', borderBottom: '1px solid #2e2e2e' }}
            onClick={handleRulerClick}
            role="slider"
            aria-label="Timeline ruler"
          >
            {ticks.map((ms) => (
              <div
                key={ms}
                className="absolute top-0 bottom-0 flex flex-col items-start"
                style={{ left: ms * PIXELS_PER_MS }}
              >
                <div
                  className="w-px bg-border"
                  style={{ height: ms % 10000 === 0 ? '100%' : '50%', marginTop: ms % 10000 === 0 ? 0 : '50%' }}
                />
                {ms % 10000 === 0 && (
                  <span
                    className="timecode text-[9px] text-text-muted absolute"
                    style={{ left: 3, top: 4 }}
                  >
                    {formatTime(ms)}
                  </span>
                )}
              </div>
            ))}

            {/* Playhead on ruler */}
            <div
              className="absolute top-0 bottom-0 w-px bg-accent pointer-events-none z-10"
              style={{ left: playheadMs * PIXELS_PER_MS }}
            />
          </div>

          {/* Tracks */}
          <div className="relative">
            {tracks.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8 gap-2 text-center px-4">
                <svg className="w-8 h-8 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 17V7m0 10a2 2 0 01-2 2H5a2 2 0 01-2-2V7a2 2 0 012-2h2a2 2 0 012 2m0 10a2 2 0 002 2h2a2 2 0 002-2M9 7a2 2 0 012-2h2a2 2 0 012 2m0 10V7m0 10a2 2 0 002 2h2a2 2 0 002-2V7a2 2 0 00-2-2h-2a2 2 0 00-2 2" />
                </svg>
                <p className="text-xs text-text-muted">
                  Add clips from the Media Bin
                </p>
              </div>
            ) : (
              <>
                {tracks.map((track) => {
                  const trackClips = clips.filter((c) => c.track === track);
                  return (
                    <div
                      key={track}
                      className="relative"
                      style={{ height: TRACK_HEIGHT, borderBottom: '1px solid #1e1e1e' }}
                    >
                      {/* Track label */}
                      <div
                        className="absolute left-0 top-0 bottom-0 flex items-center px-1"
                        style={{ width: 0 }}
                      />

                      {/* Clips */}
                      {trackClips.map((clip) => (
                        <TimelineClipComponent
                          key={clip.id}
                          clip={clip}
                          pixelsPerMs={PIXELS_PER_MS}
                          isSelected={selectedClipId === clip.id}
                          onClick={() => setSelectedClip(clip.id)}
                        />
                      ))}
                    </div>
                  );
                })}

                {/* Playhead */}
                <PlayheadMarker
                  positionPx={playheadMs * PIXELS_PER_MS}
                  totalHeightPx={tracks.length * TRACK_HEIGHT}
                />
              </>
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

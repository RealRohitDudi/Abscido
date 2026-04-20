import React, { useState, useCallback } from 'react';
import { useProject, useTimeline, useTranscript, useStore } from '../../store';
import { useIpc } from '../../hooks/useIpc';
import type { MediaFile, IpcResult, TimelineClip } from '../../types';
import { ImportPanel } from './ImportPanel';
import { Button } from '../ui/Button';

function formatDuration(ms: number): string {
  const totalSecs = Math.floor(ms / 1000);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  return `${mins}:${secs.toString().padStart(2, '0')}`;
}

interface MediaCardProps {
  file: MediaFile;
  onAddToTimeline: (file: MediaFile) => void;
  onRemove: (fileId: number) => void;
}

const MediaCard: React.FC<MediaCardProps> = ({ file, onAddToTimeline, onRemove }) => {
  const [thumbnail, setThumbnail] = useState<string | null>(file.thumbnailPath);
  const { invoke } = useIpc();

  React.useEffect(() => {
    if (!thumbnail && file.thumbnailPath) {
      setThumbnail(file.thumbnailPath);
    } else if (!thumbnail) {
      // Try to load thumbnail
      invoke<IpcResult<string>>(window.electronAPI.channels.MEDIA_THUMBNAIL, {
        filePath: file.filePath,
        timeMs: Math.min(1000, file.durationMs / 2),
        mediaFileId: file.id,
      }).then((result) => {
        if (result.success) setThumbnail(result.data);
      }).catch(() => {});
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file.id]);

  const filename = file.filePath.split('/').pop() ?? file.filePath;

  return (
    <div
      className="group card overflow-hidden cursor-pointer hover:border-accent/40 transition-all duration-150"
      draggable
    >
      {/* Thumbnail */}
      <div
        className="relative w-full overflow-hidden bg-black/40 flex items-center justify-center"
        style={{ aspectRatio: '16/9' }}
      >
        {thumbnail ? (
          <img
            src={thumbnail}
            alt={filename}
            className="w-full h-full object-cover"
          />
        ) : (
          <div className="shimmer w-full h-full absolute inset-0" />
        )}
        <div className="absolute bottom-1 right-1 bg-black/70 rounded px-1 py-0.5">
          <span className="timecode text-[10px] text-white">{formatDuration(file.durationMs)}</span>
        </div>
        {/* Hover overlay */}
        <div className="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 transition-opacity flex items-center justify-center gap-2">
          <button
            onClick={(e) => { e.stopPropagation(); onAddToTimeline(file); }}
            className="bg-accent hover:bg-accent-hover text-white text-xs px-2 py-1 rounded-md transition-colors font-medium"
          >
            Add to Timeline
          </button>
        </div>
      </div>

      {/* Info */}
      <div className="px-2 py-1.5 flex items-center justify-between gap-2">
        <div className="min-w-0 flex-1">
          <p className="text-xs text-text-primary truncate font-medium">{filename}</p>
          <p className="text-[10px] text-text-muted mt-0.5">
            {file.width > 0 ? `${file.width}×${file.height}` : ''}{file.fps > 0 ? ` · ${file.fps}fps` : ''}
          </p>
        </div>
        <button
          onClick={(e) => { e.stopPropagation(); onRemove(file.id); }}
          className="opacity-0 group-hover:opacity-100 w-5 h-5 flex items-center justify-center rounded text-text-muted hover:text-danger transition-all"
          aria-label="Remove"
        >
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
    </div>
  );
};

export const MediaBin: React.FC = () => {
  const { mediaFiles, removeMediaFile, currentProject } = useProject();
  const { clips, addClip } = useTimeline();
  const { setTranscribing, setTranscribeProgress, loadTranscript } = useTranscript();
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();

  const handleAddToTimeline = useCallback(
    async (file: MediaFile): Promise<void> => {
      if (!currentProject) return;

      // Calculate position after last clip
      const lastClipEnd = clips.reduce((max, c) => {
        return Math.max(max, c.positionMs + (c.outPointMs - c.inPointMs));
      }, 0);

      try {
        const result = await invoke<IpcResult<TimelineClip>>(
          window.electronAPI.channels.CLIP_ADD,
          {
            projectId: currentProject.id,
            mediaFileId: file.id,
            positionMs: lastClipEnd,
            inPointMs: 0,
            outPointMs: file.durationMs,
            track: 0,
          },
        );

        if (!result.success) {
          addToast({ type: 'error', message: result.error });
          return;
        }

        const clip = result.data;
        addClip(clip);
        addToast({ type: 'success', message: `Added "${file.filePath.split('/').pop()}" to timeline` });
      } catch (err) {
        addToast({ type: 'error', message: 'Failed to add clip to timeline' });
      }
    },
    [currentProject, clips, addClip, addToast, invoke],
  );

  const handleRemove = useCallback(
    (fileId: number): void => {
      removeMediaFile(fileId);
    },
    [removeMediaFile],
  );

  return (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="px-3 pt-3 pb-2 flex-shrink-0">
        <h2 className="text-xs font-semibold text-text-muted uppercase tracking-wider">
          Media Bin
        </h2>
      </div>

      {/* Import button */}
      <ImportPanel />

      {/* File list */}
      <div className="flex-1 overflow-y-auto p-3">
        {mediaFiles.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full gap-3 text-center">
            <div className="w-12 h-12 rounded-full bg-white/5 flex items-center justify-center">
              <svg className="w-6 h-6 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M7 4v16M17 4v16M3 8h4m10 0h4M3 12h18M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
              </svg>
            </div>
            <div>
              <p className="text-xs text-text-muted">No media imported</p>
              <p className="text-[11px] text-text-muted/60 mt-0.5">
                Import video files to get started
              </p>
            </div>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {mediaFiles.map((file) => (
              <MediaCard
                key={file.id}
                file={file}
                onAddToTimeline={handleAddToTimeline}
                onRemove={handleRemove}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

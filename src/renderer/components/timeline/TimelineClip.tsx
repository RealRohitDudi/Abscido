import React from 'react';
import { useTimeline, useProject } from '../../store';
import { useTimelineSync } from '../../hooks/useTimelineSync';
import type { TimelineClip } from '../../types';

interface TimelineClipProps {
  clip: TimelineClip;
  pixelsPerMs: number;
  isSelected: boolean;
  onClick: () => void;
}

function formatDuration(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const secs = s % 60;
  return `${m}:${secs.toString().padStart(2, '0')}`;
}

export const TimelineClipComponent: React.FC<TimelineClipProps> = ({
  clip,
  pixelsPerMs,
  isSelected,
  onClick,
}) => {
  const { mediaFiles } = useProject();
  const { getDeletedRangesForClip, getSavedDurationMs } = useTimelineSync();

  const mediaFile = mediaFiles.find((f) => f.id === clip.mediaFileId);
  const filename = mediaFile?.filePath.split('/').pop() ?? 'Unknown';

  const clipDurationMs = clip.outPointMs - clip.inPointMs;
  const clipWidthPx = clipDurationMs * pixelsPerMs;
  const clipLeftPx = clip.positionMs * pixelsPerMs;

  const deletedRanges = getDeletedRangesForClip(clip.id);
  const savedMs = getSavedDurationMs(clip.id);

  return (
    <div
      className={`timeline-clip ${isSelected ? 'selected' : ''}`}
      style={{
        left: clipLeftPx,
        width: Math.max(4, clipWidthPx),
        top: 4,
        bottom: 4,
        position: 'absolute',
      }}
      onClick={onClick}
      title={`${filename} · ${formatDuration(clipDurationMs)}`}
    >
      {/* Clip label */}
      <div className="px-2 flex items-center gap-1 overflow-hidden min-w-0 w-full">
        <svg className="w-3 h-3 text-white/60 shrink-0" fill="currentColor" viewBox="0 0 24 24">
          <path d="M17 10.5V7c0-.55-.45-1-1-1H4c-.55 0-1 .45-1 1v10c0 .55.45 1 1 1h12c.55 0 1-.45 1-1v-3.5l4 4v-11l-4 4z" />
        </svg>
        <span className="text-[10px] text-white/90 truncate font-medium">{filename}</span>
        {savedMs > 0 && (
          <span className="ml-auto text-[9px] text-danger/80 shrink-0">
            -{formatDuration(savedMs)}
          </span>
        )}
      </div>

      {/* Deleted regions overlay */}
      {deletedRanges.map((range, i) => {
        const rangeLeft = (range.startMs - clip.inPointMs) * pixelsPerMs;
        const rangeWidth = (range.endMs - range.startMs) * pixelsPerMs;
        return (
          <div
            key={i}
            className="timeline-deleted-region"
            style={{
              left: Math.max(0, rangeLeft),
              width: Math.max(2, rangeWidth),
            }}
            title={`Cut: ${formatDuration(range.endMs - range.startMs)}`}
          />
        );
      })}
    </div>
  );
};

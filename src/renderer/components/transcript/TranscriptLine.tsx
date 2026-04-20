import React from 'react';
import type { TranscriptSegment, TranscriptWord } from '../../types';
import { TranscriptWordComponent } from './TranscriptWord';

interface TranscriptLineProps {
  segment: TranscriptSegment;
  words: TranscriptWord[];
  currentTimeMs: number;
  onWordClick: (word: TranscriptWord) => void;
  clipLabel?: string;
}

function formatTimecode(ms: number): string {
  const s = Math.floor(ms / 1000);
  const m = Math.floor(s / 60);
  const secs = s % 60;
  return `${m}:${secs.toString().padStart(2, '0')}`;
}

export const TranscriptLine: React.FC<TranscriptLineProps> = React.memo(
  ({ segment, words, currentTimeMs, onWordClick, clipLabel }) => {
    // Find words that belong to this segment's time range
    const segmentWords = words.filter(
      (w) => w.startMs >= segment.startMs && w.endMs <= segment.endMs + 100,
    );

    // Is this segment currently being played?
    const isActive = currentTimeMs >= segment.startMs && currentTimeMs <= segment.endMs;

    return (
      <div
        className={`flex gap-3 py-1 px-1 rounded-md transition-colors duration-150 ${
          isActive ? 'bg-white/5' : ''
        }`}
        data-segment-id={segment.id}
        data-start-ms={segment.startMs}
      >
        {/* Timecode gutter */}
        <div className="flex-shrink-0 w-12 text-right pt-0.5">
          <span
            className="timecode text-[10px] text-text-muted cursor-pointer hover:text-accent transition-colors"
            onClick={() => onWordClick({ ...segmentWords[0], id: segmentWords[0]?.id ?? 0 })}
            title={`Jump to ${formatTimecode(segment.startMs)}`}
          >
            {formatTimecode(segment.startMs)}
          </span>
        </div>

        {/* Words */}
        <div className="flex-1 leading-relaxed transcript-selectable">
          {segmentWords.length > 0 ? (
            <p className="text-sm text-text-primary leading-loose">
              {segmentWords.map((word, i) => (
                <React.Fragment key={word.id}>
                  <TranscriptWordComponent
                    word={word}
                    currentTimeMs={currentTimeMs}
                    onWordClick={onWordClick}
                  />
                  {i < segmentWords.length - 1 && ' '}
                </React.Fragment>
              ))}
            </p>
          ) : (
            <p className="text-sm text-text-muted italic">{segment.text}</p>
          )}
        </div>
      </div>
    );
  },
);

TranscriptLine.displayName = 'TranscriptLine';

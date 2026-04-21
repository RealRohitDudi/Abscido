import React, { useCallback } from 'react';
import type { TranscriptWord } from '../../types';
import { useTranscript } from '../../store';

interface TranscriptWordProps {
  word: TranscriptWord;
  currentTimeMs: number;
  onWordClick: (word: TranscriptWord) => void;
}

export const TranscriptWordComponent: React.FC<TranscriptWordProps> = React.memo(
  ({ word, currentTimeMs, onWordClick }) => {
    const { deletedWordIds, badTakeWordIds, selectedWordIds, badTakeReviews } = useTranscript();

    const isDeleted = deletedWordIds.has(word.id);
    const isBadTake = badTakeWordIds.has(word.id);
    const isSelected = selectedWordIds.has(word.id);

    // Check if bad take is accepted (treat as deleted)
    const isBadTakeAccepted = isBadTake && badTakeReviews.some(
      (r) => r.wordIds.includes(word.id) && r.status === 'accepted',
    );

    // Is this the currently playing word?
    const isPlaying =
      !isDeleted &&
      currentTimeMs >= word.startMs &&
      currentTimeMs < word.endMs;

    const handleClick = useCallback(
      (e: React.MouseEvent): void => {
        e.stopPropagation();
        onWordClick(word);
      },
      [onWordClick, word],
    );

    let className = 'word-default';
    if (isDeleted || isBadTakeAccepted) {
      className = 'word-deleted';
    } else if (isBadTake) {
      className = 'word-bad-take';
    } else if (isPlaying) {
      className = 'word-playing';
    }

    if (isSelected && !isDeleted) {
      className += ' word-selected';
    }

    return (
      <span
        className={`inline-block ${className}`}
        data-word-id={word.id}
        data-start-ms={word.startMs}
        data-end-ms={word.endMs}
        data-clip-id={word.clipId}
        onClick={handleClick}
        title={isDeleted ? 'Deleted (cut from video)' : isBadTake ? 'AI-flagged bad take' : undefined}
      >
        {word.word}
      </span>
    );
  },
  (prev, next) => {
    // Custom memo comparison: only re-render on state changes that affect this word
    const prevIsDeleted = prev.word.id in prev.word;
    const nextIsDeleted = next.word.id in next.word;
    if (prev.currentTimeMs !== next.currentTimeMs) {
      const wasPlaying =
        prev.currentTimeMs >= prev.word.startMs && prev.currentTimeMs < prev.word.endMs;
      const isNowPlaying =
        next.currentTimeMs >= next.word.startMs && next.currentTimeMs < next.word.endMs;
      if (wasPlaying !== isNowPlaying) return false;
    }
    return (
      prev.word.id === next.word.id &&
      prev.onWordClick === next.onWordClick
    );
  },
);

TranscriptWordComponent.displayName = 'TranscriptWordComponent';

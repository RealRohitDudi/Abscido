import { useCallback, useEffect, useRef } from 'react';
import { useTranscript, useStore } from '../store';
import type { TranscriptWord } from '../types';

/**
 * Core hook for text-based video editing.
 * Manages word selection via the browser Selection API and keyboard shortcuts.
 */
export function useTranscriptEdit() {
  const {
    deletedWordIds,
    selectedWordIds,
    setSelectedWords,
    clearSelection,
    deleteSelectedWords,
    undoDelete,
    redoDelete,
  } = useTranscript();

  const containerRef = useRef<HTMLDivElement | null>(null);

  /**
   * Resolve which word IDs are covered by the current browser selection.
   */
  const resolveSelectionWordIds = useCallback((): number[] => {
    const selection = window.getSelection();
    if (!selection || selection.isCollapsed) return [];

    const container = containerRef.current;
    if (!container) return [];

    const selectedIds: number[] = [];

    // Walk all word spans inside the container
    const wordSpans = container.querySelectorAll('[data-word-id]');
    wordSpans.forEach((span) => {
      const wordId = parseInt(span.getAttribute('data-word-id') ?? '0', 10);
      if (!wordId) return;

      // Check if this span is within the selection range
      const range = selection.getRangeAt(0);
      const spanRange = document.createRange();
      spanRange.selectNode(span);

      const intersects =
        range.compareBoundaryPoints(Range.END_TO_START, spanRange) <= 0 &&
        range.compareBoundaryPoints(Range.START_TO_END, spanRange) >= 0;

      if (intersects && !deletedWordIds.has(wordId)) {
        selectedIds.push(wordId);
      }
    });

    return selectedIds;
  }, [deletedWordIds]);

  /**
   * Handle browser selection changes — sync to Zustand store.
   */
  const handleSelectionChange = useCallback(() => {
    const ids = resolveSelectionWordIds();
    if (ids.length > 0) {
      setSelectedWords(new Set(ids));
    } else {
      // Only clear if selection is truly empty (not just moved)
      const selection = window.getSelection();
      if (!selection || selection.isCollapsed) {
        clearSelection();
      }
    }
  }, [resolveSelectionWordIds, setSelectedWords, clearSelection]);

  /**
   * Handle keyboard shortcuts within the transcript editor.
   */
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      const target = e.target as HTMLElement;
      // Only handle if focus is within the transcript container
      if (!containerRef.current?.contains(target)) return;

      const isMac = navigator.platform.includes('Mac');
      const modifier = isMac ? e.metaKey : e.ctrlKey;

      // Delete/Backspace → cut selected words
      if ((e.key === 'Delete' || e.key === 'Backspace') && selectedWordIds.size > 0) {
        e.preventDefault();
        deleteSelectedWords();
        return;
      }

      // Cmd+Z → undo
      if (modifier && e.key === 'z' && !e.shiftKey) {
        e.preventDefault();
        undoDelete();
        return;
      }

      // Cmd+Shift+Z → redo
      if (modifier && (e.key === 'Z' || (e.key === 'z' && e.shiftKey))) {
        e.preventDefault();
        redoDelete();
        return;
      }
    },
    [selectedWordIds, deleteSelectedWords, undoDelete, redoDelete],
  );

  // Attach selection change listener
  useEffect(() => {
    document.addEventListener('selectionchange', handleSelectionChange);
    return () => document.removeEventListener('selectionchange', handleSelectionChange);
  }, [handleSelectionChange]);

  // Attach keydown listener
  useEffect(() => {
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleKeyDown]);

  /**
   * Click on a word to seek the player to its timestamp.
   */
  const handleWordClick = useCallback(
    (word: TranscriptWord) => {
      if (deletedWordIds.has(word.id)) return;
      // Seek player
      const seekMs = word.startMs;
      const playerSeek = useStore.getState().seek;
      playerSeek(seekMs);
    },
    [deletedWordIds],
  );

  return {
    containerRef,
    handleWordClick,
    selectedWordIds,
    deletedWordIds,
  };
}

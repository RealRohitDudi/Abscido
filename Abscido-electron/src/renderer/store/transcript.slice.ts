import type { StateCreator } from 'zustand';
import type { TranscriptWord, TranscriptSegment, BadTakeReview } from '../types';

// Stack entry for undo/redo
interface UndoEntry {
  type: 'delete' | 'restore';
  wordIds: number[];
}

export interface TranscriptSlice {
  wordsByClipId: Record<number, TranscriptWord[]>;
  segmentsByClipId: Record<number, TranscriptSegment[]>;
  deletedWordIds: Set<number>;
  badTakeWordIds: Set<number>;
  selectedWordIds: Set<number>;
  badTakeReviews: BadTakeReview[];
  undoStack: UndoEntry[];
  redoStack: UndoEntry[];
  isTranscribing: Record<number, boolean>;
  transcribeProgress: Record<number, number>;
  transcribeStage: Record<number, string>;
  isDetectingBadTakes: boolean;

  // Loading transcript data
  loadTranscript: (
    clipId: number,
    words: TranscriptWord[],
    segments: TranscriptSegment[],
  ) => void;
  clearTranscript: (clipId: number) => void;

  // Word selection
  setSelectedWords: (wordIds: Set<number>) => void;
  addSelectedWord: (wordId: number) => void;
  clearSelection: () => void;

  // Deletion (soft delete = cut video)
  deleteSelectedWords: () => void;
  deleteWords: (wordIds: number[]) => void;
  restoreWords: (wordIds: number[]) => void;

  // Undo/redo
  undoDelete: () => void;
  redoDelete: () => void;

  // Bad takes AI flow
  markBadTakes: (reviews: BadTakeReview[]) => void;
  acceptBadTake: (reviewId: string) => void;
  rejectBadTake: (reviewId: string) => void;
  acceptAllBadTakes: () => void;
  rejectAllBadTakes: () => void;
  clearBadTakeReviews: () => void;
  setIsDetectingBadTakes: (detecting: boolean) => void;

  // Transcription status
  setTranscribing: (clipId: number, isTranscribing: boolean) => void;
  setTranscribeProgress: (clipId: number, progress: number, stage: string) => void;

  // Helpers
  getActiveWords: (clipId: number) => TranscriptWord[];
  getWordCount: () => number;
  getDeletedDurationMs: () => number;
}

export const createTranscriptSlice: StateCreator<
  TranscriptSlice,
  [['zustand/devtools', never]],
  [],
  TranscriptSlice
> = (set, get) => ({
  wordsByClipId: {},
  segmentsByClipId: {},
  deletedWordIds: new Set(),
  badTakeWordIds: new Set(),
  selectedWordIds: new Set(),
  badTakeReviews: [],
  undoStack: [],
  redoStack: [],
  isTranscribing: {},
  transcribeProgress: {},
  transcribeStage: {},
  isDetectingBadTakes: false,

  loadTranscript: (clipId, words, segments) =>
    set(
      (state) => ({
        wordsByClipId: { ...state.wordsByClipId, [clipId]: words },
        segmentsByClipId: { ...state.segmentsByClipId, [clipId]: segments },
        // Pre-populate deletedWordIds from loaded state
        deletedWordIds: new Set([
          ...state.deletedWordIds,
          ...words.filter((w) => w.isDeleted).map((w) => w.id),
        ]),
      }),
      false,
      'transcript/loadTranscript',
    ),

  clearTranscript: (clipId) =>
    set(
      (state) => {
        const newWords = { ...state.wordsByClipId };
        const newSegments = { ...state.segmentsByClipId };
        const clipWordIds = new Set((state.wordsByClipId[clipId] ?? []).map((w) => w.id));
        const newDeleted = new Set([...state.deletedWordIds].filter((id) => !clipWordIds.has(id)));
        delete newWords[clipId];
        delete newSegments[clipId];
        return { wordsByClipId: newWords, segmentsByClipId: newSegments, deletedWordIds: newDeleted };
      },
      false,
      'transcript/clearTranscript',
    ),

  setSelectedWords: (wordIds) =>
    set({ selectedWordIds: wordIds }, false, 'transcript/setSelectedWords'),

  addSelectedWord: (wordId) =>
    set(
      (state) => ({ selectedWordIds: new Set([...state.selectedWordIds, wordId]) }),
      false,
      'transcript/addSelectedWord',
    ),

  clearSelection: () =>
    set({ selectedWordIds: new Set() }, false, 'transcript/clearSelection'),

  deleteSelectedWords: () => {
    const { selectedWordIds, deleteWords } = get();
    if (selectedWordIds.size === 0) return;
    deleteWords([...selectedWordIds]);
  },

  deleteWords: (wordIds: number[]) => {
    if (wordIds.length === 0) return;
    set(
      (state) => ({
        deletedWordIds: new Set([...state.deletedWordIds, ...wordIds]),
        selectedWordIds: new Set(),
        undoStack: [...state.undoStack, { type: 'delete', wordIds }],
        redoStack: [], // Clear redo stack on new action
      }),
      false,
      'transcript/deleteWords',
    );

    // Persist to DB
    window.electronAPI.invoke(window.electronAPI.channels.WORDS_SOFT_DELETE, { wordIds })
      .catch((err) => console.error('[TranscriptSlice] Failed to persist deletion:', err));
  },

  restoreWords: (wordIds: number[]) => {
    if (wordIds.length === 0) return;
    set(
      (state) => ({
        deletedWordIds: new Set([...state.deletedWordIds].filter((id) => !wordIds.includes(id))),
      }),
      false,
      'transcript/restoreWords',
    );

    window.electronAPI.invoke(window.electronAPI.channels.WORDS_RESTORE, { wordIds })
      .catch((err) => console.error('[TranscriptSlice] Failed to persist restore:', err));
  },

  undoDelete: () => {
    const { undoStack } = get();
    if (undoStack.length === 0) return;

    const last = undoStack[undoStack.length - 1];
    set(
      (state) => ({
        undoStack: state.undoStack.slice(0, -1),
        redoStack: [...state.redoStack, last],
      }),
      false,
      'transcript/undoDelete',
    );

    if (last.type === 'delete') {
      get().restoreWords(last.wordIds);
    } else {
      get().deleteWords(last.wordIds);
    }
  },

  redoDelete: () => {
    const { redoStack } = get();
    if (redoStack.length === 0) return;

    const last = redoStack[redoStack.length - 1];
    set(
      (state) => ({
        redoStack: state.redoStack.slice(0, -1),
        undoStack: [...state.undoStack, last],
      }),
      false,
      'transcript/redoDelete',
    );

    if (last.type === 'delete') {
      // Re-apply deletion without adding to undo stack again
      set(
        (state) => ({
          deletedWordIds: new Set([...state.deletedWordIds, ...last.wordIds]),
        }),
        false,
        'transcript/redoDeleteApply',
      );
      window.electronAPI.invoke(window.electronAPI.channels.WORDS_SOFT_DELETE, { wordIds: last.wordIds })
        .catch((err) => console.error('[TranscriptSlice] Failed to persist redo:', err));
    } else {
      set(
        (state) => ({
          deletedWordIds: new Set([...state.deletedWordIds].filter((id) => !last.wordIds.includes(id))),
        }),
        false,
        'transcript/redoRestoreApply',
      );
      window.electronAPI.invoke(window.electronAPI.channels.WORDS_RESTORE, { wordIds: last.wordIds })
        .catch((err) => console.error('[TranscriptSlice] Failed to persist redo restore:', err));
    }
  },

  markBadTakes: (reviews) =>
    set(
      (state) => {
        const newBadTakeIds = new Set(state.badTakeWordIds);
        for (const review of reviews) {
          for (const id of review.wordIds) newBadTakeIds.add(id);
        }
        return { badTakeReviews: reviews, badTakeWordIds: newBadTakeIds };
      },
      false,
      'transcript/markBadTakes',
    ),

  acceptBadTake: (reviewId) => {
    const { badTakeReviews } = get();
    const review = badTakeReviews.find((r) => r.id === reviewId);
    if (!review) return;

    set(
      (state) => ({
        badTakeReviews: state.badTakeReviews.map((r) =>
          r.id === reviewId ? { ...r, status: 'accepted' as const } : r,
        ),
        deletedWordIds: new Set([...state.deletedWordIds, ...review.wordIds]),
      }),
      false,
      'transcript/acceptBadTake',
    );

    window.electronAPI.invoke(window.electronAPI.channels.WORDS_SOFT_DELETE, {
      wordIds: review.wordIds,
    }).catch(console.error);
  },

  rejectBadTake: (reviewId) => {
    const { badTakeReviews } = get();
    const review = badTakeReviews.find((r) => r.id === reviewId);
    if (!review) return;

    set(
      (state) => ({
        badTakeReviews: state.badTakeReviews.map((r) =>
          r.id === reviewId ? { ...r, status: 'rejected' as const } : r,
        ),
        badTakeWordIds: new Set([...state.badTakeWordIds].filter((id) => !review.wordIds.includes(id))),
      }),
      false,
      'transcript/rejectBadTake',
    );
  },

  acceptAllBadTakes: () => {
    const { badTakeReviews } = get();
    const pendingWordIds = badTakeReviews
      .filter((r) => r.status === 'pending')
      .flatMap((r) => r.wordIds);

    set(
      (state) => ({
        badTakeReviews: state.badTakeReviews.map((r) =>
          r.status === 'pending' ? { ...r, status: 'accepted' as const } : r,
        ),
        deletedWordIds: new Set([...state.deletedWordIds, ...pendingWordIds]),
      }),
      false,
      'transcript/acceptAllBadTakes',
    );

    if (pendingWordIds.length > 0) {
      window.electronAPI.invoke(window.electronAPI.channels.WORDS_SOFT_DELETE, {
        wordIds: pendingWordIds,
      }).catch(console.error);
    }
  },

  rejectAllBadTakes: () => {
    const { badTakeReviews } = get();
    const pendingWordIds = new Set(
      badTakeReviews.filter((r) => r.status === 'pending').flatMap((r) => r.wordIds),
    );

    set(
      (state) => ({
        badTakeReviews: state.badTakeReviews.map((r) =>
          r.status === 'pending' ? { ...r, status: 'rejected' as const } : r,
        ),
        badTakeWordIds: new Set([...state.badTakeWordIds].filter((id) => !pendingWordIds.has(id))),
      }),
      false,
      'transcript/rejectAllBadTakes',
    );
  },

  clearBadTakeReviews: () =>
    set(
      { badTakeReviews: [], badTakeWordIds: new Set() },
      false,
      'transcript/clearBadTakeReviews',
    ),

  setIsDetectingBadTakes: (detecting) =>
    set({ isDetectingBadTakes: detecting }, false, 'transcript/setIsDetectingBadTakes'),

  setTranscribing: (clipId, isTranscribing) =>
    set(
      (state) => ({
        isTranscribing: { ...state.isTranscribing, [clipId]: isTranscribing },
      }),
      false,
      'transcript/setTranscribing',
    ),

  setTranscribeProgress: (clipId, progress, stage) =>
    set(
      (state) => ({
        transcribeProgress: { ...state.transcribeProgress, [clipId]: progress },
        transcribeStage: { ...state.transcribeStage, [clipId]: stage },
      }),
      false,
      'transcript/setTranscribeProgress',
    ),

  getActiveWords: (clipId: number) => {
    const { wordsByClipId, deletedWordIds } = get();
    const words = wordsByClipId[clipId] ?? [];
    return words.filter((w) => !deletedWordIds.has(w.id));
  },

  getWordCount: () => {
    const { wordsByClipId, deletedWordIds } = get();
    let count = 0;
    for (const words of Object.values(wordsByClipId)) {
      count += words.filter((w) => !deletedWordIds.has(w.id)).length;
    }
    return count;
  },

  getDeletedDurationMs: () => {
    const { wordsByClipId, deletedWordIds } = get();
    let ms = 0;
    for (const words of Object.values(wordsByClipId)) {
      for (const w of words) {
        if (deletedWordIds.has(w.id)) {
          ms += w.endMs - w.startMs;
        }
      }
    }
    return ms;
  },
});

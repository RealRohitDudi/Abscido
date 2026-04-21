import { create } from 'zustand';
import { devtools } from 'zustand/middleware';
import { createProjectSlice, type ProjectSlice } from './project.slice';
import { createTimelineSlice, type TimelineSlice } from './timeline.slice';
import { createTranscriptSlice, type TranscriptSlice } from './transcript.slice';
import { createPlayerSlice, type PlayerSlice } from './player.slice';

// Toast notification state
export interface ToastNotification {
  id: string;
  type: 'success' | 'error' | 'warning' | 'info';
  message: string;
  duration: number;
}

export interface ToastSlice {
  toasts: ToastNotification[];
  addToast: (toast: Omit<ToastNotification, 'id'>) => void;
  removeToast: (id: string) => void;
}

// Modal state
export type ActiveModal = 'settings' | 'export' | 'newProject' | 'openProject' | null;

export interface ModalSlice {
  activeModal: ActiveModal;
  openModal: (modal: ActiveModal) => void;
  closeModal: () => void;
}

// Combined store type
export type RootStore = ProjectSlice &
  TimelineSlice &
  TranscriptSlice &
  PlayerSlice &
  ToastSlice &
  ModalSlice;

export const useStore = create<RootStore>()(
  devtools(
    (...args) => ({
      // Project slice
      ...createProjectSlice(...args),

      // Timeline slice
      ...createTimelineSlice(...args),

      // Transcript slice
      ...createTranscriptSlice(...args),

      // Player slice
      ...createPlayerSlice(...args),

      // Toast slice (inline — small enough)
      toasts: [],
      addToast: (toast) => {
        const id = `toast_${Date.now()}_${Math.random()}`;
        args[0](
          (state) => ({ toasts: [...state.toasts, { ...toast, id }] }),
          false,
          'toast/addToast',
        );
        // Auto-remove after duration
        setTimeout(() => {
          args[0](
            (state) => ({ toasts: state.toasts.filter((t) => t.id !== id) }),
            false,
            'toast/removeToast',
          );
        }, toast.duration || 4000);
      },
      removeToast: (id) => {
        args[0](
          (state) => ({ toasts: state.toasts.filter((t) => t.id !== id) }),
          false,
          'toast/removeToast',
        );
      },

      // Modal slice (inline)
      activeModal: null,
      openModal: (modal) => args[0]({ activeModal: modal }, false, 'modal/openModal'),
      closeModal: () => args[0]({ activeModal: null }, false, 'modal/closeModal'),
    }),
    {
      name: 'AbscidoStore',
      enabled: process.env.NODE_ENV !== 'production',
    },
  ),
);

// Convenience selectors
export const useProject = () =>
  useStore((s) => ({
    currentProject: s.currentProject,
    mediaFiles: s.mediaFiles,
    isLoadingProject: s.isLoadingProject,
    projectError: s.projectError,
    setProject: s.setProject,
    setMediaFiles: s.setMediaFiles,
    addMediaFile: s.addMediaFile,
    removeMediaFile: s.removeMediaFile,
    createProject: s.createProject,
    loadProject: s.loadProject,
    saveProject: s.saveProject,
    clearProject: s.clearProject,
  }));

export const useTimeline = () =>
  useStore((s) => ({
    clips: s.clips,
    playheadMs: s.playheadMs,
    isPlaying: s.isPlaying,
    totalDurationMs: s.totalDurationMs,
    selectedClipId: s.selectedClipId,
    selectedClipIds: s.selectedClipIds,
    setClips: s.setClips,
    addClip: s.addClip,
    addClips: s.addClips,
    removeClip: s.removeClip,
    removeClips: s.removeClips,
    updateClip: s.updateClip,
    trimClip: s.trimClip,
    setPlayhead: s.setPlayhead,
    setIsPlaying: s.setIsPlaying,
    setSelectedClip: s.setSelectedClip,
    setSelectedClipIds: s.setSelectedClipIds,
    seekTo: s.seekTo,
  }));

export const useTranscript = () =>
  useStore((s) => ({
    wordsByClipId: s.wordsByClipId,
    segmentsByClipId: s.segmentsByClipId,
    deletedWordIds: s.deletedWordIds,
    badTakeWordIds: s.badTakeWordIds,
    selectedWordIds: s.selectedWordIds,
    badTakeReviews: s.badTakeReviews,
    undoStack: s.undoStack,
    redoStack: s.redoStack,
    isTranscribing: s.isTranscribing,
    transcribeProgress: s.transcribeProgress,
    transcribeStage: s.transcribeStage,
    isDetectingBadTakes: s.isDetectingBadTakes,
    loadTranscript: s.loadTranscript,
    clearTranscript: s.clearTranscript,
    setSelectedWords: s.setSelectedWords,
    clearSelection: s.clearSelection,
    deleteSelectedWords: s.deleteSelectedWords,
    deleteWords: s.deleteWords,
    restoreWords: s.restoreWords,
    undoDelete: s.undoDelete,
    redoDelete: s.redoDelete,
    markBadTakes: s.markBadTakes,
    acceptBadTake: s.acceptBadTake,
    rejectBadTake: s.rejectBadTake,
    acceptAllBadTakes: s.acceptAllBadTakes,
    rejectAllBadTakes: s.rejectAllBadTakes,
    clearBadTakeReviews: s.clearBadTakeReviews,
    setIsDetectingBadTakes: s.setIsDetectingBadTakes,
    setTranscribing: s.setTranscribing,
    setTranscribeProgress: s.setTranscribeProgress,
    getActiveWords: s.getActiveWords,
    getWordCount: s.getWordCount,
    getDeletedDurationMs: s.getDeletedDurationMs,
  }));

export const usePlayer = () =>
  useStore((s) => ({
    currentTimeMs: s.currentTimeMs,
    durationMs: s.durationMs,
    volume: s.volume,
    playbackRate: s.playbackRate,
    isPlaying: s.isPlaying,
    isMuted: s.isMuted,
    videoRef: s.videoRef,
    setCurrentTime: s.setCurrentTime,
    setDuration: s.setDuration,
    setVolume: s.setVolume,
    setPlaybackRate: s.setPlaybackRate,
    setIsPlaying: s.setIsPlaying,
    setVideoRef: s.setVideoRef,
    play: s.play,
    pause: s.pause,
    togglePlay: s.togglePlay,
    seek: s.seek,
    toggleMute: s.toggleMute,
  }));

export const useToasts = () => useStore((s) => ({ toasts: s.toasts, addToast: s.addToast, removeToast: s.removeToast }));
export const useModal = () => useStore((s) => ({ activeModal: s.activeModal, openModal: s.openModal, closeModal: s.closeModal }));

import type { StateCreator } from 'zustand';
import type { TimelineClip } from '../types';

export interface TimelineSlice {
  clips: TimelineClip[];
  playheadMs: number;
  isPlaying: boolean;
  totalDurationMs: number;
  selectedClipId: number | null;

  setClips: (clips: TimelineClip[]) => void;
  addClip: (clip: TimelineClip) => void;
  removeClip: (clipId: number) => void;
  updateClip: (clipId: number, updates: Partial<TimelineClip>) => void;
  trimClip: (clipId: number, inPointMs: number, outPointMs: number) => void;
  setPlayhead: (ms: number) => void;
  setIsPlaying: (playing: boolean) => void;
  setSelectedClip: (clipId: number | null) => void;
  seekTo: (ms: number) => void;
  calculateTotalDuration: () => void;
}

export const createTimelineSlice: StateCreator<
  TimelineSlice,
  [['zustand/devtools', never]],
  [],
  TimelineSlice
> = (set, get) => ({
  clips: [],
  playheadMs: 0,
  isPlaying: false,
  totalDurationMs: 0,
  selectedClipId: null,

  setClips: (clips) => {
    set({ clips }, false, 'timeline/setClips');
    get().calculateTotalDuration();
  },

  addClip: (clip) => {
    set(
      (state) => ({ clips: [...state.clips, clip] }),
      false,
      'timeline/addClip',
    );
    get().calculateTotalDuration();
  },

  removeClip: (clipId) => {
    set(
      (state) => ({ clips: state.clips.filter((c) => c.id !== clipId) }),
      false,
      'timeline/removeClip',
    );
    get().calculateTotalDuration();
  },

  updateClip: (clipId, updates) =>
    set(
      (state) => ({
        clips: state.clips.map((c) => (c.id === clipId ? { ...c, ...updates } : c)),
      }),
      false,
      'timeline/updateClip',
    ),

  trimClip: (clipId, inPointMs, outPointMs) => {
    set(
      (state) => ({
        clips: state.clips.map((c) =>
          c.id === clipId ? { ...c, inPointMs, outPointMs } : c,
        ),
      }),
      false,
      'timeline/trimClip',
    );
    get().calculateTotalDuration();
  },

  setPlayhead: (ms) => set({ playheadMs: ms }, false, 'timeline/setPlayhead'),

  setIsPlaying: (playing) => set({ isPlaying: playing }, false, 'timeline/setIsPlaying'),

  setSelectedClip: (clipId) =>
    set({ selectedClipId: clipId }, false, 'timeline/setSelectedClip'),

  seekTo: (ms) => set({ playheadMs: ms }, false, 'timeline/seekTo'),

  calculateTotalDuration: () => {
    const { clips } = get();
    if (clips.length === 0) {
      set({ totalDurationMs: 0 }, false, 'timeline/calculateTotalDuration');
      return;
    }
    const total = clips.reduce((max, clip) => {
      const clipEnd = clip.positionMs + (clip.outPointMs - clip.inPointMs);
      return Math.max(max, clipEnd);
    }, 0);
    set({ totalDurationMs: total }, false, 'timeline/calculateTotalDuration');
  },
});

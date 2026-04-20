import type { StateCreator } from 'zustand';
import type { TimelineClip } from '../types';

export interface TimelineSlice {
  clips: TimelineClip[];
  playheadMs: number;
  isPlaying: boolean;
  totalDurationMs: number;
  selectedClipId: number | null; // Primary selected clip
  selectedClipIds: number[];     // All selected (includes linked pair)

  setClips: (clips: TimelineClip[]) => void;
  addClip: (clip: TimelineClip) => void;
  addClips: (clips: TimelineClip[]) => void;
  removeClip: (clipId: number) => void;
  removeClips: (clipIds: number[]) => void;
  updateClip: (clipId: number, updates: Partial<TimelineClip>) => void;
  trimClip: (clipId: number, inPointMs: number, outPointMs: number) => void;
  setPlayhead: (ms: number) => void;
  setIsPlaying: (playing: boolean) => void;
  setSelectedClip: (clipId: number | null) => void;
  setSelectedClipIds: (clipIds: number[]) => void;
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
  selectedClipIds: [],

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

  addClips: (clips) => {
    set(
      (state) => ({ clips: [...state.clips, ...clips] }),
      false,
      'timeline/addClips',
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

  removeClips: (clipIds) => {
    const idSet = new Set(clipIds);
    set(
      (state) => ({ clips: state.clips.filter((c) => !idSet.has(c.id)) }),
      false,
      'timeline/removeClips',
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

  setSelectedClip: (clipId) => {
    const { clips } = get();
    if (clipId === null) {
      set({ selectedClipId: null, selectedClipIds: [] }, false, 'timeline/setSelectedClip');
      return;
    }
    // Find the clip and its linked partner
    const clip = clips.find((c) => c.id === clipId);
    const ids = [clipId];
    if (clip?.linkedClipId) {
      ids.push(clip.linkedClipId);
    }
    set({ selectedClipId: clipId, selectedClipIds: ids }, false, 'timeline/setSelectedClip');
  },

  setSelectedClipIds: (clipIds) =>
    set({ selectedClipIds: clipIds, selectedClipId: clipIds[0] ?? null }, false, 'timeline/setSelectedClipIds'),

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

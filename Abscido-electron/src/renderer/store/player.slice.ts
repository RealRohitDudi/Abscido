import type { StateCreator } from 'zustand';

export interface PlayerSlice {
  currentTimeMs: number;
  durationMs: number;
  volume: number;
  playbackRate: number;
  isPlaying: boolean;
  isMuted: boolean;
  videoRef: HTMLVideoElement | null;

  setCurrentTime: (ms: number) => void;
  setDuration: (ms: number) => void;
  setVolume: (volume: number) => void;
  setPlaybackRate: (rate: number) => void;
  setIsPlaying: (playing: boolean) => void;
  setIsMuted: (muted: boolean) => void;
  setVideoRef: (ref: HTMLVideoElement | null) => void;
  play: () => void;
  pause: () => void;
  togglePlay: () => void;
  seek: (ms: number) => void;
  toggleMute: () => void;
}

export const createPlayerSlice: StateCreator<
  PlayerSlice,
  [['zustand/devtools', never]],
  [],
  PlayerSlice
> = (set, get) => ({
  currentTimeMs: 0,
  durationMs: 0,
  volume: 1,
  playbackRate: 1,
  isPlaying: false,
  isMuted: false,
  videoRef: null,

  setCurrentTime: (ms) => set({ currentTimeMs: ms }, false, 'player/setCurrentTime'),

  setDuration: (ms) => set({ durationMs: ms }, false, 'player/setDuration'),

  setVolume: (volume) => {
    const { videoRef } = get();
    if (videoRef) videoRef.volume = volume;
    set({ volume }, false, 'player/setVolume');
  },

  setPlaybackRate: (rate) => {
    const { videoRef } = get();
    if (videoRef) videoRef.playbackRate = rate;
    set({ playbackRate: rate }, false, 'player/setPlaybackRate');
  },

  setIsPlaying: (playing) => set({ isPlaying: playing }, false, 'player/setIsPlaying'),

  setIsMuted: (muted) => {
    const { videoRef } = get();
    if (videoRef) videoRef.muted = muted;
    set({ isMuted: muted }, false, 'player/setIsMuted');
  },

  setVideoRef: (ref) => set({ videoRef: ref }, false, 'player/setVideoRef'),

  play: () => {
    const { videoRef } = get();
    if (videoRef) {
      videoRef.play().catch((err) => console.warn('[Player] Play failed:', err));
    }
    set({ isPlaying: true }, false, 'player/play');
  },

  pause: () => {
    const { videoRef } = get();
    if (videoRef) videoRef.pause();
    set({ isPlaying: false }, false, 'player/pause');
  },

  togglePlay: () => {
    const { isPlaying, play, pause } = get();
    if (isPlaying) pause();
    else play();
  },

  seek: (ms: number) => {
    const { videoRef } = get();
    if (videoRef) {
      videoRef.currentTime = ms / 1000;
    }
    set({ currentTimeMs: ms }, false, 'player/seek');
  },

  toggleMute: () => {
    const { isMuted, setIsMuted } = get();
    setIsMuted(!isMuted);
  },
});

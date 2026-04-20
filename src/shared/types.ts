// ─── Domain Types ──────────────────────────────────────────────────────────────

export interface Project {
  id: number;
  name: string;
  createdAt: string;
  updatedAt: string;
  exportPath: string | null;
}

export interface MediaFile {
  id: number;
  projectId: number;
  filePath: string;
  durationMs: number;
  width: number;
  height: number;
  fps: number;
  codec: string;
  thumbnailPath: string | null;
  createdAt: string;
}

export interface TimelineClip {
  id: number;
  projectId: number;
  mediaFileId: number;
  positionMs: number;
  inPointMs: number;
  outPointMs: number;
  track: number;
  isDeleted: boolean;
  createdAt: string;
}

export interface TranscriptWord {
  id: number;
  clipId: number;
  word: string;
  startMs: number;
  endMs: number;
  confidence: number;
  speaker: string | null;
  isDeleted: boolean;
}

export interface TranscriptSegment {
  id: number;
  clipId: number;
  text: string;
  startMs: number;
  endMs: number;
  isDeleted: boolean;
}

// ─── Transcript Result ─────────────────────────────────────────────────────────

export interface TranscriptResult {
  clipId: number;
  words: TranscriptWord[];
  segments: TranscriptSegment[];
}

// ─── Bad Take Detection ────────────────────────────────────────────────────────

export interface BadTakeResult {
  wordIds: number[];
  reason: string;
}

export interface BadTakeReview {
  id: string;
  wordIds: number[];
  reason: string;
  status: 'pending' | 'accepted' | 'rejected';
}

// ─── Edit Decision List ────────────────────────────────────────────────────────

export interface EDLSegment {
  startMs: number;
  endMs: number;
}

export interface EDLClip {
  clipId: number;
  mediaFilePath: string;
  segments: EDLSegment[];
}

export interface EditDecisionList {
  projectId: number;
  clips: EDLClip[];
}

// ─── Export ────────────────────────────────────────────────────────────────────

export type ExportQuality = 'low' | 'medium' | 'high' | 'lossless';
export type ExportFormat = 'mp4' | 'mov' | 'webm';

export interface ExportPreset {
  format: ExportFormat;
  quality: ExportQuality;
  width?: number;
  height?: number;
  fps?: number;
  bitrate?: string;
}

// ─── Media Info ────────────────────────────────────────────────────────────────

export interface MediaStream {
  codecType: string;
  codecName: string;
  width?: number;
  height?: number;
  fps?: number;
  sampleRate?: number;
  channels?: number;
}

export interface MediaInfo {
  filePath: string;
  durationMs: number;
  width: number;
  height: number;
  fps: number;
  codec: string;
  bitrate: number;
  size: number;
  streams: MediaStream[];
}

// ─── Full Project State ────────────────────────────────────────────────────────

export interface FullProjectState {
  project: Project;
  mediaFiles: MediaFile[];
  clips: TimelineClip[];
  transcriptWords: Record<number, TranscriptWord[]>;
  transcriptSegments: Record<number, TranscriptSegment[]>;
}

export interface PartialProjectState {
  clips?: Partial<TimelineClip>[];
  mediaFiles?: Partial<MediaFile>[];
}

// ─── IPC Result Wrappers ───────────────────────────────────────────────────────

export interface IpcSuccess<T> {
  success: true;
  data: T;
}

export interface IpcError {
  success: false;
  error: string;
  code: string;
}

export type IpcResult<T> = IpcSuccess<T> | IpcError;

// ─── Settings ─────────────────────────────────────────────────────────────────

export interface AppSettings {
  openaiApiKey: string;
  anthropicApiKey: string;
  defaultLanguage: string;
  defaultExportPath: string;
}

// ─── Progress Events ───────────────────────────────────────────────────────────

export interface TranscribeProgressEvent {
  clipId: number;
  progress: number;
  stage: 'extracting' | 'uploading' | 'transcribing' | 'saving';
}

export interface ExportProgressEvent {
  progress: number;
  eta: number;
  stage: 'compiling' | 'encoding' | 'muxing';
}

// ─── Language Support ─────────────────────────────────────────────────────────

export interface SupportedLanguage {
  code: string;
  name: string;
}

export const SUPPORTED_LANGUAGES: SupportedLanguage[] = [
  { code: 'en', name: 'English' },
  { code: 'es', name: 'Spanish' },
  { code: 'fr', name: 'French' },
  { code: 'de', name: 'German' },
  { code: 'hi', name: 'Hindi' },
  { code: 'ja', name: 'Japanese' },
  { code: 'pt', name: 'Portuguese' },
  { code: 'ar', name: 'Arabic' },
  { code: 'zh', name: 'Chinese (Simplified)' },
  { code: 'ko', name: 'Korean' },
  { code: 'it', name: 'Italian' },
  { code: 'nl', name: 'Dutch' },
];

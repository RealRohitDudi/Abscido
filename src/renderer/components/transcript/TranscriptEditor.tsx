import React, { useEffect, useCallback, useState, useRef } from 'react';
import { useTranscript, useTimeline, usePlayer, useProject, useStore } from '../../store';
import { useTranscriptEdit } from '../../hooks/useTranscriptEdit';
import { useIpc, useIpcListener } from '../../hooks/useIpc';
import { TranscriptLine } from './TranscriptLine';
import { BadTakeHighlight } from './BadTakeHighlight';
import { Button } from '../ui/Button';
import { Progress } from '../ui/Progress';
import type {
  TranscriptWord,
  TranscriptResult,
  BadTakeResult,
  BadTakeReview,
  IpcResult,
  TranscribeProgressEvent,
} from '../../types';
import { SUPPORTED_LANGUAGES } from '../../../shared/types';

// ─── Local model types (mirrors whisper-local.service.ts) ───────────────────

interface WhisperLocalModel {
  id: string;
  label: string;
  sizeLabel: string;
  sizeMB: number;
  englishOnly: boolean;
  isDownloaded: boolean;
}

// ─── Model Manager Panel ────────────────────────────────────────────────────

const ModelManagerPanel: React.FC<{
  selectedModelId: string;
  onSelect: (id: string) => void;
}> = ({ selectedModelId, onSelect }) => {
  const { invoke } = useIpc();
  const addToast = useStore((s) => s.addToast);
  const [models, setModels] = useState<WhisperLocalModel[]>([]);
  const [downloading, setDownloading] = useState<string | null>(null);
  const [dlProgress, setDlProgress] = useState(0);
  const [dlStatus, setDlStatus] = useState('');

  // Refresh model list
  const refresh = useCallback(async () => {
    const res = await invoke<IpcResult<WhisperLocalModel[]>>(
      window.electronAPI.channels.WHISPER_LOCAL_LIST_MODELS,
    );
    if (res.success) setModels(res.data);
  }, [invoke]);

  useEffect(() => { void refresh(); }, [refresh]);

  // Listen for download progress
  useIpcListener<{ modelId: string; progress: number; status: string }>(
    window.electronAPI?.channels?.WHISPER_LOCAL_DOWNLOAD_PROGRESS ?? 'whisper-local:downloadProgress',
    ({ modelId, progress, status }) => {
      if (modelId === downloading) {
        setDlProgress(progress);
        setDlStatus(status);
        if (progress >= 100) {
          setDownloading(null);
          void refresh();
        }
      }
    },
  );

  const handleDownload = async (modelId: string) => {
    setDownloading(modelId);
    setDlProgress(0);
    setDlStatus('Starting…');
    const res = await invoke<IpcResult<null>>(
      window.electronAPI.channels.WHISPER_LOCAL_DOWNLOAD_MODEL,
      { modelId },
    );
    if (!res.success) {
      addToast({ type: 'error', message: res.error });
      setDownloading(null);
    }
    await refresh();
  };

  const handleDelete = async (modelId: string) => {
    await invoke(window.electronAPI.channels.WHISPER_LOCAL_DELETE_MODEL, { modelId });
    if (selectedModelId === modelId) onSelect('');
    await refresh();
    addToast({ type: 'info', message: 'Model deleted' });
  };

  return (
    <div
      className="flex-shrink-0 border-b border-border"
      style={{ background: '#111', maxHeight: 240, overflowY: 'auto' }}
    >
      <div className="px-4 py-2 flex items-center justify-between">
        <span className="text-[10px] text-text-muted uppercase tracking-wider font-semibold">
          On-Device Models
        </span>
        <button
          onClick={refresh}
          className="text-text-muted hover:text-text-primary text-[10px] transition-colors"
        >
          ↻ Refresh
        </button>
      </div>

      <div className="px-3 pb-3 space-y-1.5">
        {models.map((m) => {
          const isSelected = selectedModelId === m.id;
          const isDl = downloading === m.id;

          return (
            <div
              key={m.id}
              onClick={() => m.isDownloaded && onSelect(m.id)}
              className={`rounded-lg px-3 py-2 flex items-center gap-3 transition-all cursor-pointer ${
                isSelected
                  ? 'bg-accent/20 border border-accent/40'
                  : 'bg-white/4 border border-transparent hover:border-white/10'
              } ${!m.isDownloaded ? 'opacity-70 cursor-default' : ''}`}
            >
              {/* Selection dot */}
              <div
                className={`w-2 h-2 rounded-full flex-shrink-0 transition-colors ${
                  isSelected ? 'bg-accent' : 'bg-white/20'
                }`}
              />

              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-medium text-text-primary truncate">
                    {m.label}
                  </span>
                  <span className="text-[10px] text-text-muted">{m.sizeLabel}</span>
                  {m.englishOnly && (
                    <span className="text-[9px] bg-white/8 text-text-muted px-1 rounded">EN</span>
                  )}
                </div>

                {/* Download progress */}
                {isDl && (
                  <div className="mt-1">
                    <Progress value={dlProgress} label={dlStatus} showPercent animated size="xs" />
                  </div>
                )}
              </div>

              {/* Action button */}
              <div className="flex-shrink-0">
                {m.isDownloaded ? (
                  <button
                    onClick={(e) => { e.stopPropagation(); void handleDelete(m.id); }}
                    className="text-[10px] text-danger/60 hover:text-danger px-1.5 py-0.5 rounded transition-colors"
                  >
                    Delete
                  </button>
                ) : isDl ? (
                  <span className="text-[10px] text-accent animate-pulse">{dlProgress}%</span>
                ) : (
                  <button
                    onClick={(e) => { e.stopPropagation(); void handleDownload(m.id); }}
                    className="text-[10px] text-accent hover:text-accent-hover px-1.5 py-0.5 rounded border border-accent/30 hover:border-accent/60 transition-colors"
                  >
                    Download
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};

// ─── Main component ──────────────────────────────────────────────────────────

export const TranscriptEditor: React.FC = () => {
  const {
    wordsByClipId, segmentsByClipId, deletedWordIds, selectedWordIds,
    undoStack, redoStack, isTranscribing, transcribeProgress, transcribeStage,
    isDetectingBadTakes, loadTranscript, deleteSelectedWords, undoDelete,
    redoDelete, setTranscribing, setTranscribeProgress, markBadTakes,
    setIsDetectingBadTakes, getWordCount, getDeletedDurationMs,
  } = useTranscript();

  const { clips, selectedClipId } = useTimeline();
  const { currentTimeMs } = usePlayer();
  const { currentProject, mediaFiles } = useProject();
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();
  const { containerRef, handleWordClick } = useTranscriptEdit();

  const [selectedLanguage, setSelectedLanguage] = useState('en');
  const [transcribeMode, setTranscribeMode] = useState<'cloud' | 'local'>('cloud');
  const [selectedLocalModel, setSelectedLocalModel] = useState('');
  const [localProgress, setLocalProgress] = useState(0);
  const [localStatus, setLocalStatus] = useState('');
  const [isLocalTranscribing, setIsLocalTranscribing] = useState(false);
  const isCancelledRef = useRef(false);

  const handleCancelTranscription = useCallback(() => {
    isCancelledRef.current = true;
    window.electronAPI.send('transcribe:cancel');
    addToast({ type: 'info', message: 'Cancelling transcription...' });
  }, [addToast]);

  // Listen for cloud transcription progress
  useIpcListener<TranscribeProgressEvent>(
    window.electronAPI?.channels?.TRANSCRIBE_PROGRESS ?? 'transcribe:progress',
    (data) => { setTranscribeProgress(data.clipId, data.progress, data.stage); },
  );

  // Listen for local transcription progress
  useIpcListener<{ clipId: number; progress: number; status: string }>(
    window.electronAPI?.channels?.WHISPER_LOCAL_TRANSCRIBE_PROGRESS ?? 'whisper-local:transcribeProgress',
    ({ progress, status }) => { setLocalProgress(progress); setLocalStatus(status); },
  );

  // ─── Cloud transcribe ────────────────────────────────────────────────────

  const handleTranscribeAll = useCallback(async (): Promise<void> => {
    if (!currentProject) { addToast({ type: 'warning', message: 'No active project' }); return; }
    const clipsToTranscribe = clips.filter((c) => !wordsByClipId[c.id]?.length);
    if (clipsToTranscribe.length === 0) { addToast({ type: 'info', message: 'All clips already transcribed' }); return; }

    isCancelledRef.current = false;

    for (const clip of clipsToTranscribe) {
      if (isCancelledRef.current) break;
      const mediaFile = mediaFiles.find((f) => f.id === clip.mediaFileId);
      if (!mediaFile) continue;
      setTranscribing(clip.id, true);
      try {
        const result = await invoke<IpcResult<TranscriptResult>>(
          window.electronAPI.channels.TRANSCRIBE_CLIP,
          { clipId: clip.id, mediaFilePath: mediaFile.filePath, language: selectedLanguage },
        );
        if (result.success) {
          loadTranscript(clip.id, result.data.words, result.data.segments);
          addToast({ type: 'success', message: `Transcribed ${mediaFile.filePath.split('/').pop()}` });
        } else if (result.error !== 'CANCELLED_BY_USER') {
          addToast({ type: 'error', message: result.error });
        }
      } finally {
        setTranscribing(clip.id, false);
      }
    }
  }, [currentProject, clips, wordsByClipId, mediaFiles, selectedLanguage, setTranscribing, loadTranscript, addToast, invoke]);

  // ─── Local transcribe ────────────────────────────────────────────────────

  const handleLocalTranscribeAll = useCallback(async (): Promise<void> => {
    if (!currentProject) { addToast({ type: 'warning', message: 'No active project' }); return; }
    if (!selectedLocalModel) { addToast({ type: 'warning', message: 'Select a downloaded model first' }); return; }

    const clipsToTranscribe = clips.filter((c) => !wordsByClipId[c.id]?.length);
    if (clipsToTranscribe.length === 0) { addToast({ type: 'info', message: 'All clips already transcribed' }); return; }

    setIsLocalTranscribing(true);
    setLocalProgress(0);
    setLocalStatus('Starting…');
    isCancelledRef.current = false;

    for (const clip of clipsToTranscribe) {
      if (isCancelledRef.current) break;
      const mediaFile = mediaFiles.find((f) => f.id === clip.mediaFileId);
      if (!mediaFile) continue;

      try {
        const result = await invoke<IpcResult<TranscriptResult>>(
          window.electronAPI.channels.WHISPER_LOCAL_TRANSCRIBE,
          {
            clipId: clip.id,
            mediaFilePath: mediaFile.filePath,
            modelId: selectedLocalModel,
            language: selectedLanguage === 'auto' ? 'auto' : selectedLanguage,
          },
        );
        if (result.success) {
          loadTranscript(clip.id, result.data.words, result.data.segments);
          addToast({ type: 'success', message: `Transcribed (on-device): ${mediaFile.filePath.split('/').pop()}` });
        } else if (result.error !== 'CANCELLED_BY_USER') {
          addToast({ type: 'error', message: result.error });
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (!msg.includes('CANCELLED_BY_USER')) {
          addToast({ type: 'error', message: msg || 'Local transcription failed' });
        }
      }
    }

    setIsLocalTranscribing(false);
  }, [currentProject, clips, wordsByClipId, mediaFiles, selectedLanguage, selectedLocalModel, setIsLocalTranscribing, loadTranscript, addToast, invoke]);

  // ─── Bad takes ───────────────────────────────────────────────────────────

  const handleRemoveBadTakes = useCallback(async (): Promise<void> => {
    if (!currentProject) { addToast({ type: 'warning', message: 'No active project' }); return; }
    const allWords: TranscriptWord[] = [];
    for (const clipId of Object.keys(wordsByClipId).map(Number)) {
      allWords.push(...(wordsByClipId[clipId] ?? []).filter((w) => !deletedWordIds.has(w.id)));
    }
    if (allWords.length === 0) { addToast({ type: 'warning', message: 'Transcribe clips first' }); return; }
    setIsDetectingBadTakes(true);
    try {
      const result = await invoke<IpcResult<BadTakeResult[]>>(
        window.electronAPI.channels.AI_REMOVE_BAD_TAKES,
        { transcriptJson: JSON.stringify(allWords.map((w) => ({ word_id: w.id, text: w.word, start_ms: w.startMs, end_ms: w.endMs })), null, 2) },
      );
      if (!result.success) { addToast({ type: 'error', message: result.error }); return; }
      if (result.data.length === 0) { addToast({ type: 'success', message: 'No bad takes detected!' }); return; }
      markBadTakes(result.data.map((bt, i) => ({ id: `badtake_${i}_${Date.now()}`, wordIds: bt.wordIds, reason: bt.reason, status: 'pending' as const })));
      addToast({ type: 'info', message: `Found ${result.data.length} bad take(s) — review below`, duration: 5000 });
    } finally {
      setIsDetectingBadTakes(false);
    }
  }, [currentProject, wordsByClipId, deletedWordIds, setIsDetectingBadTakes, markBadTakes, addToast, invoke]);

  const handleDeleteSelection = useCallback((): void => {
    if (selectedWordIds.size === 0) { addToast({ type: 'info', message: 'No words selected' }); return; }
    deleteSelectedWords();
  }, [selectedWordIds, deleteSelectedWords, addToast]);

  const anyCloudTranscribing = Object.values(isTranscribing).some(Boolean);
  const anyTranscribing = anyCloudTranscribing || isLocalTranscribing;
  const transcribingClipIds = clips.filter((c) => isTranscribing[c.id]);
  const overallProgress = isLocalTranscribing
    ? localProgress
    : transcribingClipIds.length > 0
      ? transcribingClipIds.reduce((avg, c) => avg + (transcribeProgress[c.id] ?? 0), 0) / transcribingClipIds.length
      : 0;
  const progressLabel = isLocalTranscribing ? localStatus : (transcribeStage[transcribingClipIds[0]?.id] ?? 'Processing…');

  const wordCount = getWordCount();
  const deletedDurationMs = getDeletedDurationMs();
  const transcribedClipIds = clips.filter((c) => wordsByClipId[c.id]?.length > 0).map((c) => c.id);
  const hasContent = transcribedClipIds.length > 0 || clips.length > 0;

  const isEnglishOnlyLocal = transcribeMode === 'local' && selectedLocalModel.endsWith('.en');
  const displayLanguage = isEnglishOnlyLocal ? 'en' : selectedLanguage;

  return (
    <div className="flex flex-col h-full" style={{ background: '#141414' }}>

      {/* ── Toolbar ─────────────────────────────────────────────────────── */}
      <div
        className="flex items-center gap-2 px-4 py-2 flex-shrink-0 flex-wrap"
        style={{ background: '#111', borderBottom: '1px solid #1e1e1e' }}
      >
        {/* Mode toggle */}
        <div
          className="flex rounded-md overflow-hidden border flex-shrink-0"
          style={{ borderColor: '#2e2e2e' }}
        >
          {(['cloud', 'local'] as const).map((mode) => (
            <button
              key={mode}
              onClick={() => setTranscribeMode(mode)}
              className={`px-2.5 py-1 text-[10px] font-medium uppercase tracking-wider transition-colors ${
                transcribeMode === mode
                  ? 'bg-accent text-white'
                  : 'text-text-muted hover:text-text-primary hover:bg-white/5'
              }`}
            >
              {mode === 'cloud' ? '☁ Cloud API' : '⚡ On-Device'}
            </button>
          ))}
        </div>

        <div className="w-px h-5 bg-border" />

        {/* Language selector */}
        <div className="flex items-center gap-1.5">
          <label className="text-[10px] text-text-muted uppercase tracking-wider">Lang</label>
          <select
            id="transcript-language"
            value={displayLanguage}
            onChange={(e) => setSelectedLanguage(e.target.value)}
            disabled={isEnglishOnlyLocal}
            title={isEnglishOnlyLocal ? "This model is English-only" : ""}
            className="select text-xs py-1 h-7 disabled:opacity-50 disabled:cursor-not-allowed"
            style={{ width: 110 }}
          >
            <option value="auto">Auto-detect</option>
            {SUPPORTED_LANGUAGES.map((lang) => (
              <option key={lang.code} value={lang.code}>{lang.name}</option>
            ))}
          </select>
        </div>

        <div className="w-px h-5 bg-border" />

        {/* Transcribe button */}
        <Button
          id="btn-transcribe-all"
          variant="secondary"
          size="xs"
          loading={anyTranscribing}
          onClick={transcribeMode === 'cloud' ? handleTranscribeAll : handleLocalTranscribeAll}
          icon={
            <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
            </svg>
          }
        >
          Transcribe All
        </Button>

        {/* Bad takes (only in cloud mode / if transcript exists) */}
        {transcribedClipIds.length > 0 && (
          <Button
            id="btn-remove-bad-takes"
            variant="ghost"
            size="xs"
            loading={isDetectingBadTakes}
            onClick={handleRemoveBadTakes}
            icon={<span className="text-warning text-xs">✦</span>}
            className="text-warning hover:text-warning border-warning/20 hover:border-warning/40"
          >
            Bad Takes
          </Button>
        )}

        <div className="w-px h-5 bg-border" />

        {/* Undo / Redo */}
        {(['undo', 'redo'] as const).map((action) => (
          <button
            key={action}
            id={`btn-${action}`}
            onClick={action === 'undo' ? undoDelete : redoDelete}
            disabled={action === 'undo' ? undoStack.length === 0 : redoStack.length === 0}
            className="w-7 h-7 flex items-center justify-center rounded text-text-muted hover:text-text-primary hover:bg-white/10 disabled:opacity-30 disabled:cursor-not-allowed transition-colors"
            title={action === 'undo' ? 'Undo (⌘Z)' : 'Redo (⌘⇧Z)'}
          >
            <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              {action === 'undo'
                ? <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 10h10a8 8 0 018 8v2M3 10l6 6m-6-6l6-6" />
                : <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 10H11a8 8 0 00-8 8v2m18-10l-6 6m6-6l-6-6" />
              }
            </svg>
          </button>
        ))}

        {selectedWordIds.size > 0 && (
          <>
            <div className="w-px h-5 bg-border" />
            <Button id="btn-remove-selection" variant="danger" size="xs" onClick={handleDeleteSelection}>
              Remove ({selectedWordIds.size})
            </Button>
          </>
        )}

        {/* Stats */}
        <div className="ml-auto flex items-center gap-3">
          {wordCount > 0 && <span className="text-[10px] text-text-muted">{wordCount.toLocaleString()} words</span>}
          {deletedDurationMs > 0 && <span className="text-[10px] text-success">−{Math.round(deletedDurationMs / 1000)}s saved</span>}
        </div>
      </div>

      {/* ── On-Device model manager panel ───────────────────────────────── */}
      {transcribeMode === 'local' && (
        <ModelManagerPanel
          selectedModelId={selectedLocalModel}
          onSelect={setSelectedLocalModel}
        />
      )}

      {/* ── Progress bar ────────────────────────────────────────────────── */}
      {anyTranscribing && (
        <div className="px-4 py-1.5 flex-shrink-0 border-b border-border flex items-center gap-3">
          <div className="flex-1">
            <Progress value={overallProgress} label={progressLabel} showPercent={!isLocalTranscribing} animated />
          </div>
          <Button variant="ghost" size="xs" onClick={handleCancelTranscription}>
            Cancel
          </Button>
        </div>
      )}

      {/* ── Transcript content ───────────────────────────────────────────── */}
      <div className="flex-1 overflow-hidden flex flex-col">
        <div
          ref={containerRef}
          className="flex-1 overflow-y-auto px-4 py-4 transcript-selectable"
          id="transcript-editor"
        >
          {!hasContent ? (
            <div className="flex flex-col items-center justify-center h-full gap-4 text-center">
              <div
                className="w-20 h-20 rounded-2xl flex items-center justify-center"
                style={{ background: 'linear-gradient(135deg, rgba(124,108,250,0.15), rgba(124,108,250,0.05))' }}
              >
                <svg className="w-10 h-10 text-accent/60" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
              </div>
              <div>
                <h3 className="text-base font-semibold text-text-primary mb-1">No transcript yet</h3>
                <p className="text-sm text-text-muted max-w-xs leading-relaxed">
                  Add clips to the timeline, then click{' '}
                  <span className="text-text-primary font-medium">Transcribe All</span>.
                </p>
                <p className="text-xs text-text-muted/60 mt-2">
                  {transcribeMode === 'local'
                    ? '⚡ On-Device: no API key needed — runs fully offline'
                    : '☁ Cloud: uses OpenAI Whisper API'}
                </p>
              </div>
            </div>
          ) : transcribedClipIds.length === 0 && clips.length > 0 ? (
            <div className="flex flex-col items-center justify-center h-full gap-4 text-center">
              <div className="w-14 h-14 rounded-full bg-white/5 flex items-center justify-center">
                <svg className="w-7 h-7 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
                </svg>
              </div>
              <p className="text-sm text-text-primary font-medium">
                {clips.length} clip{clips.length !== 1 ? 's' : ''} ready to transcribe
              </p>
              <p className="text-xs text-text-muted">
                {transcribeMode === 'local' && !selectedLocalModel
                  ? '⚡ Download a model above, then click Transcribe All'
                  : 'Click Transcribe All above'}
              </p>
            </div>
          ) : (
            <div className="space-y-6">
              {clips.map((clip) => {
                const words = wordsByClipId[clip.id] ?? [];
                const segments = segmentsByClipId[clip.id] ?? [];
                const mediaFile = mediaFiles.find((f) => f.id === clip.mediaFileId);
                const filename = mediaFile?.filePath.split('/').pop() ?? `Clip ${clip.id}`;
                if (words.length === 0) return null;

                return (
                  <div key={clip.id}>
                    <div className="flex items-center gap-2 mb-3">
                      <div className="h-px flex-1" style={{ background: '#2e2e2e' }} />
                      <span className="text-[10px] text-text-muted font-medium uppercase tracking-wider px-2">
                        {filename}
                      </span>
                      <div className="h-px flex-1" style={{ background: '#2e2e2e' }} />
                    </div>

                    {isTranscribing[clip.id] && (
                      <div className="mb-3">
                        <Progress value={transcribeProgress[clip.id] ?? 0} label={transcribeStage[clip.id] ?? 'processing'} showPercent animated size="xs" />
                      </div>
                    )}

                    <div className="space-y-0.5">
                      {segments.length > 0 ? (
                        segments.map((segment) => (
                          <TranscriptLine
                            key={segment.id}
                            segment={segment}
                            words={words}
                            currentTimeMs={currentTimeMs}
                            onWordClick={handleWordClick}
                            clipLabel={filename}
                          />
                        ))
                      ) : (
                        <div className="flex gap-3 py-1 px-1">
                          <div className="flex-shrink-0 w-12" />
                          <p className="flex-1 text-sm text-text-primary leading-loose transcript-selectable">
                            {words.map((word, i) => (
                              <React.Fragment key={word.id}>
                                <span
                                  className={deletedWordIds.has(word.id) ? 'word-deleted' : 'word-default'}
                                  data-word-id={word.id}
                                  data-start-ms={word.startMs}
                                  data-end-ms={word.endMs}
                                  data-clip-id={word.clipId}
                                  onClick={() => handleWordClick(word)}
                                >
                                  {word.word}
                                </span>
                                {i < words.length - 1 && ' '}
                              </React.Fragment>
                            ))}
                          </p>
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <BadTakeHighlight />
      </div>
    </div>
  );
};

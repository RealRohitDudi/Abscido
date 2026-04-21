import React, { useEffect, useState, useCallback } from 'react';
import { useModal, useProject, useStore, useTimeline, useTranscript } from './store';
import { useIpc, useAppMenuListener, useIpcListener } from './hooks/useIpc';
import { TopBar } from './components/layout/TopBar';
import { Sidebar } from './components/layout/Sidebar';
import { WorkspaceLayout } from './components/layout/WorkspaceLayout';
import { Modal } from './components/ui/Modal';
import { Button } from './components/ui/Button';
import { Progress } from './components/ui/Progress';
import { ToastContainer } from './components/ui/Toast';
import type {
  IpcResult,
  AppSettings,
  Project,
  FullProjectState,
  ExportPreset,
  ExportProgressEvent,
} from './types';

// ─── Settings Modal ────────────────────────────────────────────────────────────
const SettingsModal: React.FC = () => {
  const { closeModal } = useModal();
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();

  const [openaiKey, setOpenaiKey] = useState('');
  const [anthropicKey, setAnthropicKey] = useState('');
  const [defaultLang, setDefaultLang] = useState('en');
  const [isSaving, setIsSaving] = useState(false);

  useEffect(() => {
    invoke<IpcResult<AppSettings>>(window.electronAPI.channels.SETTINGS_GET).then((result) => {
      if (result.success) {
        setOpenaiKey(result.data.openaiApiKey);
        setAnthropicKey(result.data.anthropicApiKey);
        setDefaultLang(result.data.defaultLanguage || 'en');
      }
    });
  }, [invoke]);

  const handleSave = async (): Promise<void> => {
    setIsSaving(true);
    try {
      const result = await invoke<IpcResult<null>>(window.electronAPI.channels.SETTINGS_SET, {
        openaiApiKey: openaiKey,
        anthropicApiKey: anthropicKey,
        defaultLanguage: defaultLang,
      });

      if (result.success) {
        addToast({ type: 'success', message: 'Settings saved' });
        closeModal();
      } else {
        addToast({ type: 'error', message: result.error });
      }
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <Modal
      title="Settings"
      size="md"
      footer={
        <>
          <Button variant="ghost" size="sm" onClick={closeModal}>Cancel</Button>
          <Button variant="primary" size="sm" loading={isSaving} onClick={handleSave}>
            Save Settings
          </Button>
        </>
      }
    >
      <div className="space-y-5">
        {/* API Keys notice */}
        <div className="rounded-lg p-3 text-xs text-text-muted" style={{ background: '#1a1a1a', border: '1px solid #2e2e2e' }}>
          <p className="flex items-center gap-1.5">
            <svg className="w-3.5 h-3.5 text-accent shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
            </svg>
            API keys are stored securely on your Mac and never transmitted to Abscido servers.
          </p>
        </div>

        {/* OpenAI */}
        <div>
          <label className="block text-xs font-medium text-text-secondary mb-1.5">
            OpenAI API Key
            <span className="text-text-muted ml-1 font-normal">(for Whisper transcription)</span>
          </label>
          <input
            id="settings-openai-key"
            type="password"
            className="input"
            value={openaiKey}
            onChange={(e) => setOpenaiKey(e.target.value)}
            placeholder="sk-..."
            autoComplete="off"
          />
        </div>

        {/* Anthropic */}
        <div>
          <label className="block text-xs font-medium text-text-secondary mb-1.5">
            Anthropic API Key
            <span className="text-text-muted ml-1 font-normal">(for Claude bad take detection)</span>
          </label>
          <input
            id="settings-anthropic-key"
            type="password"
            className="input"
            value={anthropicKey}
            onChange={(e) => setAnthropicKey(e.target.value)}
            placeholder="sk-ant-..."
            autoComplete="off"
          />
        </div>
      </div>
    </Modal>
  );
};

// ─── New Project Modal ────────────────────────────────────────────────────────
const NewProjectModal: React.FC = () => {
  const { closeModal } = useModal();
  const { createProject } = useProject();
  const addToast = useStore((s) => s.addToast);

  const [projectName, setProjectName] = useState('');
  const [isCreating, setIsCreating] = useState(false);

  const handleCreate = async (): Promise<void> => {
    const name = projectName.trim();
    if (!name) return;

    setIsCreating(true);
    try {
      const project = await createProject(name);
      if (project) {
        addToast({ type: 'success', message: `Created project "${name}"` });
        closeModal();
      }
    } finally {
      setIsCreating(false);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent): void => {
    if (e.key === 'Enter') handleCreate();
  };

  return (
    <Modal
      title="New Project"
      size="sm"
      footer={
        <>
          <Button variant="ghost" size="sm" onClick={closeModal}>Cancel</Button>
          <Button
            variant="primary"
            size="sm"
            loading={isCreating}
            onClick={handleCreate}
            disabled={!projectName.trim()}
          >
            Create
          </Button>
        </>
      }
    >
      <div>
        <label className="block text-xs font-medium text-text-secondary mb-1.5">
          Project Name
        </label>
        <input
          id="new-project-name"
          type="text"
          className="input"
          value={projectName}
          onChange={(e) => setProjectName(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder="My Video Project"
          autoFocus
        />
      </div>
    </Modal>
  );
};

// ─── Open Project Modal ────────────────────────────────────────────────────────
const OpenProjectModal: React.FC = () => {
  const { closeModal } = useModal();
  const { loadProject, setClips, setMediaFiles } = { ...useProject(), ...useTimeline() };
  const setTranscriptData = useTranscript().loadTranscript;
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();
  const [projects, setProjects] = useState<Project[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isOpening, setIsOpening] = useState(false);
  const setClipsFn = useTimeline().setClips;
  const setMediaFilesFn = useProject().setMediaFiles;
  const setProjectFn = useProject().setProject;

  useEffect(() => {
    invoke<IpcResult<Project[]>>(window.electronAPI.channels.PROJECT_LIST).then((result) => {
      if (result.success) setProjects(result.data);
      setIsLoading(false);
    });
  }, [invoke]);

  const handleOpen = async (projectId: number): Promise<void> => {
    setIsOpening(true);
    try {
      const result = await invoke<IpcResult<FullProjectState>>(
        window.electronAPI.channels.PROJECT_LOAD,
        { projectId },
      );
      if (result.success) {
        const state = result.data;
        setProjectFn(state.project);
        setMediaFilesFn(state.mediaFiles);
        setClipsFn(state.clips);
        for (const [clipId, words] of Object.entries(state.transcriptWords)) {
          const segments = state.transcriptSegments[parseInt(clipId)] ?? [];
          setTranscriptData(parseInt(clipId), words, segments);
        }
        addToast({ type: 'success', message: `Opened "${state.project.name}"` });
        closeModal();
      } else {
        addToast({ type: 'error', message: result.error });
      }
    } finally {
      setIsOpening(false);
    }
  };

  return (
    <Modal title="Open Project" size="md">
      {isLoading ? (
        <div className="flex items-center justify-center py-8">
          <div className="spin w-6 h-6 border-2 border-accent border-t-transparent rounded-full" />
        </div>
      ) : projects.length === 0 ? (
        <div className="text-center py-8">
          <p className="text-sm text-text-muted">No projects yet</p>
          <p className="text-xs text-text-muted/60 mt-1">Create a new project to get started</p>
        </div>
      ) : (
        <div className="flex flex-col gap-1.5 max-h-64 overflow-y-auto">
          {projects.map((project) => (
            <button
              key={project.id}
              onClick={() => handleOpen(project.id)}
              disabled={isOpening}
              className="flex items-center justify-between p-3 rounded-lg border border-border hover:border-accent/40 hover:bg-accent/5 transition-all text-left disabled:opacity-50"
            >
              <div>
                <p className="text-sm font-medium text-text-primary">{project.name}</p>
                <p className="text-[10px] text-text-muted mt-0.5">
                  {new Date(project.updatedAt).toLocaleDateString()}
                </p>
              </div>
              <svg className="w-4 h-4 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </button>
          ))}
        </div>
      )}
      <div className="mt-4">
        <Button variant="ghost" size="sm" onClick={closeModal} className="w-full">
          Cancel
        </Button>
      </div>
    </Modal>
  );
};

// ─── Export Modal ──────────────────────────────────────────────────────────────
const ExportModal: React.FC = () => {
  const { closeModal } = useModal();
  const { currentProject } = useProject();
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();

  const [preset, setPreset] = useState<ExportPreset>({
    format: 'mp4',
    quality: 'high',
  });
  const [isExporting, setIsExporting] = useState(false);
  const [exportProgress, setExportProgress] = useState(0);

  useIpcListener<ExportProgressEvent>(
    window.electronAPI.channels.EXPORT_PROGRESS,
    (data) => {
      setExportProgress(data.progress);
    },
  );

  const handleExport = async (): Promise<void> => {
    if (!currentProject) return;

    const saveResult = await invoke<IpcResult<string | null>>(
      window.electronAPI.channels.APP_OPEN_SAVE_DIALOG,
      {
        defaultPath: `${currentProject.name}_export.${preset.format}`,
        filters: [{ name: 'Video', extensions: [preset.format] }],
      },
    );
    if (!saveResult.success || !saveResult.data) return;

    setIsExporting(true);
    setExportProgress(0);

    try {
      const result = await invoke<IpcResult<{ outputPath: string }>>(
        window.electronAPI.channels.EXPORT_RENDER,
        {
          projectId: currentProject.id,
          outputPath: saveResult.data,
          preset,
        },
      );

      if (result.success) {
        addToast({ type: 'success', message: 'Export complete!', duration: 6000 });
        invoke(window.electronAPI.channels.APP_SHOW_IN_FINDER, {
          filePath: result.data.outputPath,
        }).catch(() => {});
        closeModal();
      } else {
        addToast({ type: 'error', message: result.error });
      }
    } finally {
      setIsExporting(false);
      setExportProgress(0);
    }
  };

  return (
    <Modal
      title="Export Video"
      size="sm"
      footer={
        !isExporting ? (
          <>
            <Button variant="ghost" size="sm" onClick={closeModal}>Cancel</Button>
            <Button variant="primary" size="sm" onClick={handleExport}>
              Export
            </Button>
          </>
        ) : undefined
      }
    >
      <div className="space-y-4">
        {isExporting ? (
          <div className="py-4">
            <Progress value={exportProgress} label="Exporting…" showPercent animated />
          </div>
        ) : (
          <>
            <div>
              <label className="block text-xs font-medium text-text-secondary mb-1.5">Format</label>
              <select
                className="select"
                value={preset.format}
                onChange={(e) => setPreset((p) => ({ ...p, format: e.target.value as ExportPreset['format'] }))}
              >
                <option value="mp4">MP4 (H.264)</option>
                <option value="mov">MOV (QuickTime)</option>
                <option value="webm">WebM (VP9)</option>
              </select>
            </div>
            <div>
              <label className="block text-xs font-medium text-text-secondary mb-1.5">Quality</label>
              <select
                className="select"
                value={preset.quality}
                onChange={(e) => setPreset((p) => ({ ...p, quality: e.target.value as ExportPreset['quality'] }))}
              >
                <option value="lossless">Lossless</option>
                <option value="high">High (CRF 18)</option>
                <option value="medium">Medium (CRF 23)</option>
                <option value="low">Low (CRF 28)</option>
              </select>
            </div>
          </>
        )}
      </div>
    </Modal>
  );
};

// ─── First Launch Settings Gate ────────────────────────────────────────────────
const FirstLaunchGate: React.FC<{ onDone: () => void }> = ({ onDone }) => {
  const [openaiKey, setOpenaiKey] = useState('');
  const [anthropicKey, setAnthropicKey] = useState('');
  const [isSaving, setIsSaving] = useState(false);
  const { invoke } = useIpc();
  const addToast = useStore((s) => s.addToast);

  const handleSave = async (): Promise<void> => {
    setIsSaving(true);
    try {
      await invoke(window.electronAPI.channels.SETTINGS_SET, {
        openaiApiKey: openaiKey,
        anthropicApiKey: anthropicKey,
      });
      addToast({ type: 'success', message: 'API keys saved — welcome to Abscido!' });
      onDone();
    } finally {
      setIsSaving(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ background: '#0f0f0f' }}>
      <div className="w-full max-w-md mx-4 animate-slide-up">
        {/* Logo */}
        <div className="text-center mb-8">
          <div
            className="w-16 h-16 rounded-2xl mx-auto mb-4 flex items-center justify-center"
            style={{ background: 'linear-gradient(135deg, #7c6cfa, #5a4fd4)' }}
          >
            <svg className="w-8 h-8 text-white" fill="currentColor" viewBox="0 0 24 24">
              <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z" />
            </svg>
          </div>
          <h1 className="text-2xl font-bold text-text-primary">Welcome to Abscido</h1>
          <p className="text-sm text-text-muted mt-1">
            The text-based video editor for macOS
          </p>
        </div>

        {/* Setup card */}
        <div className="card p-6 space-y-5">
          <div>
            <h2 className="text-sm font-semibold text-text-primary mb-1">Set up API Keys</h2>
            <p className="text-xs text-text-muted">
              Abscido uses OpenAI Whisper for transcription and Claude for AI editing.
              Your keys are stored securely on your Mac only.
            </p>
          </div>

          <div>
            <label className="block text-xs font-medium text-text-secondary mb-1.5">
              OpenAI API Key <span className="text-danger">*</span>
            </label>
            <input
              id="first-launch-openai-key"
              type="password"
              className="input"
              value={openaiKey}
              onChange={(e) => setOpenaiKey(e.target.value)}
              placeholder="sk-..."
              autoFocus
            />
            <p className="text-[10px] text-text-muted mt-1">Required for Whisper transcription</p>
          </div>

          <div>
            <label className="block text-xs font-medium text-text-secondary mb-1.5">
              Anthropic API Key
              <span className="text-text-muted ml-1 font-normal">(optional)</span>
            </label>
            <input
              id="first-launch-anthropic-key"
              type="password"
              className="input"
              value={anthropicKey}
              onChange={(e) => setAnthropicKey(e.target.value)}
              placeholder="sk-ant-..."
            />
            <p className="text-[10px] text-text-muted mt-1">For AI bad take removal (optional)</p>
          </div>

          <Button
            variant="primary"
            size="md"
            loading={isSaving}
            onClick={handleSave}
            disabled={!openaiKey.trim()}
            className="w-full"
          >
            Get Started
          </Button>

          <button
            onClick={onDone}
            className="w-full text-xs text-text-muted hover:text-text-secondary transition-colors"
          >
            Skip for now (you can add keys in Settings)
          </button>
        </div>
      </div>
    </div>
  );
};

// ─── Root App ──────────────────────────────────────────────────────────────────
export const App: React.FC = () => {
  const { activeModal, openModal, closeModal } = useModal();
  const { openModal: openModalFn } = useModal();
  const [showFirstLaunch, setShowFirstLaunch] = useState(false);
  const [isCheckingKeys, setIsCheckingKeys] = useState(true);
  const { invoke } = useIpc();

  // Check if this is first launch (no API keys set)
  useEffect(() => {
    invoke<IpcResult<{ hasOpenAI: boolean; hasAnthropic: boolean }>>(
      window.electronAPI.channels.SETTINGS_HAS_KEYS,
    ).then((result) => {
      if (result.success && !result.data.hasOpenAI) {
        setShowFirstLaunch(true);
      }
      setIsCheckingKeys(false);
    }).catch(() => {
      setIsCheckingKeys(false);
    });

    // Cleanup temp files from previous crash
    invoke(window.electronAPI.channels.APP_CLEANUP_TEMP).catch(() => {});
  }, [invoke]);

  // Listen for menu events from main process
  useAppMenuListener('openSettings', () => openModalFn('settings'));
  useAppMenuListener('newProject', () => openModalFn('newProject'));
  useAppMenuListener('openProject', () => openModalFn('openProject'));
  useAppMenuListener('export', () => openModalFn('export'));

  // Global keyboard shortcuts
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent): void => {
      const isMac = navigator.platform.includes('Mac');
      const modifier = isMac ? e.metaKey : e.ctrlKey;

      // Space → play/pause (when not in input)
      if (e.key === ' ' && !(e.target instanceof HTMLInputElement) && !(e.target instanceof HTMLTextAreaElement)) {
        e.preventDefault();
        // Trigger play/pause via Zustand store — always reads latest state
        useStore.getState().togglePlay();
        return;
      }

      // Cmd+I → import media
      if (modifier && e.key === 'i') {
        e.preventDefault();
        invoke(window.electronAPI.channels.MEDIA_IMPORT, {}).catch(() => {});
        return;
      }

      // Cmd+N → new project
      if (modifier && e.key === 'n') {
        e.preventDefault();
        openModalFn('newProject');
        return;
      }

      // Cmd+O → open project
      if (modifier && e.key === 'o') {
        e.preventDefault();
        openModalFn('openProject');
        return;
      }

      // Cmd+, → settings
      if (modifier && e.key === ',') {
        e.preventDefault();
        openModalFn('settings');
        return;
      }

      // Cmd+E → export
      if (modifier && e.key === 'e') {
        e.preventDefault();
        openModalFn('export');
        return;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [invoke, openModalFn]);

  if (isCheckingKeys) {
    return (
      <div className="fixed inset-0 flex items-center justify-center" style={{ background: '#0f0f0f' }}>
        <div className="spin w-6 h-6 border-2 border-accent border-t-transparent rounded-full" />
      </div>
    );
  }

  if (showFirstLaunch) {
    return (
      <>
        <FirstLaunchGate onDone={() => setShowFirstLaunch(false)} />
        <ToastContainer />
      </>
    );
  }

  return (
    <div className="flex flex-col h-screen overflow-hidden" style={{ background: '#0f0f0f' }}>
      {/* Top bar */}
      <TopBar />

      {/* Main workspace */}
      <div className="flex flex-1 overflow-hidden">
        <Sidebar />
        <WorkspaceLayout />
      </div>

      {/* Modals */}
      {activeModal === 'settings' && <SettingsModal />}
      {activeModal === 'newProject' && <NewProjectModal />}
      {activeModal === 'openProject' && <OpenProjectModal />}
      {activeModal === 'export' && <ExportModal />}

      {/* Toast notifications */}
      <ToastContainer />
    </div>
  );
};

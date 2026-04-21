import React, { useState } from 'react';
import { useProject, useStore, useTimeline } from '../../store';
import { useIpc } from '../../hooks/useIpc';
import type { MediaFile, MediaInfo, IpcResult, TimelineClip } from '../../types';
import { Button } from '../ui/Button';

export const ImportPanel: React.FC = () => {
  const [isImporting, setIsImporting] = useState(false);
  const { currentProject, addMediaFile } = useProject();
  const { addClip } = useTimeline();
  const addToast = useStore((s) => s.addToast);
  const { invoke } = useIpc();

  const handleImport = async (): Promise<void> => {
    if (!currentProject) {
      addToast({ type: 'warning', message: 'Please create or open a project first' });
      return;
    }

    setIsImporting(true);
    try {
      const result = await invoke<IpcResult<MediaInfo[]>>(
        window.electronAPI.channels.MEDIA_IMPORT,
        {},
      );

      if (!result.success) {
        if (result.code !== 'CANCELLED') {
          addToast({ type: 'error', message: result.error });
        }
        return;
      }

      for (const info of result.data) {
        // Save to DB
        const saveResult = await invoke<IpcResult<MediaFile>>(
          window.electronAPI.channels.MEDIA_ADD_TO_PROJECT,
          {
            projectId: currentProject.id,
            filePath: info.filePath,
            durationMs: info.durationMs,
            width: info.width,
            height: info.height,
            fps: info.fps,
            codec: info.codec,
          },
        );

        if (!saveResult.success) {
          addToast({ type: 'error', message: `Failed to import: ${saveResult.error}` });
          continue;
        }

        const mediaFile = saveResult.data;
        addMediaFile(mediaFile);

        // Generate thumbnail async (don't await)
        invoke(window.electronAPI.channels.MEDIA_THUMBNAIL, {
          filePath: info.filePath,
          timeMs: Math.min(1000, info.durationMs / 2),
          mediaFileId: mediaFile.id,
        }).catch(console.error);
      }

      addToast({
        type: 'success',
        message: `Imported ${result.data.length} file${result.data.length !== 1 ? 's' : ''}`,
      });
    } catch (err) {
      addToast({
        type: 'error',
        message: err instanceof Error ? err.message : 'Import failed',
      });
    } finally {
      setIsImporting(false);
    }
  };

  return (
    <div className="px-3 py-2 border-b border-border flex-shrink-0">
      <Button
        variant="primary"
        size="sm"
        onClick={handleImport}
        loading={isImporting}
        className="w-full"
        icon={
          <svg className="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
          </svg>
        }
      >
        Import Media
      </Button>
    </div>
  );
};

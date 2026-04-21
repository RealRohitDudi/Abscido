import React from 'react';
import { useProject, useModal, useStore } from '../../store';
import { Button } from '../ui/Button';

export const TopBar: React.FC = () => {
  const { currentProject, saveProject } = useProject();
  const { openModal } = useModal();
  const addToast = useStore((s) => s.addToast);

  const handleSave = async (): Promise<void> => {
    if (!currentProject) return;
    await saveProject();
    addToast({ type: 'success', message: 'Project saved', duration: 2000 });
  };

  return (
    <header
      className="h-11 flex items-center justify-between px-4 flex-shrink-0 titlebar-drag"
      style={{ background: '#0f0f0f', borderBottom: '1px solid #1e1e1e' }}
    >
      {/* Traffic lights space + logo */}
      <div className="flex items-center gap-3 titlebar-no-drag" style={{ paddingLeft: '72px' }}>
        <div className="flex items-center gap-2">
          <div
            className="w-5 h-5 rounded-md flex items-center justify-center"
            style={{ background: 'linear-gradient(135deg, #7c6cfa, #5a4fd4)' }}
          >
            <svg className="w-3 h-3 text-white" fill="currentColor" viewBox="0 0 24 24">
              <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2zm-5 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z" />
            </svg>
          </div>
          <span className="text-sm font-semibold text-text-primary tracking-tight">Abscido</span>
          {currentProject && (
            <>
              <span className="text-text-muted text-sm">/</span>
              <span className="text-sm text-text-secondary truncate max-w-[180px]">
                {currentProject.name}
              </span>
            </>
          )}
        </div>
      </div>

      {/* Center: nothing (stretch) */}
      <div className="flex-1" />

      {/* Right: actions */}
      <div className="flex items-center gap-2 titlebar-no-drag">
        {currentProject && (
          <Button
            variant="ghost"
            size="xs"
            onClick={handleSave}
            icon={
              <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 7H5a2 2 0 00-2 2v9a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-3m-1 4l-3 3m0 0l-3-3m3 3V4" />
              </svg>
            }
          >
            Save
          </Button>
        )}
        <Button
          variant="ghost"
          size="xs"
          onClick={() => openModal('settings')}
          icon={
            <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" />
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
            </svg>
          }
        >
          Settings
        </Button>
      </div>
    </header>
  );
};

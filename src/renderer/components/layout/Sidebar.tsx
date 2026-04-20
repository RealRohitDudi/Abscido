import React from 'react';
import { useModal, useProject } from '../../store';
import { Button } from '../ui/Button';

export const Sidebar: React.FC = () => {
  const { openModal } = useModal();
  const { currentProject } = useProject();

  const navItems = [
    {
      id: 'media',
      icon: (
        <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M7 4v16M17 4v16M3 8h4m10 0h4M3 12h18M3 16h4m10 0h4M4 20h16a1 1 0 001-1V5a1 1 0 00-1-1H4a1 1 0 00-1 1v14a1 1 0 001 1z" />
        </svg>
      ),
      label: 'Media',
    },
  ];

  return (
    <aside className="flex flex-col" style={{ width: 48, background: '#0f0f0f', borderRight: '1px solid #1e1e1e' }}>
      <div className="flex-1 flex flex-col items-center gap-1 pt-3">
        {navItems.map((item) => (
          <button
            key={item.id}
            className="w-9 h-9 flex items-center justify-center rounded-lg text-text-secondary hover:text-text-primary hover:bg-white/8 transition-colors titlebar-no-drag"
            title={item.label}
          >
            {item.icon}
          </button>
        ))}
      </div>

      {/* Bottom: new project */}
      <div className="flex flex-col items-center pb-3 gap-2 titlebar-no-drag">
        <button
          onClick={() => openModal('newProject')}
          className="w-9 h-9 flex items-center justify-center rounded-lg text-text-secondary hover:text-text-primary hover:bg-white/8 transition-colors"
          title="New Project (⌘N)"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M12 4v16m8-8H4" />
          </svg>
        </button>
        <button
          onClick={() => openModal('openProject')}
          className="w-9 h-9 flex items-center justify-center rounded-lg text-text-secondary hover:text-text-primary hover:bg-white/8 transition-colors"
          title="Open Project (⌘O)"
        >
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M5 19a2 2 0 01-2-2V7a2 2 0 012-2h4l2 2h4a2 2 0 012 2v1M5 19h14a2 2 0 002-2v-5a2 2 0 00-2-2H9a2 2 0 00-2 2v5a2 2 0 01-2 2z" />
          </svg>
        </button>
      </div>
    </aside>
  );
};

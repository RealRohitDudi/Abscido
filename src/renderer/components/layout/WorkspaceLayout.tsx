import React from 'react';
import { MediaBin } from '../media/MediaBin';
import { VideoPlayer } from '../player/VideoPlayer';
import { TranscriptEditor } from '../transcript/TranscriptEditor';
import { Timeline } from '../timeline/Timeline';

export const WorkspaceLayout: React.FC = () => {
  return (
    <div className="flex flex-1 overflow-hidden">
      {/* Left Panel: Media Bin (280px) */}
      <div
        className="flex flex-col flex-shrink-0 border-r border-border overflow-hidden"
        style={{ width: 280 }}
      >
        <MediaBin />
      </div>

      {/* Center Panel: Video Player + Transcript Editor */}
      <div className="flex flex-col flex-1 overflow-hidden min-w-0">
        {/* Video Player — 40% of center height */}
        <div
          className="flex-shrink-0 border-b border-border"
          style={{ height: '40%', minHeight: 180 }}
        >
          <VideoPlayer />
        </div>

        {/* Transcript Editor — 60% of center height */}
        <div className="flex-1 overflow-hidden">
          <TranscriptEditor />
        </div>
      </div>

      {/* Right Panel: Timeline + Export (320px) */}
      <div
        className="flex flex-col flex-shrink-0 border-l border-border overflow-hidden"
        style={{ width: 320 }}
      >
        <Timeline />
      </div>
    </div>
  );
};

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

      {/* Center Panel: Video Player + Timeline */}
      <div className="flex flex-col flex-1 overflow-hidden min-w-0 border-r border-border">
        {/* Video Player — 50% of center height */}
        <div
          className="flex-shrink-0 border-b border-border"
          style={{ height: '50%', minHeight: 180 }}
        >
          <VideoPlayer />
        </div>

        {/* Timeline — 50% of center height */}
        <div className="flex-1 overflow-hidden">
          <Timeline />
        </div>
      </div>

      {/* Right Panel: Transcript Editor (360px) */}
      <div
        className="flex flex-col flex-shrink-0 overflow-hidden bg-background"
        style={{ width: 360 }}
      >
        <TranscriptEditor />
      </div>
    </div>
  );
};

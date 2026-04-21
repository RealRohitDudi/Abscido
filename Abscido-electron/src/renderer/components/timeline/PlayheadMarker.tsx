import React from 'react';

interface PlayheadMarkerProps {
  positionPx: number;
  totalHeightPx: number;
}

export const PlayheadMarker: React.FC<PlayheadMarkerProps> = ({ positionPx, totalHeightPx }) => {
  return (
    <div
      className="playhead-line pointer-events-none"
      style={{ left: positionPx, height: totalHeightPx }}
      aria-hidden="true"
    />
  );
};

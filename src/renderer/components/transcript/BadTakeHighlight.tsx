import React from 'react';
import { useTranscript } from '../../store';
import { Button } from '../ui/Button';
import type { BadTakeReview } from '../../types';

interface BadTakeCardProps {
  review: BadTakeReview;
  onAccept: () => void;
  onReject: () => void;
}

const BadTakeCard: React.FC<BadTakeCardProps> = ({ review, onAccept, onReject }) => {
  const statusColors = {
    pending: 'border-warning/30 bg-warning/5',
    accepted: 'border-danger/30 bg-danger/5',
    rejected: 'border-border bg-transparent opacity-50',
  };

  return (
    <div className={`rounded-lg border p-3 transition-all duration-200 ${statusColors[review.status]}`}>
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-1.5 mb-1">
            <span
              className={`inline-block w-2 h-2 rounded-full shrink-0 ${
                review.status === 'accepted'
                  ? 'bg-danger'
                  : review.status === 'rejected'
                  ? 'bg-border'
                  : 'bg-warning'
              }`}
            />
            <span className="text-xs font-medium text-text-primary">{review.reason}</span>
          </div>
          <p className="text-[10px] text-text-muted">
            {review.wordIds.length} word{review.wordIds.length !== 1 ? 's' : ''}
            {review.status === 'accepted' ? ' · Will be cut' : review.status === 'rejected' ? ' · Kept' : ''}
          </p>
        </div>

        {review.status === 'pending' && (
          <div className="flex gap-1 shrink-0">
            <button
              onClick={onReject}
              className="text-[10px] px-2 py-0.5 rounded border border-border text-text-muted hover:text-text-primary hover:border-text-muted transition-colors"
            >
              Keep
            </button>
            <button
              onClick={onAccept}
              className="text-[10px] px-2 py-0.5 rounded bg-danger/10 border border-danger/30 text-danger hover:bg-danger/20 transition-colors"
            >
              Cut
            </button>
          </div>
        )}

        {review.status !== 'pending' && (
          <span
            className={`text-[10px] font-medium shrink-0 ${
              review.status === 'accepted' ? 'text-danger' : 'text-text-muted'
            }`}
          >
            {review.status === 'accepted' ? 'Cut' : 'Kept'}
          </span>
        )}
      </div>
    </div>
  );
};

export const BadTakeHighlight: React.FC = () => {
  const {
    badTakeReviews,
    acceptBadTake,
    rejectBadTake,
    acceptAllBadTakes,
    rejectAllBadTakes,
    clearBadTakeReviews,
  } = useTranscript();

  if (badTakeReviews.length === 0) return null;

  const pendingCount = badTakeReviews.filter((r) => r.status === 'pending').length;
  const acceptedCount = badTakeReviews.filter((r) => r.status === 'accepted').length;

  return (
    <div className="border-t border-border flex-shrink-0" style={{ maxHeight: '40%' }}>
      {/* Panel header */}
      <div className="flex items-center justify-between px-4 py-2 border-b border-border">
        <div className="flex items-center gap-2">
          <span className="text-xs font-semibold text-warning">✦ Bad Takes Review</span>
          <span className="text-[10px] bg-warning/10 text-warning px-1.5 py-0.5 rounded-full">
            {badTakeReviews.length} found
          </span>
          {acceptedCount > 0 && (
            <span className="text-[10px] bg-danger/10 text-danger px-1.5 py-0.5 rounded-full">
              {acceptedCount} to cut
            </span>
          )}
        </div>
        <div className="flex items-center gap-1">
          {pendingCount > 0 && (
            <>
              <Button variant="danger" size="xs" onClick={acceptAllBadTakes}>
                Cut All ({pendingCount})
              </Button>
              <Button variant="ghost" size="xs" onClick={rejectAllBadTakes}>
                Keep All
              </Button>
            </>
          )}
          <button
            onClick={clearBadTakeReviews}
            className="ml-1 w-5 h-5 flex items-center justify-center rounded text-text-muted hover:text-text-primary hover:bg-white/10 transition-colors"
            title="Clear bad take reviews"
          >
            <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
      </div>

      {/* Review list */}
      <div className="overflow-y-auto px-3 py-2 flex flex-col gap-1.5" style={{ maxHeight: 'calc(40vh - 48px)' }}>
        {badTakeReviews.map((review) => (
          <BadTakeCard
            key={review.id}
            review={review}
            onAccept={() => acceptBadTake(review.id)}
            onReject={() => rejectBadTake(review.id)}
          />
        ))}
      </div>
    </div>
  );
};

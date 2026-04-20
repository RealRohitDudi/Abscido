import React, { useEffect, useCallback } from 'react';
import { useModal } from '../../store';

interface ModalProps {
  title: string;
  children: React.ReactNode;
  onClose?: () => void;
  size?: 'sm' | 'md' | 'lg' | 'xl';
  footer?: React.ReactNode;
  closeOnOverlayClick?: boolean;
}

const sizeStyles: Record<string, string> = {
  sm: 'max-w-sm',
  md: 'max-w-md',
  lg: 'max-w-lg',
  xl: 'max-w-2xl',
};

export const Modal: React.FC<ModalProps> = ({
  title,
  children,
  onClose,
  size = 'md',
  footer,
  closeOnOverlayClick = true,
}) => {
  const { closeModal } = useModal();

  const handleClose = useCallback(() => {
    if (onClose) onClose();
    else closeModal();
  }, [onClose, closeModal]);

  // Escape key to close
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent): void => {
      if (e.key === 'Escape') handleClose();
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [handleClose]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center animate-fade-in">
      {/* Overlay */}
      <div
        className="absolute inset-0 bg-black/60 backdrop-blur-sm"
        onClick={closeOnOverlayClick ? handleClose : undefined}
        aria-hidden="true"
      />

      {/* Modal panel */}
      <div
        className={`
          relative w-full ${sizeStyles[size]} mx-4
          glass rounded-xl shadow-2xl border border-white/10
          animate-slide-up
        `}
        role="dialog"
        aria-modal="true"
        aria-labelledby="modal-title"
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-border">
          <h2 id="modal-title" className="text-base font-semibold text-text-primary">
            {title}
          </h2>
          <button
            onClick={handleClose}
            className="w-7 h-7 flex items-center justify-center rounded-md text-text-muted hover:text-text-primary hover:bg-white/10 transition-colors"
            aria-label="Close modal"
          >
            <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Body */}
        <div className="px-6 py-5">{children}</div>

        {/* Footer */}
        {footer && (
          <div className="px-6 py-4 border-t border-border flex items-center justify-end gap-3">
            {footer}
          </div>
        )}
      </div>
    </div>
  );
};

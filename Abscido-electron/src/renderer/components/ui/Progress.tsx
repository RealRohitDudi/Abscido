import React from 'react';

interface ProgressProps {
  value: number; // 0–100
  label?: string;
  showPercent?: boolean;
  className?: string;
  color?: 'accent' | 'success' | 'danger' | 'warning';
  size?: 'xs' | 'sm' | 'md';
  animated?: boolean;
}

const colorStyles: Record<string, string> = {
  accent: 'bg-gradient-to-r from-accent to-accent-hover',
  success: 'bg-success',
  danger: 'bg-danger',
  warning: 'bg-warning',
};

const sizeStyles: Record<string, string> = {
  xs: 'h-0.5',
  sm: 'h-1',
  md: 'h-1.5',
};

export const Progress: React.FC<ProgressProps> = ({
  value,
  label,
  showPercent = false,
  className = '',
  color = 'accent',
  size = 'sm',
  animated = false,
}) => {
  const clampedValue = Math.min(100, Math.max(0, value));

  return (
    <div className={`w-full ${className}`}>
      {(label || showPercent) && (
        <div className="flex justify-between items-center mb-1.5">
          {label && <span className="text-xs text-text-secondary">{label}</span>}
          {showPercent && (
            <span className="text-xs text-text-muted font-mono">{Math.round(clampedValue)}%</span>
          )}
        </div>
      )}
      <div className={`progress-bar ${sizeStyles[size]}`}>
        <div
          className={`${colorStyles[color]} h-full rounded-full transition-all duration-300 ease-out`}
          style={{
            width: `${clampedValue}%`,
            backgroundSize: animated ? '200% 100%' : undefined,
            animation: animated ? 'shimmer 1.5s linear infinite' : undefined,
          }}
        />
      </div>
    </div>
  );
};

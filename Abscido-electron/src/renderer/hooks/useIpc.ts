import { useEffect, useCallback, useRef } from 'react';
import type { IpcResult } from '../types';

type IpcInvokeResult<T> = IpcResult<T>;

/**
 * Typed hook for invoking IPC channels and listening to events.
 * Wraps window.electronAPI with convenience methods.
 */
export function useIpc() {
  const invoke = useCallback(
    async <T = unknown>(channel: string, payload?: unknown): Promise<IpcInvokeResult<T>> => {
      try {
        const result = await window.electronAPI.invoke<IpcInvokeResult<T>>(channel, payload);
        return result;
      } catch (err) {
        return {
          success: false,
          error: err instanceof Error ? err.message : String(err),
          code: 'IPC_ERROR',
        };
      }
    },
    [],
  );

  const listen = useCallback(
    <T = unknown>(
      channel: string,
      callback: (data: T) => void,
    ): (() => void) => {
      return window.electronAPI.on(channel, (...args: unknown[]) => {
        callback(args[0] as T);
      });
    },
    [],
  );

  return { invoke, listen, channels: window.electronAPI.channels };
}

/**
 * Listen to an IPC event channel and auto-cleanup on unmount.
 */
export function useIpcListener<T = unknown>(
  channel: string,
  callback: (data: T) => void,
  deps: React.DependencyList = [],
): void {
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    const cleanup = window.electronAPI.on(channel, (...args: unknown[]) => {
      callbackRef.current(args[0] as T);
    });
    return cleanup;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [channel, ...deps]);
}

/**
 * Listen to app-level menu events (sent from main process).
 */
export function useAppMenuListener(
  event: string,
  callback: () => void,
): void {
  const callbackRef = useRef(callback);
  callbackRef.current = callback;

  useEffect(() => {
    const cleanup = window.electronAPI.on(`app:${event}`, () => {
      callbackRef.current();
    });
    return cleanup;
  }, [event]);
}

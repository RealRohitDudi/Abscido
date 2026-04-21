import type { StateCreator } from 'zustand';
import type { Project, MediaFile, IpcResult } from '../types';

export interface ProjectSlice {
  currentProject: Project | null;
  mediaFiles: MediaFile[];
  isLoadingProject: boolean;
  projectError: string | null;

  setProject: (project: Project | null) => void;
  setMediaFiles: (files: MediaFile[]) => void;
  addMediaFile: (file: MediaFile) => void;
  removeMediaFile: (fileId: number) => void;
  createProject: (name: string) => Promise<Project | null>;
  loadProject: (projectId: number) => Promise<void>;
  saveProject: () => Promise<void>;
  clearProject: () => void;
}

export const createProjectSlice: StateCreator<
  ProjectSlice,
  [['zustand/devtools', never]],
  [],
  ProjectSlice
> = (set, get) => ({
  currentProject: null,
  mediaFiles: [],
  isLoadingProject: false,
  projectError: null,

  setProject: (project) => set({ currentProject: project }, false, 'project/setProject'),

  setMediaFiles: (files) => set({ mediaFiles: files }, false, 'project/setMediaFiles'),

  addMediaFile: (file) =>
    set(
      (state) => ({ mediaFiles: [...state.mediaFiles, file] }),
      false,
      'project/addMediaFile',
    ),

  removeMediaFile: (fileId) =>
    set(
      (state) => ({ mediaFiles: state.mediaFiles.filter((f) => f.id !== fileId) }),
      false,
      'project/removeMediaFile',
    ),

  createProject: async (name: string) => {
    set({ isLoadingProject: true, projectError: null }, false, 'project/createProject');
    try {
      const result = await window.electronAPI.invoke<IpcResult<Project>>(
        window.electronAPI.channels.PROJECT_CREATE,
        { name },
      );
      if (result.success) {
        set({ currentProject: result.data, mediaFiles: [], isLoadingProject: false });
        return result.data;
      } else {
        set({ projectError: result.error, isLoadingProject: false });
        return null;
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      set({ projectError: msg, isLoadingProject: false });
      return null;
    }
  },

  loadProject: async (projectId: number) => {
    set({ isLoadingProject: true, projectError: null }, false, 'project/loadProject');
    try {
      const result = await window.electronAPI.invoke(
        window.electronAPI.channels.PROJECT_LOAD,
        { projectId },
      );
      if ((result as IpcResult<unknown>).success) {
        const data = (result as IpcResult<{ project: Project; mediaFiles: MediaFile[] }>).data;
        if (data && typeof data === 'object' && 'project' in data) {
          set({ currentProject: data.project, mediaFiles: data.mediaFiles, isLoadingProject: false });
        }
      } else {
        set({ projectError: (result as IpcResult<never>).error, isLoadingProject: false });
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      set({ projectError: msg, isLoadingProject: false });
    }
  },

  saveProject: async () => {
    const { currentProject } = get();
    if (!currentProject) return;
    try {
      await window.electronAPI.invoke(window.electronAPI.channels.PROJECT_SAVE, {
        projectId: currentProject.id,
        state: {},
      });
    } catch (err) {
      console.error('[ProjectSlice] Save failed:', err);
    }
  },

  clearProject: () =>
    set(
      { currentProject: null, mediaFiles: [], projectError: null },
      false,
      'project/clearProject',
    ),
});

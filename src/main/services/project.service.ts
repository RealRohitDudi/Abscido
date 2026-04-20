import { app } from 'electron';
import fs from 'fs';
import path from 'path';
import type { FullProjectState, PartialProjectState } from '../../shared/types';
import { projectRepo } from '../db/repositories/project.repo';
import { clipRepo } from '../db/repositories/clip.repo';
import { transcriptRepo } from '../db/repositories/transcript.repo';

// Auto-save interval (30 seconds)
const AUTO_SAVE_INTERVAL_MS = 30_000;

let autoSaveTimer: ReturnType<typeof setInterval> | null = null;
let dirtyProjects = new Set<number>();

export const projectService = {
  /**
   * Load the complete state of a project including all media, clips, and transcripts
   */
  loadProject(projectId: number): FullProjectState {
    const project = projectRepo.findById(projectId);
    if (!project) throw new Error(`Project ${projectId} not found`);

    const mediaFiles = clipRepo.findMediaFilesByProject(projectId);
    const clips = clipRepo.findClipsByProject(projectId);

    const transcriptWords: FullProjectState['transcriptWords'] = {};
    const transcriptSegments: FullProjectState['transcriptSegments'] = {};

    for (const clip of clips) {
      transcriptWords[clip.id] = transcriptRepo.findWordsByClip(clip.id);
      transcriptSegments[clip.id] = transcriptRepo.findSegmentsByClip(clip.id);
    }

    return {
      project,
      mediaFiles,
      clips,
      transcriptWords,
      transcriptSegments,
    };
  },

  /**
   * Save partial project state (e.g. clip positions, in/out points)
   */
  saveProject(projectId: number, state: PartialProjectState): void {
    if (state.clips) {
      for (const clip of state.clips) {
        if (clip.id) {
          clipRepo.updateClip(clip.id, {
            positionMs: clip.positionMs,
            inPointMs: clip.inPointMs,
            outPointMs: clip.outPointMs,
            track: clip.track,
          });
        }
      }
    }

    projectRepo.touch(projectId);
    dirtyProjects.delete(projectId);
  },

  /**
   * Mark a project as having unsaved changes
   */
  markDirty(projectId: number): void {
    dirtyProjects.add(projectId);
  },

  /**
   * Start the auto-save loop
   */
  startAutoSave(): void {
    if (autoSaveTimer) return;

    autoSaveTimer = setInterval(() => {
      if (dirtyProjects.size === 0) return;

      for (const projectId of dirtyProjects) {
        try {
          projectRepo.touch(projectId);
          dirtyProjects.delete(projectId);
          console.log(`[ProjectService] Auto-saved project ${projectId}`);
        } catch (err) {
          console.error(`[ProjectService] Auto-save failed for project ${projectId}:`, err);
        }
      }
    }, AUTO_SAVE_INTERVAL_MS);
  },

  /**
   * Stop the auto-save loop
   */
  stopAutoSave(): void {
    if (autoSaveTimer) {
      clearInterval(autoSaveTimer);
      autoSaveTimer = null;
    }
  },

  /**
   * On launch: clean up orphaned temp files from previous crash
   */
  recoverFromCrash(): void {
    const tempDir = path.join(app.getPath('temp'), 'abscido');
    if (!fs.existsSync(tempDir)) return;

    try {
      const files = fs.readdirSync(tempDir);
      let cleaned = 0;
      for (const file of files) {
        const filePath = path.join(tempDir, file);
        fs.unlinkSync(filePath);
        cleaned++;
      }
      if (cleaned > 0) {
        console.log(`[ProjectService] Crash recovery: removed ${cleaned} orphaned temp files`);
      }
    } catch (err) {
      console.warn('[ProjectService] Crash recovery error:', err);
    }
  },

  /**
   * Get the default projects directory
   */
  getProjectsDirectory(): string {
    return path.join(app.getPath('documents'), 'Abscido Projects');
  },
};

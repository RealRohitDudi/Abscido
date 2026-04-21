import { getDatabase } from '../database';
import type { Project } from '../../../shared/types';

interface ProjectRow {
  id: number;
  name: string;
  created_at: string;
  updated_at: string;
  export_path: string | null;
}

function rowToProject(row: ProjectRow): Project {
  return {
    id: row.id,
    name: row.name,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    exportPath: row.export_path,
  };
}

export const projectRepo = {
  create(name: string): Project {
    const db = getDatabase();
    const stmt = db.prepare(`
      INSERT INTO projects (name) VALUES (?)
    `);
    const result = stmt.run(name);
    return this.findById(result.lastInsertRowid as number)!;
  },

  findById(id: number): Project | null {
    const db = getDatabase();
    const row = db
      .prepare('SELECT * FROM projects WHERE id = ?')
      .get(id) as ProjectRow | undefined;
    return row ? rowToProject(row) : null;
  },

  findAll(): Project[] {
    const db = getDatabase();
    const rows = db
      .prepare('SELECT * FROM projects ORDER BY updated_at DESC')
      .all() as ProjectRow[];
    return rows.map(rowToProject);
  },

  update(id: number, data: Partial<Pick<Project, 'name' | 'exportPath'>>): Project | null {
    const db = getDatabase();
    const fields: string[] = ['updated_at = datetime(\'now\')'];
    const values: (string | null | number)[] = [];

    if (data.name !== undefined) {
      fields.push('name = ?');
      values.push(data.name);
    }
    if (data.exportPath !== undefined) {
      fields.push('export_path = ?');
      values.push(data.exportPath);
    }

    values.push(id);
    db.prepare(`UPDATE projects SET ${fields.join(', ')} WHERE id = ?`).run(...values);
    return this.findById(id);
  },

  delete(id: number): void {
    const db = getDatabase();
    db.prepare('DELETE FROM projects WHERE id = ?').run(id);
  },

  touch(id: number): void {
    const db = getDatabase();
    db.prepare("UPDATE projects SET updated_at = datetime('now') WHERE id = ?").run(id);
  },
};

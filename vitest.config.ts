import { defineConfig } from 'vitest/config';
import path from 'path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['src/tests/**/*.test.ts'],
    alias: {
      '@shared': path.resolve(__dirname, 'src/shared'),
    },
  },
});

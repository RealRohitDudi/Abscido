import { app, BrowserWindow, Menu, shell, protocol, net } from 'electron';
import path from 'path';
import { getDatabase, closeDatabase } from './db/database';
import { registerAllHandlers } from './ipc/index';
import { projectService } from './services/project.service';


const isDev = !app.isPackaged;

let mainWindow: BrowserWindow | null = null;

// ─── Codec & hardware acceleration flags (must be set before app.whenReady) ─────
// These unlock HEVC / H.265, hardware decoding, and .mov support on macOS
app.commandLine.appendSwitch('enable-accelerated-video-decode');
app.commandLine.appendSwitch('enable-gpu-rasterization');
if (process.platform === 'darwin') {
  // Enable macOS native HEVC decoder (needed for many .mov screen recordings)
  app.commandLine.appendSwitch('enable-features', 'PlatformHEVCDecoderSupport');
}

// ─── Media protocol (must register scheme BEFORE app is ready) ───────────────
// Allows the renderer to load local media files via media:///absolute/path
// with full range-request support (required for video seeking).
protocol.registerSchemesAsPrivileged([
  {
    scheme: 'media',
    privileges: {
      secure: true,
      standard: true,
      stream: true,
      supportFetchAPI: true,
      bypassCSP: true,
    },
  },
]);

function createWindow(): void {
  mainWindow = new BrowserWindow({
    width: 1440,
    height: 900,
    minWidth: 1024,
    minHeight: 700,
    backgroundColor: '#0f0f0f',
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: false, // Required for preload to access Node built-ins via contextBridge
      webSecurity: true,
    },
    show: false, // Show after ready-to-show to avoid white flash
  });

  // Set CSP
  mainWindow.webContents.session.webRequest.onHeadersReceived((details, callback) => {
    callback({
      responseHeaders: {
        ...details.responseHeaders,
        'Content-Security-Policy': [
          isDev
            ? "default-src 'self' 'unsafe-inline' 'unsafe-eval' http://localhost:5173 ws://localhost:5173; img-src 'self' data: blob:; media-src 'self' blob: file:;"
            : "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; media-src 'self' blob: file:;",
        ],
      },
    });
  });

  // Show window gracefully
  mainWindow.once('ready-to-show', () => {
    mainWindow?.show();
  });

  // Load renderer
  if (isDev) {
    mainWindow.loadURL('http://localhost:5173');
    mainWindow.webContents.openDevTools({ mode: 'detach' });
  } else {
    mainWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }

  mainWindow.on('closed', () => {
    mainWindow = null;
  });

  // Handle external link opens
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: 'deny' };
  });
}

function buildAppMenu(): void {
  const template: Electron.MenuItemConstructorOptions[] = [
    {
      label: app.name,
      submenu: [
        { role: 'about' },
        { type: 'separator' },
        {
          label: 'Settings',
          accelerator: 'Cmd+,',
          click: () => mainWindow?.webContents.send('app:openSettings'),
        },
        { type: 'separator' },
        { role: 'services' },
        { type: 'separator' },
        { role: 'hide' },
        { role: 'hideOthers' },
        { role: 'unhide' },
        { type: 'separator' },
        { role: 'quit' },
      ],
    },
    {
      label: 'File',
      submenu: [
        {
          label: 'New Project',
          accelerator: 'CmdOrCtrl+N',
          click: () => mainWindow?.webContents.send('app:newProject'),
        },
        {
          label: 'Open Project',
          accelerator: 'CmdOrCtrl+O',
          click: () => mainWindow?.webContents.send('app:openProject'),
        },
        { type: 'separator' },
        {
          label: 'Import Media',
          accelerator: 'CmdOrCtrl+I',
          click: () => mainWindow?.webContents.send('app:importMedia'),
        },
        { type: 'separator' },
        {
          label: 'Save Project',
          accelerator: 'CmdOrCtrl+S',
          click: () => mainWindow?.webContents.send('app:saveProject'),
        },
        { type: 'separator' },
        {
          label: 'Export',
          accelerator: 'CmdOrCtrl+E',
          click: () => mainWindow?.webContents.send('app:export'),
        },
      ],
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' },
        { role: 'selectAll' },
      ],
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        isDev ? { role: 'toggleDevTools' } : { label: '', visible: false },
        { type: 'separator' },
        { role: 'resetZoom' },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
      ],
    },
    {
      label: 'Window',
      submenu: [{ role: 'minimize' }, { role: 'zoom' }, { role: 'close' }],
    },
  ];

  const menu = Menu.buildFromTemplate(template);
  Menu.setApplicationMenu(menu);
}

// ─── App Lifecycle ──────────────────────────────────────────────────────────

app.whenReady().then(() => {
  // Initialize database
  getDatabase();

  // Register media:// protocol with correct MIME types and range-request support.
  // net.fetch('file://') may return Content-Type: application/octet-stream which
  // Chromium rejects. We rebuild the response with the correct video/* type.
  const MIME_MAP: Record<string, string> = {
    '.mov':  'video/quicktime',
    '.mp4':  'video/mp4',
    '.m4v':  'video/mp4',
    '.mkv':  'video/x-matroska',
    '.avi':  'video/x-msvideo',
    '.webm': 'video/webm',
    '.ogv':  'video/ogg',
    '.mp3':  'audio/mpeg',
    '.aac':  'audio/aac',
    '.wav':  'audio/wav',
    '.m4a':  'audio/mp4',
    '.ogg':  'audio/ogg',
    '.flac': 'audio/flac',
  };

  protocol.handle('media', async (request) => {
    // Path is passed as query param ?p= to avoid Electron's standard-protocol
    // host-normalization bug (media:///Users/foo → media://users/foo, losing leading /)
    const url = new URL(request.url);
    const filePath = url.searchParams.get('p') ?? '';
    if (!filePath) return new Response('Missing path', { status: 400 });

    const ext = path.extname(filePath).toLowerCase();
    const contentType = MIME_MAP[ext] ?? 'video/mp4';

    try {
      // Encode spaces/special chars but keep slashes
      const encoded = filePath.split('/').map(encodeURIComponent).join('/');
      const response = await net.fetch('file://' + encoded);
      const headers = new Headers(response.headers);
      headers.set('Content-Type', contentType);
      headers.set('Accept-Ranges', 'bytes');
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers,
      });
    } catch (err) {
      console.error('[media://] failed to serve:', filePath, err);
      return new Response('File not found', { status: 404 });
    }
  });

  // Crash recovery: clean up orphaned temp files
  projectService.recoverFromCrash();

  // Register all IPC handlers
  registerAllHandlers();

  // Start auto-save
  projectService.startAutoSave();

  // Build native menu
  buildAppMenu();

  // Create the main window
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  projectService.stopAutoSave();
  closeDatabase();
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('before-quit', () => {
  projectService.stopAutoSave();
  closeDatabase();
});

// Prevent navigation to external URLs
app.on('web-contents-created', (_event, contents) => {
  contents.on('will-navigate', (event, navigationUrl) => {
    const parsedUrl = new URL(navigationUrl);
    if (isDev && parsedUrl.hostname === 'localhost') return;
    event.preventDefault();
  });
});

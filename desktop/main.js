// Electron shell for ZACman (Kugelschlucker). Loads the exact same web/index.html
// that runs in the browser artifact, as a native window — this is the packaging
// target for a Steam build (see ../docs/STEAM_ROADMAP.md for the full path from
// here to a Steamworks upload).
const { app, BrowserWindow, Menu, globalShortcut } = require('electron');
const path = require('path');

function createWindow() {
  const win = new BrowserWindow({
    width: 1400,
    height: 900,
    minWidth: 900,
    minHeight: 600,
    backgroundColor: '#05070f',
    title: 'ZACman',
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  Menu.setApplicationMenu(null);
  win.loadFile(path.join(__dirname, '..', 'web', 'index.html'));

  win.once('ready-to-show', () => win.show());

  // F11 toggles a native fullscreen window (in addition to the page's own
  // pointer-lock/fullscreen handling from a click, which still works too).
  win.webContents.on('did-finish-load', () => {
    globalShortcut.register('F11', () => win.setFullScreen(!win.isFullScreen()));
  });

  win.on('closed', () => globalShortcut.unregisterAll());
}

app.whenReady().then(createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit();
});

app.on('activate', () => {
  if (BrowserWindow.getAllWindows().length === 0) createWindow();
});

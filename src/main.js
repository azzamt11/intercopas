const { app, BrowserWindow, clipboard, ipcMain, nativeTheme } = require('electron');
const path = require('node:path');
const fs = require('node:fs');

const API_BASE = 'https://threads-api.aazzam.my.id';
const POST_TYPE = 'clipboard';
const POLL_INTERVAL_MS = 15_000;
let mainWindow;
let pollTimer;
let watchTimer;
let token = '';
let enabled = false;
let busy = false;
let lastClipboard = '';
let newestPostId = 0;
let lastRemoteContent = '';
let cursorInitialized = false;
let activity = 'Connect your API account to start syncing.';
let latestClipboard = '';

const settingsPath = () => path.join(app.getPath('userData'), 'settings.json');
function readSettings() {
  try { return JSON.parse(fs.readFileSync(settingsPath(), 'utf8')); }
  catch { return {}; }
}
function saveSettings() {
  fs.mkdirSync(path.dirname(settingsPath()), { recursive: true });
  fs.writeFileSync(settingsPath(), JSON.stringify({ token, enabled }, null, 2), { mode: 0o600 });
}
function status() {
  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.webContents.send('sync-status', { enabled, connected: Boolean(token), activity, latestClipboard });
  }
}
function setActivity(value) { activity = value; status(); }
function authHeaders() { return { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }; }
async function api(pathname, options = {}) {
  const response = await fetch(`${API_BASE}${pathname}`, { ...options, headers: { ...authHeaders(), ...options.headers } });
  if (!response.ok) throw new Error(`${response.status}: ${(await response.text()).slice(0, 180)}`);
  if (response.status === 204) return null;
  return response.json();
}

async function login(phone, password) {
  const response = await fetch(`${API_BASE}/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone, password })
  });
  if (!response.ok) throw new Error(`${response.status}: ${(await response.text()).slice(0, 180)}`);
  const result = await response.json();
  if (!result.token) throw new Error('The login response did not include a token.');
  token = result.token;
  enabled = true;
  newestPostId = 0; lastRemoteContent = ''; cursorInitialized = false; latestClipboard = '';
  saveSettings(); startSync();
  return { ok: true, user: result.user?.name || '' };
}

async function uploadClipboard(content) {
  if (!token || !enabled || !content.trim()) return;
  try {
    await api('/posts', { method: 'POST', body: JSON.stringify({ content, type: POST_TYPE, parent_post_id: null }) });
    lastRemoteContent = content;
    setActivity(`Copied to Intercopas · ${new Date().toLocaleTimeString()}`);
  } catch (error) {
    setActivity(`Upload failed: ${error.message}`);
  }
}

async function pollPosts() {
  if (!token || !enabled || busy) return;
  busy = true;
  try {
    const posts = await api(`/posts?type=${encodeURIComponent(POST_TYPE)}`);
    const ordered = (posts || []).slice().sort((a, b) => Number(a.id) - Number(b.id));
    if (!cursorInitialized) {
      newestPostId = ordered.reduce((max, post) => Math.max(max, Number(post.id) || 0), 0);
      cursorInitialized = true;
      const latest = ordered.at(-1);
      if (latest?.content) {
        latestClipboard = latest.content;
        lastRemoteContent = latest.content;
        if (latest.content !== lastClipboard) {
          clipboard.writeText(latest.content);
          lastClipboard = latest.content;
        }
      }
      setActivity('Syncing clipboard every 15 seconds.');
      return;
    }
    const unseen = ordered.filter(post => Number(post.id) > newestPostId);
    if (unseen.length) {
      for (const post of unseen) {
        newestPostId = Math.max(newestPostId, Number(post.id) || 0);
        if (post.content && post.content !== lastClipboard) {
          lastRemoteContent = post.content;
          latestClipboard = post.content;
          clipboard.writeText(post.content);
          lastClipboard = post.content;
        }
      }
      if (unseen.length) latestClipboard = unseen[unseen.length - 1].content || latestClipboard;
      setActivity(`Received clipboard · ${new Date().toLocaleTimeString()}`);
    }
  } catch (error) {
    setActivity(`Sync failed: ${error.message}`);
  } finally { busy = false; }
}

function startSync() {
  clearInterval(pollTimer); clearInterval(watchTimer);
  lastClipboard = clipboard.readText();
  if (!enabled || !token) { status(); return; }
  cursorInitialized = false;
  pollPosts();
  pollTimer = setInterval(pollPosts, POLL_INTERVAL_MS);
  watchTimer = setInterval(() => {
    const current = clipboard.readText();
    if (current === lastClipboard) return;
    lastClipboard = current;
    if (current && current !== lastRemoteContent) uploadClipboard(current);
  }, 400);
  setActivity('Syncing clipboard every 15 seconds.');
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 390, height: 510, minWidth: 360, minHeight: 440,
    title: 'Intercopas · Clipboard overlay', backgroundColor: '#f7f5f0',
    alwaysOnTop: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, nodeIntegration: false }
  });
  mainWindow.loadFile(path.join(__dirname, 'index.html'));
  mainWindow.on('closed', () => { mainWindow = null; });
}

app.whenReady().then(() => {
  nativeTheme.themeSource = 'light';
  const settings = readSettings(); token = settings.token || ''; enabled = Boolean(settings.enabled && token);
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
app.on('before-quit', () => { clearInterval(pollTimer); clearInterval(watchTimer); });

ipcMain.handle('get-state', () => ({ enabled, connected: Boolean(token), activity, latestClipboard, apiBase: API_BASE, postType: POST_TYPE, pollSeconds: POLL_INTERVAL_MS / 1000 }));
ipcMain.handle('login', async (_event, credentials) => {
  try { return await login(String(credentials?.phone || '').trim(), String(credentials?.password || '')); }
  catch (error) { return { ok: false, error: error.message }; }
});
ipcMain.handle('set-enabled', (_event, value) => { enabled = Boolean(value && token); saveSettings(); startSync(); return { enabled }; });
ipcMain.handle('copy-now', () => {
  const content = clipboard.readText();
  if (!content.trim()) return { ok: false, error: 'The clipboard has no text to send.' };
  lastClipboard = content; uploadClipboard(content); return { ok: true };
});
ipcMain.handle('fetch-now', () => pollPosts());
ipcMain.handle('get-clipboard', () => clipboard.readText());

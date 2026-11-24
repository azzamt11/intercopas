const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('intercopas', {
  getState: () => ipcRenderer.invoke('get-state'),
  login: credentials => ipcRenderer.invoke('login', credentials),
  setEnabled: enabled => ipcRenderer.invoke('set-enabled', enabled),
  copyNow: () => ipcRenderer.invoke('copy-now'),
  fetchNow: () => ipcRenderer.invoke('fetch-now'),
  getClipboard: () => ipcRenderer.invoke('get-clipboard'),
  onStatus: callback => ipcRenderer.on('sync-status', (_event, state) => callback(state))
});

const $ = id => document.getElementById(id);
const enabledInput = $('enabled');
const activity = $('activity');
let toastTimer;

function toast(message) {
  const node = $('toast'); node.textContent = message; node.classList.add('show');
  clearTimeout(toastTimer); toastTimer = setTimeout(() => node.classList.remove('show'), 2600);
}
function renderState(state) {
  $('connection-state').textContent = state.connected ? 'Connected' : 'Not connected';
  $('connection-state').classList.toggle('on', state.connected);
  enabledInput.checked = state.enabled;
  enabledInput.disabled = !state.connected;
  $('connect').textContent = state.connected ? 'Connected' : 'Sign in';
  $('connect').disabled = state.connected;
  activity.textContent = state.activity;
  $('latest-clipboard').textContent = state.latestClipboard || 'Copy text on this desktop to share it.';
  $('copy-state').textContent = state.latestClipboard ? 'Ready to paste on another desktop' : 'Waiting for a copy';
  document.body.classList.toggle('is-enabled', state.enabled);
}

window.intercopas.onStatus(renderState);
window.intercopas.getState().then(renderState);
$('login-form').addEventListener('submit', async event => {
  event.preventDefault();
  const phone = $('phone').value.trim();
  const password = $('password').value;
  if (!phone || password.length < 4) {
    $('login-error').textContent = 'Enter your phone number and password.';
    return;
  }
  $('connect').disabled = true;
  $('login-error').textContent = 'Signing in…';
  const result = await window.intercopas.login({ phone, password });
  if (result.ok) {
    $('password').value = '';
    $('login-error').textContent = result.user ? `Signed in as ${result.user}.` : 'Signed in successfully.';
    renderState(await window.intercopas.getState());
    toast('Clipboard sync is on.');
  } else {
    $('connect').disabled = false;
    $('login-error').textContent = result.error;
  }
});
enabledInput.addEventListener('change', async () => renderState({ ...(await window.intercopas.getState()), ...(await window.intercopas.setEnabled(enabledInput.checked)) }));
$('send-now').addEventListener('click', async () => {
  const result = await window.intercopas.copyNow();
  toast(result.ok ? 'Current clipboard sent.' : result.error);
});
$('check-now').addEventListener('click', async () => {
  await window.intercopas.fetchNow();
  toast('Checked for new clipboard posts.');
});

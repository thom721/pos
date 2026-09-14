const API = '/api/affiliate';
const TOKEN_KEY = 'affiliate_token';

function getToken() { return localStorage.getItem(TOKEN_KEY); }
function setToken(t) { localStorage.setItem(TOKEN_KEY, t); }
function clearToken() { localStorage.removeItem(TOKEN_KEY); }

async function api(path, { method = 'GET', body, auth = false } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (auth) {
    const t = getToken();
    if (t) headers['Authorization'] = `Bearer ${t}`;
  }
  const res = await fetch(API + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch (_) {}
  if (!res.ok) {
    const detail = (data && (data.detail || data.message)) || 'Une erreur est survenue.';
    throw new Error(typeof detail === 'string' ? detail : JSON.stringify(detail));
  }
  return data;
}

// ── Navigation entre sections ────────────────────────────────────────────
const VIEWS = ['login', 'register', 'verify', 'dashboard'];
function showView(name) {
  const explainer = document.getElementById('explainer');
  const topNav = document.getElementById('topNav');
  explainer.hidden = (name === 'dashboard');
  topNav.hidden = (name === 'dashboard');
  for (const v of VIEWS) {
    document.getElementById('view-' + v).hidden = (v !== name);
  }
}

let _pendingVerifyEmail = null;

// ── Inscription ───────────────────────────────────────────────────────────
document.getElementById('registerForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const msg = document.getElementById('registerMsg');
  msg.textContent = '';
  msg.className = 'msg';
  try {
    const email = document.getElementById('regEmail').value.trim();
    await api('/register', {
      method: 'POST',
      body: {
        full_name: document.getElementById('regName').value.trim(),
        email,
        phone: document.getElementById('regPhone').value.trim() || null,
        password: document.getElementById('regPassword').value,
      },
    });
    _pendingVerifyEmail = email;
    document.getElementById('verifyEmailLabel').textContent = email;
    showView('verify');
  } catch (err) {
    msg.textContent = err.message;
    msg.className = 'msg error';
  }
});

// ── Vérification email ───────────────────────────────────────────────────
document.getElementById('verifyForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const msg = document.getElementById('verifyMsg');
  msg.textContent = '';
  msg.className = 'msg';
  try {
    await api('/verify-email', {
      method: 'POST',
      body: { email: _pendingVerifyEmail, code: document.getElementById('verifyCode').value.trim() },
    });
    msg.textContent = 'Email vérifié — vous pouvez vous connecter.';
    msg.className = 'msg ok';
    setTimeout(() => showView('login'), 1200);
  } catch (err) {
    msg.textContent = err.message;
    msg.className = 'msg error';
  }
});

async function resendCode() {
  if (!_pendingVerifyEmail) return;
  try {
    await api('/resend-code', { method: 'POST', body: { email: _pendingVerifyEmail } });
    const msg = document.getElementById('verifyMsg');
    msg.textContent = 'Code renvoyé.';
    msg.className = 'msg ok';
  } catch (_) {}
}

// ── Connexion ─────────────────────────────────────────────────────────────
document.getElementById('loginForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const msg = document.getElementById('loginMsg');
  msg.textContent = '';
  msg.className = 'msg';
  try {
    const data = await api('/login', {
      method: 'POST',
      body: {
        email: document.getElementById('loginEmail').value.trim(),
        password: document.getElementById('loginPassword').value,
      },
    });
    setToken(data.access_token);
    await loadDashboard();
  } catch (err) {
    msg.textContent = err.message;
    msg.className = 'msg error';
  }
});

function logout() {
  clearToken();
  showView('login');
}

// ── Dashboard ─────────────────────────────────────────────────────────────
function fmtMoney(n) {
  return Number(n).toLocaleString('fr-FR', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + ' HTG';
}

const STATUS_LABEL = { pending: 'En attente', approved: 'Approuvé', paid: 'Payé', rejected: 'Rejeté' };

async function loadDashboard() {
  try {
    const d = await api('/me/dashboard', { auth: true });
    document.getElementById('dashName').textContent = d.full_name;
    document.getElementById('dashBalance').textContent = fmtMoney(d.available_balance);

    const link = `${window.location.origin}/register?ref=${d.referral_code}`;
    document.getElementById('refLinkInput').value = link;

    const tBody = document.querySelector('#tenantsTable tbody');
    tBody.innerHTML = '';
    document.getElementById('tenantsEmpty').hidden = d.referred_tenants.length > 0;
    for (const t of d.referred_tenants) {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${escapeHtml(t.business_name)}</td>` +
        `<td>${new Date(t.created_at).toLocaleDateString('fr-FR')}</td>` +
        `<td>${fmtMoney(t.total_earned)}</td>`;
      tBody.appendChild(tr);
    }

    const wBody = document.querySelector('#withdrawalsTable tbody');
    wBody.innerHTML = '';
    document.getElementById('withdrawalsEmpty').hidden = d.withdrawals.length > 0;
    for (const w of d.withdrawals) {
      const tr = document.createElement('tr');
      tr.innerHTML = `<td>${new Date(w.created_at).toLocaleDateString('fr-FR')}</td>` +
        `<td>${fmtMoney(w.amount)}</td>` +
        `<td><span class="status-pill status-${w.status}">${STATUS_LABEL[w.status] || w.status}</span></td>`;
      wBody.appendChild(tr);
    }

    showView('dashboard');
  } catch (err) {
    clearToken();
    showView('login');
  }
}

function escapeHtml(s) {
  const d = document.createElement('div');
  d.textContent = s;
  return d.innerHTML;
}

function copyRefLink() {
  const input = document.getElementById('refLinkInput');
  input.select();
  navigator.clipboard?.writeText(input.value).catch(() => document.execCommand('copy'));
}

document.getElementById('withdrawForm').addEventListener('submit', async (e) => {
  e.preventDefault();
  const msg = document.getElementById('wdMsg');
  msg.textContent = '';
  msg.className = 'msg';
  try {
    await api('/me/withdrawals', {
      method: 'POST',
      auth: true,
      body: {
        amount: parseFloat(document.getElementById('wdAmount').value),
        payout_method: document.getElementById('wdMethod').value.trim(),
      },
    });
    msg.textContent = 'Demande de retrait envoyée.';
    msg.className = 'msg ok';
    document.getElementById('withdrawForm').reset();
    await loadDashboard();
  } catch (err) {
    msg.textContent = err.message;
    msg.className = 'msg error';
  }
});

// ── Démarrage ─────────────────────────────────────────────────────────────
if (getToken()) {
  loadDashboard();
} else {
  showView('login');
}

(function () {
  const pageNames = {
    'index.html': 'home',
    'Proclamateurs.html': 'proclamateurs',
    'groupes.html': 'pdf:allgroups',
    'Rapports.html': 'rapports',
    'Messagerie.html': 'rapports',
    'attention-pastorale.html': 'rapports:attention',
    'Programmation.html': 'programmation',
    'Souscription.html': 'souscription',
    'assistance.html': 'assistance',
    'pdf.html': 'pdf',
    'pionnier_encourager.html': 'pionnier_encourager',
    'debonhomme2fr.html': 'taches'
  };

  function currentPage() {
    const file = window.location.pathname.split('/').pop() || 'index.html';
    return pageNames[file] || 'home';
  }

  function accessKey() {
    return `assemblee-access-${window.appAuth.config.assemblyId}`;
  }

  function clearAuthSession() {
    localStorage.removeItem('sb-grrxlasibdntcjuqqfjl-auth-token');
    localStorage.removeItem('sb-fmffzzmlsnmlxfuwnmka-auth-token');
  }

  function cacheAccess(access) {
    localStorage.setItem(accessKey(), JSON.stringify(access));
  }

  function readCachedAccess() {
    try { return JSON.parse(localStorage.getItem(accessKey()) || 'null'); } catch (_) { return null; }
  }

  function applyMenuPermissions(access) {
    document.querySelectorAll('[data-page]').forEach(link => {
      const allowed = ['owner', 'coordinateur', 'secretaire'].includes(access.role) || access.pages.some(page => page === link.dataset.page || page.startsWith(`${link.dataset.page}:`));
      link.hidden = !allowed;
    });
    document.querySelectorAll('[data-access-feature]').forEach(element => {
      const feature = element.dataset.accessFeature;
      const parent = feature.split(':')[0];
      const allowed = ['owner', 'coordinateur', 'secretaire'].includes(access.role) || access.pages.includes(feature) || access.pages.includes(parent);
      element.hidden = !allowed;
    });
    document.querySelectorAll('[data-access-feature].active[hidden]').forEach(active => {
      const replacement = active.closest('ul, .nav')?.querySelector('[data-access-feature]:not([hidden])');
      if (replacement) replacement.click();
    });
    window.dispatchEvent(new CustomEvent('app-access-ready', { detail: access }));
  }

  function hasPageAccess(access, page) {
    const parent = page.split(':')[0];
    return ['owner', 'coordinateur', 'secretaire'].includes(access.role) || access.pages.some(item => item === page || item === parent || item.startsWith(`${page}:`));
  }

  function showAccessStatus(access) {
    const element = document.getElementById('accessStatus');
    if (element) element.textContent = `Rôle : ${access.role}`;
  }

  function getUserFullName(user) {
    const metadata = user?.user_metadata || {};
    const firstName = metadata.prenom || metadata.first_name || metadata.firstName || '';
    const lastName = metadata.nom || metadata.last_name || metadata.lastName || '';
    return [firstName, lastName].filter(Boolean).join(' ').replace(/\s+/g, ' ').trim();
  }

  function showUserIdentity(user) {
    const fullName = getUserFullName(user) || localStorage.getItem('assemblee-user-name') || user?.email || 'Utilisateur connecté';
    const element = document.getElementById('userInfo');
    if (element) element.textContent = fullName;
    if (fullName !== user?.email && fullName !== 'Utilisateur connecté') {
      localStorage.setItem('assemblee-user-name', fullName);
    }
  }

  async function loadAccess(userId) {
    const assemblyId = window.appAuth.config.assemblyId;
    const { data: membership, error: membershipError } = await window.appAuth.client
      .from('assembly_memberships').select('role,proclamateur_id').eq('assembly_id', assemblyId).eq('user_id', userId).maybeSingle();
    if (membershipError || !membership) return null;
    const { data: permissions, error: permissionsError } = await window.appAuth.client
      .from('assembly_page_permissions').select('page_key').eq('assembly_id', assemblyId).eq('user_id', userId);
    if (permissionsError) throw permissionsError;
    return { role: membership.role, pages: (permissions || []).map(item => item.page_key), proclamateurId: membership.proclamateur_id || '' };
  }

  async function requestAccess() {
    try {
      await window.appAuth.client.rpc('request_assembly_access', { target_assembly_id: window.appAuth.config.assemblyId });
    } catch (error) {
      console.warn('Demande d’accès indisponible :', error);
    }
  }

  function denyPage() {
    if (currentPage() !== 'home') window.location.replace('index.html?access=denied');
  }
  function isLoginPage() {
    return /connexion\.html$/i.test(window.location.pathname);
  }

  function hasOfflineAccess() {
    return localStorage.getItem('assemblee-offline-access') === 'true';
  }

  function showOfflineStatus() {
    const status = document.createElement('div');
    status.setAttribute('role', 'status');
    status.style.cssText = 'position:fixed;left:16px;right:16px;bottom:16px;z-index:2000;padding:12px 16px;border:1px solid #b9cbd4;border-radius:8px;background:#eef5f7;color:#214b63;font:600 13px/1.4 Arial,sans-serif;box-shadow:0 8px 20px rgba(0,0,0,.12)';
    status.textContent = 'Mode hors connexion : vos données restent locales et seront synchronisées au retour d’Internet.';
    document.body.appendChild(status);
  }

  function showConfigurationWarning() {
    const warning = document.createElement('div');
    warning.setAttribute('role', 'status');
    warning.style.cssText = 'position:fixed;left:16px;right:16px;bottom:16px;z-index:2000;padding:12px 16px;border:1px solid #d8c39a;border-radius:8px;background:#fff8e6;color:#5f4b20;font:600 13px/1.4 Arial,sans-serif;box-shadow:0 8px 20px rgba(0,0,0,.12)';
    warning.textContent = 'Supabase non disponible. L’application continue en mode local et synchronise dès que la configuration est active.';
    document.body.appendChild(warning);
  }

  async function protectPage() {
    if (isLoginPage()) return;

    const configured = window.appAuth?.validate
      ? await window.appAuth.validate()
      : Boolean(window.appAuth?.configured && window.appAuth.client);

    if (!configured || !window.appAuth?.client) {
      const access = readCachedAccess();
      if (access) {
        applyMenuPermissions(access);
        showAccessStatus(access);
        showUserIdentity({ email: localStorage.getItem('assemblee-offline-email') || 'Utilisateur local' });
        showOfflineStatus();
        if (!hasPageAccess(access, currentPage())) denyPage();
        return;
      }
      showConfigurationWarning();
      return;
    }

    let access = readCachedAccess();
    if (!navigator.onLine && hasOfflineAccess() && access) {
      applyMenuPermissions(access);
      showAccessStatus(access);
      showUserIdentity({ email: localStorage.getItem('assemblee-offline-email') });
      showOfflineStatus();
          if (!hasPageAccess(access, currentPage())) denyPage();
    } else {
      try {
        const { data, error } = await window.appAuth.client.auth.getSession();
        if ((error || !data.session) && !hasOfflineAccess()) {
          window.location.replace('connexion.html');
          return;
        }
        if (data.session) {
          localStorage.setItem('assemblee-offline-access', 'true');
          localStorage.setItem('assemblee-offline-email', data.session.user?.email || '');
          showUserIdentity(data.session.user);
          access = await loadAccess(data.session.user.id);
          if (!access) {
            await requestAccess();
            alert('Votre demande d’accès a été envoyée. Un administrateur doit encore vous autoriser.');
            await window.appAuth.client.auth.signOut();
            window.location.replace('connexion.html');
            return;
          }
          cacheAccess(access);
          applyMenuPermissions(access);
          showAccessStatus(access);
          if (!hasPageAccess(access, currentPage())) {
            denyPage();
            return;
          }
        }
        if (error && hasOfflineAccess() && access) showOfflineStatus();
      } catch (error) {
        if (!hasOfflineAccess() || !access) {
          window.location.replace('connexion.html');
          return;
        }
        applyMenuPermissions(access);
        showAccessStatus(access);
        showUserIdentity({ email: localStorage.getItem('assemblee-offline-email') });
        if (!hasPageAccess(access, currentPage())) denyPage();
        showOfflineStatus();
      }
    }
    const logoutButton = document.getElementById('logoutBtn');
    if (logoutButton) {
      logoutButton.addEventListener('click', async event => {
        event.preventDefault();
        logoutButton.setAttribute('aria-busy', 'true');
        localStorage.removeItem('assemblee-offline-access');
        localStorage.removeItem('assemblee-offline-email');
        localStorage.removeItem('assemblee-user-name');
        localStorage.removeItem(accessKey());
        clearAuthSession();
        try {
          await Promise.race([
            window.appAuth.client.auth.signOut({ scope: 'local' }),
            new Promise(resolve => window.setTimeout(resolve, 1500))
          ]);
        } catch (error) {
          console.warn('Déconnexion distante indisponible :', error);
        } finally {
          window.location.replace('connexion.html');
        }
      });
    }
  }

  window.appAuthAccess = {
    pageNames,
    getCached: readCachedAccess,
    isAdmin: () => ['owner', 'coordinateur', 'secretaire'].includes(readCachedAccess()?.role)
  };

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', protectPage, { once: true });
  } else {
    protectPage();
  }
})();

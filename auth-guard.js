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
    return page === 'home' || ['owner', 'coordinateur', 'secretaire'].includes(access.role) || access.pages.some(item => item === page || item === parent || item.startsWith(`${page}:`));
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
    if (membershipError) throw membershipError;
    if (!membership) return null;
    if (!['owner', 'coordinateur', 'secretaire'].includes(membership.role)) {
      if (!membership.proclamateur_id) return null;
      const { data: member, error: memberError } = await window.appAuth.client
        .from('app_sync_records')
        .select('record_id')
        .eq('assembly_id', assemblyId)
        .eq('database_name', 'ProclamateursDB')
        .eq('store_name', 'proclamateurs')
        .eq('record_id', membership.proclamateur_id)
        .is('deleted_at', null)
        .maybeSingle();
      if (memberError) throw memberError;
      if (!member) return null;
    }
    const { data: permissions, error: permissionsError } = await window.appAuth.client
      .from('assembly_page_permissions').select('page_key').eq('assembly_id', assemblyId).eq('user_id', userId);
    if (permissionsError) throw permissionsError;
    return { role: membership.role, pages: (permissions || []).map(item => item.page_key), proclamateurId: membership.proclamateur_id || '' };
  }

  function denyPage() {
    if (currentPage() !== 'home') window.location.replace('index.html?access=denied');
  }
  function isLoginPage() {
    return /connexion\.html$/i.test(window.location.pathname);
  }

  async function protectPage() {
    if (isLoginPage()) return;
    document.documentElement.style.visibility = 'hidden';
    localStorage.removeItem('assemblee-offline-access');

    const configured = window.appAuth?.validate
      ? await window.appAuth.validate()
      : Boolean(window.appAuth?.configured && window.appAuth.client);

    if (!configured || !window.appAuth?.client) {
      if (!isLoginPage()) window.location.replace('connexion.html');
      return;
    }

    let access = null;
    try {
      const { data, error } = await window.appAuth.client.auth.getSession();
      if (error) throw error;
      if (!data.session) {
        localStorage.removeItem('assemblee-offline-email');
        localStorage.removeItem(accessKey());
        window.location.replace('connexion.html');
        return;
      }

      showUserIdentity(data.session.user);
      access = await loadAccess(data.session.user.id);
      if (!access) {
        localStorage.removeItem('assemblee-offline-email');
        localStorage.removeItem(accessKey());
        try {
          await window.appAuth.client.auth.signOut({ scope: 'local' });
        } catch (signOutError) {
          console.warn('Impossible de fermer la session sans accès membre :', signOutError);
        }
        alert('L’accès est réservé aux membres invités et associés à une fiche de l’assemblée.');
        window.location.replace('connexion.html');
        return;
      }
      localStorage.setItem('assemblee-offline-email', data.session.user?.email || '');
      cacheAccess(access);
      applyMenuPermissions(access);
      showAccessStatus(access);
      if (!hasPageAccess(access, currentPage())) {
        denyPage();
        return;
      }
    } catch (error) {
      console.error('Vérification des droits membre impossible :', error);
      window.location.replace('connexion.html');
      return;
    }
    document.documentElement.style.visibility = '';
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

(function () {
  const databases = [
    { name: 'ProclamateursDB', stores: ['proclamateurs', 'detailPredication', 'pionniersAuxiliaire', 'permanentCandidatures', 'groupLeaders'] },
    { name: 'AssistanceDB', stores: ['attendance'] },
    { name: 'ProgrammationDB', stores: ['visites', 'epreuves', 'formations'] },
    { name: 'GestionDB', stores: ['tasks'] }
  ];
  const stateKey = 'assemblee-sync-state-v2';
  const localBroadcastKey = 'assemblee-local-sync';
  const memberPrivateFields = [
    'birthdate', 'age', 'contactName', 'contactPhone', 'dateNaissance', 'date_naissance',
    'datenaissance', 'datedenaissance', 'dateDeNaissance', 'date_of_birth', 'dateOfBirth',
    'naissance', 'birth', 'dob', 'personne_a_contacter', 'personneContact', 'personne_contact',
    'personne', 'contact_telephone', 'contact_tel', 'telephone_contact', 'numero_contact',
    'contactNumber', 'contact_name', 'emergencyContactName', 'emergency_contact_name',
    'emergencyContactPhone', 'emergency_contact_phone', 'contact'
  ];
  let running = false;
  let realtimeChannel = null;
  let hasUnsavedChanges = false;
  let refreshTimer = null;
  let syncScheduleTimer = null;
  let syncPending = false;
  let updateReloadRequested = false;
  let availableLocalStores = new Set();
  const ignoredTransactions = new WeakSet();

  function getSupabaseClient() {
    if (window.appAuth?.client) return window.appAuth.client;
    if (window.supabase && typeof window.supabase.createClient === 'function' && window.appAuth?.config) {
      return window.supabase.createClient(window.appAuth.config.url, window.appAuth.config.anonKey, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
      });
    }
    return null;
  }

  function broadcastLocalUpdate(type, payload) {
    if (!('BroadcastChannel' in window)) return;
    try {
      const channel = new BroadcastChannel(localBroadcastKey);
      channel.postMessage({ type, payload, source: 'local-app' });
      channel.close();
    } catch (_) {
      // ignorer le fallback si BroadcastChannel n’est pas disponible
    }
  }

  function recordId(record) {
    return String(record?.id ?? record?.proclamateurId ?? record?.group ?? '');
  }

  function fingerprint(record) {
    function sortKeys(value) {
      if (Array.isArray(value)) return value.map(sortKeys);
      if (value && typeof value === 'object') {
        return Object.keys(value).sort().reduce((sorted, key) => {
          sorted[key] = sortKeys(value[key]);
          return sorted;
        }, {});
      }
      return value;
    }
    return JSON.stringify(sortKeys(record));
  }

  function getMemberPrivateData(payload) {
    const privateData = {};
    const birthdate = payload.birthdate || payload.dateNaissance || payload.date_naissance || payload.datenaissance || payload.datedenaissance || payload.dateDeNaissance || payload.date_of_birth || payload.dateOfBirth || payload.naissance || payload.birth || payload.dob;
    const contactName = payload.contactName || payload.personne_a_contacter || payload.personneContact || payload.personne_contact || payload.personne || payload.contact_name || payload.emergencyContactName || payload.emergency_contact_name;
    const contactPhone = payload.contactPhone || payload.contact_telephone || payload.contact_tel || payload.telephone_contact || payload.numero_contact || payload.contactNumber || payload.emergencyContactPhone || payload.emergency_contact_phone || payload.contact;
    if (memberPrivateFields.some(field => Object.prototype.hasOwnProperty.call(payload, field) && ['birthdate', 'dateNaissance', 'date_naissance', 'datenaissance', 'datedenaissance', 'dateDeNaissance', 'date_of_birth', 'dateOfBirth', 'naissance', 'birth', 'dob'].includes(field))) {
      privateData.birthdate = birthdate || '';
    }
    if (memberPrivateFields.some(field => Object.prototype.hasOwnProperty.call(payload, field) && ['contactName', 'personne_a_contacter', 'personneContact', 'personne_contact', 'personne', 'contact_name', 'emergencyContactName', 'emergency_contact_name'].includes(field))) {
      privateData.contactName = contactName || '';
    }
    if (memberPrivateFields.some(field => Object.prototype.hasOwnProperty.call(payload, field) && ['contactPhone', 'contact_telephone', 'contact_tel', 'telephone_contact', 'numero_contact', 'contactNumber', 'emergencyContactPhone', 'emergency_contact_phone', 'contact'].includes(field))) {
      privateData.contactPhone = contactPhone || '';
    }
    return privateData;
  }

  function stripMemberPrivateData(payload) {
    const sanitized = { ...payload };
    memberPrivateFields.forEach(field => delete sanitized[field]);
    return sanitized;
  }

  function privateStateKey(item) {
    return `private|${recordKey(item)}`;
  }

  function isPrivateMemberRecord(item) {
    return (item.database_name === 'ProclamateursDB' && item.store_name === 'proclamateurs')
      || (item.database_name === 'ProgrammationDB' && item.store_name === 'epreuves');
  }

  function privateMemberId(item) {
    return item.store_name === 'epreuves'
      ? String(item.payload.frereId || '')
      : String(item.record_id || '');
  }

  function recordTimestamp(record, fallback) {
    const value = record?.updatedAt || record?.updated_at || record?.modifiedAt || record?.modified_at;
    const time = value ? Date.parse(value) : NaN;
    return Number.isFinite(time) ? new Date(time).toISOString() : fallback;
  }

  function readState() {
    try { return JSON.parse(localStorage.getItem(stateKey) || '{}'); } catch (_) { return {}; }
  }

  function writeState(state) {
    localStorage.setItem(stateKey, JSON.stringify(state));
  }

  function showRemoteUpdateNotice(count = 1) {
    let notice = document.getElementById('appRemoteUpdateNotice');
    if (!notice) {
      notice = document.createElement('div');
      notice.id = 'appRemoteUpdateNotice';
      notice.setAttribute('role', 'status');
      notice.style.cssText = 'position:fixed;left:16px;right:16px;bottom:16px;z-index:2100;display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 16px;border:1px solid #b9cbd4;border-radius:8px;background:#eef5f7;color:#214b63;font:600 13px/1.4 Arial,sans-serif;box-shadow:0 8px 20px rgba(0,0,0,.12)';
      const message = document.createElement('span');
      message.dataset.role = 'message';
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = 'Actualiser maintenant';
      button.style.cssText = 'padding:7px 12px;border:0;border-radius:6px;background:#214b63;color:#fff;font:inherit;cursor:pointer';
      button.addEventListener('click', () => window.location.reload());
      notice.append(message, button);
      document.body.appendChild(notice);
    }
    const message = notice.querySelector('[data-role="message"]');
    if (message) {
      message.textContent = hasUnsavedChanges
        ? `${count} mise${count > 1 ? 's' : ''} à jour reçue${count > 1 ? 's' : ''}. Actualisez lorsque vos modifications en cours sont enregistrées.`
        : `${count} mise${count > 1 ? 's' : ''} à jour reçue${count > 1 ? 's' : ''}. Actualisation de l’écran…`;
    }
  }

  function refreshForRemoteUpdate() {
    showRemoteUpdateNotice();
    if (hasUnsavedChanges) return;
    window.clearTimeout(refreshTimer);
    refreshTimer = window.setTimeout(() => window.location.reload(), 500);
  }

  function scheduleSync(reason) {
    window.clearTimeout(syncScheduleTimer);
    syncScheduleTimer = window.setTimeout(() => syncNow(reason), 250);
  }

  function watchLocalDatabaseWrites() {
    const databasePrototype = window.IDBDatabase?.prototype;
    const originalTransaction = databasePrototype?.transaction;
    if (!originalTransaction || originalTransaction.appSyncWrapped) return;

    const wrappedTransaction = function (...args) {
      const transaction = originalTransaction.apply(this, args);
      const options = args[1];
      const mode = typeof options === 'string' ? options : options?.mode;
      const isSyncDatabase = databases.some(database => database.name === this.name);
      if (mode === 'readwrite' && isSyncDatabase) {
        transaction.addEventListener('complete', () => {
          if (!ignoredTransactions.has(transaction)) scheduleSync('modification locale');
        }, { once: true });
      }
      return transaction;
    };
    wrappedTransaction.appSyncWrapped = true;
    databasePrototype.transaction = wrappedTransaction;
  }

  function openDatabase(name) {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(name);
      request.onsuccess = event => resolve(event.target.result);
      request.onerror = () => reject(request.error);
    });
  }

  function readStore(database, storeName) {
    return new Promise((resolve, reject) => {
      if (!database.objectStoreNames.contains(storeName)) { resolve([]); return; }
      const request = database.transaction(storeName, 'readonly').objectStore(storeName).getAll();
      request.onsuccess = () => resolve(request.result || []);
      request.onerror = () => reject(request.error);
    });
  }

  async function readLocalRecords() {
    const records = [];
    availableLocalStores = new Set();
    for (const databaseConfig of databases) {
      let database;
      try {
        database = await openDatabase(databaseConfig.name);
      } catch (error) {
        throw new Error(`Impossible de lire la base locale ${databaseConfig.name} : ${error.message}`);
      }
      for (const storeName of databaseConfig.stores) {
        if (!database.objectStoreNames.contains(storeName)) continue;
        availableLocalStores.add(`${databaseConfig.name}|${storeName}`);
        const rows = await readStore(database, storeName);
        rows.forEach(payload => records.push({ database_name: databaseConfig.name, store_name: storeName, record_id: recordId(payload), payload }));
      }
      database.close();
    }
    availableLocalStores.add('LocalStorageDB|pioneerEncouragementReport');
    const storedReport = localStorage.getItem('pioneerEncouragementReport');
    if (storedReport !== null) {
      let value;
      try {
        value = JSON.parse(storedReport);
      } catch (error) {
        throw new Error(`Les données locales des encouragements ne sont pas un JSON valide : ${error.message}`);
      }
      records.push({
        database_name: 'LocalStorageDB',
        store_name: 'pioneerEncouragementReport',
        record_id: 'pioneerEncouragementReport',
        payload: { id: 'pioneerEncouragementReport', value }
      });
    }
    return records.filter(item => item.record_id);
  }

  async function writeLocalRecord(item) {
    if (item.database_name === 'LocalStorageDB' && item.store_name === 'pioneerEncouragementReport') {
      localStorage.setItem('pioneerEncouragementReport', JSON.stringify(item.payload.value));
      return;
    }
    const databaseConfig = databases.find(config => config.name === item.database_name);
    if (!databaseConfig) return;
    const database = await openDatabase(databaseConfig.name);
    if (!database.objectStoreNames.contains(item.store_name)) {
      database.close();
      throw new Error(`Le stockage local ${item.database_name}/${item.store_name} n’est pas initialisé sur cet appareil.`);
    }
    await new Promise((resolve, reject) => {
      const transaction = database.transaction(item.store_name, 'readwrite');
      ignoredTransactions.add(transaction);
      const request = transaction.objectStore(item.store_name).put(item.payload);
      request.onsuccess = resolve;
      request.onerror = () => reject(request.error);
    });
    database.close();
  }

  async function deleteLocalRecord(item) {
    if (item.database_name === 'LocalStorageDB' && item.store_name === 'pioneerEncouragementReport') {
      localStorage.removeItem('pioneerEncouragementReport');
      return;
    }
    const databaseConfig = databases.find(config => config.name === item.database_name);
    if (!databaseConfig) return;
    const database = await openDatabase(databaseConfig.name);
    if (!database.objectStoreNames.contains(item.store_name)) {
      database.close();
      throw new Error(`Le stockage local ${item.database_name}/${item.store_name} n’est pas initialisé sur cet appareil.`);
    }
    await new Promise((resolve, reject) => {
      const transaction = database.transaction(item.store_name, 'readwrite');
      ignoredTransactions.add(transaction);
      const request = transaction.objectStore(item.store_name).delete(item.record_id);
      request.onsuccess = resolve;
      request.onerror = () => reject(request.error);
    });
    database.close();
  }

  function recordKey(item) {
    return `${item.database_name}|${item.store_name}|${item.record_id}`;
  }

  async function applyRemoteRecord(row) {
    if (!row || row.assembly_id !== window.appAuth?.config?.assemblyId) return;
    const state = readState();
    const key = recordKey(row);
    const known = state[key]?.remoteUpdatedAt || '';
    if (known && row.updated_at <= known) return;

    const localRecords = await readLocalRecords();
    if (!availableLocalStores.has(`${row.database_name}|${row.store_name}`)) return;
    const localItem = localRecords.find(item => recordKey(item) === key);
    const localHash = localItem ? fingerprint(localItem.payload) : '';
    if (state[key]?.hash && localHash !== state[key].hash) {
      syncNow('résolution d’une modification locale').catch(error => console.warn('Synchronisation différée indisponible :', error));
      return;
    }
    if (!row.deleted_at && localItem && localHash === fingerprint(row.payload)) {
      state[key] = { hash: localHash, remoteUpdatedAt: row.updated_at };
      writeState(state);
      return;
    }
    if (row.deleted_at && !localItem) return;

    if (row.deleted_at) {
      await deleteLocalRecord(row);
      delete state[key];
    } else {
      await writeLocalRecord(row);
      state[key] = { hash: fingerprint(row.payload), remoteUpdatedAt: row.updated_at };
    }
    writeState(state);
    refreshForRemoteUpdate();
    window.dispatchEvent(new CustomEvent('app-sync-updated', { detail: row }));
  }

  function unsubscribeRealtime() {
    if (!realtimeChannel) return;
    try {
      realtimeChannel.unsubscribe();
    } catch (_) {
      // ignorer si le canal a déjà été détruit
    }
    realtimeChannel = null;
  }

  function subscribeToRealtime() {
    const client = getSupabaseClient();
    const assemblyId = window.appAuth?.config?.assemblyId;
    if (!client || !assemblyId) {
      unsubscribeRealtime();
      return;
    }
    if (realtimeChannel) return;

    const channelName = `assembly-sync-${assemblyId}`;
    realtimeChannel = window.appRealtimeManager?.ensureChannel(channelName, channel => {
      channel.on('postgres_changes', {
        event: '*', schema: 'public', table: 'app_sync_records',
        filter: `assembly_id=eq.${assemblyId}`
      }, payload => {
        if (payload.eventType === 'DELETE') return;
        applyRemoteRecord(payload.new).catch(error => console.warn('Mise à jour temps réel indisponible :', error));
      });
    }, {
      client,
      onStatus: status => {
        if (status === 'SUBSCRIBED') appSyncStatus('Synchronisation en temps réel active.');
        if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
          unsubscribeRealtime();
          appSyncStatus('Synchronisation en attente. Nouvelle tentative automatique.', true);
        }
      }
    });
  }

  async function readRemoteRecords(client, assemblyId) {
    const pageSize = 1000;
    const rows = [];

    for (let offset = 0; ; offset += pageSize) {
      const { data, error } = await client
        .from('app_sync_records')
        .select('*')
        .eq('assembly_id', assemblyId)
        .order('database_name')
        .order('store_name')
        .order('record_id')
        .range(offset, offset + pageSize - 1);
      if (error) throw error;

      rows.push(...(data || []));
      if (!data || data.length < pageSize) return rows;
    }
  }

  async function preparePrivateMemberData(client, assemblyId, localRows, remote, state) {
    const changedRecords = [];
    const pendingHashes = new Map();
    for (const item of localRows) {
      if (!isPrivateMemberRecord(item)) continue;
      const remoteRow = remote.get(recordKey(item));
      if (remoteRow?.deleted_at) continue;
      if (item.store_name === 'epreuves') continue;
      const privateData = getMemberPrivateData(item.payload);
      if (!Object.keys(privateData).length) continue;
      const key = privateStateKey(item);
      const hash = fingerprint(privateData);
      if (state[key]?.hash !== hash) {
        changedRecords.push({ id: privateMemberId(item), ...privateData });
        pendingHashes.set(privateMemberId(item), { key, hash });
      }
    }

    let deniedCount = 0;
    if (changedRecords.length) {
      const { data, error } = await client.rpc('save_assembly_member_private_data', {
        target_assembly_id: assemblyId,
        target_records: changedRecords
      });
      if (error) throw error;
      const deniedIds = new Set((data?.denied_ids || []).map(String));
      deniedCount = Number(data?.denied || 0);
      pendingHashes.forEach((value, id) => {
        state[value.key] = { hash: deniedIds.has(id) ? fingerprint({}) : value.hash };
      });
    }

    for (const item of localRows) {
      if (!isPrivateMemberRecord(item)) continue;
      const sanitized = stripMemberPrivateData(item.payload);
      if (fingerprint(sanitized) !== fingerprint(item.payload)) {
        item.payload = sanitized;
        await writeLocalRecord(item);
      }
    }
    return deniedCount;
  }

  async function refreshPrivateMemberData(client, assemblyId, localRows, state) {
    const { data, error } = await client.rpc('get_assembly_member_private_data', {
      target_assembly_id: assemblyId
    });
    if (error) throw error;
    const privateById = new Map((Array.isArray(data) ? data : []).map(item => [String(item.id), item]));

    for (const item of localRows) {
      if (!isPrivateMemberRecord(item)) continue;
      const personId = privateMemberId(item);
      if (!personId) continue;
      const privateData = item.store_name === 'proclamateurs' ? privateById.get(personId) || {} : {};
      const sanitized = stripMemberPrivateData(item.payload);
      const merged = { ...sanitized, ...privateData };
      if (fingerprint(merged) !== fingerprint(item.payload)) {
        item.payload = merged;
        await writeLocalRecord(item);
      }
      state[privateStateKey(item)] = { hash: fingerprint(getMemberPrivateData(privateData)) };
    }
  }

  function registerServiceWorker() {
    if (!('serviceWorker' in navigator)) return;
    function showAppUpdateNotice(registration) {
      const waitingWorker = registration.waiting;
      if (!waitingWorker || document.getElementById('appVersionUpdateNotice')) return;

      const notice = document.createElement('div');
      notice.id = 'appVersionUpdateNotice';
      notice.setAttribute('role', 'status');
      notice.style.cssText = 'position:fixed;left:16px;right:16px;bottom:76px;z-index:2100;display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 16px;border:1px solid #b9cbd4;border-radius:8px;background:#eef5f7;color:#214b63;font:600 13px/1.4 Arial,sans-serif;box-shadow:0 8px 20px rgba(0,0,0,.12)';

      const message = document.createElement('span');
      message.textContent = 'Une nouvelle version de l’application est disponible.';

      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = 'Actualiser maintenant';
      button.style.cssText = 'padding:7px 12px;border:0;border-radius:6px;background:#214b63;color:#fff;font:inherit;cursor:pointer';
      button.addEventListener('click', () => {
        updateReloadRequested = true;
        button.disabled = true;
        button.textContent = 'Actualisation…';
        waitingWorker.postMessage({ type: 'SKIP_WAITING' });
      });

      notice.append(message, button);
      document.body.appendChild(notice);
    }

    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (updateReloadRequested) window.location.reload();
    });

    navigator.serviceWorker.register('./sw.js').then(registration => {
      if (registration.waiting) showAppUpdateNotice(registration);

      registration.addEventListener('updatefound', () => {
        const installingWorker = registration.installing;
        if (!installingWorker) return;
        installingWorker.addEventListener('statechange', () => {
          if (installingWorker.state === 'installed' && navigator.serviceWorker.controller) {
            showAppUpdateNotice(registration);
          }
        });
      });

      registration.update().catch(error => {
        console.warn('Vérification de la nouvelle version indisponible :', error);
      });
    }).catch(error => {
      console.warn('Mise à jour automatique de l’application indisponible :', error);
    });
  }

  async function syncNow(reason) {
    const client = getSupabaseClient();
    if (running) {
      syncPending = true;
      return;
    }
    if (!navigator.onLine) return;
    running = true;

    const status = window.appSyncStatus;

    try {
      const configured = window.appAuth?.validate
        ? await window.appAuth.validate()
        : Boolean(window.appAuth?.configured && window.appAuth.client);

      if (!client || !configured) {
        appSyncStatus('Mode local uniquement. Configurez Supabase pour la synchronisation multi-utilisateur.', true);
        return;
      }

      const { data: session, error: sessionError } = await client.auth.getSession();
      if (sessionError) throw sessionError;
      if (!session.session) return;
      subscribeToRealtime();
      const assemblyId = window.appAuth.config.assemblyId;
      const remoteRows = await readRemoteRecords(client, assemblyId);
      const remote = new Map(remoteRows.map(row => [recordKey(row), row]));
      const localRows = await readLocalRecords();
      const state = readState();
      const privateDataDenied = await preparePrivateMemberData(client, assemblyId, localRows, remote, state);
      const local = new Map(localRows.map(row => [recordKey(row), row]));
      const outgoing = [];
      let remoteApplied = 0;
      const now = new Date().toISOString();

      for (const item of localRows) {
        const key = recordKey(item);
        const localHash = fingerprint(item.payload);
        const previous = state[key];
        const remoteRow = remote.get(key);
        if (item.store_name === 'detailPredication' && previous && !remoteRow) {
          await deleteLocalRecord(item);
          delete state[key];
          remoteApplied += 1;
          continue;
        }
        if (!previous) {
          if (!remoteRow) {
            const localUpdatedAt = recordTimestamp(item.payload, now);
            outgoing.push({ assembly_id: assemblyId, user_id: session.session.user.id, database_name: item.database_name, store_name: item.store_name, record_id: item.record_id, payload: item.payload, updated_at: localUpdatedAt, deleted_at: null });
            state[key] = { hash: localHash, remoteUpdatedAt: localUpdatedAt };
          } else if (remoteRow.deleted_at) {
            await deleteLocalRecord(item);
            state[key] = { deletedAt: remoteRow.updated_at, remoteUpdatedAt: remoteRow.updated_at };
            remoteApplied += 1;
          } else {
            await writeLocalRecord({ ...item, payload: remoteRow.payload });
            state[key] = { hash: fingerprint(remoteRow.payload), remoteUpdatedAt: remoteRow.updated_at };
            remoteApplied += 1;
          }
        } else if (previous.hash !== localHash) {
          const localUpdatedAt = recordTimestamp(item.payload, now);
          const remoteUpdatedAt = remoteRow?.updated_at || '';
          if (!remoteRow || localUpdatedAt >= remoteUpdatedAt) {
            outgoing.push({ assembly_id: assemblyId, user_id: session.session.user.id, database_name: item.database_name, store_name: item.store_name, record_id: item.record_id, payload: item.payload, updated_at: localUpdatedAt, deleted_at: null });
            state[key] = { hash: localHash, remoteUpdatedAt: localUpdatedAt };
          } else {
            await writeLocalRecord({ ...item, payload: remoteRow.payload });
            state[key] = { hash: fingerprint(remoteRow.payload), remoteUpdatedAt: remoteRow.updated_at };
            remoteApplied += 1;
          }
        } else if (remoteRow && remoteRow.updated_at > (previous.remoteUpdatedAt || '')) {
          if (remoteRow.deleted_at) {
            await deleteLocalRecord(item);
            delete state[key];
            remoteApplied += 1;
          } else {
            await writeLocalRecord({ ...item, payload: remoteRow.payload });
            state[key] = { hash: fingerprint(remoteRow.payload), remoteUpdatedAt: remoteRow.updated_at };
            remoteApplied += 1;
          }
        }
      }

      for (const [key, remoteRow] of remote) {
        if (!availableLocalStores.has(`${remoteRow.database_name}|${remoteRow.store_name}`)) continue;
        if (!local.has(key)) {
          if (state[key] && !remoteRow.deleted_at) {
            outgoing.push({ ...remoteRow, user_id: session.session.user.id, updated_at: now, deleted_at: now, payload: remoteRow.payload });
            state[key] = { deletedAt: now, remoteUpdatedAt: now };
          } else if (!remoteRow.deleted_at) {
            await writeLocalRecord(remoteRow);
            state[key] = { hash: fingerprint(remoteRow.payload), remoteUpdatedAt: remoteRow.updated_at };
            remoteApplied += 1;
          }
        }
      }

      for (const [key, previous] of Object.entries(state)) {
        const [database_name, store_name, record_id] = key.split('|');
        if (!availableLocalStores.has(`${database_name}|${store_name}`)) continue;
        if (!local.has(key) && !remote.has(key) && previous.hash && !previous.deletedAt) {
          outgoing.push({ assembly_id: assemblyId, user_id: session.session.user.id, database_name, store_name, record_id, payload: {}, updated_at: now, deleted_at: now });
          state[key] = { deletedAt: now, remoteUpdatedAt: now };
        }
      }

      if (outgoing.length) {
        const { error: writeError } = await client.from('app_sync_records').upsert(outgoing, { onConflict: 'assembly_id,database_name,store_name,record_id' });
        if (writeError) throw writeError;
        broadcastLocalUpdate('sync-success', { reason, count: outgoing.length });
      }

      writeState(state);
      if (remoteApplied) refreshForRemoteUpdate();
      await refreshPrivateMemberData(client, assemblyId, await readLocalRecords(), state);
      writeState(state);
      if (status) status(`Synchronisation terminée${reason ? ` (${reason})` : ''}.${privateDataDenied ? ' Certaines données privées n’ont pas été modifiées faute d’autorisation.' : ''}`);
    } catch (error) {
      console.warn('Synchronisation indisponible :', error);
      if (status) status(`Données locales conservées. Échec de synchronisation : ${error.message || error}`, true);
    } finally {
      running = false;
      if (syncPending) {
        syncPending = false;
        scheduleSync('modification en attente');
      }
    }
  }

  window.appSyncStatus = function (message, isError) {
    const element = document.getElementById('syncStatus');
    if (element) { element.textContent = message; element.dataset.error = isError ? 'true' : 'false'; }
    if (isError) console.warn('Synchronisation indisponible :', message);
  };
  window.appSync = { syncNow, subscribeToRealtime };
  document.addEventListener('input', event => {
    if (event.isTrusted) hasUnsavedChanges = true;
  }, true);
  document.addEventListener('change', event => {
    if (event.isTrusted) hasUnsavedChanges = true;
  }, true);
  watchLocalDatabaseWrites();
  window.addEventListener('online', () => syncNow('connexion rétablie'));
  window.addEventListener('DOMContentLoaded', () => {
    registerServiceWorker();
    window.setTimeout(() => syncNow('démarrage'), 1200);
  });
  window.setInterval(() => syncNow('mise à jour automatique'), 15000);
})();

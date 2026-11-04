console.log({
  configured: window.appAuth?.configured,
  mode: window.appAuth?.mode,
  client: !!window.appAuth?.client,
  assemblyId: window.appAuth?.config?.assemblyId
});
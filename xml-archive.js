/* Histórico privado de XMLs. Arquivos originais ficam na conta, nunca no GitHub. */
(function(){
  'use strict';
  const MAX_BYTES = 5 * 1024 * 1024;
  const PAGE_SIZE = 20;
  const META = 'id,nome_arquivo,fornecedor,numero_nota,chave_nfe,valor_total,tamanho_bytes,created_at';
  const el = id => document.getElementById(id);
  let userId = null;
  let generation = 0;
  let page = 0;
  let rows = [];
  let total = 0;
  let busy = false;
  let searchTimer;

  function current(id, version){ return userId === id && generation === version; }
  function status(message, error){
    el('snArchiveStatus').textContent = message;
    el('snArchiveStatus').classList.toggle('archive-error', !!error);
  }
  function render(){
    const body = el('snArchiveBody');
    body.replaceChildren();
    rows.forEach(row => {
      const tr = document.createElement('tr');
      const values = [row.nome_arquivo, row.fornecedor || '—', row.numero_nota || '—',
        new Date(row.created_at).toLocaleString('pt-BR'),
        Number(row.valor_total).toLocaleString('pt-BR', {style:'currency', currency:'BRL'})];
      values.forEach(value => { const td = document.createElement('td'); td.textContent = value; tr.appendChild(td); });
      const actions = document.createElement('td');
      ['Abrir', 'Baixar XML'].forEach((label, index) => {
        const button = document.createElement('button');
        button.type = 'button'; button.className = 'ghost small'; button.textContent = label;
        button.disabled = busy;
        button.setAttribute('aria-label', label + ' — ' + row.nome_arquivo);
        button.addEventListener('click', () => openFile(row, index === 1));
        actions.appendChild(button);
      });
      tr.appendChild(actions); body.appendChild(tr);
    });
    el('snArchiveEmpty').hidden = busy || rows.length > 0;
    el('snArchiveEmpty').textContent = el('snArchiveSearch').value.trim()
      ? 'Nenhum XML encontrado para esta busca.' : 'Nenhum XML guardado. Importe uma nota para começar.';
    el('snArchiveCount').textContent = total + ' XML(s) · página ' + (page + 1);
    el('snArchivePrev').disabled = busy || page === 0;
    el('snArchiveNext').disabled = busy || (page + 1) * PAGE_SIZE >= total;
    el('snArchiveRefresh').disabled = busy || !userId;
  }
  function storageError(error){
    if(error && ['42P01', 'PGRST205'].includes(error.code)) return 'O histórico ainda não foi ativado no banco. O XML não foi guardado.';
    return 'Não foi possível acessar o histórico. Verifique a conexão e tente novamente.';
  }
  async function refresh(){
    if(!userId) return;
    const id = userId;
    const version = ++generation;
    busy = true; status('Carregando XMLs da sua conta…'); render();
    try{
      let query = window.sbClient.from('xml_documentos').select(META, {count:'exact'}).eq('user_id', id);
      // Somente caracteres de busca: evita interpolar operadores PostgREST em .or().
      const term = el('snArchiveSearch').value.trim().replace(/[^\p{L}\p{N}\s._-]/gu, '').slice(0, 100);
      if(term) query = query.or('nome_arquivo.ilike.%' + term + '%,fornecedor.ilike.%' + term + '%,numero_nota.ilike.%' + term + '%,chave_nfe.ilike.%' + term + '%');
      const {data, error, count} = await query.order('created_at', {ascending:false}).order('id').range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);
      if(!current(id, version)) return;
      if(error) throw error;
      rows = data || []; total = count || 0;
      status('Guardados na sua conta. Você pode abrir ou baixar os arquivos em outro aparelho.');
    }catch(error){
      if(!current(id, version)) return;
      rows = []; total = 0; status(storageError(error), true);
    }finally{
      if(current(id, version)){ busy = false; render(); }
    }
  }
  async function save(file, parsed){
    const id = userId;
    if(!id) throw new Error('Entre na sua conta para guardar o XML.');
    if(!file.size || file.size > MAX_BYTES) throw new Error('Selecione um XML de até 5 MB.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    const hash = Array.from(new Uint8Array(digest), b => b.toString(16).padStart(2, '0')).join('');
    let binary = '';
    for(let i = 0; i < bytes.length; i += 32768) binary += String.fromCharCode(...bytes.subarray(i, i + 32768));
    if(userId !== id) throw new Error('A sessão mudou. Entre novamente e reenvie o XML.');
    const record = {
      user_id:id, documento_id:parsed.chaveNfe || hash, sha256:hash,
      nome_arquivo:file.name.slice(0, 255), fornecedor:(parsed.emitName || '').slice(0, 500),
      numero_nota:(parsed.numeroNota || '').slice(0, 30), chave_nfe:parsed.chaveNfe || null,
      valor_total:parsed.valorTotal || 0, tamanho_bytes:bytes.length, xml_base64:btoa(binary)
    };
    const {error} = await window.sbClient.from('xml_documentos').insert(record);
    if(userId !== id) throw new Error('A sessão mudou. Confira o histórico ao entrar novamente.');
    if(error && error.code !== '23505') throw new Error('XML não guardado. ' + storageError(error) + ' Selecione o arquivo novamente para tentar salvar.');
    page = 0; el('snArchiveSearch').value = ''; await refresh();
    return error ? 'Este XML já está guardado na sua conta; nenhuma cópia duplicada foi criada.' : 'XML guardado na sua conta com sucesso.';
  }
  async function openFile(row, download){
    const id = userId, version = ++generation;
    busy = true; status(download ? 'Preparando o XML original…' : 'Abrindo XML…'); render();
    try{
      const {data, error} = await window.sbClient.from('xml_documentos').select('xml_base64,nome_arquivo').eq('id', row.id).eq('user_id', id).single();
      if(!current(id, version)) return;
      if(error) throw new Error(storageError(error));
      const bytes = Uint8Array.from(atob(data.xml_base64), char => char.charCodeAt(0));
      const file = new File([bytes], data.nome_arquivo, {type:'application/xml'});
      if(download){
        const url = URL.createObjectURL(file);
        const a = document.createElement('a'); a.href = url; a.download = file.name;
        document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 1000);
      }else{
        // O callback também verifica a sessão após ler o arquivo.
        await window.snOpenArchivedXml(file, () => current(id, version));
      }
      if(current(id, version)) status(download ? 'Download do XML original iniciado.' : 'XML aberto para consulta e precificação.');
    }catch(error){
      if(current(id, version)) status(error.message || storageError(error), true);
    }finally{
      if(current(id, version)){ busy = false; render(); }
    }
  }
  function setUser(id){
    if(userId === id) return;
    userId = id; generation++; page = 0; rows = []; total = 0; busy = false;
    clearTimeout(searchTimer); el('snArchiveSearch').value = '';
    el('snArchiveReceipt').textContent = '';
    el('clearXmlBtn').click();
    status(id ? 'Carregando XMLs da sua conta…' : 'Entre na sua conta para consultar os XMLs.'); render();
    // Nenhuma chamada ao Supabase dentro do callback de autenticação.
    if(id) setTimeout(refresh, 0);
  }
  el('snArchiveRefresh').addEventListener('click', refresh);
  el('snArchiveSearch').addEventListener('input', () => {
    page = 0; clearTimeout(searchTimer); searchTimer = setTimeout(refresh, 300);
  });
  el('snArchivePrev').addEventListener('click', () => { if(page > 0){ page--; refresh(); } });
  el('snArchiveNext').addEventListener('click', () => { if((page + 1) * PAGE_SIZE < total){ page++; refresh(); } });
  window.snXmlArchive = {setUser, save, refresh, getUserId:() => userId, maxBytes:MAX_BYTES};
})();

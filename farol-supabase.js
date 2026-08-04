/* ============================================================
 * FAROL-GUIA — ponte com o Supabase
 * ------------------------------------------------------------
 * Base fiscal unificada compartilhada por GUIA-SN e GUIA-LP.
 * O projeto Supabase é o mesmo nos dois repositórios: cada app
 * lê a MESMA base de NCM e os MESMOS parâmetros do RICMS/AC, e
 * aplica em cima disso o motor de cálculo do seu regime.
 *
 * Princípio de segurança dos dados:
 *   1. a base embutida no HTML continua sendo a base de partida
 *      — a página funciona sem internet, como antes;
 *   2. a base do Supabase só substitui a embutida DEPOIS de
 *      passar por validação estrutural completa;
 *   3. qualquer falha (rede, resposta truncada, formato
 *      inesperado) mantém a base embutida intacta.
 * Ou seja: sincronizar nunca deixa a ferramenta pior do que
 * estava. Na pior hipótese ela continua na base local.
 *
 * Não depende de nenhuma biblioteca — fala direto com a API
 * REST do Supabase (PostgREST) usando fetch.
 * ============================================================ */
(function () {
  'use strict';

  var CONFIG = {
    url: 'https://dewyncwpubygjdthwixr.supabase.co',
    // Chave publicável (anon). A base é somente-leitura: as políticas de
    // RLS do projeto só permitem SELECT, então expor esta chave no
    // front-end é o uso previsto pelo Supabase.
    key: 'sb_publishable_vCouzu-NLEdL8xvmgU3HvA_V6fJDZxc',
    timeoutMs: 15000,
  };

  var CACHE_NCM = 'farol:cache:ncm:v1';
  var CACHE_FISCAL = 'farol:cache:fiscal:v1';

  // ---------- utilidades ----------

  function lerCache(chave) {
    try {
      var bruto = window.localStorage.getItem(chave);
      return bruto ? JSON.parse(bruto) : null;
    } catch (e) {
      return null;
    }
  }

  function gravarCache(chave, valor) {
    try {
      window.localStorage.setItem(chave, JSON.stringify(valor));
      return true;
    } catch (e) {
      // cota estourada ou modo privativo — segue sem cache
      return false;
    }
  }

  function rpc(nome) {
    var controle = typeof AbortController !== 'undefined' ? new AbortController() : null;
    var expirou = setTimeout(function () {
      if (controle) controle.abort();
    }, CONFIG.timeoutMs);

    return fetch(CONFIG.url + '/rest/v1/rpc/' + nome, {
      method: 'GET',
      headers: {
        apikey: CONFIG.key,
        Authorization: 'Bearer ' + CONFIG.key,
        Accept: 'application/json',
      },
      signal: controle ? controle.signal : undefined,
    })
      .then(function (resposta) {
        clearTimeout(expirou);
        if (!resposta.ok) {
          throw new Error('Supabase respondeu ' + resposta.status + ' em ' + nome);
        }
        return resposta.json();
      })
      .catch(function (erro) {
        clearTimeout(expirou);
        throw erro;
      });
  }

  // ---------- validação ----------

  /* A base de NCM é o coração das duas ferramentas: um NCM com o segmento
   * de ST errado muda o ICMS a recolher. Por isso a base remota só entra
   * em uso se passar por TODAS as checagens abaixo. Qualquer reprovação
   * mantém a base embutida. */
  function validarNcm(bundle) {
    if (!bundle || typeof bundle !== 'object') return 'resposta vazia';
    if (!Array.isArray(bundle.segs) || !bundle.segs.length) return 'lista de segmentos de ST ausente';
    if (!Array.isArray(bundle.monos) || !bundle.monos.length) return 'lista de grupos monofásicos ausente';
    if (!Array.isArray(bundle.rows) || !bundle.rows.length) return 'nenhum NCM recebido';

    // total declarado pelo banco x linhas efetivamente recebidas:
    // pega resposta truncada no meio do caminho.
    if (typeof bundle.total === 'number' && bundle.total !== bundle.rows.length) {
      return 'recebidos ' + bundle.rows.length + ' NCMs de ' + bundle.total + ' esperados';
    }

    // Varre TODAS as linhas: formato, código de 8 dígitos, índices dentro
    // dos arrays, MVA numérica, e coerência entre segmento de ST e MVA.
    for (var i = 0; i < bundle.rows.length; i++) {
      var linha = bundle.rows[i];
      if (typeof linha !== 'string') return 'linha ' + i + ' não é texto';
      var p = linha.split('|');
      if (p.length !== 5) return 'linha ' + i + ' com ' + p.length + ' campos (esperado 5)';
      if (!/^[0-9]{8}$/.test(p[0])) return 'NCM inválido na linha ' + i + ': "' + p[0] + '"';
      if (!p[1]) return 'descrição vazia no NCM ' + p[0];
      if (p[2] !== '') {
        var iSeg = parseInt(p[2], 10);
        if (!(iSeg >= 0 && iSeg < bundle.segs.length) || !bundle.segs[iSeg]) {
          return 'segmento de ST inexistente no NCM ' + p[0];
        }
        // no RICMS/AC o segmento sempre vem acompanhado da MVA de referência
        if (p[3] === '' || !isFinite(parseFloat(p[3]))) return 'MVA ausente ou inválida no NCM ' + p[0];
      } else if (p[3] !== '') {
        return 'MVA sem segmento de ST no NCM ' + p[0];
      }
      if (p[4] !== '') {
        var iMono = parseInt(p[4], 10);
        if (!(iMono >= 0 && iMono < bundle.monos.length) || !bundle.monos[iMono]) {
          return 'grupo monofásico inexistente no NCM ' + p[0];
        }
      }
    }
    return null; // aprovada
  }

  function validarFiscal(f) {
    if (!f || typeof f !== 'object') return 'resposta vazia';
    if (!Array.isArray(f.cesta) || !f.cesta.length) return 'cesta básica ausente';
    if (!Array.isArray(f.rt) || !f.rt.length) return 'regras da Reforma Tributária ausentes';
    if (!f.regions || !f.regions.AC) return 'tabela de UFs ausente';
    if (!f.grupos || !f.grupos['sul-sudeste']) return 'alíquotas por grupo de origem ausentes';
    if (!f.params || typeof f.params.ALIQ_INTERNA_AC !== 'number') return 'alíquota interna do Acre ausente';
    if (typeof f.params.ALIQ_CESTA_AC !== 'number') return 'alíquota da cesta básica ausente';

    for (var i = 0; i < f.cesta.length; i++) {
      if (!f.cesta[i] || !/^[0-9]{2,8}$/.test(f.cesta[i].pref || '')) return 'prefixo inválido na cesta básica';
      if (typeof f.cesta[i].interna !== 'boolean') return 'cesta básica sem marcação de produção interna';
    }
    for (var j = 0; j < f.rt.length; j++) {
      if (!f.rt[j] || !Array.isArray(f.rt[j].pref) || !f.rt[j].pref.length) return 'regra da Reforma sem prefixos';
      if (!f.rt[j].cst || !f.rt[j].ct) return 'regra da Reforma sem CST/cClassTrib';
    }
    return null;
  }

  // ---------- indicador visual ----------

  var elStatus = null;

  function montarStatus() {
    if (elStatus || !document.body) return;
    var estilo = document.createElement('style');
    estilo.textContent =
      '.farol-db-status{position:fixed;right:14px;bottom:14px;z-index:9999;' +
      'font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;font-size:11px;' +
      'letter-spacing:.04em;padding:7px 12px;border-radius:999px;cursor:pointer;' +
      'border:1px solid #d8d2c4;background:#fff;color:#3c4a5e;' +
      'box-shadow:0 3px 12px rgba(24,36,55,.14);transition:opacity .2s;user-select:none;}' +
      '.farol-db-status:hover{opacity:.85;}' +
      '.farol-db-status .pt{display:inline-block;width:7px;height:7px;border-radius:50%;' +
      'margin-right:7px;vertical-align:middle;background:#a97a2f;}' +
      '.farol-db-status.ok .pt{background:#3f6650;}' +
      '.farol-db-status.erro .pt{background:#8c3b2e;}' +
      '@media print{.farol-db-status{display:none;}}';
    document.head.appendChild(estilo);

    elStatus = document.createElement('div');
    elStatus.className = 'farol-db-status';
    elStatus.title = 'Origem da base fiscal — clique para sincronizar novamente';
    elStatus.addEventListener('click', function () {
      API.sincronizar(true);
    });
    document.body.appendChild(elStatus);
  }

  function status(texto, classe, titulo) {
    montarStatus();
    if (!elStatus) return;
    elStatus.className = 'farol-db-status' + (classe ? ' ' + classe : '');
    elStatus.innerHTML = '<span class="pt"></span>' + texto;
    if (titulo) elStatus.title = titulo;
  }

  function comSeparador(n) {
    return Number(n).toLocaleString('pt-BR');
  }

  // ---------- API pública ----------

  var API = {
    config: CONFIG,
    origem: 'embutida', // 'embutida' | 'cache' | 'supabase'
    ultimoErro: null,

    // Cada página registra aqui como aplicar os dados e como se redesenhar.
    aplicarNcm: null,
    aplicarFiscal: null,
    aoAtualizar: null,

    aplicar: function (ncm, fiscal, origem) {
      var problema = validarNcm(ncm);
      if (problema) throw new Error('base de NCM recusada: ' + problema);

      if (fiscal) {
        var problemaFiscal = validarFiscal(fiscal);
        if (problemaFiscal) {
          // Os parâmetros fiscais são opcionais: se vierem estranhos, ficamos
          // com os embutidos e seguimos usando a base de NCM, que foi aprovada.
          fiscal = null;
          API.ultimoErro = 'parâmetros fiscais recusados: ' + problemaFiscal;
        }
      }

      if (typeof API.aplicarNcm === 'function') API.aplicarNcm(ncm);
      if (fiscal && typeof API.aplicarFiscal === 'function') API.aplicarFiscal(fiscal);
      API.origem = origem;
      if (typeof API.aoAtualizar === 'function') API.aoAtualizar();

      status(
        'Supabase · ' + comSeparador(ncm.rows.length) + ' NCMs',
        'ok',
        'Base fiscal sincronizada com o Supabase' +
          (origem === 'cache' ? ' (cópia local desta sessão)' : '') +
          '. Clique para sincronizar novamente.'
      );
      return true;
    },

    /* Sincroniza a base com o Supabase.
     * forcar = true ignora o cache local e baixa tudo de novo. */
    sincronizar: function (forcar) {
      status('sincronizando…', '', 'Consultando a base fiscal no Supabase');

      var cacheNcm = forcar ? null : lerCache(CACHE_NCM);
      var cacheFiscal = forcar ? null : lerCache(CACHE_FISCAL);

      // 1) Cache válido entra em uso na hora — a tela já fica com a base do
      //    Supabase antes mesmo de a rede responder.
      if (cacheNcm && cacheNcm.bundle && cacheNcm.hash) {
        try {
          API.aplicar(cacheNcm.bundle, cacheFiscal ? cacheFiscal.bundle : null, 'cache');
        } catch (e) {
          cacheNcm = null;
        }
      }

      // 2) Confere a assinatura da base no servidor (consulta barata).
      return rpc('ncm_versao')
        .then(function (versao) {
          if (
            cacheNcm &&
            cacheNcm.hash === versao.hash &&
            cacheNcm.bundle &&
            cacheNcm.bundle.rows.length === versao.total &&
            cacheFiscal
          ) {
            // Cache bate com o servidor: nada a baixar.
            status(
              'Supabase · ' + comSeparador(versao.total) + ' NCMs',
              'ok',
              'Base conferida com o Supabase (hash ' + versao.hash.slice(0, 8) + '). Clique para sincronizar novamente.'
            );
            return 'cache';
          }
          // 3) Baixa a base completa.
          return Promise.all([rpc('ncm_bundle'), rpc('fiscal_bundle')]).then(function (r) {
            var ncm = r[0];
            var fiscal = r[1];
            API.aplicar(ncm, fiscal, 'supabase');
            gravarCache(CACHE_NCM, { hash: versao.hash, bundle: ncm });
            gravarCache(CACHE_FISCAL, { hash: versao.hash, bundle: fiscal });
            return 'supabase';
          });
        })
        .catch(function (erro) {
          API.ultimoErro = erro && erro.message ? erro.message : String(erro);
          if (API.origem === 'embutida') {
            status('base local', 'erro', 'Sem conexão com o Supabase — usando a base embutida no arquivo. ' + API.ultimoErro);
          } else {
            status(
              'Supabase · cópia local',
              '',
              'Não foi possível conferir com o servidor agora; em uso a última base sincronizada. ' + API.ultimoErro
            );
          }
          return null;
        });
    },
  };

  window.FarolDB = API;

  /* ------------------------------------------------------------
   * Compatibilidade: a aba "Custo Operacional" grava via
   * window.storage, que só existe no ambiente onde a ferramenta
   * foi prototipada. Servida como página normal (GitHub Pages,
   * arquivo local), esse objeto não existe e as despesas se
   * perdiam a cada recarga. O adaptador abaixo só é criado
   * quando window.storage está ausente, então nada muda onde o
   * objeto original existe.
   * ------------------------------------------------------------ */
  if (!window.storage) {
    window.storage = {
      get: function (chave) {
        try {
          var v = window.localStorage.getItem('farol:' + chave);
          return Promise.resolve(v === null ? null : { value: v });
        } catch (e) {
          return Promise.resolve(null);
        }
      },
      set: function (chave, valor) {
        try {
          window.localStorage.setItem('farol:' + chave, valor);
        } catch (e) {
          /* modo privativo / cota — segue sem persistir */
        }
        return Promise.resolve(true);
      },
    };
  }
})();

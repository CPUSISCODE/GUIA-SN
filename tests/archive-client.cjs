// Supabase substituto somente para testes da interface; RLS é testado no banco real.
class ArchiveClient {
  constructor(){ this.records = []; this.error = null; this.readBarrier = null; }
  from(table){
    if(table !== 'xml_documentos') throw new Error('Unexpected table');
    const client = this;
    let fields = '*', filters = [], start = 0, end = Infinity, search = '', one = false;
    const query = {
      select(value){ fields = value; return query; },
      eq(field, value){ filters.push([field,value]); return query; },
      order(){ return query; },
      range(a,b){ start = a; end = b; return query; },
      or(value){ search = value.split('.ilike.%')[1].split('%')[0].toLowerCase(); return query; },
      single(){ one = true; return query; },
      async insert(record){
        if(client.error) return {error:client.error};
        if(client.records.some(row => row.user_id === record.user_id && (row.documento_id === record.documento_id || row.sha256 === record.sha256))) return {error:{code:'23505'}};
        client.records.unshift({...record, id:String(client.records.length + 1), created_at:new Date().toISOString()});
        return {error:null};
      },
      async then(resolve, reject){
        try{
          if(client.readBarrier) await client.readBarrier;
          if(client.error) return resolve({error:client.error});
          let data = client.records.filter(row => filters.every(([field,value]) => row[field] === value));
          if(search) data = data.filter(row => ['nome_arquivo','fornecedor','numero_nota','chave_nfe'].some(key => String(row[key] || '').toLowerCase().includes(search)));
          const count = data.length;
          data = data.slice(start, end + 1).map(row => Object.fromEntries(fields.split(',').map(key => [key,row[key]])));
          resolve({data:one ? data[0] : data, count, error:null});
        }catch(error){ reject(error); }
      }
    };
    return query;
  }
}
module.exports = ArchiveClient;

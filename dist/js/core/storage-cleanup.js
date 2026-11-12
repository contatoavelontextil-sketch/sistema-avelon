export function cleanupFiles(files,{days=0,state='all',query='',now=Date.now()}={}){const term=String(query).normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();return files.filter(f=>!f.deleted_at&&(!days||new Date(f.created_at).getTime()<=now-days*86400000)&&(state==='all'||state==='archived'&&f.archived||state==='active'&&!f.archived)&&(!term||[f.name,f.reference].join(' ').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().includes(term)));}
export async function purgeAttachment(ctx,id){
 const prepared=await ctx.rpc('owner_prepare_attachment_delete',{p_attachment:id});if(prepared.already_deleted)return;
 try{await ctx.removeStoredFile(prepared.storage_path)}catch(error){
  // Uma resposta perdida não significa falha: o servidor confere se o objeto saiu.
  try{await ctx.rpc('owner_finish_attachment_delete',{p_attachment:id});return}catch{throw error}
 }
 await ctx.rpc('owner_finish_attachment_delete',{p_attachment:id});
}

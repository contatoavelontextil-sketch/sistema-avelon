// Functions receive shared services and state through an explicit application context.
export function install(ctx){
async function api(path,{method='GET',body,auth=true,headers={}}={}){
 if(auth&&ctx.session?.expires_at<Date.now()/1000+60)await ctx.refresh();
 const r=await fetch(ctx.config.url+path,{method,headers:{apikey:ctx.config.key,'Content-Type':'application/json',...(auth&&ctx.session?{Authorization:'Bearer '+ctx.session.access_token}:{}),...headers},body:body===undefined?undefined:JSON.stringify(body)});
 const data=await r.json().catch(()=>null);
 if(!r.ok){if(r.status===401&&auth){ctx.saveSession(null);ctx.login();throw new Error('Sua sessão expirou. Entre novamente.')}throw new Error(data?.msg||data?.message||data?.error_description||'Não foi possível concluir. Tente novamente.')}
 return data;
}

async function load(){const p=await ctx.api('/rest/v1/profiles?select=*');ctx.profile=p[0];if(!ctx.profile?.active)throw Error('Seu cadastro está aguardando aprovação do administrador.');const s=await ctx.api('/rest/v1/settings?select=data');ctx.settings=s[0]?.data||{};[ctx.clients,ctx.products,ctx.quotes]=await Promise.all(['clients','products','quotes'].map(t=>ctx.api('/rest/v1/'+t+'?select=*&order=created_at.desc')));document.documentElement.style.setProperty('--accent',ctx.settings.accent||'#ddab63')}
Object.assign(ctx,{api,load});
}

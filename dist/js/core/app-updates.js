export function newerRelease(current,remote){return !!remote&&typeof remote.build==='string'&&remote.build!==current.build&&Number.isFinite(Date.parse(remote.published_at))&&Date.parse(remote.published_at)>Date.parse(current.published_at)}
export function install(ctx){
 const current={build:document.querySelector('meta[name="avelon-build"]')?.content,published_at:document.querySelector('meta[name="avelon-build-time"]')?.content};
 const dirtyForms=new Set();let pending=null,busy=false,lastCheck=0;
 for(const event of ['input','change'])document.addEventListener(event,e=>{const form=e.target.closest?.('form');if(form&&e.isTrusted)dirtyForms.add(form)});
 function show(remote){
  pending=remote;if(document.getElementById('app-update-notice'))return;
  const notice=document.createElement('aside');notice.id='app-update-notice';notice.setAttribute('aria-label','Atualização do sistema');notice.setAttribute('role','status');notice.innerHTML='<span>Nova versão disponível.</span><button type="button">Atualizar</button>';
  notice.querySelector('button').onclick=()=>{
   const unsaved=[...dirtyForms].some(form=>form.isConnected)||document.querySelector('dialog[open]');
   if(unsaved&&!window.confirm('Há uma edição ou janela aberta. Salve ou conclua seu trabalho antes de atualizar. Deseja atualizar agora mesmo?'))return;
   const url=new URL(location.href);url.searchParams.set('_avelon_update',pending.build);location.replace(url.href);
  };document.body.append(notice);
 }
 async function check(){
  if(!current.build||busy||document.hidden||Date.now()-lastCheck<10000)return;busy=true;lastCheck=Date.now();
  try{const url=new URL('release.json',document.baseURI);url.searchParams.set('check',String(Date.now()));const response=await fetch(url,{cache:'no-store',credentials:'omit',signal:AbortSignal.timeout(10000)});if(!response.ok)return;const remote=await response.json();if(newerRelease(current,remote))show(remote)}catch{}finally{busy=false}
 }
 window.addEventListener('focus',check);window.addEventListener('online',check);document.addEventListener('visibilitychange',()=>{if(!document.hidden)check()});setInterval(check,60000);ctx.checkForUpdate=check;check();
}

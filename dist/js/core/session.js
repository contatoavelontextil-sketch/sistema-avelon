import {createSessionStore,SESSION_KEY} from './session-store.js?v=20261111-v15a';
export function install(ctx){
 const store=createSessionStore({persistent:localStorage,temporary:sessionStorage});let refreshPromise;
 ctx.session=store.read();
 function endSession(message='Entre novamente para continuar.'){
  store.clear();ctx.session=null;ctx.profile=null;ctx.clients=[];ctx.suppliers=[];ctx.products=[];ctx.quotes=[];ctx.quoteVersions=[];ctx.business={};ctx.orderFinance=[];ctx.paymentReceipts=[];ctx.draft=[];ctx.viewQuote=null;ctx.settings={};
  document.querySelectorAll('dialog[open]').forEach(d=>d.close());ctx.login?.();ctx.toast?.(message);
 }
 function ensureSession(){if(!ctx.session)return false;const s=store.read();if(!s){endSession('Seu acesso expirou por inatividade ou foi encerrado. Entre novamente.');return false}ctx.session=s;return true}
 function saveSession(session,options){if(!session){endSession();return}ctx.session=store.write(session,options)}
 function applySessionPolicy(profile){
  if(!ctx.session)return;const policy={persistent:profile.session_persistent===true,idleMinutes:Number(profile.session_idle_minutes??(profile.is_owner?14400:30))};
  ctx.session=store.write(ctx.session,{touch:false,policy});if(!ctx.session)endSession('O tempo de inatividade definido para este acesso terminou. Entre novamente.');
 }
 async function refresh(){
  if(refreshPromise)return refreshPromise;
  const run=async()=>{if(!ensureSession())throw Error('Entre novamente para continuar.');if(ctx.session.expires_at>Date.now()/1000+60)return;
   try{const session=await ctx.api('/auth/v1/token?grant_type=refresh_token',{method:'POST',auth:false,body:{refresh_token:ctx.session.refresh_token}});saveSession({...session,expires_at:Date.now()/1000+session.expires_in},{touch:false})}catch(e){if([400,401,403].includes(e.status))endSession('Sua sessão foi encerrada. Entre novamente.');throw e}
  };
  refreshPromise=(navigator.locks?.request?navigator.locks.request('avelon-auth-refresh',run):run()).finally(()=>refreshPromise=null);return refreshPromise;
 }
 function activity(e){if(!e.isTrusted||!ctx.session)return;if(ensureSession())ctx.session=store.touch()}
 for(const event of ['pointerdown','keydown','wheel','touchstart'])document.addEventListener(event,activity,{passive:true});
 setInterval(()=>{if(ctx.session)ensureSession()},30000);
 const check=()=>{if(ctx.session&&!document.hidden)ensureSession()};window.addEventListener('focus',check);document.addEventListener('visibilitychange',check);
 window.addEventListener('storage',e=>{if(e.key!==SESSION_KEY||!ctx.session)return;const oldUser=ctx.session.user?.id,next=store.read();if(!next){endSession('O acesso foi encerrado neste navegador.');return}ctx.session=next;if(oldUser&&next.user?.id!==oldUser){ctx.profile=null;ctx.clients=[];ctx.suppliers=[];ctx.products=[];ctx.quotes=[];ctx.quoteVersions=[];ctx.business={};ctx.draft=[];ctx.start?.()}});
 let checkingPolicy=false,lastPolicyCheck=0;
 async function checkPolicy(){if(checkingPolicy||!ctx.session||document.hidden||Date.now()-lastPolicyCheck<60000)return;checkingPolicy=true;lastPolicyCheck=Date.now();try{const rows=await ctx.api('/rest/v1/profiles?select=id,active,is_owner,session_persistent,session_idle_minutes');if(!rows[0]?.active){endSession('Seu acesso foi bloqueado. Entre em contato com o administrador.');return}if(ctx.profile)Object.assign(ctx.profile,rows[0]);applySessionPolicy(rows[0])}catch{}finally{checkingPolicy=false}}
 setInterval(checkPolicy,60000);window.addEventListener('focus',checkPolicy);
 Object.assign(ctx,{saveSession,refresh,ensureSession,applySessionPolicy,endSession});
}

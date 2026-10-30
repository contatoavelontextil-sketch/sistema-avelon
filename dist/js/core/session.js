// Functions receive shared services and state through an explicit application context.
export function install(ctx){
function saveSession(s){ctx.session=s;if(s)sessionStorage.setItem('avelon_session_gghclidwfawpniuwtuyy',JSON.stringify(s));else sessionStorage.removeItem('avelon_session_gghclidwfawpniuwtuyy')}

async function refresh(){try{const s=await ctx.api('/auth/v1/token?grant_type=refresh_token',{method:'POST',auth:false,body:{refresh_token:ctx.session.refresh_token}});ctx.saveSession({...s,expires_at:Date.now()/1000+s.expires_in})}catch(e){ctx.saveSession(null);throw e}}
Object.assign(ctx,{saveSession,refresh});
}

export function install(ctx){
 function can(resource,action='view'){return !!ctx.profile?.active&&(ctx.profile.is_owner||((ctx.profile.permissions?.[resource]?.[action])??(ctx.profile.role==='admin')))}
 function routeAllowed(page){if(page==='home')return true;if(page==='users')return ctx.profile?.role==='admin';if(page==='settings')return ['settings_company','settings_quotes','settings_appearance','settings_production','settings_finance','settings_reports'].some(r=>can(r,'view'));if(page==='client-new')return can('clients','create');if(page==='product-new')return can('products','create');if(page==='quote')return can('quotes','create')&&can('clients')&&can('products');if(page==='view')return can('quotes');return can(page)}
 function applyPermissions(){document.querySelectorAll('[data-nav],[data-action]').forEach(b=>{const page=b.dataset.nav||b.dataset.action;if(!routeAllowed(page))b.hidden=true});if(!can('quotes','print'))ctx.$('#print')?.remove();}
 Object.assign(ctx,{can,routeAllowed,applyPermissions});
}

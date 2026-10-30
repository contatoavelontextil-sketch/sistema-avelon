export function install(ctx){
const $ = (s) => document.querySelector(s);
const esc = (s='') => String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money = n => Number(n||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
const date = d => new Date(d.slice(0,10)+'T12:00:00').toLocaleDateString('pt-BR');
const paths={home:'M3 10 12 3l9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z',clients:'M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8m8-7a4 4 0 0 1 0 8m5 9v-2a4 4 0 0 0-3-3.87',products:'m3 7 9-4 9 4v10l-9 4-9-4Zm0 0 9 4 9-4M12 11v10M7 5l10 4',quotes:'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Zm0 0v6h6M8 13h8M8 17h5',plus:'M12 5v14M5 12h14',arrow:'M5 12h14m-5-5 5 5-5 5',logout:'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4m7 14 5-5-5-5M21 12H9',print:'M6 9V2h12v7M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2M6 14h12v8H6Z',lock:'M5 11h14v10H5ZM8 11V7a4 4 0 0 1 8 0v4',x:'m6 6 12 12M6 18 18 6'};
const icon = name=>`<svg class="icon" aria-hidden="true" viewBox="0 0 24 24"><path d="${paths[name]||paths.arrow}"/></svg>`;
const brand=()=>`<div class="brand"><img src="${esc(ctx.settings.logo||'logo.png')}" alt="${esc(ctx.settings.company||'Avelon Têxtil')}"></div>`;
const field=(label,name,type='text',value='',attrs='')=>`<label class="field">${label}<input name="${name}" type="${type}" value="${esc(value)}" ${attrs}></label>`;
const navItem=(id,title)=>`<button data-nav="${id}" class="${ctx.current===id||(id==='quotes'&&ctx.current==='quote')?'active':''}">${icon(id)}${title}</button>`;
Object.assign(ctx,{$,esc,money,date,icon,brand,field,navItem});
}

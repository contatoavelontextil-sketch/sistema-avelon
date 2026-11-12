import {helpArticles,helpFaqs,searchHelp,normalizeHelp} from '../core/help-content.js?v=20261111-v15a';
export function install(ctx){
 function helpPage(){
  ctx.shell(`${ctx.head('Central de ajuda','Manual do usuário e respostas para o dia a dia da Avelon.')}<section class="panel help-intro"><div><span class="eyebrow">APRENDA NO SEU RITMO</span><h2>Do primeiro orçamento à entrega.</h2><p>Encontre o passo a passo de cada área. Os atalhos respeitam as permissões do seu acesso.</p></div><div class="help-intro-actions"><button class="primary" id="help-start">Começar pelo básico</button><button class="secondary" id="help-download">Baixar manual</button></div></section><section class="panel"><div class="panelbody help-controls"><label class="field">Buscar no manual e nas perguntas<input id="help-search" type="search" placeholder="Ex.: recibo, margem, fornecedor…" maxlength="150"></label><label class="field">Área do manual<select id="help-category"><option value="">Todas as áreas</option>${[...new Set(helpArticles.map(a=>a.category))].map(c=>`<option>${ctx.esc(c)}</option>`).join('')}</select></label></div></section><div class="help-tabs" role="group" aria-label="Conteúdo de ajuda"><button class="secondary" id="help-manual-tab" aria-pressed="true">Manual do usuário</button><button class="secondary" id="help-faq-tab" aria-pressed="false">Perguntas frequentes</button></div><p id="help-count" class="muted" role="status" aria-live="polite"></p><section id="help-results" aria-label="Orientações"></section><p class="note">Orientações revisadas em 12/11/2026. Algumas ações dependem das permissões e configurações da empresa. Esta central orienta o uso do sistema; não realiza envios ao cliente nem operações bancárias.</p>`);
  let mode='manual';
  const openArticle=id=>{mode='manual';ctx.$('#help-search').value='';ctx.$('#help-category').value='';draw();const detail=ctx.$('#help-'+id);if(detail){detail.open=true;detail.querySelector('summary').focus();detail.scrollIntoView({block:'nearest',behavior:'smooth'})}};
  function draw(){
   const query=ctx.$('#help-search').value,category=ctx.$('#help-category').value;
   ctx.$('#help-manual-tab').setAttribute('aria-pressed',String(mode==='manual'));ctx.$('#help-faq-tab').setAttribute('aria-pressed',String(mode==='faq'));
   const article=a=>`<details class="panel help-article" id="help-${a.id}"><summary><span><small>${ctx.esc(a.category)}</small><strong>${ctx.esc(a.title)}</strong></span>${ctx.icon('plus')}</summary><div class="help-article-body"><ol>${a.steps.map(s=>`<li>${ctx.esc(s)}</li>`).join('')}</ol>${a.route&&ctx.routeAllowed(a.route)?`<button class="secondary small" data-help-route="${a.route}">Abrir esta área ${ctx.icon('arrow')}</button>`:''}</div></details>`;
   let rows;
   if(mode==='manual'){rows=searchHelp(helpArticles,query,category);ctx.$('#help-results').innerHTML=rows.map(article).join('');}
   else{const terms=normalizeHelp(query).trim().split(/\s+/).filter(Boolean);rows=helpFaqs.filter(f=>{const a=helpArticles.find(a=>a.id===f.article);return (!category||a?.category===category)&&terms.every(t=>normalizeHelp(f.question+' '+f.answer).includes(t))});ctx.$('#help-results').innerHTML=rows.map(f=>`<details class="panel help-article"><summary><strong>${ctx.esc(f.question)}</strong>${ctx.icon('plus')}</summary><div class="help-article-body"><p>${ctx.esc(f.answer)}</p><button class="secondary small" data-help-article="${f.article}">Ver passo a passo ${ctx.icon('arrow')}</button></div></details>`).join('');}
   ctx.$('#help-count').textContent=`${rows.length} ${mode==='manual'?'orientações':'perguntas'} encontradas`;
   if(!rows.length)ctx.$('#help-results').innerHTML=ctx.empty('Nenhum resultado','Tente outro termo ou selecione todas as áreas.');
   document.querySelectorAll('[data-help-route]').forEach(b=>b.onclick=()=>ctx.render(b.dataset.helpRoute));
   document.querySelectorAll('[data-help-article]').forEach(b=>b.onclick=()=>openArticle(b.dataset.helpArticle));
  }
  ctx.$('#help-search').oninput=draw;ctx.$('#help-category').onchange=draw;
  ctx.$('#help-manual-tab').onclick=()=>{mode='manual';draw()};ctx.$('#help-faq-tab').onclick=()=>{mode='faq';draw()};ctx.$('#help-start').onclick=()=>openArticle('primeiros-passos');
  ctx.$('#help-download').onclick=()=>{const text='# Sistema Avelon — Manual do usuário\n\nRevisado em 12/11/2026.\n\n'+helpArticles.map(a=>'## '+a.title+'\n\n'+a.steps.map((s,i)=>(i+1)+'. '+s).join('\n\n')).join('\n\n')+'\n\n## Perguntas frequentes\n\n'+helpFaqs.map(f=>'### '+f.question+'\n\n'+f.answer).join('\n\n');const url=URL.createObjectURL(new Blob(['\ufeff'+text],{type:'text/plain;charset=utf-8'}));const a=document.createElement('a');a.href=url;a.download='Avelon-Manual-do-Usuario.txt';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);ctx.toast('Manual preparado para baixar.')};
  draw();
 }
 Object.assign(ctx,{helpPage});
}

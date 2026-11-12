import {assetPosition} from '../core/business.js?v=20261111-v15a';
import {qrcode} from '../../vendor/qrcode-2.0.4.mjs?v=20261111-v15a';

const code = number => number ? 'AVL'+String(number).padStart(4,'0') : '—';

export function install(ctx){
 const labelUrl = (token,print=false) => new URL('patrimonio.html'+(print?'?etiqueta=1':'')+'#'+encodeURIComponent(token),location.href).href;
 const acquired = a => !a.acquired_on ? 'Não informada' : a.acquisition_month_only ? a.acquired_on.slice(5,7)+'/'+a.acquired_on.slice(0,4) : ctx.date(a.acquired_on);
 function assetsPage(){
  const assets=(ctx.business.assets||[]).filter(a=>!a.archived).sort((a,b)=>(a.asset_number??Infinity)-(b.asset_number??Infinity));
  const rows=assets.map(a=>{
   const pos=assetPosition(a);
   return `<tr><td><strong>${code(a.asset_number)}</strong></td><td><strong>${ctx.esc(a.name)}</strong><small>${ctx.esc(a.specifications)}${a.active?'':' · Inativo'}</small></td><td>${acquired(a)}</td><td>${ctx.money(a.cost)}</td><td>${a.acquired_on?ctx.money(pos.depreciation):'Data pendente'}</td><td>${ctx.money(pos.value)}</td><td><div class="asset-actions">${ctx.can('assets','edit')?`<button class="secondary small" data-asset-edit="${a.id}">Editar</button>`:''}${ctx.can('attachments','view')?`<button class="secondary small" data-asset-invoice="${a.id}">Nota fiscal</button>`:''}${a.active&&(a.label_token||ctx.can('assets','edit'))?`<button class="secondary small" data-asset-label="${a.id}">Etiqueta QR</button>`:''}</div></td></tr>`;
  }).join('');
  ctx.shell(`${ctx.head('Patrimônio da empresa','Identificação, notas fiscais e depreciação gerencial.')}<div class="toolbar">${ctx.can('assets','create')?'<button class="primary" id="new-asset">Cadastrar bem</button>':''}</div><section class="panel">${rows?`<div class="table-wrap"><table><thead><tr><th>Patrimônio</th><th>Bem / especificações</th><th>Aquisição</th><th>Custo</th><th>Depreciação</th><th>Valor atual</th><th>Ações</th></tr></thead><tbody>${rows}</tbody></table></div>`:ctx.empty('Patrimônio organizado.','Cadastre máquinas, equipamentos e outros bens.')}</section><p class="note">Novos bens recebem um número AVL e depreciação linear de 10% ao ano, a partir do mês seguinte à aquisição. A depreciação fica pendente quando a data não foi informada.</p>`);
  ctx.$('#new-asset')?.addEventListener('click',()=>edit());
  for(const a of assets){
   ctx.$('[data-asset-edit="'+a.id+'"]')?.addEventListener('click',()=>edit(a));
   ctx.$('[data-asset-invoice="'+a.id+'"]')?.addEventListener('click',()=>ctx.attachmentsDialog('asset',a.id,'Nota fiscal · '+code(a.asset_number)));
   ctx.$('[data-asset-label="'+a.id+'"]')?.addEventListener('click',()=>label(a));
  }
 }
 function edit(a={}){
  const date=a.acquired_on||'';
  const d=ctx.modal(a.id?'Editar '+code(a.asset_number):'Cadastrar bem',`<form><div class="grid2">${ctx.field('Nome do bem','name','text',a.name||'','required maxlength="200"')}${ctx.field('Mês da aquisição','month','month',date.slice(0,7))}${ctx.field('Data exata (opcional)','day','date',a.acquisition_month_only?'':date)}${ctx.field('Custo de aquisição (R$)','cost','number',a.cost||'','required min="0.01" step="0.01" '+(a.id?'disabled':''))}<label class="field span2">Especificações do bem<textarea name="specifications" maxlength="3000">${ctx.esc(a.specifications||'')}</textarea></label><label class="field span2">Observações internas<textarea name="notes" maxlength="5000">${ctx.esc(a.notes||'')}</textarea></label><label class="check-row"><input type="checkbox" name="active" ${a.active===false?'':'checked'}>Bem ativo</label></div><p class="error" role="alert"></p><div class="form-actions"><button type="button" class="secondary" data-close>Cancelar</button><button class="primary">Salvar bem</button></div></form>`);
  d.querySelector('form').onsubmit=async e=>{
   e.preventDefault();const b=e.submitter;b.disabled=true;
   try{
    const fd=new FormData(e.target),data=Object.fromEntries(fd);
    if(data.day&&data.month&&data.day.slice(0,7)!==data.month)throw Error('A data exata precisa corresponder ao mês informado.');
    data.acquired_on=data.day||(data.month?data.month+'-01':'');
    data.acquisition_month_only=!!data.month&&!data.day;
    data.active=fd.has('active');
    await ctx.rpc('save_company_asset',{p_id:a.id||null,p_data:data});
    await ctx.load();d.close();assetsPage();
   }catch(err){d.querySelector('.error').textContent=err.message;b.disabled=false;}
  };
 }
 function label(a){
  const editable=ctx.can('assets','edit');
  const d=ctx.modal('Etiqueta de patrimônio',`<p>${ctx.esc(a.name)}</p><p class="note">Quem escanear a etiqueta pode consultar o número, as especificações e o contato comercial da Avelon pelo celular.</p><div class="asset-label-preview"></div><p class="error" role="alert"></p><div class="form-actions">${editable?'<button type="button" class="primary" id="asset-label-enable">Gerar etiqueta pública</button><button type="button" class="secondary" id="asset-label-disable" hidden>Desativar consulta</button>':''}<button class="secondary" data-close>Fechar</button></div>`);
  const enable=d.querySelector('#asset-label-enable'),disable=d.querySelector('#asset-label-disable'),preview=d.querySelector('.asset-label-preview');
  function draw(){
   if(enable)enable.hidden=!!a.label_token;
   if(disable)disable.hidden=!a.label_token;
   preview.replaceChildren();
   if(!a.label_token)return;
   const link=labelUrl(a.label_token);
   const qr=qrcode(0,'M');qr.addData(link);qr.make();
   const image=document.createElement('img');
   image.src=qr.createDataURL(5);image.alt='QR Code de '+code(a.asset_number);
   preview.append(image);
   const print=document.createElement('a');
   print.textContent='Abrir etiqueta para imprimir';print.href=labelUrl(a.label_token,true);
   print.target='_blank';print.rel='noopener noreferrer';preview.append(print);
  }
  async function update(enabled,button){
   button.disabled=true;
   try{
    a.label_token=await ctx.rpc('set_company_asset_label',{p_id:a.id,p_enabled:enabled});
    await ctx.load();
    a.asset_number=ctx.business.assets.find(item=>item.id===a.id)?.asset_number;
    draw();d.querySelector('.error').textContent='';
   }catch(err){d.querySelector('.error').textContent=err.message;}
   finally{button.disabled=false;}
  }
  if(enable)enable.onclick=()=>update(true,enable);
  if(disable)disable.onclick=()=>update(false,disable);
  draw();
 }
 Object.assign(ctx,{assetsPage});
}

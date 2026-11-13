import {financialSummary,outstanding,today} from '../core/business.js?v=20261111-v15a';
import {financeGroup,financeGroups} from '../core/finance-categories.js?v=20261111-v15a';

export function install(ctx){
 function financeAnalysis(container){
  const {entries=[],settlements=[]}=ctx.business;
  const now=today();
  container.innerHTML=`<section class="panel"><form class="panelbody"><div class="grid2">${ctx.field('De','from','date',now.slice(0,7)+'-01','required')}${ctx.field('Até','to','date',now,'required')}<label class="field">Regime<select name="basis"><option value="cash">Caixa · baixas</option><option value="accrual">Competência · títulos</option></select></label><label class="field">Grupo<select name="group"><option value="">Todos os grupos</option>${Object.entries(financeGroups).map(([key,label])=>`<option value="${key}">${label}</option>`).join('')}</select></label></div><div class="form-actions"><button class="primary">Atualizar análise</button>${ctx.can('reports','print')?'<button class="secondary" type="button" data-analysis-csv>Exportar CSV</button><button class="secondary" type="button" data-analysis-print>Imprimir relatório</button>':''}</div><p role="alert" class="error"></p></form></section><div class="finance-analysis-results"></div>`;
  const form=container.querySelector('form'),output=container.querySelector('.finance-analysis-results');
  let categories=[];
  function draw(){
   const {from,to,basis,group}=Object.fromEntries(new FormData(form));
   if(!from||!to||from>to){form.querySelector('.error').textContent='Informe um período válido.';return false;}
   form.querySelector('.error').textContent='';
   const filtered=entries.filter(e=>!e.voided&&(!group||financeGroup(e)===group));
   const operating=filtered.filter(e=>group==='transfer'||e.class!=='transfer');
   const {rows,totals}=financialSummary(operating,settlements,from,to,basis);
   const overdue=filtered.filter(e=>e.due_date<now&&e.due_date>=from&&e.due_date<=to&&e.kind==='expense').reduce((sum,e)=>sum+outstanding(e,settlements),0);
   const byCategory=new Map(),byMonth=new Map();
   for(const row of rows){
    const key=row.category||'Sem categoria';
    const category=byCategory.get(key)||{label:key,income:0,expense:0};
    category[row.kind]+=row.value;byCategory.set(key,category);
    const month=row.date.slice(0,7);
    const monthly=byMonth.get(month)||{label:month,income:0,expense:0};
    monthly[row.kind]+=row.value;byMonth.set(month,monthly);
   }
   categories=[...byCategory.values()].sort((a,b)=>b.expense+b.income-a.expense-a.income);
   const series=[...byMonth.values()].sort((a,b)=>a.label.localeCompare(b.label));
   const max=Math.max(1,...series.flatMap(m=>[m.income,m.expense]));
   const metric=(label,value)=>`<article class="metric"><span>${label}</span><strong>${ctx.money(value)}</strong></article>`;
   output.innerHTML=`<h2>Análise financeira · ${ctx.date(from)} a ${ctx.date(to)}</h2><p>${basis==='cash'?'Regime de caixa':'Regime de competência'} · ${ctx.esc(financeGroups[group]||'Todos os grupos')}${group==='transfer'?' · movimentações entre contas':' · transferências fora dos totais'}.</p><div class="metrics dashboard-metrics">${metric('Entradas',totals.income)}${metric('Saídas',totals.expense)}${metric('Entradas menos saídas',totals.cash_result)}${metric('Resultado operacional',totals.operating_result)}${metric('A pagar vencido no período',overdue)}</div><section class="panel"><div class="panelbody finance-bars"><h3>Entradas e saídas por mês</h3>${series.map(m=>`<div><strong>${ctx.esc(m.label)}</strong><div>Entradas · ${ctx.money(m.income)}<meter aria-label="Entradas" min="0" max="${max}" value="${m.income}"></meter></div><div>Saídas · ${ctx.money(m.expense)}<meter aria-label="Saídas" min="0" max="${max}" value="${m.expense}"></meter></div></div>`).join('')||'<p>Sem movimentação no período.</p>'}</div></section><section class="panel"><div class="panelhead"><h3>Totais por categoria</h3></div><div class="table-wrap"><table><thead><tr><th>Categoria</th><th>Entradas</th><th>Saídas</th><th>Diferença</th></tr></thead><tbody>${categories.map(c=>`<tr><td>${ctx.esc(c.label)}</td><td>${ctx.money(c.income)}</td><td>${ctx.money(c.expense)}</td><td>${ctx.money(c.income-c.expense)}</td></tr>`).join('')}</tbody></table></div></section>`;
   return true;
  }
  form.onsubmit=e=>{e.preventDefault();draw();};
  form.querySelector('[data-analysis-csv]')?.addEventListener('click',()=>{
   if(!draw())return;
   const quote=value=>'"'+String(value).replaceAll('"','""')+'"';
   const csv=['Categoria;Entradas;Saídas;Diferença',...categories.map(c=>[quote(/^[=+@\-\t\r\n]/.test(c.label)?"'"+c.label:c.label),...([c.income,c.expense,c.income-c.expense].map(n=>n.toFixed(2).replace('.',',')))].join(';'))].join('\r\n');
   const url=URL.createObjectURL(new Blob(['\ufeff',csv],{type:'text/csv;charset=utf-8'}));
   const link=document.createElement('a');link.href=url;link.download='analise-financeira-avelon.csv';link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
  });
  form.querySelector('[data-analysis-print]')?.addEventListener('click',()=>{
   if(!draw())return;
   const report=window.open('','_blank');
   if(!report){ctx.toast('Permita abrir a janela de impressão.');return;}
   report.opener=null;
   report.document.title='Análise financeira · Avelon';
   report.document.body.append(output.cloneNode(true));
   report.print();
  });
  draw();
 }
 Object.assign(ctx,{financeAnalysis});
}

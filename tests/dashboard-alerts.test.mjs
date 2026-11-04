import test from 'node:test';
import assert from 'node:assert/strict';
import {dashboardAlerts} from '../dist/js/core/dashboard-alerts.js';
import {STAGES} from '../dist/js/core/business.js';
const today='2026-11-04';
test('orçamento enviado não vira produção e conta a pagar não vira pedido',()=>{
 const q=[{id:'q',stage:'sent'}],e=[{id:'cafe',kind:'expense',amount:22,due_date:'2026-11-03'}];
 const a=dashboardAlerts(q,e,[],STAGES,today);
 assert.equal(a.commercial.length,1);assert.equal(a.production.length,0);assert.equal(a.operational.length,0);assert.equal(a.payables.length,1);assert.equal(a.financial[0].timing,'Vencido');assert.equal(a.financial[0].pending,22);
});
test('etapas comerciais, produção, prontos e suspensos ficam identificados',()=>{
 const stages=[...STAGES,{key:'custom',requires_production:true}],quotes=['draft','sent','awaiting_deposit','production','cutting','personalization','sewing','ready','awaiting_balance','suspended','completed','cancelled','custom'].map(stage=>({id:stage,stage}));
 const a=dashboardAlerts(quotes,[],[],stages,today);
 assert.deepEqual(a.commercial.map(q=>q.stage),['draft','sent','awaiting_deposit']);assert.equal(a.production.length,6);assert.equal(a.ready.length,1);assert.equal(a.operational.length,8);assert.equal(a.production.some(q=>['suspended','awaiting_balance'].includes(q.stage)),false);
});
test('financeiro respeita baixa parcial, estorno, cancelamento e datas',()=>{
 const e=[{id:'late',kind:'expense',amount:100,due_date:'2026-11-01'},{id:'today',kind:'income',amount:50,due_date:today},{id:'future',kind:'expense',amount:25,due_date:'2026-11-10'},{id:'void',kind:'expense',amount:70,due_date:'2026-11-01',voided:true},{id:'paid',kind:'expense',amount:10,due_date:'2026-11-01'}];
 const s=[{entry_id:'late',amount:30},{entry_id:'late',amount:20,reversed:true},{entry_id:'paid',amount:10}];
 const a=dashboardAlerts([],e,s,STAGES,today);
 assert.deepEqual(a.financial.map(e=>[e.id,e.pending,e.timing]),[['late',70,'Vencido'],['today',50,'Vence hoje'],['future',25,'A vencer']]);assert.equal(a.payables.length,2);assert.equal(a.receivables.length,1);
});

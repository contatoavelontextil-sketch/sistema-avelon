import test from 'node:test';
import assert from 'node:assert/strict';
import {salesReceived} from '../dist/js/core/dashboard-totals.js';
import {financialSummary} from '../dist/js/core/business.js';
test('vendas recebidas somam entrada e saldo uma vez e excluem transferências, rendimento, estorno e futuro',()=>{
 const entries=[{id:'sale',kind:'income',class:'revenue',category:'Vendas'},{id:'own',kind:'income',class:'transfer'},{id:'yield',kind:'income',class:'revenue',category:'Rendimentos'},{id:'void',kind:'income',class:'revenue',voided:true}];
 const settled=[{entry_id:'sale',amount:50,paid_on:'2026-10-01'},{entry_id:'sale',amount:50,paid_on:'2026-11-01'},{entry_id:'sale',amount:10,paid_on:'2026-11-01',reversed:true},{entry_id:'sale',amount:25,paid_on:'2026-11-03'},{entry_id:'own',amount:160,paid_on:'2026-11-01'},{entry_id:'yield',amount:2,paid_on:'2026-11-01'},{entry_id:'void',amount:30,paid_on:'2026-11-01'}];
 assert.equal(salesReceived(entries,settled,'2026-11-02'),100);
 assert.equal(salesReceived(entries,[...settled,{entry_id:'sale',amount:20,paid_on:'2026-11-02'}],'2026-11-02'),120);
 assert.equal(salesReceived(entries,settled.map((s,i)=>i===1?{...s,reversed:true}:s),'2026-11-02'),50);
});
test('movimentação mensal separa entradas e saídas sem contar transferência própria',()=>{
 const entries=[{id:'own',kind:'income',class:'transfer'},{id:'expense',kind:'expense',class:'expense'}];
 const settled=[{entry_id:'own',amount:160,paid_on:'2026-11-01'},{entry_id:'expense',amount:289.87,paid_on:'2026-11-01'}];
 const summary=financialSummary(entries.filter(e=>!['transfer','equity'].includes(e.class)),settled,'2026-11-01','2026-11-02');
 assert.equal(summary.totals.income,0);assert.equal(summary.totals.expense,289.87);
});

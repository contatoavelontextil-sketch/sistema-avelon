import test from 'node:test';
import assert from 'node:assert/strict';
import {productionDeadline} from '../dist/js/core/business.js';
test('entrega substitui prazo padrão e usa emissão em São Paulo',()=>{
 assert.deepEqual(productionDeadline('2026-11-02T12:00:00Z','2026-11-17',10),{days:11,delivery:'2026-11-17',from:'2026-11-02',overdue:false});
 assert.equal(productionDeadline('2026-11-03T01:00:00Z','2026-11-17',10).days,11);
});
test('datas atravessam meses, ano e fevereiro bissexto',()=>{
 assert.equal(productionDeadline('2026-12-31','2027-01-02',10).days,1);
 assert.equal(productionDeadline('2028-02-28','2028-03-01',10).days,2);
 assert.equal(productionDeadline('2026-11-04','2026-11-04',10).days,0);
 assert.equal(productionDeadline('2026-11-04','2026-11-03',10).days,-1);
});
test('sem entrega mantém configuração; data inválida não inventa prazo',()=>{
 assert.equal(productionDeadline('2026-11-04',null,10).days,10);
 assert.equal(productionDeadline('2026-11-04',null,0),null);
 assert.equal(productionDeadline('2026-11-04','2026-02-30',10),null);
});

test('fim de semana não conta e emissão não é contada duas vezes',()=>{
 assert.equal(productionDeadline('2026-11-06','2026-11-09',10).days,1);
 assert.equal(productionDeadline('2026-11-07','2026-11-08',10).days,0);
 assert.equal(productionDeadline('2026-11-09','2026-11-08',10).overdue,true);
});

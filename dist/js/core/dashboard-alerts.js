import {outstanding,productionStage} from './business.js?v=20261104-v13a';
// Commercial proposals, physical production and financial obligations are independent.
export function dashboardAlerts(quotes,entries,settlements,stages,today){
 const commercial=quotes.filter(q=>['draft','sent','awaiting_deposit'].includes(q.stage));
 const production=quotes.filter(q=>productionStage(q.stage,stages));
 const operational=quotes.filter(q=>productionStage(q.stage,stages)||['suspended','awaiting_balance'].includes(q.stage));
 const financial=entries.filter(e=>!e.voided&&outstanding(e,settlements)>0).map(e=>({...e,pending:outstanding(e,settlements),timing:e.due_date<today?'Vencido':e.due_date===today?'Vence hoje':'A vencer'})).sort((a,b)=>a.due_date.localeCompare(b.due_date)||a.id.localeCompare(b.id));
 return {commercial,production,operational,financial,payables:financial.filter(e=>e.kind==='expense'),receivables:financial.filter(e=>e.kind==='income'),ready:production.filter(q=>q.stage==='ready')};
}

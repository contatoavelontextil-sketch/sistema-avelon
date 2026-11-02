import {round} from './business.js?v=20261102-v6b';
// Counts cash received for sales, never quote totals plus their settlements.
export function salesReceived(entries,settlements,through){
 const sales=new Set(entries.filter(e=>!e.voided&&e.kind==='income'&&e.class==='revenue'&&!/^rendimentos?$/i.test((e.category||'').trim())).map(e=>e.id));
 return round(settlements.filter(s=>!s.reversed&&s.paid_on<=through&&sales.has(s.entry_id)).reduce((sum,s)=>sum+Number(s.amount),0));
}

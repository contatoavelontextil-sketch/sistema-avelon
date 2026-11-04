import {round} from './business.js?v=20261104-v9a';
// Counts cash received for sales, never quote totals plus their settlements.
export function salesReceived(entries,settlements,through){
 const sales=new Set(entries.filter(e=>!e.voided&&e.kind==='income'&&e.class==='revenue'&&!/^rendimentos?$/i.test((e.category||'').trim())).map(e=>e.id));
 return round(settlements.filter(s=>!s.reversed&&s.paid_on<=through&&sales.has(s.entry_id)).reduce((sum,s)=>sum+Number(s.amount),0));
}
export function expensesPaid(entries,settlements,through){
 const expenses=new Set(entries.filter(e=>!e.voided&&e.kind==='expense'&&!['transfer','equity'].includes(e.class)).map(e=>e.id));
 return round(settlements.filter(s=>!s.reversed&&s.paid_on<=through&&expenses.has(s.entry_id)).reduce((sum,s)=>sum+Number(s.amount),0));
}

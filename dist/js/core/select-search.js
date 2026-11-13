import {fold} from './finance-categories.js?v=20261111-v15a';
export function installSelectSearch(){
 const enhanced=new WeakSet();
 function add(select){
  if(enhanced.has(select)||select.multiple||select.size>1)return;
  enhanced.add(select);
  const search=document.createElement('button');
  search.type='button';search.className='secondary small select-search';
  search.textContent='Buscar na lista';
  search.onclick=()=>{
   if(select.disabled)return;
   const dialog=document.createElement('dialog');
   dialog.className='select-search-dialog';
   const heading=document.createElement('h2');heading.textContent='Buscar na lista';
   const input=document.createElement('input');input.type='search';input.placeholder='Digite para filtrar';input.setAttribute('aria-label','Buscar opção');
   const results=document.createElement('div');results.className='select-search-results';
   const close=document.createElement('button');close.type='button';close.className='secondary';close.textContent='Fechar';close.onclick=()=>dialog.close();
   function draw(){
    results.replaceChildren();
    const query=fold(input.value);
    for(const option of select.options){
     if(option.disabled||option.hidden||option.parentElement.disabled||!fold(option.label).includes(query))continue;
     const item=document.createElement('button');item.type='button';item.className='secondary';
     item.textContent=option.label;
     if(option.selected)item.setAttribute('aria-current','true');
     item.onclick=()=>{select.selectedIndex=option.index;select.dispatchEvent(new Event('input',{bubbles:true}));select.dispatchEvent(new Event('change',{bubbles:true}));dialog.close();};
     results.append(item);
    }
    if(!results.childElementCount)results.textContent='Nenhuma opção encontrada.';
   }
   input.oninput=draw;dialog.append(heading,input,results,close);document.body.append(dialog);
   dialog.addEventListener('close',()=>{dialog.remove();if(search.isConnected)search.focus();},{once:true});
   draw();dialog.showModal();input.focus();
  };
  select.after(search);
 }
 function scan(node){
  if(node.nodeType!==1)return;
  if(node.matches('select'))add(node);
  node.querySelectorAll('select').forEach(add);
 }
 new MutationObserver(records=>{for(const record of records)for(const node of record.addedNodes)scan(node);}).observe(document.body,{subtree:true,childList:true});
 scan(document.body);
}

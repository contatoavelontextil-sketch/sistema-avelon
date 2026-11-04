import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {install} from '../dist/js/core/app-install.js';
test('manifesto fica dentro do sistema e fornece ícones instaláveis',()=>{
 const manifest=JSON.parse(fs.readFileSync(new URL('../dist/manifest.webmanifest',import.meta.url)));
 const base=new URL('https://contatoavelontextil-sketch.github.io/sistema-avelon/');
 assert.equal(new URL(manifest.start_url,base).href,base.href);assert.equal(new URL(manifest.scope,base).href,base.href);assert.equal(manifest.display,'standalone');
 for(const size of [192,512]){const icon=manifest.icons.find(i=>i.sizes===`${size}x${size}`&&i.purpose==='any');assert.ok(icon);const png=fs.readFileSync(new URL('../dist/'+icon.src,import.meta.url));assert.equal(png.readUInt32BE(16),size);assert.equal(png.readUInt32BE(20),size)}
});
function fixture(){const events={},calls={prompts:0,dialogs:0,toasts:[]};let onClick;
 globalThis.window={addEventListener:(event,handler)=>events[event]=handler,matchMedia:()=>({matches:false})};
 Object.defineProperty(globalThis,'navigator',{configurable:true,value:{}});
 globalThis.document={baseURI:'https://contatoavelontextil-sketch.github.io/sistema-avelon/',addEventListener:(event,handler)=>{if(event==='click')onClick=handler}};
 const ctx={esc:s=>s,toast:s=>calls.toasts.push(s),modal:()=>{calls.dialogs++;return {querySelector:()=>({})}}};install(ctx);
 return {events,calls,click:()=>onClick({target:{closest:()=>({})}})};
}
test('instalação nativa exige clique e conclusão não é presumida',async()=>{
 const f=fixture();let prevented=false;f.events.beforeinstallprompt({preventDefault(){prevented=true},prompt:async()=>{f.calls.prompts++},userChoice:Promise.resolve({outcome:'accepted'})});assert.equal(prevented,true);assert.equal(f.calls.prompts,0);await f.click();assert.equal(f.calls.prompts,1);assert.equal(f.calls.toasts.length,0);f.events.appinstalled();assert.equal(f.calls.toasts.length,1);
});
test('navegador sem instalação e cancelamento recebem orientação',async()=>{
 const f=fixture();await f.click();assert.equal(f.calls.dialogs,1);f.events.beforeinstallprompt({preventDefault(){},prompt:async()=>{},userChoice:Promise.resolve({outcome:'dismissed'})});await f.click();assert.equal(f.calls.dialogs,2);assert.equal(f.calls.toasts.length,0);
});

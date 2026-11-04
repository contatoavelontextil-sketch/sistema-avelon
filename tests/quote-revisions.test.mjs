import test from 'node:test';
import assert from 'node:assert/strict';
import {quoteReference,currentQuoteVersions} from '../dist/js/core/business.js';
test('número comercial permanece e revisão avança',()=>{
 assert.equal(quoteReference({number:196,base_number:196,revision_no:0}),'0196');
 assert.equal(quoteReference({number:198,base_number:196,revision_no:1}),'0196 Rev. 01');
 assert.equal(quoteReference({number:199,base_number:196,revision_no:2}),'0196 Rev. 02');
 assert.equal(quoteReference({number:12345,base_number:12345,revision_no:101}),'12345 Rev. 101');
});
test('painel conta apenas a versão atual sem apagar o histórico',()=>{
 const versions=[{id:'a',superseded_by:'b'},{id:'b',superseded_by:'c'},{id:'c',superseded_by:null},{id:'separate'}];
 assert.deepEqual(currentQuoteVersions(versions).map(q=>q.id),['c','separate']);assert.equal(versions.length,4);
});

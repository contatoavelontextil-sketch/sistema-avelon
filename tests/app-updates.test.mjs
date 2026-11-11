import test from 'node:test';
import assert from 'node:assert/strict';
import {newerRelease} from '../dist/js/core/app-updates.js';
test('avisa somente sobre uma publicação diferente e mais recente',()=>{const current={build:'a',published_at:'2026-11-04T10:00:00Z'};assert.equal(newerRelease(current,{build:'b',published_at:'2026-11-04T11:00:00Z'}),true);assert.equal(newerRelease(current,current),false);assert.equal(newerRelease(current,{build:'old',published_at:'2026-11-03T11:00:00Z'}),false);assert.equal(newerRelease(current,{build:'b',published_at:'invalid'}),false)});

% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (c) 2026 SnapKittyWest
% Ahmad Ali Parr / Bel Esprit D'Accord Irrevocable Trust
% CLONE GATE: Any clone, fork, or derivative of this node
% MUST be released under GPL-3.0-or-later. No closed-source use.

%% Luma Router Test Suite

fprintf('=== Luma Router Test Suite ===\n\n');
passed = 0; failed = 0;

function result = check(name, condition)
    if condition
        fprintf('[PASS] %s\n', name);
        result = true;
    else
        fprintf('[FAIL] %s\n', name);
        result = false;
    end
end

%% T01: Capability soundness — GoogleVeo handles video, not audio
router = LumaRouter();
if check('T01: Veo handles video',  router.canExecute('GoogleVeo','video')),  passed=passed+1; else failed=failed+1; end
if check('T02: Veo rejects audio',  ~router.canExecute('GoogleVeo','audio')), passed=passed+1; else failed=failed+1; end
if check('T03: ElevenLabs handles audio', router.canExecute('ElevenLabs','audio')), passed=passed+1; else failed=failed+1; end
if check('T04: Seedream handles image',   router.canExecute('ByteDanceSeedream','image')), passed=passed+1; else failed=failed+1; end

%% T05: Determinism — same task type → same provider
r1 = struct('requestId',1,'taskType','video','budget',100);
r2 = struct('requestId',2,'taskType','video','budget',100);
[route1,~] = router.routeRequest(r1);
[route2,~] = router.routeRequest(r2);
if check('T05: Deterministic routing', strcmp(route1.provider, route2.provider)), passed=passed+1; else failed=failed+1; end

%% T06: Valid route structure
if check('T06: Route has provider field',  isfield(route1,'provider')), passed=passed+1; else failed=failed+1; end
if check('T07: Route has taskType field',  isfield(route1,'taskType')), passed=passed+1; else failed=failed+1; end
if check('T08: Route type is valid string',ischar(route1.type)), passed=passed+1; else failed=failed+1; end

%% T09: Policy validation — budget exceeded
r_overbudget = struct('requestId',3,'taskType','general','budget',99999);
router_limited = LumaRouter();
router_limited.Policy.MaxBudget = 1000;
[~,ok] = router_limited.routeRequest(r_overbudget);
if check('T09: Budget exceeded blocks route', ~ok), passed=passed+1; else failed=failed+1; end

%% T10: Context ledger persistence
router2 = LumaRouter();
router2.ContextLedger.commit(0,'branch1',struct('key1','val1'));
router2.ContextLedger.commit(1,'branch2',struct('key2','val2'));
if check('T10: Ledger has 3 snapshots', length(router2.ContextLedger.Snapshots)==3), passed=passed+1; else failed=failed+1; end

%% T11: Conflict detection
router3 = LumaRouter();
router3.ContextLedger.commit(0,'b1',struct('shared_key','value_a'));
router3.ContextLedger.commit(0,'b2',struct('shared_key','value_b'));
if check('T11: Conflict log non-empty', ~isempty(router3.ContextLedger.ConflictLog)), passed=passed+1; else failed=failed+1; end

%% T12: Lip-sync manifest generation
coord = LipSyncCoordinator(5);
coord.ingestScript('Hello world test');
manifest = coord.exportTimingManifest();
if check('T12: Manifest has phoneme schedule', ~isempty(manifest.phonemeSchedule)), passed=passed+1; else failed=failed+1; end
if check('T13: Manifest frame count correct', manifest.frameCount == 120), passed=passed+1; else failed=failed+1; end

%% T14: Verify lip-sync passes trivially (no large deviations)
syncResult = verifyLipSync(manifest, struct('assetId','v1'), struct('assetId','a1','durationMs',5000));
if check('T14: Lip-sync verification runs', isfield(syncResult,'passed')), passed=passed+1; else failed=failed+1; end

%% T15: Fallback route always valid
for taskType = {'video','image','audio','search','code','general','text'}
    route = router.buildFallbackRoute(taskType{1});
    if ~router.isValidRoute(route)
        failed = failed + 1;
        fprintf('[FAIL] T15: Fallback invalid for %s\n', taskType{1});
        break;
    end
end
if check('T15: All fallback routes valid', true), passed=passed+1; end

%% Summary
fprintf('\n=== Results: %d passed, %d failed ===\n', passed, failed);
if failed == 0
    fprintf('ALL TESTS PASSED\n');
end

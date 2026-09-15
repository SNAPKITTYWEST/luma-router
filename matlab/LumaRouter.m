% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (c) 2026 SnapKittyWest
% Ahmad Ali Parr / Bel Esprit D'Accord Irrevocable Trust
% CLONE GATE: Any clone, fork, or derivative of this node
% MUST be released under GPL-3.0-or-later. No closed-source use.

classdef LumaRouter < handle
    % LumaRouter - Recursive routing system with shared context
    % Maintains deterministic dispatch across heterogeneous model providers

    properties
        EnabledProviders
        DefaultProviderMap
        MaxRouteDepth
        Policy
        ContextLedger
        AssetGraph
        CurrentRouteId
        TraceRegistry
    end

    methods
        function obj = LumaRouter(providerList, policy)
            if nargin < 1
                providerList = {'GoogleVeo', 'ByteDanceSeedream', ...
                               'Kling', 'ElevenLabs', 'LumaLLM', ...
                               'SearchBackend', 'CodeBackend'};
            end
            if nargin < 2
                policy = LumaRouter.RoutingPolicy();
            end

            obj.EnabledProviders = providerList;
            obj.DefaultProviderMap = containers.Map('KeyType','char', 'ValueType','any');
            obj.MaxRouteDepth = 100;
            obj.Policy = policy;
            obj.ContextLedger = LumaRouter.ContextLedger();
            obj.AssetGraph = LumaRouter.AssetGraph();
            obj.CurrentRouteId = 0;
            obj.TraceRegistry = containers.Map('KeyType','double', 'ValueType','any');

            obj.DefaultProviderMap('text')      = 'LumaLLM';
            obj.DefaultProviderMap('image')     = 'ByteDanceSeedream';
            obj.DefaultProviderMap('video')     = 'GoogleVeo';
            obj.DefaultProviderMap('audio')     = 'ElevenLabs';
            obj.DefaultProviderMap('search')    = 'SearchBackend';
            obj.DefaultProviderMap('code')      = 'CodeBackend';
            obj.DefaultProviderMap('composite') = 'LumaLLM';
            obj.DefaultProviderMap('general')   = 'FallbackBackend';
        end

        function [route, success] = routeRequest(obj, request)
            if ~obj.validatePolicy(request)
                success = false; route = struct(); return;
            end
            taskType = obj.classifyRequest(request);
            route = obj.findRouteForTask(taskType, request.budget);
            if ~obj.isValidRoute(route)
                route = obj.buildFallbackRoute(taskType);
            end
            trace = obj.createRouteTrace(request, route);
            obj.TraceRegistry(request.requestId) = trace;
            success = true;
        end

        function isValid = validatePolicy(obj, request)
            switch request.taskType
                case 'video',  isValid = obj.Policy.AllowVideo;
                case 'image',  isValid = obj.Policy.AllowImage;
                case 'audio',  isValid = obj.Policy.AllowAudio;
                case 'search', isValid = obj.Policy.AllowSearch;
                case 'code',   isValid = obj.Policy.AllowCode;
                otherwise,     isValid = true;
            end
            if request.budget > obj.Policy.MaxBudget
                isValid = false;
            end
        end

        function taskType = classifyRequest(~, request)
            if nargin < 1 || isempty(request.taskType)
                taskType = 'general';
            else
                taskType = request.taskType;
            end
        end

        function route = findRouteForTask(obj, taskType, ~)
            primaryProvider = obj.getPrimaryProvider(taskType);
            if ~isempty(primaryProvider) && obj.isProviderEnabled(primaryProvider)
                route.primary = obj.buildDirectRoute(primaryProvider, taskType);
                if ~obj.canExecute(primaryProvider, taskType)
                    route.fallback = obj.buildFallbackRoute(taskType);
                else
                    route.fallback = obj.buildSecondaryProviderRoute(taskType);
                end
                route.type = 'fallback';
            else
                route = obj.buildFallbackRoute(taskType);
                route.type = 'fallback_only';
            end
        end

        function provider = getPrimaryProvider(obj, taskType)
            if obj.DefaultProviderMap.isKey(taskType)
                provider = obj.DefaultProviderMap(taskType);
            else
                provider = 'FallbackBackend';
            end
        end

        function enabled = isProviderEnabled(obj, provider)
            enabled = any(strcmp(obj.EnabledProviders, provider)) || ...
                      strcmp(provider, 'FallbackBackend');
        end

        function route = buildDirectRoute(obj, provider, taskType)
            route.provider   = provider;
            route.taskType   = taskType;
            route.type       = 'direct';
            route.capability = obj.getCapabilityProof(provider, taskType);
        end

        function route = buildFallbackRoute(obj, taskType)
            route.provider   = 'FallbackBackend';
            route.taskType   = taskType;
            route.type       = 'fallback';
            route.capability = obj.getCapabilityProof('FallbackBackend', 'general');
        end

        function route = buildSecondaryProviderRoute(obj, taskType)
            secondaryProviders = obj.getSecondaryProviders(taskType);
            if ~isempty(secondaryProviders)
                routes = cell(length(secondaryProviders), 1);
                for i = 1:length(secondaryProviders)
                    routes{i} = obj.buildDirectRoute(secondaryProviders{i}, taskType);
                end
                route.type      = 'sequence';
                route.subroutes = routes;
                route.provider  = secondaryProviders{1};
                route.taskType  = taskType;
            else
                route = obj.buildFallbackRoute(taskType);
            end
        end

        function providers = getSecondaryProviders(~, taskType)
            switch taskType
                case 'video', providers = {'Kling'};
                otherwise,    providers = {};
            end
        end

        function result = canExecute(obj, provider, taskType)
            capabilities = obj.getCapabilities(provider);
            result = ismember(taskType, capabilities);
        end

        function capabilities = getCapabilities(~, provider)
            switch provider
                case 'LumaLLM',           capabilities = {'text','composite','general'};
                case 'GoogleVeo',          capabilities = {'video'};
                case 'ByteDanceSeedream',  capabilities = {'image'};
                case 'Kling',              capabilities = {'video'};
                case 'ElevenLabs',         capabilities = {'audio'};
                case 'SearchBackend',      capabilities = {'search'};
                case 'CodeBackend',        capabilities = {'code'};
                case 'FallbackBackend',    capabilities = {'general','text','image','video','audio'};
                otherwise,                 capabilities = {};
            end
        end

        function proof = getCapabilityProof(~, provider, taskType)
            proof = sprintf('%s_capable_of_%s', provider, taskType);
        end

        function isValid = isValidRoute(obj, route)
            if ~isfield(route,'provider') || ~isfield(route,'taskType')
                isValid = false;
            elseif strcmp(route.type,'fallback')
                isValid = true;
            else
                isValid = obj.canExecute(route.provider, route.taskType);
            end
        end

        function trace = createRouteTrace(obj, request, route)
            obj.CurrentRouteId = obj.CurrentRouteId + 1;
            trace = struct(...
                'traceId',      obj.CurrentRouteId,...
                'requestId',    request.requestId,...
                'routeType',    route.type,...
                'provider',     route.provider,...
                'taskType',     route.taskType,...
                'timestamp',    datetime('now'),...
                'state',        'pending',...
                'parentTraceId', []...
            );
        end
    end

    methods (Static)
        function runTests()
            fprintf('=== Running Routing System Tests ===\n');

            router = LumaRouter();
            route = router.buildDirectRoute('GoogleVeo', 'video');
            assert(router.canExecute('GoogleVeo', 'video'),  'Capability check failed');
            assert(~router.canExecute('GoogleVeo', 'audio'), 'Capability leak detected');
            fprintf('[PASS] Capability soundness\n');

            r1 = struct('requestId',1,'taskType','video','budget',100);
            r2 = struct('requestId',2,'taskType','video','budget',100);
            [route1,~] = router.routeRequest(r1);
            [route2,~] = router.routeRequest(r2);
            assert(strcmp(route1.provider, route2.provider), 'Non-deterministic routing');
            fprintf('[PASS] Determinism\n');

            router.ContextLedger.commit(0,'test',struct('fact1','value1'));
            router.ContextLedger.commit(1,'test2',struct('fact2','value2'));
            assert(length(router.ContextLedger.Snapshots) == 3, 'Context not persisted');
            fprintf('[PASS] Context persistence\n');

            fprintf('=== All tests completed ===\n');
        end
    end

    % =========================================================================
    % Nested Classes
    % =========================================================================

    classdef RoutingPolicy < handle
        properties
            AllowVideo  = true
            AllowImage  = true
            AllowAudio  = true
            AllowSearch = true
            AllowCode   = true
            MaxBudget   = 10000
            MaxDuration = 180
            MaxDepth    = 100
        end
    end

    classdef ContextLedger < handle
        properties
            Snapshots
            HeadSnapshotIndex
            BranchRegistry
            ConflictLog
        end

        methods
            function obj = ContextLedger()
                obj.Snapshots = {struct('version',0,'facts',struct(),'parent',[])};
                obj.HeadSnapshotIndex = 1;
                obj.BranchRegistry = containers.Map('KeyType','char','ValueType','any');
                obj.ConflictLog = [];
            end

            function result = commit(obj, baseVersion, branchId, newFacts)
                headIdx     = obj.HeadSnapshotIndex;
                headVersion = obj.Snapshots{headIdx}.version;

                if baseVersion == headVersion
                    merged = obj.mergeFacts(obj.Snapshots{headIdx}.facts, newFacts);
                    snap = struct('version',headVersion+1,'parent',headVersion,...
                                  'facts',merged,'timestamp',datetime('now'));
                    obj.Snapshots{end+1} = snap;
                    obj.HeadSnapshotIndex = length(obj.Snapshots);
                    result.status       = 'OK';
                    result.newSnapshotId = snap.version;
                    result.affectedAssets = fieldnames(newFacts);
                elseif obj.isAncestor(baseVersion, headVersion)
                    conflicts = obj.detectConflicts(newFacts, headVersion);
                    if isempty(conflicts)
                        result = obj.mergeWithHead(newFacts, headVersion);
                    else
                        result = obj.handleConflict(baseVersion,branchId,conflicts,newFacts);
                    end
                else
                    result = obj.forkVariant(branchId, newFacts);
                end
            end

            function snap = read(obj, version)
                idx = obj.findSnapshotIndex(version);
                if idx > 0, snap = obj.Snapshots{idx};
                else,        snap = obj.Snapshots{1}; end
            end

            function merged = mergeFacts(~, base, newFacts)
                merged = base;
                keys = fieldnames(newFacts);
                for i = 1:length(keys)
                    merged.(keys{i}) = newFacts.(keys{i});
                end
            end

            function idx = findSnapshotIndex(obj, version)
                idx = 0;
                for i = 1:length(obj.Snapshots)
                    if obj.Snapshots{i}.version == version
                        idx = i; return;
                    end
                end
            end

            function bool = isAncestor(obj, ancestor, descendant)
                curr = descendant;
                while curr > 0
                    if curr == ancestor, bool = true; return; end
                    idx = obj.findSnapshotIndex(curr);
                    if idx > 0, curr = obj.Snapshots{idx}.parent;
                    else,        curr = 0; end
                end
                bool = false;
            end

            function conflicts = detectConflicts(obj, newFacts, ~)
                headFacts = obj.Snapshots{obj.HeadSnapshotIndex}.facts;
                newKeys  = fieldnames(newFacts);
                headKeys = fieldnames(headFacts);
                conflicts = intersect(newKeys, headKeys, 'stable');
            end

            function result = mergeWithHead(obj, newFacts, headVersion)
                merged = obj.mergeFacts(obj.Snapshots{obj.HeadSnapshotIndex}.facts, newFacts);
                snap   = struct('version', headVersion+1, 'parent', headVersion,...
                                'facts', merged, 'timestamp', datetime('now'));
                obj.Snapshots{end+1} = snap;
                obj.HeadSnapshotIndex = length(obj.Snapshots);
                result.status = 'OK';
                result.newSnapshotId = snap.version;
                result.affectedAssets = fieldnames(newFacts);
            end

            function result = handleConflict(obj, baseVersion, branchId, conflicts, newFacts)
                maxV = max(cellfun(@(s) s.version, obj.Snapshots));
                snap = struct('version', maxV+1, 'parent', baseVersion,...
                              'facts', newFacts,...
                              'variantOf', obj.Snapshots{obj.HeadSnapshotIndex}.version,...
                              'reason', sprintf('Branch %s conflicted', branchId),...
                              'timestamp', datetime('now'));
                obj.Snapshots{end+1} = snap;
                for i = 1:length(conflicts)
                    entry = struct('factKey', conflicts{i},...
                                   'status', 'unresolved',...
                                   'timestamp', datetime('now'));
                    obj.ConflictLog(end+1) = entry;
                end
                result.status = 'CONFLICT';
                result.newSnapshotId = snap.version;
                result.affectedAssets = fieldnames(newFacts);
            end

            function result = forkVariant(obj, branchId, newFacts)
                maxV = max(cellfun(@(s) s.version, obj.Snapshots));
                snap = struct('version', maxV+1,...
                              'parent', obj.Snapshots{obj.HeadSnapshotIndex}.version,...
                              'facts', newFacts,...
                              'variantOf', obj.Snapshots{obj.HeadSnapshotIndex}.version,...
                              'reason', sprintf('Explicit branch %s', branchId),...
                              'timestamp', datetime('now'));
                obj.Snapshots{end+1} = snap;
                obj.BranchRegistry(branchId) = snap.version;
                result.status = 'OK';
                result.newSnapshotId = snap.version;
                result.affectedAssets = fieldnames(newFacts);
            end
        end
    end

    classdef AssetGraph < handle
        properties
            Nodes
            Edges
        end

        methods
            function obj = AssetGraph()
                obj.Nodes = {}; obj.Edges = {};
            end

            function nodeId = addAsset(obj, asset)
                obj.Nodes{end+1} = asset;
                nodeId = asset.assetId;
            end

            function addEdge(obj, sourceId, targetId, edgeType)
                obj.Edges{end+1} = struct('source',sourceId,'target',targetId,...
                                          'edgeType',edgeType,'timestamp',datetime('now'));
            end

            function exists = nodeExists(obj, assetId)
                exists = false;
                for i = 1:length(obj.Nodes)
                    if strcmp(obj.Nodes{i}.assetId, assetId)
                        exists = true; return;
                    end
                end
            end
        end
    end
end

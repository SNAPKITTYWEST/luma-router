% SPDX-License-Identifier: GPL-3.0-or-later
% Copyright (c) 2026 SnapKittyWest
% Ahmad Ali Parr / Bel Esprit D'Accord Irrevocable Trust
% CLONE GATE: Any clone, fork, or derivative of this node
% MUST be released under GPL-3.0-or-later. No closed-source use.

%% Simple Transformer Encoder for Sequence Classification in MATLAB
% A minimal, from-scratch Transformer built with dlarray.
% Task: classify sine vs square wave sequences.
%
% Requirements: MATLAB R2021a+ with Deep Learning Toolbox
% Run: Just run this script. No extra files needed.

rng(0);

%% Hyperparameters
dModel    = 32;   % embedding dimension (must be divisible by numHeads)
numHeads  = 4;
numLayers = 2;
dFF       = 64;   % feed-forward hidden size
T         = 30;   % sequence length
inputDim  = 1;
numClasses= 2;
learnRate = 1e-3;
numEpochs = 15;
miniBatchSize = 64;

%% 1. Generate synthetic data: sine vs square
N = 1200;
X = zeros(inputDim, T, N, 'single');
Yidx = zeros(1,N);
t = linspace(0,1,T);
for i = 1:N
    if rand < 0.5
        X(1,:,i) = sin(2*pi*2*t) + 0.15*randn(1,T,'single');
        Yidx(i) = 1;
    else
        X(1,:,i) = sign(sin(2*pi*2*t)) + 0.15*randn(1,T,'single');
        Yidx(i) = 2;
    end
end
% train/test split
idx = randperm(N);
trainIdx = idx(1:1000); testIdx = idx(1001:end);
Xtrain = X(:,:,trainIdx); Ytrain = Yidx(trainIdx);
Xtest  = X(:,:,testIdx);  Ytest  = Yidx(testIdx);

%% 2. Init parameters
params = initTransformerParams(inputDim, dModel, numHeads, numLayers, dFF, numClasses);
pe = dlarray(single(sinusoidalPE(dModel, T))); % dModel x T
pe = reshape(pe, dModel, T, 1);

% Adam state
avgG = []; avgSqG = []; iter = 0;

%% 3. Training loop
numTrain = size(Xtrain,3);
numIterPerEpoch = floor(numTrain / miniBatchSize);

for epoch = 1:numEpochs
    idx = randperm(numTrain);
    totalLoss = 0;
    for k = 1:numIterPerEpoch
        iter = iter + 1;
        batchIdx = idx((k-1)*miniBatchSize+1:k*miniBatchSize);
        dlX = dlarray(Xtrain(:,:,batchIdx)); % inputDim x T x B
        dlY = Ytrain(batchIdx); % 1 x B, not dlarray

        [grad, loss] = dlfeval(@modelGradients, dlX, dlY, params, pe);
        [params, avgG, avgSqG] = adamupdate(params, grad, avgG, avgSqG, iter, learnRate);

        totalLoss = totalLoss + double(gather(extractdata(loss)));
    end
    % quick train accuracy
    acc = evaluateAccuracy(params, pe, Xtrain, Ytrain);
    fprintf('Epoch %d, loss=%.4f, train acc=%.3f\n', epoch, totalLoss/numIterPerEpoch, acc);
end

%% 4. Test
testAcc = evaluateAccuracy(params, pe, Xtest, Ytest);
fprintf('Test accuracy: %.3f\n', testAcc);

%% ---------- Functions ----------

function params = initTransformerParams(inputDim, dModel, numHeads, numLayers, dFF, numClasses)
    % He initialization
    params.dModel = dModel;
    params.numHeads = numHeads;
    params.numLayers = numLayers;

    params.We = dlarray(randn(dModel, inputDim,'single') * sqrt(2/inputDim));
    params.be = dlarray(zeros(dModel,1,'single'));

    params.layers = cell(numLayers,1);
    for l = 1:numLayers
        p.numHeads = numHeads;
        p.Wq = dlarray(randn(dModel,dModel,'single')*sqrt(2/dModel));
        p.bq = dlarray(zeros(dModel,1,'single'));
        p.Wk = dlarray(randn(dModel,dModel,'single')*sqrt(2/dModel));
        p.bk = dlarray(zeros(dModel,1,'single'));
        p.Wv = dlarray(randn(dModel,dModel,'single')*sqrt(2/dModel));
        p.bv = dlarray(zeros(dModel,1,'single'));
        p.Wo = dlarray(randn(dModel,dModel,'single')*sqrt(2/dModel));
        p.bo = dlarray(zeros(dModel,1,'single'));
        p.W1 = dlarray(randn(dFF,dModel,'single')*sqrt(2/dModel));
        p.b1 = dlarray(zeros(dFF,1,'single'));
        p.W2 = dlarray(randn(dModel,dFF,'single')*sqrt(2/dFF));
        p.b2 = dlarray(zeros(dModel,1,'single'));
        p.gamma1 = dlarray(ones(dModel,1,'single'));
        p.beta1  = dlarray(zeros(dModel,1,'single'));
        p.gamma2 = dlarray(ones(dModel,1,'single'));
        p.beta2  = dlarray(zeros(dModel,1,'single'));
        params.layers{l} = p;
    end
    params.Wc = dlarray(randn(numClasses,dModel,'single')*sqrt(2/dModel));
    params.bc = dlarray(zeros(numClasses,1,'single'));
end

function pe = sinusoidalPE(dModel, T)
    pe = zeros(dModel, T, 'single');
    pos = 0:T-1;
    divTerm = exp((0:2:dModel-1)' * (-log(10000.0)/dModel));
    pe(1:2:end,:) = sin(divTerm * pos);
    pe(2:2:end,:) = cos(divTerm * pos);
end

function [grad, loss] = modelGradients(dlX, Yidx, params, pe)
    logits = modelForward(dlX, params, pe); % numClasses x B
    B = size(logits,2);
    % stable softmax + crossentropy
    m = max(logits,[],1);
    logSoft = logits - m - log(sum(exp(logits - m),1));
    % gather log-prob of true class
    % Yidx: 1 x B double
    linIdx = sub2ind(size(logSoft), Yidx, 1:B);
    % need to handle dlarray indexing: extract then index
    % workaround: loop-free via one-hot
    Yonehot = zeros(size(logSoft),'single');
    Yonehot(linIdx) = 1;
    Yonehot = dlarray(Yonehot);
    loss = -sum(sum(Yonehot .* logSoft)) / B;
    grad = dlgradient(loss, params);
end

function logits = modelForward(dlX, params, pe)
    % dlX: inputDim x T x B
    [~, T, B] = size(dlX);
    dModel = params.dModel;

    Xflat = reshape(dlX, size(dlX,1), T*B);
    Eflat = params.We * Xflat + params.be; % broadcast be
    X = reshape(Eflat, dModel, T, B) + pe; % pe is dModel x T x 1

    for l = 1:params.numLayers
        X = encoderLayerForward(X, params.layers{l});
    end

    pooled = mean(X,2); % dModel x 1 x B
    pooled = reshape(pooled, dModel, B);
    logits = params.Wc * pooled + params.bc; % numClasses x B
end

function X = encoderLayerForward(X, p)
    A = multiHeadAttention(X, p);
    X = layerNorm(X + A, p.gamma1, p.beta1, 1e-5);
    F = feedForward(X, p);
    X = layerNorm(X + F, p.gamma2, p.beta2, 1e-5);
end

function Y = multiHeadAttention(X, p)
    % X: dModel x T x B
    [dModel, T, B] = size(X);
    numHeads = p.numHeads;
    dHead = dModel / numHeads;

    Xflat = reshape(X, dModel, T*B);
    Qflat = p.Wq * Xflat + p.bq;
    Kflat = p.Wk * Xflat + p.bk;
    Vflat = p.Wv * Xflat + p.bv;

    Q = reshape(Qflat, dModel, T, B);
    K = reshape(Kflat, dModel, T, B);
    V = reshape(Vflat, dModel, T, B);

    Oheads = zeros(dModel, T, B, 'single');
    Oheads = dlarray(Oheads);

    for h = 1:numHeads
        idx = (h-1)*dHead+1 : h*dHead;
        Qh_all = Q(idx,:,:); % dHead x T x B
        Kh_all = K(idx,:,:);
        Vh_all = V(idx,:,:);
        Oh = zeros(dHead, T, B, 'single');
        Oh = dlarray(Oh);
        for b = 1:B
            qb = Qh_all(:,:,b); % dHead x T
            kb = Kh_all(:,:,b);
            vb = Vh_all(:,:,b);
            scores = (qb' * kb) / sqrt(single(dHead)); % T x T
            w = softmaxRows(scores); % T x T
            ob = vb * w'; % dHead x T
            Oh(:,:,b) = ob;
        end
        Oheads(idx,:,:) = Oh;
    end

    Oflat = reshape(Oheads, dModel, T*B);
    Yflat = p.Wo * Oflat + p.bo;
    Y = reshape(Yflat, dModel, T, B);
end

function S = softmaxRows(M)
    % softmax over dim 2 (rows = queries, cols = keys)
    m = max(M,[],2);
    E = exp(M - m);
    S = E ./ sum(E,2);
end

function F = feedForward(X, p)
    [dModel, T, B] = size(X);
    Xflat = reshape(X, dModel, T*B);
    H = relu(p.W1 * Xflat + p.b1);
    Fflat = p.W2 * H + p.b2;
    F = reshape(Fflat, dModel, T, B);
end

function Y = layerNorm(X, gamma, beta, eps)
    mu = mean(X,1);
    xc = X - mu;
    v = mean(xc.^2,1);
    Xhat = xc ./ sqrt(v + eps);
    Y = gamma .* Xhat + beta;
end

function acc = evaluateAccuracy(params, pe, Xdata, Yidx)
    B = 256;
    N = size(Xdata,3);
    correct = 0;
    for i = 1:B:N
        j = min(i+B-1,N);
        dlX = dlarray(Xdata(:,:,i:j));
        logits = modelForward(dlX, params, pe);
        [~, pred] = max(extractdata(gather(logits)),[],1);
        correct = correct + sum(pred == Yidx(i:j));
    end
    acc = correct / N;
end

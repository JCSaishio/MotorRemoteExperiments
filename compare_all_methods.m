function results = compare_all_methods()
% COMPARE_ALL_METHODS  PSO vs EA vs Bat, per performance metric, at ONE ref.
%
% A single reference is given to ALL three optimizers (PSO, Earthquake, Bat).
% For every performance index (IAE, ITAE, ISE, ITSE) each optimizer is tuned
% with the SAME editable cost function, and the script records:
%   - the PID gains [Kp, Ki, Kd],
%   - the best cost,
%   - the number of iterations actually run, and
%   - the RUNTIME (wall-clock time for all iterations of that run).
%
% GRAPHS: for EACH metric there are three figures - system response, control
% input and convergence - and in EACH of those the three algorithms (PSO, EA,
% Bat) are overlaid (color = algorithm) for a direct comparison.
%
% EXCEL: one sheet per metric (algorithms as columns; Kp/Ki/Kd/BestCost/
% Iterations/Runtime beneath), plus a long-format 'Summary' sheet.
%
% The cost function is the SAME for all optimizers and is fully editable in
% this file: see pid_cost() at the bottom, and the Metrics list below.
%
% OUTPUT:
%   results = struct array (nMetric*nMethod x 1) with fields:
%             Metric, Algorithm, Kp, Ki, Kd, bestCost, Iterations, Runtime
%
% REQUIREMENTS:
%   - Control System Toolbox (for tf, pid, feedback, step)

clc; clear; close all;

%% ------------------------------------------------------------------------
% 1) PLANT
% -------------------------------------------------------------------------
s = tf('s');
G = 1731.3048/(s^2 + 472.6205*s + 3495.7927);

% Simulation time vector for step response
tFinal = 5;          % [s] simulation horizon
dt     = 0.01;       % [s] time step
t      = 0:dt:tFinal;

%% ------------------------------------------------------------------------
% 2) SINGLE REFERENCE (given to every method)  [RPM -> rad/s]
% -------------------------------------------------------------------------
rpm2rads = 2*pi/60;                 % RPM -> rad/s
rads2rpm = 60/(2*pi);               % rad/s -> RPM

Reference_RPM = 50;                 % single setpoint in RPM (edit me)
r             = Reference_RPM * rpm2rads;   % rad/s (calculations)

%% ------------------------------------------------------------------------
% 3) METRICS TO SWEEP  (the editable performance indices)
% -------------------------------------------------------------------------
Metrics = {'IAE', 'ITAE', 'ISE', 'ITSE'};   % edit / reorder / trim as needed
nMetric = numel(Metrics);

%% ------------------------------------------------------------------------
% 4) METHODS TO COMPARE
% -------------------------------------------------------------------------
Methods = {'PSO', 'EA', 'Bat'};
nMethod = numel(Methods);

%% ------------------------------------------------------------------------
% 5) SHARED OPTIONS (identical for every method -> fair comparison)
% -------------------------------------------------------------------------
opt.nVar   = 3;             % [Kp, Ki, Kd]
opt.VarMin = [0   0   0];   % lower bounds
opt.VarMax = [50 50 50];    % upper bounds

% Search budget. MaxIter is shared; the population is a SEPARATE editable
% variable per method (kept EQUAL by default for a fair comparison, but you
% can change each one individually here).
opt.MaxIter  = 500;         % maximum iterations (shared by all methods)
opt.pso.nPop = 30;          % PSO swarm size (number of particles)
opt.ea.nPop  = 30;          % EA population size (number of epicenters)
opt.bat.nPop = 30;          % Bat population size (number of bats)

% Early-stop: consecutive stalled iterations (no cost improvement) to stop
opt.stallLimit = 50;
opt.stallTol   = 1e-6;

% Derivative-filter option (see Pso_pid_tuning for details)
opt.useDerivFilter = true;   % true = filtered derivative, false = ideal PID
opt.Tf             = 1e-3;   % derivative filter time constant [s]

% Control-effort (motor voltage) limit (used by the shared cost function)
opt.Vmax     = 11.5;         % motor voltage limit [V]
opt.Vpenalty = 50;           % penalty weight for exceeding Vmax

% --- PSO-specific ---
opt.pso.w0    = 0.8;         % inertia weight (initial)
opt.pso.wdamp = 0.99;        % inertia damping
opt.pso.c1    = 1.5;         % cognitive coefficient
opt.pso.c2    = 1.5;         % social coefficient

% --- Earthquake-specific ---
opt.ea.SrRatio    = 0.02;    % S-range (~2% of the search-space diagonal)
opt.ea.lambdaLame = 1.5;     % Lame parameter lambda
opt.ea.muLame     = 1.5;     % Lame parameter mu
opt.ea.rhoMin     = 2200;    % minimum density
opt.ea.rhoMax     = 3300;    % maximum density

% --- Bat-specific ---
opt.bat.fmin  = 0;           % minimum frequency
opt.bat.fmax  = 2;           % maximum frequency
opt.bat.A0    = 1.0;         % initial loudness
opt.bat.r0    = 0.5;         % initial pulse rate
opt.bat.alpha = 0.9;         % loudness decay
opt.bat.gamma = 0.9;         % pulse-rate growth

%% ------------------------------------------------------------------------
% 6) OUTPUT FILE (never overwrite: auto-version the filename)
% -------------------------------------------------------------------------
% The workbook is saved in the 'SimResults' folder next to this script (the
% folder is created if it does not exist). The first run writes
% 'Methods_comparison.xlsx'. If that already exists the previous file is kept
% and a new one is created with an "_iterN" suffix
% (Methods_comparison_iter2.xlsx, _iter3.xlsx, ...).
scriptDir  = fileparts(mfilename('fullpath'));
resultsDir = fullfile(scriptDir, 'SimResults');
if ~exist(resultsDir, 'dir')
    mkdir(resultsDir);
end
baseName  = fullfile(resultsDir, 'Methods_comparison');
outFile   = [baseName '.xlsx'];
ver       = 1;
while exist(outFile, 'file')
    ver     = ver + 1;
    outFile = sprintf('%s_iter%d.xlsx', baseName, ver);
end
fprintf('Results will be written to %s (previous files are kept).\n', outFile);

%% ------------------------------------------------------------------------
% 7) RUN: for each metric, tune every method and overlay them
% -------------------------------------------------------------------------
methodColors = lines(nMethod);      % one color per algorithm

% Temporary folder for the exported figure images (embedded into Excel and
% then cleaned up). embedList records which images go on which metric sheet.
figDir = tempname;
mkdir(figDir);
embedList = struct('Sheet', {}, 'Files', {});

results = struct('Metric', {}, 'Algorithm', {}, 'Kp', {}, 'Ki', {}, ...
                 'Kd', {}, 'bestCost', {}, 'Iterations', {}, 'Runtime', {});

summary = {'Metric', 'Algorithm', 'Kp', 'Ki', 'Kd', ...
           'BestCost', 'Iterations', 'Runtime [s]'};

for m = 1:nMetric
    metric     = Metrics{m};
    opt.metric = metric;

    % Per-metric collectors (columns = methods)
    gainsAll   = zeros(3, nMethod);
    costAll    = zeros(1, nMethod);
    itersAll   = zeros(1, nMethod);
    runtimeAll = zeros(1, nMethod);

    % Three figures for this metric; each overlays the three algorithms
    figResp = figure('Name', sprintf('System response - %s', metric)); hold on;
    figCtrl = figure('Name', sprintf('Control input - %s',   metric)); hold on;
    figConv = figure('Name', sprintf('Convergence - %s',     metric)); hold on;

    fprintf('\n################ METRIC %s (%d/%d) ################\n', metric, m, nMetric);
    fprintf('%-6s  %-9s  %-9s  %-9s  %-10s  %-6s  %-11s\n', ...
            'Method', 'Kp', 'Ki', 'Kd', 'BestCost', 'Iters', 'Runtime[s]');

    for j = 1:nMethod
        method = Methods{j};
        col    = methodColors(j, :);

        % --- Run the selected optimizer, timing the whole run ------------
        tStart = tic;
        switch method
            case 'PSO'
                [bestPID, bestCost, BestCost] = runPSO(G, t, r, opt);
            case 'EA'
                [bestPID, bestCost, BestCost] = runEA(G, t, r, opt);
            case 'Bat'
                [bestPID, bestCost, BestCost] = runBat(G, t, r, opt);
        end
        runtime = toc(tStart);
        nIter   = numel(BestCost);

        gainsAll(:, j) = [bestPID.Kp; bestPID.Ki; bestPID.Kd];
        costAll(j)     = bestCost;
        itersAll(j)    = nIter;
        runtimeAll(j)  = runtime;

        % --- System response (RPM) ---------------------------------------
        Cbest = makePID(bestPID.Kp, bestPID.Ki, bestPID.Kd, opt);
        Tbest = feedback(Cbest*G, 1);
        [yBest, tSim] = step(Tbest, t);
        yBest = r * yBest;

        figure(figResp);
        plot(tSim, yBest * rads2rpm, 'LineWidth', 1.8, 'Color', col, ...
             'DisplayName', method);

        % --- Control input (motor voltage) -------------------------------
        Tu = feedback(Cbest, G);
        try
            [uBest, tU] = step(Tu, t);
            uBest = r * uBest;
            figure(figCtrl);
            plot(tU, uBest, 'LineWidth', 1.8, 'Color', col, ...
                 'DisplayName', method);
        catch ME
            warning(['Control signal for %s (%s) could not be simulated ', ...
                     '(%s). Enable opt.useDerivFilter to plot it.'], ...
                     method, metric, ME.message);
        end

        % --- Convergence -------------------------------------------------
        figure(figConv);
        semilogy(BestCost, 'LineWidth', 1.8, 'Color', col, ...
                 'DisplayName', method);

        % --- Record ------------------------------------------------------
        results(end+1) = struct('Metric', metric, 'Algorithm', method, ...
                                'Kp', bestPID.Kp, 'Ki', bestPID.Ki, ...
                                'Kd', bestPID.Kd, 'bestCost', bestCost, ...
                                'Iterations', nIter, 'Runtime', runtime); %#ok<AGROW>

        summary(end+1, :) = {metric, method, bestPID.Kp, bestPID.Ki, ...
                             bestPID.Kd, bestCost, nIter, runtime}; %#ok<AGROW>

        fprintf('%-6s  %-9.4g  %-9.4g  %-9.4g  %-10.4g  %-6d  %-11.4g\n', ...
                method, bestPID.Kp, bestPID.Ki, bestPID.Kd, bestCost, nIter, runtime);
    end

    % --- Finish this metric's system-response figure ---------------------
    figure(figResp);
    grid on;
    xlabel('Time [s]');
    ylabel('Angular speed [RPM]');
    title(sprintf('System response: PSO vs EA vs Bat (%s, r = %g RPM)', metric, Reference_RPM));
    yline(Reference_RPM, 'k--', 'Reference', 'HandleVisibility', 'off');
    legend('show', 'Location', 'southeast');

    % --- Finish this metric's control-input figure -----------------------
    figure(figCtrl);
    grid on;
    xlabel('Time [s]');
    ylabel('Control signal u(t) (motor voltage) [V]');
    title(sprintf('Control input: PSO vs EA vs Bat (%s, r = %g RPM)', metric, Reference_RPM));
    yline(opt.Vmax, 'k--', sprintf('V_{max} = %g V', opt.Vmax), 'HandleVisibility', 'off');
    legend('show', 'Location', 'northeast');

    % --- Finish this metric's convergence figure -------------------------
    figure(figConv);
    set(gca, 'YScale', 'log');
    grid on;
    xlabel('Iteration');
    ylabel(sprintf('Best Cost (%s)', metric));
    title(sprintf('Convergence: PSO vs EA vs Bat (%s, r = %g RPM)', metric, Reference_RPM));
    legend('show', 'Location', 'northeast');

    % --- Export the three figures to images (for embedding in Excel) -----
    fResp = fullfile(figDir, sprintf('%s_1_response.png',    metric));
    fCtrl = fullfile(figDir, sprintf('%s_2_control.png',     metric));
    fConv = fullfile(figDir, sprintf('%s_3_convergence.png', metric));
    saveFigurePng(figResp, fResp);
    saveFigurePng(figCtrl, fCtrl);
    saveFigurePng(figConv, fConv);
    embedList(end+1) = struct('Sheet', metric, ...
                              'Files', {{fResp, fCtrl, fConv}}); %#ok<AGROW>

    % --- Write this metric's Excel sheet (algorithms as columns) ---------
    header  = [{metric}, Methods];
    rowKp   = [{'Kp'},          num2cell(gainsAll(1, :))];
    rowKi   = [{'Ki'},          num2cell(gainsAll(2, :))];
    rowKd   = [{'Kd'},          num2cell(gainsAll(3, :))];
    rowCost = [{'BestCost'},    num2cell(costAll)];
    rowIter = [{'Iterations'},  num2cell(itersAll)];
    rowTime = [{'Runtime [s]'}, num2cell(runtimeAll)];
    sheetTable = [header; rowKp; rowKi; rowKd; rowCost; rowIter; rowTime];

    writecell(sheetTable, outFile, 'Sheet', metric);
end

%% ------------------------------------------------------------------------
% 8) WRITE THE COMBINED SUMMARY SHEET
% -------------------------------------------------------------------------
writecell(summary, outFile, 'Sheet', 'Summary');

%% ------------------------------------------------------------------------
% 9) WRITE THE PARAMETERS SHEET (settings used for this run)
% -------------------------------------------------------------------------
paramTable = {
    'Parameter',              'Value'
    'Reference [RPM]',        Reference_RPM
    'Metrics',                strjoin(Metrics, ', ')
    'MaxIter (shared)',       opt.MaxIter
    'VarMin [Kp Ki Kd]',      mat2str(opt.VarMin)
    'VarMax [Kp Ki Kd]',      mat2str(opt.VarMax)
    'stallLimit',             opt.stallLimit
    'stallTol',               opt.stallTol
    'useDerivFilter',         mat2str(opt.useDerivFilter)
    'Tf [s]',                 opt.Tf
    'Vmax [V]',               opt.Vmax
    'Vpenalty',               opt.Vpenalty
    '',                       ''
    'PSO parameters',         ''
    'nPop',                   opt.pso.nPop
    'w0 (initial inertia)',   opt.pso.w0
    'wdamp',                  opt.pso.wdamp
    'c1 (cognitive)',         opt.pso.c1
    'c2 (social)',            opt.pso.c2
    '',                       ''
    'EA parameters',          ''
    'nPop (epicenters)',      opt.ea.nPop
    'SrRatio',                opt.ea.SrRatio
    'lambdaLame',             opt.ea.lambdaLame
    'muLame',                 opt.ea.muLame
    'rhoMin',                 opt.ea.rhoMin
    'rhoMax',                 opt.ea.rhoMax
    '',                       ''
    'Bat parameters',         ''
    'nPop (bats)',            opt.bat.nPop
    'fmin',                   opt.bat.fmin
    'fmax',                   opt.bat.fmax
    'A0 (loudness)',          opt.bat.A0
    'r0 (pulse rate)',        opt.bat.r0
    'alpha (loudness decay)', opt.bat.alpha
    'gamma (pulse growth)',   opt.bat.gamma
};

writecell(paramTable, outFile, 'Sheet', 'Parameters');

%% ------------------------------------------------------------------------
% 10) EMBED THE FIGURES INTO THE EXCEL WORKBOOK
% -------------------------------------------------------------------------
% Each metric sheet gets its three figures inserted below the data table.
% Requires Excel (COM automation, Windows). If it fails (no Excel, etc.) the
% images are kept in a folder next to the workbook as a fallback.
embedded = embed_figures_excel(outFile, embedList);

if embedded
    rmdir(figDir, 's');   % success -> remove the temporary images
    fprintf('\nComparison done. Results (with embedded graphs) written to %s\n', outFile);
else
    [~, base] = fileparts(outFile);
    figFolder = fullfile(resultsDir, [base '_figures']);
    if exist(figFolder, 'dir'); rmdir(figFolder, 's'); end
    movefile(figDir, figFolder);
    warning(['Could not embed figures into Excel. The graphs were saved as ', ...
             'PNG files in the folder "%s" instead.'], figFolder);
    fprintf('\nComparison done. Results written to %s\n', outFile);
end
fprintf('  Sheets: %s, Summary, Parameters\n', strjoin(Metrics, ', '));

end

%% ========================================================================
% PSO OPTIMIZER
% =========================================================================
function [bestPID, bestCost, BestCost] = runPSO(G, t, r, opt)

nPop    = opt.pso.nPop;
MaxIter = opt.MaxIter;
w       = opt.pso.w0;
wdamp   = opt.pso.wdamp;
c1      = opt.pso.c1;
c2      = opt.pso.c2;
nVar    = opt.nVar;
VarMin  = opt.VarMin;
VarMax  = opt.VarMax;
metric  = opt.metric;

VelMax = 0.2*(VarMax - VarMin);
VelMin = -VelMax;

CostFunction = @(x) pid_cost(x, G, t, r, metric, opt);

empty_particle.Position      = [];
empty_particle.Velocity      = [];
empty_particle.Cost          = [];
empty_particle.Best.Position = [];
empty_particle.Best.Cost     = [];

particle = repmat(empty_particle, nPop, 1);
GlobalBest.Cost = inf;

for i = 1:nPop
    particle(i).Position = VarMin + rand(1, nVar).*(VarMax - VarMin);
    particle(i).Velocity = zeros(1, nVar);
    particle(i).Cost     = CostFunction(particle(i).Position);

    particle(i).Best.Position = particle(i).Position;
    particle(i).Best.Cost     = particle(i).Cost;

    if particle(i).Best.Cost < GlobalBest.Cost
        GlobalBest = particle(i).Best;
    end
end

BestCost = zeros(MaxIter, 1);

diversityTol  = 1e-3;
stallLimit    = opt.stallLimit;
collapseCount = 0;
spaceDiag     = norm(VarMax - VarMin);

for it = 1:MaxIter
    for i = 1:nPop
        r1 = rand(1, nVar);
        r2 = rand(1, nVar);

        cognitive = c1.*r1.*(particle(i).Best.Position - particle(i).Position);
        social    = c2.*r2.*(GlobalBest.Position       - particle(i).Position);
        particle(i).Velocity = w.*particle(i).Velocity + cognitive + social;

        particle(i).Velocity = max(particle(i).Velocity, VelMin);
        particle(i).Velocity = min(particle(i).Velocity, VelMax);

        particle(i).Position = particle(i).Position + particle(i).Velocity;
        particle(i).Position = max(particle(i).Position, VarMin);
        particle(i).Position = min(particle(i).Position, VarMax);

        particle(i).Cost = CostFunction(particle(i).Position);

        if particle(i).Cost < particle(i).Best.Cost
            particle(i).Best.Position = particle(i).Position;
            particle(i).Best.Cost     = particle(i).Cost;
            if particle(i).Best.Cost < GlobalBest.Cost
                GlobalBest = particle(i).Best;
            end
        end
    end

    BestCost(it) = GlobalBest.Cost;

    Positions = reshape([particle.Position], nVar, nPop).';
    centroid  = mean(Positions, 1);
    diversity = mean(sqrt(sum((Positions - centroid).^2, 2))) / spaceDiag;

    if diversity < diversityTol
        collapseCount = collapseCount + 1;
    else
        collapseCount = 0;
    end

    if collapseCount >= stallLimit
        BestCost = BestCost(1:it);
        break;
    end

    w = w * wdamp;
end

bestPID.Kp = GlobalBest.Position(1);
bestPID.Ki = GlobalBest.Position(2);
bestPID.Kd = GlobalBest.Position(3);
bestCost   = GlobalBest.Cost;

end

%% ========================================================================
% EARTHQUAKE ALGORITHM OPTIMIZER
% =========================================================================
function [bestPID, bestCost, BestCost] = runEA(G, t, r, opt)

nEpi    = opt.ea.nPop;
MaxIter = opt.MaxIter;
nVar    = opt.nVar;
lb      = opt.VarMin;
ub      = opt.VarMax;
metric  = opt.metric;

SrRatio    = opt.ea.SrRatio;
lambdaLame = opt.ea.lambdaLame;
muLame     = opt.ea.muLame;
rhoMin     = opt.ea.rhoMin;
rhoMax     = opt.ea.rhoMax;

stallLimit = opt.stallLimit;
stallTol   = opt.stallTol;

CostFunction = @(x) pid_cost(x, G, t, r, metric, opt);

rangeNorm = norm(ub - lb);
Sr        = SrRatio * rangeNorm;

X = repmat(lb, nEpi, 1) + rand(nEpi, nVar).*repmat((ub - lb), nEpi, 1);
J = zeros(nEpi, 1);
for i = 1:nEpi
    J(i) = CostFunction(X(i,:));
end

[bestCost, bestIdx] = min(J);
bestPos = X(bestIdx, :);

BestCost      = zeros(MaxIter, 1);
collapseCount = 0;
prevBest      = bestCost;

for it = 1:MaxIter
    for i = 1:nEpi
        rho = rhoMin + (rhoMax - rhoMin)*rand();
        vp  = sqrt((lambdaLame + 2*muLame)/rho);
        vs  = sqrt(muLame/rho);

        if norm(X(i,:) - bestPos) <= Sr
            v = vs;
        else
            v = vp;
        end

        step_mag  = -log(rand());
        direction = sign(rand(1, nVar) - 0.5);
        direction(direction == 0) = 1;

        stepVec = v * step_mag * direction .* (ub - lb);
        newPos  = X(i,:) + stepVec;
        newPos  = max(newPos, lb);
        newPos  = min(newPos, ub);

        newJ = CostFunction(newPos);
        if newJ < J(i)
            X(i,:) = newPos;
            J(i)   = newJ;
        end
    end

    [currentBest, currentIdx] = min(J);
    if currentBest < bestCost
        bestCost = currentBest;
        bestPos  = X(currentIdx, :);
    end

    BestCost(it) = bestCost;

    if abs(prevBest - bestCost) <= stallTol*max(1, abs(prevBest))
        collapseCount = collapseCount + 1;
    else
        collapseCount = 0;
    end
    prevBest = bestCost;

    if collapseCount >= stallLimit
        BestCost = BestCost(1:it);
        break;
    end
end

bestPID.Kp = bestPos(1);
bestPID.Ki = bestPos(2);
bestPID.Kd = bestPos(3);

end

%% ========================================================================
% BAT ALGORITHM OPTIMIZER
% =========================================================================
function [bestPID, bestCost, BestCost] = runBat(G, t, r, opt)

nBats   = opt.bat.nPop;
MaxIter = opt.MaxIter;
nVar    = opt.nVar;
lb      = opt.VarMin;
ub      = opt.VarMax;
metric  = opt.metric;

fmin  = opt.bat.fmin;
fmax  = opt.bat.fmax;
A0    = opt.bat.A0;
r0    = opt.bat.r0;
alpha = opt.bat.alpha;
gamma = opt.bat.gamma;

stallLimit = opt.stallLimit;
stallTol   = opt.stallTol;

CostFunction = @(x) pid_cost(x, G, t, r, metric, opt);

Q       = zeros(nBats, 1);
vel     = zeros(nBats, nVar);
Sol     = zeros(nBats, nVar);
Fitness = zeros(nBats, 1);
A       = A0 * ones(nBats, 1);
rPulse  = r0 * ones(nBats, 1);

for i = 1:nBats
    Sol(i,:)   = lb + (ub - lb).*rand(1, nVar);
    Fitness(i) = CostFunction(Sol(i,:));
end

[bestCost, idxBest] = min(Fitness);
bestPos = Sol(idxBest, :);

BestCost      = zeros(MaxIter, 1);
collapseCount = 0;
prevBest      = bestCost;

for it = 1:MaxIter
    for i = 1:nBats
        Q(i)     = fmin + (fmax - fmin)*rand();
        vel(i,:) = vel(i,:) + (Sol(i,:) - bestPos)*Q(i);
        newSol   = Sol(i,:) + vel(i,:);

        if rand > rPulse(i)
            epsN   = randn(1, nVar);
            Amean  = mean(A);
            newSol = bestPos + epsN.*Amean;
        end

        newSol = max(lb, min(ub, newSol));
        newFitness = CostFunction(newSol);

        if (newFitness <= Fitness(i)) && (rand < A(i))
            Sol(i,:)   = newSol;
            Fitness(i) = newFitness;
            A(i)       = alpha * A(i);
            rPulse(i)  = r0 * (1 - exp(-gamma*it));
        end

        if Fitness(i) <= bestCost
            bestCost = Fitness(i);
            bestPos  = Sol(i,:);
        end
    end

    BestCost(it) = bestCost;

    if abs(prevBest - bestCost) <= stallTol*max(1, abs(prevBest))
        collapseCount = collapseCount + 1;
    else
        collapseCount = 0;
    end
    prevBest = bestCost;

    if collapseCount >= stallLimit
        BestCost = BestCost(1:it);
        break;
    end
end

bestPID.Kp = bestPos(1);
bestPID.Ki = bestPos(2);
bestPID.Kd = bestPos(3);

end

%% ========================================================================
% COST FUNCTION  (SAME for every optimizer - EDIT HERE)
% =========================================================================
function J = pid_cost(x, G, t, r, metric, opt)
% Shared evaluation function. Change the performance index, the overshoot
% handling or the voltage penalty here and it applies to PSO, EA and Bat
% identically.
%
% x = [Kp Ki Kd], r = reference (rad/s), metric = 'IAE'|'ITAE'|'ISE'|'ITSE'
Kp = x(1);
Ki = x(2);
Kd = x(3);

try
    C = makePID(Kp, Ki, Kd, opt);
    T = feedback(C*G, 1);

    % Stability check: any pole in the right half-plane -> penalize
    polesT = pole(T);
    if any(real(polesT) >= 0)
        J = 1e6;
        return;
    end

    % Step response scaled to the reference amplitude
    [y, tSim] = step(T, t);
    y = r * y;
    e = r - y;

    % Selected performance index (integral over the response)
    tSim = tSim(:);
    e    = e(:);
    switch upper(metric)
        case 'IAE'      % Integral of |error|
            J = trapz(tSim, abs(e));
        case 'ITAE'     % Integral of time * |error|
            J = trapz(tSim, tSim .* abs(e));
        case 'ISE'      % Integral of error^2
            J = trapz(tSim, e.^2);
        case 'ITSE'     % Integral of time * error^2
            J = trapz(tSim, tSim .* (e.^2));
        otherwise       % default to ITAE
            J = trapz(tSim, tSim .* abs(e));
    end

    % Control-effort penalty: keep motor voltage within +/- Vmax
    if opt.Vpenalty > 0
        try
            Tu    = feedback(C, G);
            u     = r * step(Tu, t);
            uPeak = max(abs(u));
            if uPeak > opt.Vmax
                J = J * (1 + opt.Vpenalty*(uPeak/opt.Vmax - 1));
            end
        catch
            % Control signal not simulatable (e.g. ideal PID) -> skip penalty
        end
    end

    if isnan(J) || isinf(J)
        J = 1e6;
    end

catch
    J = 1e6;
end

end

%% ========================================================================
% PID BUILDER (derivative-filter option, matches the other scripts)
% =========================================================================
function C = makePID(Kp, Ki, Kd, opt)
if isfield(opt, 'useDerivFilter') && opt.useDerivFilter
    C = pid(Kp, Ki, Kd, opt.Tf);   % filtered derivative
else
    C = pid(Kp, Ki, Kd);           % ideal PID
end

end

%% ========================================================================
% SAVE A FIGURE TO PNG (with a fallback for older MATLAB)
% =========================================================================
function saveFigurePng(figHandle, filePath)
try
    exportgraphics(figHandle, filePath, 'Resolution', 150);  % R2020a+
catch
    print(figHandle, filePath, '-dpng', '-r150');            % fallback
end
end

%% ========================================================================
% EMBED FIGURE IMAGES INTO AN EXCEL WORKBOOK (Windows + Excel via COM)
% =========================================================================
function ok = embed_figures_excel(outFile, embedList)
% Inserts each metric's images below its data table. Returns true on success.
ok = false;
excel = [];
try
    % COM needs an absolute path. outFile is already absolute (built from the
    % script folder); fall back to pwd only if a bare name was passed.
    if isempty(fileparts(outFile))
        outFull = fullfile(pwd, outFile);
    else
        outFull = outFile;
    end

    excel = actxserver('Excel.Application');
    excel.Visible        = false;
    excel.DisplayAlerts  = false;

    wb = excel.Workbooks.Open(outFull);

    for i = 1:numel(embedList)
        sh    = wb.Sheets.Item(embedList(i).Sheet);
        files = embedList(i).Files;

        % Stack the images vertically starting below the data table.
        leftPt = 10;            % [points] left margin
        topPt0 = 150;           % [points] first image top (below the table)
        wPt    = 460;           % [points] image width
        hPt    = 345;           % [points] image height
        gapPt  = 20;            % [points] vertical gap between images

        for f = 1:numel(files)
            topPt = topPt0 + (f-1)*(hPt + gapPt);
            % AddPicture(File, LinkToFile=0, SaveWithDocument=1, Left, Top, W, H)
            sh.Shapes.AddPicture(files{f}, 0, 1, leftPt, topPt, wPt, hPt);
        end
    end

    wb.Save;
    wb.Close(false);
    excel.Quit;
    delete(excel);
    ok = true;

catch ME
    warning('Excel embedding failed: %s', ME.message);
    % Best-effort cleanup of the COM server
    try
        if ~isempty(excel)
            excel.DisplayAlerts = false;
            excel.Quit;
            delete(excel);
        end
    catch
    end
    ok = false;
end
end

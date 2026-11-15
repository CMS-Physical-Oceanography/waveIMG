
% CREST PRESSURE MATCH  Finds when video-tracked bores pass each in-situ pressure sensor,
% matches them to individual waves in the (high-passed) pressure record, and stores times + heights.

%% USER INPUT
year_str = '2013';
runDate  = '20131001';       % yyyymmdd of the video run
hourStr  = '1100';           % hhmm of the video run
camera   = 'rod13';          % prefix of the saved .mat ('rod13', 'NorthTower21', 'SouthTower18', ...)

dy      = 2;      % m, alongshore half-width of the strip around each sensor
dx      = 5;      % m, cross-shore half-window; crest pts inside are projected onto the sensor with the local celerity
minGap  = 2;      % s, projected arrivals separated by more than this are separate bores
minPts  = 5;      % min crest pts for a bore passage to count
Tcut    = 30;     % s, high-pass cutoff period (removes infragravity)
maxLag  = 20;     % s, search range for each sensor's time lag relative to the video (0 = no lag search)
minBore = 10;     % min bores at a sensor needed to trust its lag estimate (else lag = 0)
tol     = 2;      % s, max |bore time - pressure crest time| to call it a match
fsP     = 2;      % Hz, pressure sample rate

%% paths
dataRoot   = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/rips_onedrive/NSF_Eddies';
matDir     = fullfile(dataRoot, 'mat_data');
insituRoot = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main/data/SURF-AI field data';

runKey = [runDate '_' hourStr];
L = dir(fullfile(matDir, [camera '_' runKey '*.mat']));
if isempty(L); error('No mat file matching %s_%s*.mat in %s', camera, runKey, matDir); end
[~, iNew] = max([L.datenum]);  L = L(iNew);                 % newest if several match
fprintf('Loading %s\n', L.name);

%% load tracked crests (only these two variables; the mat is -v7.3 so the rest isn't read)
S  = load(fullfile(L.folder, L.name), 'all_celerity_total', 'all_celerity_time_total');
t0 = datetime(runDate, 'InputFormat', 'yyyyMMdd') + hours(str2double(hourStr(1:2)));   % top of hour = pressure start (EDT)
xC = S.all_celerity_total(:,1);   yC = S.all_celerity_total(:,2);     % crest pt position [m, FRF]
cx = S.all_celerity_total(:,3);   cC = S.all_celerity_total(:,5);     % onshore celerity, celerity magnitude [m/s]
tC = seconds(S.all_celerity_time_total - t0);                         % s after top of hour
tVid = [min(tC) max(tC)];                                             % video coverage

%% sensor locations: every line that is "ID  X  Y"
SL  = dir(fullfile(insituRoot, year_str, 'Sensor locations', '*.xyz'));
tok = regexp(fileread(fullfile(SL(1).folder, SL(1).name)), '^\s*(\d+)\s+([\d.]+)\s+([\d.]+)', 'tokens', 'lineanchors');
loc = str2double(vertcat(tok{:}));                                    % [ID x y]

%% loop over sensors
presName = [runDate(5:8) hourStr(1:2) '00'];                          % mmddhh00
lags = -maxLag : 1/fsP : maxLag;
out  = struct([]);

for s = 1:size(loc,1)

    % pressure file (cm of water above sensor, float32), any subfolder layout
    P = dir(fullfile(insituRoot, year_str, 'In situ time series', '**', sprintf('%s.p%02d', presName, loc(s,1))));
    if isempty(P); continue; end
    fid = fopen(fullfile(P(1).folder, P(1).name), 'r');
    if fid < 0; warning('p%02d: cannot open %s', loc(s,1), P(1).name); continue; end
    p = fread(fid, 'float32');  fclose(fid);
    if isempty(p)
        warning('p%02d: pressure file is empty (%d bytes), skipping', loc(s,1), P(1).bytes);
    continue
end
p = p(1:min(end, 7200));
    n  = numel(p);
    tP = (0:n-1)' / fsP;                                              % s after top of hour

    % high-pass in the frequency domain: zero everything with period > Tcut
    F  = fft(p - mean(p));
    f  = (0:n-1)' * fsP / n;   f = min(f, fsP - f);
    F(f < 1/Tcut) = 0;
    eta = real(ifft(F)) / 100;                                        % m (hydrostatic)

    % individual waves: zero down-crossings, so each wave = trough followed by its crest (the bore face)
    zc = find(eta(1:end-1) > 0 & eta(2:end) <= 0);
    nW = numel(zc) - 1;
    Hw = nan(nW,1);  tCr = nan(nW,1);
    for w = 1:nW
        seg = eta(zc(w)+1 : zc(w+1));
        [cr, ic] = max(seg);
        Hw(w)  = cr - min(seg);
        tCr(w) = tP(zc(w) + ic);
    end

    % tracked crest pts near the sensor -> projected arrival time at the sensor -> group into bores
    in = abs(yC - loc(s,3)) < dy & abs(xC - loc(s,2)) < dx;
    tB = [];  cB = [];
    if nnz(in) >= minPts
        cLoc  = median(cx(in));
        [ta, ia] = sort(tC(in) + (xC(in) - loc(s,2)) / cLoc);         % offshore pts arrive later, onshore pts earlier
        ca    = cC(in);  ca = ca(ia);
        g     = cumsum([1; diff(ta) > minGap]);
        keep  = accumarray(g, 1) >= minPts;
        tB    = accumarray(g, ta, [], @median);  tB = tB(keep);       % passage time of each bore (video clock)
        cB    = accumarray(g, ca, [], @median);  cB = cB(keep);       % its celerity at the sensor
        ok    = tB >= 0 & tB <= tP(end);   tB = tB(ok);   cB = cB(ok);   % only bores inside the pressure record
    end

    % time lag of this sensor relative to the video: lag that puts the bores on the pressure crests
    lag = 0;  comp = nan(size(lags));
    if numel(tB) >= minBore && maxLag > 0
        comp = arrayfun(@(l) mean(interp1(tP, eta, tB + l), 'omitnan'), lags);   % mean eta at (bore time + lag)
        [~, im] = max(comp);  lag = lags(im);
    end
    tB = tB + lag;                                                    % bores now on the pressure clock

    % match each bore to the nearest pressure crest
    Hb = nan(size(tB));  tBc = nan(size(tB));  isBore = false(nW,1);
    if ~isempty(tB) && nW > 0
        [d, iw] = min(abs(tCr - tB'), [], 1);
        m = d(:) <= tol;   iw = iw(:);
        Hb(m) = Hw(iw(m));   tBc(m) = tCr(iw(m));   isBore(iw(m)) = true;
    end
    inVid = tCr >= tVid(1) + lag & tCr <= tVid(2) + lag;              % waves that the video could have seen

    out(end+1).id = loc(s,1);                                         %#ok<SAGROW>
    out(end).x = loc(s,2);            out(end).y = loc(s,3);
    out(end).depth  = mean(p)/100;                                    % m of water above the sensor
    out(end).lag    = lag;            out(end).lagComposite = comp;
    out(end).time   = t0 + seconds(tP);     out(end).eta = eta;       % high-passed pressure record
    out(end).tBore  = t0 + seconds(tB);     out(end).cBore = cB;      % every tracked bore passage (pressure clock)
    out(end).tCrest = t0 + seconds(tBc);    out(end).Hbore = Hb;      % matched pressure crest + its height (NaN = no match)
    out(end).tWave  = t0 + seconds(tCr);    out(end).Hwave = Hw;      % all individual waves
    out(end).isBore = isBore;                                         % which of those waves were tracked bores
    out(end).Qb     = mean(isBore(inVid));                            % fraction of waves that were tracked bores

    fprintf('p%02d  x=%5.1f y=%5.1f  h=%.2f m  Hs=%.2f m  bores=%3d  matched=%3d  lag=%+5.1f s  mean Hbore=%.2f m  Qb=%.2f\n', ...
        loc(s,1), loc(s,2), loc(s,3), mean(p)/100, 4*std(eta), numel(tB), nnz(~isnan(Hb)), lag, mean(Hb,'omitnan'), out(end).Qb);
end

%% save
% saveDir = fullfile(matDir, 'sensor_timeseries');
% if ~exist(saveDir, 'dir'); mkdir(saveDir); end
% save(fullfile(saveDir, sprintf('crestPressure_%s_%s.mat', camera, runKey)), 'out', 'dy', 'dx', 'minGap', 'minPts', 'Tcut', 'tol');

%% pressure time series with tracked bores (sensors that had bores)
% show = find(arrayfun(@(o) ~isempty(o.tBore), out));
% figure('Position', [50 50 1400 180*numel(show)+120]);
% tl = tiledlayout(numel(show), 1, 'TileSpacing', 'compact', 'Padding', 'compact');
% ax = gobjects(numel(show), 1);
% for i = 1:numel(show)
%     o = out(show(i));
%     ax(i) = nexttile; hold on
%     plot(o.time, o.eta, 'k')
%     xline(o.tBore, 'Color', [1 .6 .6])                                % every tracked bore passage
%     mt = ~isnan(o.Hbore);
%     plot(o.tCrest(mt), interp1(o.time, o.eta, o.tCrest(mt)), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 4)   % matched crest
%     ylabel('\eta [m]');  grid on;  box on
%     title(sprintf('p%02d  (x=%.0f, y=%.0f, h=%.2f m)   %d bores, %d matched, lag %+.1f s', ...
%         o.id, o.x, o.y, o.depth, numel(o.tBore), nnz(mt), o.lag), 'FontWeight', 'normal')
% end
% linkaxes(ax, 'x');
% xlim(ax(1), t0 + seconds(tVid(1) + [0 300]));                         % first 5 min; pan/zoom moves all panels
% title(tl, sprintf('%s  %s %s   pressure (> %d s removed) + tracked bores', camera, runDate, hourStr, Tcut))

%% ANIMATION: tracked crests on the map + one sensor's pressure record, side by side
animSensor = 22;        % sensor ID to follow (e.g. 22 -> p22)
animStart  = 0;         % s after the start of the video
animDur    = 5;       % s of video to animate
trail      = 1;         % s, crest pts from the last 'trail' seconds stay visible (fading tail)
presWin    = [-20 30];  % s, pressure window shown around "now"
saveVideo  = false;      % true = also write an mp4 next to the saved results
playSpeed  = 3;         % on-screen playback speed when saveVideo = false (1 = real time)

o   = out([out.id] == animSensor);
if isempty(o); error('Sensor %d has no pressure file for this run.', animSensor); end
tBs = seconds(o.tBore  - t0);                                   % bore passages, pressure clock [s after top of hour]
mt  = ~isnan(o.Hbore);
tCs = seconds(o.tCrest(mt) - t0);                               % matched pressure crests
eCs = interp1(seconds(o.time - t0), o.eta, tCs);

dtA  = median(diff(unique(tC)));                                % video frame interval
tA   = tVid(1) + animStart : dtA : tVid(1) + animStart + animDur;   % frame times, video clock
inA  = tC >= tA(1) - trail & tC <= tA(end) + dtA;                   % only the crest pts needed
xA = xC(inA);  yA = yC(inA);  tAp = tC(inA);

figA = figure('Name', 'Crests + pressure', 'Color', 'w');
tlA  = tiledlayout(figA, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');

% map
axM = nexttile(tlA, 1); hold(axM, 'on')
hTrail = plot(axM, nan, nan, '.', 'Color', [1 .7 .7], 'MarkerSize', 6);
hNow   = plot(axM, nan, nan, 'r.', 'MarkerSize', 9);
plot(axM, [out.x], [out.y], 'ko', 'MarkerFaceColor', [.6 .6 .6], 'MarkerSize', 5);
text(axM, [out.x]+2, [out.y], compose('p%02d', [out.id]), 'FontSize', 8, 'Color', [.3 .3 .3], 'Clipping', 'on');
hSens  = plot(axM, o.x, o.y, 'p', 'MarkerSize', 16, 'MarkerEdgeColor', 'k', 'MarkerFaceColor', 'y');
axis(axM, 'equal');  box(axM, 'on');  grid(axM, 'on')
xlim(axM, [min(xC) max(xC)]);  ylim(axM, [min(yC) max(yC)])
xlabel(axM, 'Cross-shore [m]');  ylabel(axM, 'Alongshore [m]')

% pressure
axP = nexttile(tlA, 2, [1 2]); hold(axP, 'on')
plot(axP, seconds(o.time - t0), o.eta, 'k')
yl = [min(o.eta) max(o.eta)] * 1.1;
hBore  = plot(axP, nan, nan, '-', 'Color', [1 .5 .5]);          % bore passages so far
hCrest = plot(axP, nan, nan, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);   % matched crests so far
hLine  = xline(axP, 0, 'b', 'LineWidth', 1.5);                  % "now"
ylim(axP, yl);  grid(axP, 'on');  box(axP, 'on')
xlabel(axP, 's after top of hour (pressure clock)');  ylabel(axP, '\eta [m]')
title(axP, sprintf('p%02d  (h = %.2f m, lag %+.1f s)   blue = now, red line = tracked bore passes, dot = matched crest', ...
    o.id, o.depth, o.lag), 'FontWeight', 'normal')

if saveVideo
    vw = VideoWriter(fullfile(saveDir, sprintf('crestPressure_%s_%s_p%02d.mp4', camera, runKey, o.id)), 'MPEG-4');
    vw.FrameRate = round(1/dtA);  open(vw);
end

for k = 1:numel(tA)
    if ~ishandle(figA); break; end
    tNow = tA(k);                                               % video clock
    tPn  = tNow + o.lag;                                        % same instant on this sensor's clock

    cur = tAp > tNow - dtA/2 & tAp <= tNow + dtA/2;
    old = tAp > tNow - trail & tAp <= tNow - dtA/2;
    set(hNow,   'XData', xA(cur), 'YData', yA(cur));
    set(hTrail, 'XData', xA(old), 'YData', yA(old));

    passed = tBs(tBs <= tPn & tBs >= tPn + presWin(1));         % bores that have reached the sensor
    xb = [passed passed nan(size(passed))]';  yb = repmat([yl nan]', 1, numel(passed));
    set(hBore,  'XData', xb(:), 'YData', yb(:));
    set(hCrest, 'XData', tCs(tCs <= tPn), 'YData', eCs(tCs <= tPn));
    hLine.Value = tPn;
    xlim(axP, tPn + presWin);

    if any(abs(tBs - tPn) < 0.75)                               % flash the sensor while a bore is on it
        set(hSens, 'MarkerFaceColor', 'r', 'MarkerSize', 22);
    else
        set(hSens, 'MarkerFaceColor', 'y', 'MarkerSize', 16);
    end
    title(axM, sprintf('Tracked crests   %s', string(t0 + seconds(tNow), 'HH:mm:ss.S')), 'FontWeight', 'normal')

    if saveVideo
        writeVideo(vw, getframe(figA));
    else
        pause(dtA / playSpeed);
    end
end
if saveVideo; close(vw); fprintf('Saved %s\n', fullfile(vw.Path, vw.Filename)); end



%% ROLLER ANGLE, CREST WIDTH + WAVE HEIGHT of the broken waves

% Breaking wave = pressure wave matched to a video-tracked bore (out.isBore).
% For each breaking crest (front face = trough -> crest):
%   H     = eta(crest) - eta(trough)                       wave height [m]
%   W     = c * (tCrest - tTrough)                         crest width: horizontal trough-to-crest distance [m]
%   angle = atand( (dEta/dt of the 20-80% rise) / c )      roller angle [deg]  
% c = the tracked bore's own celerity at the sensor (cBore), not a bin mean.
minRise = 1;      % s, min trough->crest time (at 2 Hz, shorter fronts have too few samples for a slope)
maxW    = 15;     % m, crest widths above this are discarded (wave not used at all)

brk = zeros(0, 10);
for s = 1:numel(out)
    ob = out(s);
    if ~any(ob.isBore); continue; end
    eB = ob.eta;
    tS = seconds(ob.time - t0);                                       % s after top of hour (pressure clock)
    zcB = find(eB(1:end-1) > 0 & eB(2:end) <= 0);                     % same zero down-crossings as the sensor loop

    for w = find(ob.isBore)'
        seg = eB(zcB(w)+1 : zcB(w+1));                                % trough followed by its crest
        [~, it] = min(seg);   itr = zcB(w) + it;                      % trough sample
        [~, ic] = max(seg);   icr = zcB(w) + ic;                      % crest sample
        dtF = tS(icr) - tS(itr);                                      % trough -> crest time [s]
        H   = eB(icr) - eB(itr);                                      % trough -> crest height [m]

        kB = abs(seconds(ob.tCrest - ob.tWave(w))) < 0.1;             % bore(s) matched to this wave
        cW = mean(ob.cBore(kB));                                      % celerity of this wave [m/s]
        if dtF < minRise || ~(cW > 0); continue; end
        if cW*dtF > maxW; continue; end                               % crest width cap

        % 20-80% front-face slope
        e  = eB(itr:icr);   tv = tS(itr:icr);
        lo = e(1) + 0.2*H;  hi = e(1) + 0.8*H;
        k80 = find(e >= hi, 1, 'first');                              % first sample at/above 80%
        k20 = find(e(1:k80) <= lo, 1, 'last');                        % last sample at/below 20% before that
        t20 = interp1(e(k20:k20+1), tv(k20:k20+1), lo);
        t80 = interp1(e(k80-1:k80), tv(k80-1:k80), hi);
        tanB = (hi - lo) / (t80 - t20) / cW;                          % spatial slope: (dEta/dt) / c

        brk(end+1,:) = [ob.id, ob.x, ob.y, tS(icr), cW, H, dtF, cW*dtF, tanB, atand(tanB)]; %#ok<SAGROW>
    end
end
brk = array2table(brk, 'VariableNames', {'sensor','x','y','tCrest_s','c','H','dtFront','W','slope','angle'});
brk.tCrest = t0 + seconds(brk.tCrest_s);                              % crest time as datetime (pressure clock)

fprintf('\nBroken waves (tracked bores matched to pressure crests, W <= %g m): %d\n', maxW, height(brk));
fprintf('%-7s %-6s %-9s %-9s %-9s %-10s\n', 'Sensor', 'N', 'H [m]', 'W [m]', 'c [m/s]', 'angle [deg]');
for id = unique(brk.sensor)'
    k = brk.sensor == id;
    fprintf('p%02d     %-6d %-9.2f %-9.2f %-9.2f %-10.2f\n', id, nnz(k), mean(brk.H(k)), mean(brk.W(k)), mean(brk.c(k)), mean(brk.angle(k)));
end
fprintf('all     %-6d %-9.2f %-9.2f %-9.2f %-10.2f   (median W = %.2f m, median angle = %.2f deg)\n', ...
    height(brk), mean(brk.H), mean(brk.W), mean(brk.c), mean(brk.angle), median(brk.W), median(brk.angle));

if ~isempty(brk)
    runLabel = sprintf('Breaking Crests: %s/%s/%s %s', runDate(5:6), runDate(7:8), runDate(1:4), hourStr);   % e.g. 10/01/2013 1100

    figure('Name', 'Broken Waves: H, W, roller angle', 'Color', 'w', 'Position', [80 80 1300 420]);
    tlB = tiledlayout(1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tlB, runLabel, 'FontWeight', 'bold')

    nexttile; histogram(brk.H, 'FaceColor', [0.2 0.45 0.75], 'EdgeColor', 'w');
    xline(mean(brk.H), 'k--', sprintf('mean = %.2f m', mean(brk.H)));
    xlabel('H [m]'); ylabel('Count'); grid on; box on
    title(sprintf('Wave Height (N = %d)', height(brk)), 'FontWeight', 'normal')

    nexttile; histogram(brk.W, 'BinWidth', 0.5, 'FaceColor', [0.2 0.45 0.75], 'EdgeColor', 'w');
    xline(mean(brk.W), 'k--', sprintf('mean = %.2f m', mean(brk.W)));
    xlabel('W [m]'); ylabel('Count'); xlim([0 maxW]); grid on; box on
    title(sprintf('Crest Width (W \\leq %g m)', maxW), 'FontWeight', 'normal')

    nexttile; hold on
    Hbin = 0.1;       % m, wave-height bin width
    minN = 5;         % min waves in a bin for it to be plotted
    edgesH = 0 : Hbin : ceil(max(brk.H)/Hbin)*Hbin;
    nBin   = numel(edgesH) - 1;
    ib     = discretize(brk.H, edgesH);
    nIn    = accumarray(ib, 1, [nBin 1]);                             % waves per bin
    angM   = accumarray(ib, brk.angle, [nBin 1], @mean, NaN);         % mean roller angle per bin
    angS   = accumarray(ib, brk.angle, [nBin 1], @std,  NaN);         % std
    Hc     = edgesH(1:end-1)' + Hbin/2;                               % bin centers
    okB    = nIn >= minN;

    plot(brk.H, brk.angle, '.', 'Color', [0.8 0.8 0.8], 'MarkerSize', 6);            % individual waves (background)
    errorbar(Hc(okB), angM(okB), angS(okB), '-o', 'Color', [0.2 0.45 0.75], ...
        'MarkerFaceColor', [0.2 0.45 0.75], 'MarkerSize', 5, 'LineWidth', 1.5, 'CapSize', 3);
    xlabel('Wave height H [m]'); ylabel('Roller angle [deg]'); grid on; box on
    title(sprintf('\\theta_r vs H (%.2f m bins, mean \\pm std)', Hbin), 'FontWeight', 'normal')
end
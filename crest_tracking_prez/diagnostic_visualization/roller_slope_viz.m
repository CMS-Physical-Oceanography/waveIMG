
% roller slope extraction (og method using full trough -> crest)

filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/SURF-AI field data/2013/In situ time series/1002/10021200.p33'];
fid = fopen(filename,'r');
pressure = fread(fid,'float32');
pressure = pressure / 100; % m
fclose(fid);
fprintf('Samples: %d\n',length(pressure));
fs = 2;   % sampling freq
t = (0:length(pressure)-1)/fs;
eta = pressure - mean(pressure); % m, RAW -- no smoothing applied anywhere below

ind = t <= 300;      % time intv to plot
t5 = t(ind);
eta5 = eta(ind);

% --- ripple-rejection thresholds (all operate directly on RAW eta5) ---
% Ripples are rejected by how much a peak stands out from its neighboring valleys (prominence) 
% and how far apart real waves must be in time (peak distance)
minProm         = 0.01;  % [m] min prominence to count as a real crest/trough
                          % -- raise this to drop more small ripples
minPeakDist     = 3;     % [s] min time between neighboring accepted extrema
                          % -- raise this to stop closely-spaced ripples
                          %    from being counted near a real crest/trough
minWaveHeight   = 0.035; % [m] min trough-to-crest height to keep a wave
minTroughCrestTime = 1;  % [s] min trough->crest time (rejects near-vertical noise spikes that aren't a real rise)
maxTroughCrestTime = 20; % [s] max trough->crest time (rejects drift/DC creep)

% --- find crests & troughs directly on the RAW signal ------------------
[crestVals, crestIdx] = findpeaks(eta5, 'MinPeakProminence', minProm, 'MinPeakDistance', round(minPeakDist*fs));
crestTimes = t5(crestIdx);

[troughNeg, troughIdx] = findpeaks(-eta5, 'MinPeakProminence', minProm, 'MinPeakDistance', round(minPeakDist*fs));
troughVals = -troughNeg;
troughTimes = t5(troughIdx);

% --- pair each trough with the next crest, apply height/timing gates ---
waveTroughIdx = [];
waveCrestIdx  = [];
for i = 1:length(troughIdx)
    possibleCrests = find(crestIdx > troughIdx(i));
    if isempty(possibleCrests)
        continue
    end
    j  = possibleCrests(1);           % first crest after this trough
    dt = crestTimes(j) - troughTimes(i);
    dEta = crestVals(j) - troughVals(i);   % raw amplitude difference
    if dt >= minTroughCrestTime && dt <= maxTroughCrestTime && dEta >= minWaveHeight
        waveTroughIdx(end+1) = i; 
        waveCrestIdx(end+1)  = j; 
    end
end

% --- compute the temporal trough-to-crest slopes (m/s) -----------------
% this is dEta/dt only, apply c to turn these into a roller angle.
nWaves = length(waveTroughIdx);
waveSlope  = zeros(nWaves,1);
waveHeight = zeros(nWaves,1);
waveDt     = zeros(nWaves,1);
waveTroughTime = zeros(nWaves,1);
waveCrestTime  = zeros(nWaves,1);
for k = 1:nWaves
    i = waveTroughIdx(k);
    j = waveCrestIdx(k);
    waveTroughTime(k) = troughTimes(i);
    waveCrestTime(k)  = crestTimes(j);
    waveDt(k)     = crestTimes(j) - troughTimes(i);
    waveHeight(k) = crestVals(j) - troughVals(i);
    waveSlope(k)  = waveHeight(k) / waveDt(k);   % [m/s]
end

fprintf('\nNumber of coherent waves detected: %d\n', nWaves);
fprintf('Mean trough-to-crest slope:  %.4f m/s\n', mean(waveSlope));
fprintf('Median trough-to-crest slope: %.4f m/s\n', median(waveSlope));
fprintf('Mean trough-to-crest height: %.3f m\n', mean(waveHeight));
fprintf('Mean trough-to-crest time:   %.2f s\n\n', mean(waveDt));

% plot raw signal with extracted slopes overlaid 
figure
hold on
plot(t5, eta5, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.9); % raw eta only
for k = 1:nWaves
    i = waveTroughIdx(k);
    j = waveCrestIdx(k);
    x1 = troughTimes(i); y1 = troughVals(i);
    x2 = crestTimes(j);  y2 = crestVals(j);
    plot([x1 x2], [y1 y2], 'r-', 'LineWidth', 2);
    plot(x1, y1, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5); % trough
    plot(x2, y2, 'ko', 'MarkerFaceColor', 'w', 'MarkerSize', 6); % crest
end
xlabel('Time [s]')
ylabel('\eta [m]')
title('Raw \eta: Extracted Trough-to-Crest Slopes (no smoothing)')
legend('Raw \eta', 'Extracted slopes', 'Trough', 'Crest', 'Location', 'best')
grid on; box on

% plot slope / height vs wave number/count
figure
subplot(2,1,1)
plot(1:nWaves, waveSlope, 'ko-', 'LineWidth', 1.2, 'MarkerFaceColor', 'k')
xlabel('Wave number'); ylabel('Slope [m/s]')
title('Extracted Wave Slopes (raw, temporal)')
grid on; box on
subplot(2,1,2)
plot(1:nWaves, waveHeight, 'bo-', 'LineWidth', 1.2, 'MarkerFaceColor', 'b')
xlabel('Wave number'); ylabel('Height [m]')
title('Extracted Wave Heights (raw)')
grid on; box on


%% roller slope extraction -- 20-80% front-face method (used in roller_slope_v2.m)

filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/SURF-AI field data/2013/In situ time series/1002/10021200.p43'];
fid = fopen(filename,'r');
pressure = fread(fid,'float32');
pressure = pressure / 100; % m
fclose(fid);
fprintf('Samples: %d\n',length(pressure));
fs = 2;   % sampling freq
t = (0:length(pressure)-1)/fs;
eta = pressure - mean(pressure); % m, RAW -- no smoothing applied anywhere below

ind = t <= 300;      % time intv to plot
t5 = t(ind);
eta5 = eta(ind);

% --- ripple-rejection thresholds (all operate directly on RAW eta5) ---
minProm         = 0.01;  % [m] min prominence to count as a real crest/trough
minPeakDist     = 3;     % [s] min time between neighboring accepted extrema
minWaveHeight   = 0.035; % [m] min trough-to-crest height to keep a wave
minTroughCrestTime = 1;  % [s] min trough->crest time
maxTroughCrestTime = 20; % [s] max trough->crest time

loFrac = 0.2;            % lower level of the front-face slope (fraction of wave height)
hiFrac = 0.8;            % upper level

% --- find crests & troughs directly on the RAW signal ------------------
[crestVals, crestIdx] = findpeaks(eta5, 'MinPeakProminence', minProm, 'MinPeakDistance', round(minPeakDist*fs));
crestTimes = t5(crestIdx);

[troughNeg, troughIdx] = findpeaks(-eta5, 'MinPeakProminence', minProm, 'MinPeakDistance', round(minPeakDist*fs));
troughVals = -troughNeg;
troughTimes = t5(troughIdx);

% --- pair each trough with the next crest, apply height/timing gates ---
waveTroughIdx = [];
waveCrestIdx  = [];
for i = 1:length(troughIdx)
    possibleCrests = find(crestIdx > troughIdx(i));
    if isempty(possibleCrests)
        continue
    end
    j  = possibleCrests(1);           % first crest after this trough
    dt = crestTimes(j) - troughTimes(i);
    dEta = crestVals(j) - troughVals(i);
    if dt >= minTroughCrestTime && dt <= maxTroughCrestTime && dEta >= minWaveHeight
        waveTroughIdx(end+1) = i; 
        waveCrestIdx(end+1)  = j; 
    end
end

% --- temporal slopes (m/s): full trough-to-crest AND 20-80% front face --
nWaves = length(waveTroughIdx);
waveSlopeFull  = zeros(nWaves,1);   % old method: H / (t_crest - t_trough)
waveSlope      = zeros(nWaves,1);   % 20-80% front-face slope
waveHeight     = zeros(nWaves,1);
waveDt         = zeros(nWaves,1);
waveTroughTime = zeros(nWaves,1);
waveCrestTime  = zeros(nWaves,1);
waveT20 = zeros(nWaves,1);  waveT80 = zeros(nWaves,1);   % level-crossing times
waveLo  = zeros(nWaves,1);  waveHi  = zeros(nWaves,1);   % level values [m]
for k = 1:nWaves
    i = waveTroughIdx(k);
    j = waveCrestIdx(k);
    waveTroughTime(k) = troughTimes(i);
    waveCrestTime(k)  = crestTimes(j);
    waveDt(k)     = crestTimes(j) - troughTimes(i);
    waveHeight(k) = crestVals(j) - troughVals(i);
    waveSlopeFull(k) = waveHeight(k) / waveDt(k);

    seg = (troughIdx(i):crestIdx(j))';          % samples trough -> crest
    e   = eta5(seg);
    tv  = t5(seg)';
    lo  = troughVals(i) + loFrac*waveHeight(k);
    hi  = troughVals(i) + hiFrac*waveHeight(k);

    k80 = find(e >= hi, 1, 'first');            % first sample at/above 80%
    k20 = find(e(1:k80) <= lo, 1, 'last');      % last sample at/below 20% before that
    % linear interpolation of the exact crossing times between samples
    t20 = tv(k20)   + (lo - e(k20))   / (e(k20+1) - e(k20))   * (tv(k20+1) - tv(k20));
    t80 = tv(k80-1) + (hi - e(k80-1)) / (e(k80)   - e(k80-1)) * (tv(k80)   - tv(k80-1));

    waveT20(k) = t20;  waveT80(k) = t80;
    waveLo(k)  = lo;   waveHi(k)  = hi;
    waveSlope(k) = (hi - lo) / (t80 - t20);     % [m/s]
end

fprintf('\nNumber of coherent waves detected: %d\n', nWaves);
fprintf('Mean 20-80%% front slope:      %.4f m/s\n', mean(waveSlope));
fprintf('Median 20-80%% front slope:    %.4f m/s\n', median(waveSlope));
fprintf('Mean full trough-crest slope: %.4f m/s  (old method)\n', mean(waveSlopeFull));
fprintf('Mean 20-80%% / full ratio:      %.2f\n', mean(waveSlope./waveSlopeFull));
fprintf('Mean trough-to-crest height:  %.3f m\n', mean(waveHeight));
fprintf('Mean trough-to-crest time:    %.2f s\n', mean(waveDt));
fprintf('Mean 20-80%% rise time:        %.2f s  (fs = %g Hz, dt = %.2f s)\n\n', mean(waveT80-waveT20), fs, 1/fs);

% diagnostic 1: raw signal with 20-80% front-face segments overlaid
figure
hold on
hRaw = plot(t5, eta5, 'Color', [0.6 0.6 0.6], 'LineWidth', 0.9);
for k = 1:nWaves
    i = waveTroughIdx(k);
    j = waveCrestIdx(k);
    hFull = plot([troughTimes(i) crestTimes(j)], [troughVals(i) crestVals(j)], '--', 'Color',[0.4 0.4 0.4], 'LineWidth', 1);
    hFace = plot([waveT20(k) waveT80(k)], [waveLo(k) waveHi(k)], 'r-', 'LineWidth', 2.5);
    hLvl  = plot([waveT20(k) waveT80(k)], [waveLo(k) waveHi(k)], 's', 'MarkerEdgeColor','b', 'MarkerFaceColor','b', 'MarkerSize', 4);
    hTr   = plot(troughTimes(i), troughVals(i), 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);
    hCr   = plot(crestTimes(j),  crestVals(j),  'ko', 'MarkerFaceColor', 'w', 'MarkerSize', 6);
end
xlabel('Time [s]'); ylabel('\eta [m]')
title('Raw \eta: 20-80% Front-Face Slopes (red) vs. Full Trough-to-Crest (dashed)')
if nWaves > 0
    legend([hRaw hFull hFace hLvl hTr hCr], {'Raw \eta','Full trough-crest','20-80% front face','20% / 80% crossings','Trough','Crest'}, 'Location','northwest')
end
grid on; box on
xlim([30 130]);

% diagnostic 2: slope (both methods) and height vs wave number
figure
subplot(2,1,1); hold on
plot(1:nWaves, waveSlopeFull, 'o-', 'Color',[0.5 0.5 0.5], 'LineWidth', 1.2, 'MarkerFaceColor',[0.5 0.5 0.5])
plot(1:nWaves, waveSlope, 'ro-', 'LineWidth', 1.2, 'MarkerFaceColor', 'r')
xlabel('Wave number'); ylabel('Slope [m/s]')
title('Extracted Wave Slopes (raw, temporal)')
legend('Full trough-crest', '20-80% front face', 'Location','best')
grid on; box on
subplot(2,1,2)
plot(1:nWaves, waveHeight, 'bo-', 'LineWidth', 1.2, 'MarkerFaceColor', 'b')
xlabel('Wave number'); ylabel('Height [m]')
title('Extracted Wave Heights (raw)')
grid on; box on

% diagnostic 3: zoom on the first waves -- shows samples, 20/80% levels and crossings
nZoom = min(6, nWaves);
figure
for k = 1:nZoom
    subplot(2,3,k); hold on
    w = t5 >= waveTroughTime(k)-2 & t5 <= waveCrestTime(k)+2;
    plot(t5(w), eta5(w), 'o-', 'Color',[0.5 0.5 0.5], 'MarkerSize', 4, 'MarkerFaceColor',[0.5 0.5 0.5])   % actual samples
    yline(waveLo(k), 'b--'); yline(waveHi(k), 'b--');
    plot([waveT20(k) waveT80(k)], [waveLo(k) waveHi(k)], 'r-', 'LineWidth', 2.5)
    plot([waveT20(k) waveT80(k)], [waveLo(k) waveHi(k)], 'bs', 'MarkerFaceColor','b', 'MarkerSize', 5)
    xlabel('Time [s]'); ylabel('\eta [m]')
    title(sprintf('Wave %d: %.3f m/s (full %.3f)', k, waveSlope(k), waveSlopeFull(k)), 'FontSize', 9)
    grid on; box on
end
sgtitle('20-80% Method Check (dots = 2 Hz samples, blue dashes = 20% / 80% levels)')
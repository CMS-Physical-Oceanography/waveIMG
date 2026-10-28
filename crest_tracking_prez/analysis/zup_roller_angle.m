
% zero up-crossing roller angle extraction

%  Binned mean celerity + binned mean physical roller slope
%  Celerity bins follow PIV_correction.m. Waves are detected with the
%  zero-up-crossing method (as in zup_pres.m); the temporal slope (dEta/dt) of each
%  wave front is the 20-80% rise slope, divided by the mean celerity of the bin
%  that contains the pressure sensor (location from RODSEX_sensors_locs.xyz).
%  Section 8: roller-angle time series per sensor.
%  Section 9: roller angle vs zup wave height (all sensors).

%% USER INPUT -- date/time + settings
dateTag  = '1001';    % MMDD                       % must match available pressure data...
hourStr  = '1100';    % HHMM
year_str = '2013';

bin_size  = 5;        % m  (same as PIV_correction.m)
min_c_pts = 5;       % min video celerity points per bin (same as PIV_correction.m)
fs        = 2;        % pressure sampling freq [Hz]
tMax      = Inf;      % [s] analyze first tMax seconds of the pressure record

% zero-up-crossing wave screening
wp.minPeriod          = 3;      % [s] min zero-upcrossing wave period (drops short, high-frequency waves)
wp.minWaveHeight      = 0.035;  % [m] min trough-to-crest rise of the front
wp.minTroughCrestTime = 1;      % [s] min trough->crest time
wp.maxTroughCrestTime = 20;     % [s] max trough->crest time
wp.detrendSec         = 0;      % [s] 0 = remove record mean only (as in zup_pres.m);
                                %     >0 = also subtract a moving mean of this length (e.g. 300) to remove tide

xlimPlot = [90 170];  ylimPlot = [602 840];   % same view as PIV_correction.m

% derived labels / paths
dateLabel     = sprintf('%s/%s', dateTag(1:2), dateTag(3:4));
dateTimeLabel = sprintf('%s, %s', dateLabel, hourStr);

baseDir = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main';
videoOutputFile = fullfile(baseDir, 'mat_data', sprintf('%s_%s.mat', dateTag, hourStr));
sensorFile      = fullfile(baseDir, 'data', 'sensor_data', 'RODSEX_sensors_locs.xyz');
pressDir        = fullfile(baseDir, 'data', 'SURF-AI field data', year_str, 'In situ time series', dateTag);

%% 1) load video celerity + build bin grid (same geometry as PIV_correction.m)
S = load(videoOutputFile);
all_celerity = S.all_celerity_total;    % cols: x, y, cx, cy, |c|

x_edges = min(all_celerity(:,1)) : bin_size : max(all_celerity(:,1)) + bin_size;
y_edges = min(all_celerity(:,2)) : bin_size : max(all_celerity(:,2)) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2;
y_centers = y_edges(1:end-1) + bin_size/2;
n_xbins = length(x_centers);
n_ybins = length(y_centers);
xi = discretize(all_celerity(:,1), x_edges);
yi = discretize(all_celerity(:,2), y_edges);

vel_grid = nan(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi == c & yi == r;
        if sum(mask) >= min_c_pts
            vel_grid(r,c) = mean(all_celerity(mask,5));
        end
    end
end

%% 2) read sensor locations (same parsing as plot_sensor_loc.m)
fid = fopen(sensorFile,'r');
sensorData = [];
while ~feof(fid)
    ln = fgetl(fid);
    vals = sscanf(ln,'%f');
    if numel(vals) == 4          % ID, X, Y, Z
        sensorData(end+1,:) = vals(:)';
    end
end
fclose(fid);
sensorID = sensorData(:,1);
sensorX  = sensorData(:,2);
sensorY  = sensorData(:,3);
nS = numel(sensorID);
fprintf('Number of sensors found: %d\n', nS);

%% 2b) which sensors have pressure data for this date/time?
pfileList = cell(nS,1);
sHasFile  = false(nS,1);
for s = 1:nS
    pf = fullfile(pressDir, sprintf('%s%s.p%d',   dateTag, hourStr, sensorID(s)));
    if ~isfile(pf)
        pf = fullfile(pressDir, sprintf('%s%s.p%02d', dateTag, hourStr, sensorID(s)));
    end
    if isfile(pf); pfileList{s} = pf; sHasFile(s) = true; end
end
fprintf('%d of %d sensors have pressure data for %s\n', sum(sHasFile), nS, dateTimeLabel);

%% 3) per-sensor roller slopes -> pooled into celerity bins
tslope_pool = cell(n_ybins, n_xbins);   % temporal slopes dEta/dt [m/s], pooled per bin
sBinR = nan(nS,1);  sBinC = nan(nS,1);
sNwaves = zeros(nS,1);  sTslope = nan(nS,1);  sCbin = nan(nS,1);  sUsed = false(nS,1);
sWaveT   = cell(nS,1);                  % time of each wave's front [s]
sWaveAng = cell(nS,1);                  % spatial roller angle of each wave [deg]
sWaveH   = cell(nS,1);                  % zero-up-crossing wave height of each wave [m]

for s = 1:nS
    ci = discretize(sensorX(s), x_edges);
    ri = discretize(sensorY(s), y_edges);
    if isnan(ci) || isnan(ri)
        fprintf('Sensor %d: outside celerity grid -- skipped\n', sensorID(s)); continue
    end
    sBinR(s) = ri;  sBinC(s) = ci;
    sCbin(s) = vel_grid(ri,ci);
    if isnan(sCbin(s))
        fprintf('Sensor %d: bin has < %d celerity points -- skipped\n', sensorID(s), min_c_pts); continue
    end

    % pressure file: <MMDD><HHMM>.p<ID> inside the MMDD folder
    if ~sHasFile(s)
        fprintf('Sensor %d: no pressure file for %s -- skipped\n', sensorID(s), dateTimeLabel); continue
    end
    pfile = pfileList{s};

    fidp = fopen(pfile,'r');
    pressure = fread(fidp,'float32');
    fclose(fidp);
    pressure = pressure / 100;                 % m
    eta = pressure - mean(pressure);
    eta = eta(((0:numel(eta)-1)/fs) <= tMax);

    [ws, wt, wH] = extractWaveSlopes(eta, fs, wp);
    sNwaves(s) = numel(ws);
    if isempty(ws)
        fprintf('Sensor %d: no coherent waves detected -- skipped\n', sensorID(s)); continue
    end
    sTslope(s) = mean(ws);
    sUsed(s) = true;
    tslope_pool{ri,ci} = [tslope_pool{ri,ci}; ws];

    sWaveT{s}   = wt;                          % for sections 8 and 9
    sWaveH{s}   = wH;
    sWaveAng{s} = atand(ws ./ sCbin(s));       % spatial angle: tan(beta) = (dEta/dt)/c
end

% fprintf('\n%-7s %-8s %-9s %-8s %-6s\n','Sensor','hasFile','c_bin','nWaves','used'); % print if sensors locs are rejected
% for s = 1:nS
%     fprintf('%-7d %-8d %-9.2f %-8d %-6d\n', sensorID(s), sHasFile(s), sCbin(s), sNwaves(s), sUsed(s));
% end

%% 4) bin grids: temporal slope / mean celerity = physical slope
tslope_grid = nan(n_ybins, n_xbins);
nwave_grid  = zeros(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        if ~isempty(tslope_pool{r,c})
            tslope_grid(r,c) = mean(tslope_pool{r,c});
            nwave_grid(r,c)  = numel(tslope_pool{r,c});
        end
    end
end
slope_grid = tslope_grid ./ vel_grid;     % physical roller slope tan(beta) [m/m]
angle_grid = atand(slope_grid);           % roller angle [deg]

%% 5) summary table
fprintf('\n%-7s %-8s %-8s %-9s %-10s %-10s %-9s\n', 'Sensor','X [m]','Y [m]','nWaves','c_bin','dEta/dt','Angle');
for s = find(sUsed)'
    sl = sTslope(s)/sCbin(s);
    fprintf('%-7d %-8.1f %-8.1f %-9d %-10.2f %-10.4f %-9.2f deg\n', ...
        sensorID(s), sensorX(s), sensorY(s), sNwaves(s), sCbin(s), sTslope(s), atand(sl));
end

%% 6) figure: binned mean celerity with sensors
figure; hold on
h = imagesc(x_centers, y_centers, vel_grid);
set(h,'AlphaData',~isnan(vel_grid))
set(gca,'YDir','normal')
colormap(gca, parula)
cb = colorbar; cb.Label.String = 'Mean Celerity [m/s]';
caxis([0 6]);
plot(sensorX(sHasFile), sensorY(sHasFile), 'rp', 'MarkerSize', 11, 'MarkerFaceColor', 'r');
for s = find(sHasFile)'
    text(sensorX(s)+2, sensorY(s), sprintf('%d', sensorID(s)), 'Color','r', 'FontSize',9);
end
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Binned Mean Celerity - %s', dateTimeLabel))
grid minor; box on
xlim([90 210]); ylim([600 1000]);

%% 7) figure: binned mean roller angle (grey = celerity bin w/o angle, white = no celerity)
nC   = 256;
cl = [0 10];
cmap = parula(nC);

va  = ~isnan(angle_grid);      % bins with a roller angle
vc  = ~isnan(vel_grid);        % bins with celerity data
idx = round(1 + (min(max(angle_grid,cl(1)),cl(2)) - cl(1)) / (cl(2)-cl(1)) * (nC-1));

rgb = ones(n_ybins, n_xbins, 3);               % white outside the celerity map
for k = 1:3
    layer = rgb(:,:,k);
    layer(vc)  = 0.85;                         % light grey where celerity exists
    layer(va)  = cmap(idx(va), k);             % colored where roller angle exists
    rgb(:,:,k) = layer;
end

figure; hold on
image(x_centers, y_centers, rgb);
set(gca,'YDir','normal')
colormap(gca, cmap); caxis(cl);                % drives the colorbar only
cb = colorbar; cb.Label.String = 'Mean Roller Angle [deg]';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Binned Mean Roller Angle (dEta/dt / c) - %s', dateTimeLabel))
grid minor; box on
xlim([90 210]); ylim([600 1000]);

%% 8) per-sensor roller angle time series (one figure per sensor)
% each point = one detected wave, placed at the midpoint time of its 20-80% front:
%   angle = atand( (dEta/dt) / c_bin ),  c_bin = mean video celerity of the sensor's bin
for s = find(sUsed)'
    figure('Name', sprintf('Sensor %d roller angle', sensorID(s)));
    hold on
    plot(sWaveT{s}, sWaveAng{s}, '-', 'Color', [0.75 0.75 0.75], 'LineWidth', 0.8);   % guide line
    plot(sWaveT{s}, sWaveAng{s}, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
    yline(mean(sWaveAng{s}), 'k--', sprintf('mean = %.1f°', mean(sWaveAng{s})), ...
        'LabelHorizontalAlignment','left', 'LabelVerticalAlignment','bottom');
    xlabel('Time [s]'); ylabel('Roller Angle [deg]')
    title(sprintf('Sensor %d (x = %.1f m, y = %.1f m) - %s\nc_{bin} = %.2f m/s, %d waves', ...
        sensorID(s), sensorX(s), sensorY(s), dateTimeLabel, sCbin(s), sNwaves(s)))
    grid on; box on
    ylim([0 max(sWaveAng{s})*1.15]);
    % exportgraphics(gcf, sprintf('roller_angle_sensor%d_%s_%s.png', sensorID(s), dateTag, hourStr), 'Resolution', 200);
end

%% 9) scatter: roller angle (theta) vs zero-up-crossing wave height (H), all used sensors
allH = [];  allAng = [];  allX = [];
for s = find(sUsed)'
    allH   = [allH;   sWaveH{s}];                                   
    allAng = [allAng; sWaveAng{s}];                                
    allX   = [allX;   repmat(sensorX(s), numel(sWaveAng{s}), 1)];  
end
if ~isempty(allH)
    figure
    scatter(allH, allAng, 18, allX, 'filled', 'MarkerFaceAlpha', 0.6);
    colormap(gca, parula)
    cb = colorbar; cb.Label.String = 'Sensor cross-shore position [m]';
    xlabel('Wave height H [m]'); ylabel('Roller angle \theta [deg]')
    title(sprintf('Roller Angle vs Wave Height (zero-up-crossing) - %s, %d waves', dateTimeLabel, numel(allH)))
    grid on; box on
    ylim([0 20])
end

%% local function -- zero-up-crossing wave detection + 20-80% front-face slope
function [waveSlope, waveTime, waveH] = extractWaveSlopes(eta, fs, wp)
    eta = eta(:);
    t = (0:length(eta)-1)'/fs;

    % remove the mean (as in zup_pres.m) and, optionally, a slow trend such as the tide
    enew = eta - mean(eta);
    if wp.detrendSec > 0
        enew = enew - movmean(enew, round(wp.detrendSec*fs));
    end

    % zero up-crossings: index of the first sample above zero (same rule as zup_pres.m)
    upc = find(enew(1:end-1) < 0 & enew(2:end) > 0) + 1;

    waveSlope = [];
    waveTime  = [];
    waveH     = [];

    % zup wave k lies between up-crossings k and k+1 (crest, then trough).
    % Its front face is the rise from the trough just before up-crossing k
    % up to the crest that follows it.
    for k = 2:numel(upc)-1
        Tper = t(upc(k+1)) - t(upc(k));               % zup wave period
        if Tper < wp.minPeriod; continue; end

        seg = upc(k):upc(k+1);
        H   = max(enew(seg)) - min(enew(seg));        % zup wave height (emax - emin)

        [~, im] = min(enew(upc(k-1):upc(k)));
        itr = upc(k-1) + im - 1;                      % trough before the up-crossing
        [~, ix] = max(enew(upc(k):upc(k+1)-1));
        icr = upc(k) + ix - 1;                        % crest after the up-crossing

        dt   = t(icr) - t(itr);
        dEta = enew(icr) - enew(itr);
        if dt < wp.minTroughCrestTime || dt > wp.maxTroughCrestTime || dEta < wp.minWaveHeight
            continue
        end

        % --- 20-80% front-face slope ---
        e  = enew(itr:icr);
        tv = t(itr:icr);
        lo = enew(itr) + 0.2*dEta;
        hi = enew(itr) + 0.8*dEta;

        k80 = find(e >= hi, 1, 'first');              % first sample at/above 80%
        k20 = find(e(1:k80) <= lo, 1, 'last');        % last sample at/below 20% before that
        t20 = interp1(e(k20:k20+1), tv(k20:k20+1), lo);
        t80 = interp1(e(k80-1:k80), tv(k80-1:k80), hi);

        waveSlope(end+1,1) = (hi - lo) / (t80 - t20); %#ok<AGROW>   % [m/s]
        waveTime(end+1,1)  = (t20 + t80) / 2;         %#ok<AGROW>   % [s] midpoint of the front
        waveH(end+1,1)     = H;                       %#ok<AGROW>   % [m] zup wave height
    end
end
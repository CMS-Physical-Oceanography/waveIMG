% in situ sensor data
% 1. manual sensor xyz location plot
% 2. sensor pressure time series
% 3. pressure, prob, intens time series

%% 1. sensor loc
filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/bathy_surveys/RODDebbieTimeLagFix_20131002.xyz'];
data = readmatrix(filename,'FileType','text');
x = data(:,1);
y = data(:,2);
z = data(:,3);
dx = 5;
xq = min(x):dx:max(x);
yq = min(y):dx:max(y);
[Xq,Yq] = meshgrid(xq,yq);
Zq = griddata(x,y,z,Xq,Yq,'linear'); % lin interp
Zdepth = -Zq;

figure % background bathy for 10/02
h = imagesc(xq,yq,Zdepth);
set(h,'AlphaData',~isnan(Zdepth))
set(gca,'YDir','normal')
axis tight
box on
grid minor
hold on

x22 = 133.4638; % sensor loc
y22 = 824.3041;
plot(x22,y22,'rp','MarkerSize',12,'MarkerFaceColor','r')
text(x22+8,y22,'Sensor 22','Color','r')
cb = colorbar;
cb.Label.String = 'Depth [m]';
colormap(flipud(parula))
clim([0 3])
xlabel('Cross-Shore [m]')
ylabel('Alongshore [m]')
title('Sensor 22 Location')
% xlim([100 180])
% ylim([600 1020])
xlim([74.6 250.4]); ylim([589.6 1000.4]); % matches tracking animation plot

%% 2. paros pressure sensor time series plot
filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/sensor_data/10021200.q22']; % using q22

fid = fopen(filename,'r');
pressure = fread(fid,'float32');
pressure = pressure / 100; % m
fclose(fid);
fprintf('Samples: %d\n',length(pressure));
fs = 2;   % sampling freq
t = (0:length(pressure)-1)/fs;

figure
plot(t/3600,pressure)
xlabel('Time (hours)')
ylabel('Raw Pressure [mH20]')
title('Raw Pressure at q22, 1100-1200')
grid on

eta = pressure - mean(pressure); % m
ind = t <= 300; % first 5 mins

figure
plot(t(ind),eta(ind))
xlabel('Time (s)')
yL=ylabel('$\eta$ [m]'); yL.Interpreter = 'latex';
title('Sea Surface Elevation at q22, 1100-1105'); % fix to match file
grid on


%% pres, intens, prob plots - time-synced with cross corr - 7/25

filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/' ... % check date/time
    'RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/data/sensor_data/10021200.q22'];
load(['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/' ...
    'waveIMG-main/mat_data/sensor_timeseries/sensor_1002_1200.mat'], 'sensors')

xstart = 60; % plot start time
xend   = 120;

% pressure data
fid = fopen(filename,'r');
pressure = fread(fid,'float32');
fclose(fid);
pressure = pressure/100;
eta = pressure - mean(pressure);
fs = 2;
t_pressure = (0:length(eta)-1)/fs;

% sensor (video-derived) data -- first-pass alignment only
q = 22;
sensorName = sprintf('q%d', q);
pressureStartTime = dateshift(sensors.videoStartStamps(1), 'start', 'hour');
offset_sec = seconds(sensors.videoStartStamps(1) - pressureStartTime);

t_sensor_raw = sensors.(sensorName).time + offset_sec;   % approximate alignment
intensity    = sensors.(sensorName).intensity;
probability  = sensors.(sensorName).probability;

% empirically find the residual lag via cross-correlation
eta_interp = interp1(t_pressure, eta, t_sensor_raw, 'linear', 'extrap');
eta_n   = (eta_interp - mean(eta_interp)) / std(eta_interp);
prob_n  = (probability - mean(probability)) / std(probability);
int_n   = (intensity - mean(intensity)) / std(intensity);

dt = median(diff(t_sensor_raw));
maxlag = round(20/dt);

[c_prob, lags] = xcorr(eta_n, prob_n, maxlag, 'coeff');
[c_int, ~]     = xcorr(eta_n, int_n, maxlag, 'coeff');
lag_time = lags * dt;

[~, i1] = max(c_prob);
[~, i2] = max(c_int);

best_lag_prob = lag_time(i1);
best_lag_int  = lag_time(i2);

fprintf('First-pass offset (filename index-based):     %.2f s\n', offset_sec);
fprintf('Residual lag, pressure vs probability:  %.2f s\n', best_lag_prob);
fprintf('Residual lag, pressure vs intensity:    %.2f s\n', best_lag_int);

% use probability's lag (typically the cleaner signal) as the final correction
final_lag = best_lag_prob;
t_sensor = t_sensor_raw + final_lag;   % empirically synced time vector
fprintf('Final applied lag correction: %.2f s\n', final_lag);

% plots, now using the synced t_sensor
figure
subplot(3,1,1)
plot(t_pressure, eta, 'k')
ylabel('\eta [m]')
title('q22 Pressure')
grid on
xlim([xstart xend])

subplot(3,1,2)
plot(t_sensor, intensity, 'r')
ylabel('Pixel Intensity')
title('q22 Image Intensity')
grid on
xlim([xstart xend])

subplot(3,1,3)
plot(t_sensor, probability, 'b')
ylabel('UNET Probability')
xlabel('Time [s]')
ylim([0 1])
title('q22 Wave Front Probability')
grid on
xlim([xstart xend])
linkaxes(findall(gcf,'Type','axes'), 'x')


%% extract coherent roller slopes

% input
fs = 2;                         % sampling frequency [Hz]
ind = t <= 600;                 % first 5 minutes = 300s

t5 = t(ind);
eta5 = eta(ind);

fc = 0.18; % low pass filter cutoff freq

minProm = 0.01; % Minimum prominence of a crest/trough [m], Increase this to select only larger/coherent waves .025

minPeakDist = 6; % Minimum time between neighboring extrema [s], Prevents closely spaced ripples from being selected

minWaveHeight = 0.035; % Minimum trough-to-crest wave height [m]

minTroughCrestTime = 3; % Acceptable trough-to-crest time interval [s]
maxTroughCrestTime = 20;

% Low-pass filter, 4th-order Butterworth low-pass filter
[b,a] = butter(4, fc/(fs/2), 'low');
etaSmooth = filtfilt(b,a,eta5);

% Find crests
[crestVals, crestIdx] = findpeaks(etaSmooth, 'MinPeakProminence', minProm, 'MinPeakDistance', round(minPeakDist*fs));
crestTimes = t5(crestIdx);

% Find troughs
[troughNeg, troughIdx] = findpeaks(-etaSmooth, 'MinPeakProminence', minProm, 'MinPeakDistance', round(minPeakDist*fs));
troughVals = -troughNeg;
troughTimes = t5(troughIdx);

% Pair each trough with the next crest
waveTroughIdx = [];
waveCrestIdx = [];

for i = 1:length(troughIdx)

    % Find crests occurring after this trough
    possibleCrests = find(crestIdx > troughIdx(i));

    if isempty(possibleCrests)
        continue
    end

    % Take the first crest after the trough
    j = possibleCrests(1);

    % Time from trough to crest
    dt = crestTimes(j) - troughTimes(i);

    % Wave height
    dEta = crestVals(j) - troughVals(i);

    % Keep only physically reasonable trough-to-crest pairs
    if dt >= minTroughCrestTime &&  dt <= maxTroughCrestTime &&  dEta >= minWaveHeight
        waveTroughIdx(end+1) = i;
        waveCrestIdx(end+1) = j;
    end
end

% Calculate slopes
nWaves = length(waveTroughIdx);
waveSlope = zeros(nWaves,1);
waveHeight = zeros(nWaves,1);
wavePeriodHalf = zeros(nWaves,1);

for k = 1:nWaves

    i = waveTroughIdx(k);
    j = waveCrestIdx(k);

    dt = crestTimes(j) - troughTimes(i);
    dEta = crestVals(j) - troughVals(i);

    waveSlope(k) = dEta / dt;       % [m/s]
    waveHeight(k) = dEta;           % trough-to-crest [m]
    wavePeriodHalf(k) = dt;         % [s]

end

fprintf('\nNumber of coherent waves detected: %d\n', nWaves); % print stats
fprintf('Mean trough-to-crest slope: %.4f m/s\n', mean(waveSlope));
fprintf('Median trough-to-crest slope: %.4f m/s\n', median(waveSlope));
fprintf('Mean trough-to-crest height: %.3f m\n', mean(waveHeight));
fprintf('Mean trough-to-crest time: %.2f s\n\n',  mean(wavePeriodHalf));

% Diagnostic plot
figure
hold on

% Original sea surface elevation
plot(t5, eta5, 'Color', [0.7 0.7 0.7], 'LineWidth', 0.8);

% Filtered signal
plot(t5, etaSmooth,  'b', 'LineWidth', 1.5);

% Plot extracted trough-to-crest slopes
for k = 1:nWaves

    i = waveTroughIdx(k);
    j = waveCrestIdx(k);

    % Coordinates of trough and crest
    x1 = troughTimes(i);
    x2 = crestTimes(j);

    y1 = troughVals(i);
    y2 = crestVals(j);

    % Straight-line slope
    plot([x1 x2], [y1 y2], 'r-', 'LineWidth', 2);

    % Mark trough
    plot(x1, y1,'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 5);

    % Mark crest
    plot(x2, y2, 'ko', 'MarkerFaceColor', 'w', 'MarkerSize', 6);

end

xlabel('Time [s]')
ylabel('\eta [m]')
title('Extracted Trough-to-Crest Wave Slopes')
legend('Raw \eta', 'Low-pass filtered \eta', 'Extracted slopes', 'Trough', 'Crest', 'Location','best')
grid on
box on


% 2nd diagnostic plot: slope vs. wave

figure
subplot(2,1,1)
plot(1:nWaves, waveSlope, 'ko-', 'LineWidth', 1.2, 'MarkerFaceColor','k')
xlabel('Wave number')
ylabel('Trough-to-crest slope [m/s]')
title('Extracted Wave Slopes')
grid on
box on

subplot(2,1,2)
plot(1:nWaves, waveHeight, 'bo-', 'LineWidth', 1.2, 'MarkerFaceColor','b')
xlabel('Wave number')
ylabel('Trough-to-crest height [m]')
title('Extracted Wave Heights')
grid on
box on

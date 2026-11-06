
% BATHY INVERSION  Loads video-derived celerity + survey bathy for 1 hour, inverts celerity to depth, & comparison plots.

%% USER INPUT
year_str   = '2021';
runDate    = '20210904';        % yyyymmdd of the video run
hourStr    = '1600';            % hhmm
camera     = 'NorthTower';      % 2021: 'NorthTower' | 'SouthTower' 
                                % 2013: 'rod13'  (prefix of the saved .mat)

surveyDate = '20210905';        % yyyymmdd of bathy survey to use; '' = same day as runDate

bin_size = 5;    % m
min_pts  = 3;    % min survey pts per bin                % changed from 5 (original) to 3 !!!!!!
g        = 9.81;

yr = str2double(runDate(1:4));  mo = str2double(runDate(5:6));
dy = str2double(runDate(7:8));  hr = str2double(hourStr(1:2));
dateLabel     = sprintf('%02d/%02d/%d', mo, dy, yr);
dateTimeLabel = sprintf('%s, %s', dateLabel, hourStr);

%% paths
dataRoot  = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/rips_onedrive/NSF_Eddies';
matDir    = fullfile(dataRoot, 'mat_data');
surveyDir = fullfile(dataRoot, 'data', 'bathy_surveys');
tideFile  = fullfile(dataRoot, 'data', 'tide_duck', sprintf('duck_waterLvls%s.csv', year_str));

% video output: match on camera + date_hour only, ignore anything after (_0000, _enh, _test, ...)
runKey = [runDate '_' hourStr];
L = dir(fullfile(matDir, [camera '_' runKey '*.mat']));
if isempty(L)
    error('No mat file matching %s_%s*.mat in %s', camera, runKey, matDir);
end
if numel(L) > 1
    [~, iNew] = max([L.datenum]);
    warning('%d files match; using the newest: %s', numel(L), L(iNew).name);
    L = L(iNew);
end
videoOutputFile = fullfile(L.folder, L.name);
fprintf('Loading %s\n', L.name);

% survey file: naming differs by year
if isempty(surveyDate); surveyDate = runDate; end
switch year_str
    case '2013'; surveyPattern = sprintf('RODDebbieTimeLagFix_%s.xyz', surveyDate);
    case '2021'; surveyPattern = sprintf('FRF_%s_*.csv', surveyDate);
    otherwise;   error('Add a survey filename pattern for year %s', year_str);
end
SL = dir(fullfile(surveyDir, surveyPattern));
if isempty(SL); error('No survey file matching %s in %s', surveyPattern, surveyDir); end
if numel(SL) > 1; warning('%d survey files match; using %s', numel(SL), SL(1).name); end
surveyFile  = fullfile(SL(1).folder, SL(1).name);
surveyLabel = sprintf('%s/%s', surveyDate(5:6), surveyDate(7:8));

%% load celerity (only this variable; the mat is -v7.3 so the rest isn't read)
S = load(videoOutputFile, 'all_celerity_total');
all_celerity = S.all_celerity_total;

%% auto tide lookup
Ttide = readtable(tideFile, 'TextType', 'string');
tideDate = datetime(Ttide.Date, 'InputFormat', 'yyyy/MM/dd');
tideTimeOfDay = duration(Ttide.Time_LST_LDT_, 'InputFormat', 'hh:mm');
tideTime = tideDate + tideTimeOfDay;
waterLevel = Ttide.Verified_m_;

windowStart = datetime(yr, mo, dy, hr, 0, 0);
windowEnd   = windowStart + hours(1);
inWindow = tideTime >= windowStart & tideTime < windowEnd;
if ~any(inWindow)
    error('No tide data found for %s %s.', runDate, hourStr);
end
tide = mean(waterLevel(inWindow), 'omitnan');

%% build spatial grid + raw c-bathy fig
x_edges = min(all_celerity(:,1)) : bin_size : max(all_celerity(:,1)) + bin_size;
y_edges = min(all_celerity(:,2)) : bin_size : max(all_celerity(:,2)) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2;
y_centers = y_edges(1:end-1) + bin_size/2;
n_xbins = length(x_centers);
n_ybins = length(y_centers);
xi_speed = discretize(all_celerity(:,1), x_edges);
yi_speed = discretize(all_celerity(:,2), y_edges);

vel_grid = nan(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi_speed == c & yi_speed == r;
        if sum(mask) >= 10
            vel_grid(r,c) = mean(all_celerity(mask,5));
        end
    end
end
depth_grid_speed = (vel_grid).^2 ./ g - tide;

figure; hold on
h = imagesc(x_centers, y_centers, depth_grid_speed);
set(h,'AlphaData',~isnan(depth_grid_speed))
colormap(parula)
cb = colorbar; colormap(flipud(colormap))
cb.Label.String = 'Mean Depth [m, NAVD88]';
clim([0 3]);
axis tight
set(gca,'YDir','normal')
xlabel('Cross-shore [m]');
ylabel('Alongshore [m]')
title(sprintf('c-derived Bathy - %s', dateTimeLabel), 'FontSize',15)
grid minor; box on
% xlim([90 170]); ylim([602 1000])

%% survey format is chosen from the file name
[~, surveyName] = fileparts(surveyFile);
data = readmatrix(surveyFile, 'FileType', 'text', 'NumHeaderLines', 0);

if startsWith(surveyName, 'RODDebbie')          % 2013: x y z columns
    x = data(:,1);  y = data(:,2);  z = data(:,3);
elseif startsWith(surveyName, 'FRF_')           % 2021 FRF/LARC csv
    x = data(:,8);  y = data(:,9);  z = data(:,10);   % FRF X, FRF Y, NAVD88 elevation
else
    error('Unknown survey format: %s. Add a case here.', surveyName);
end

ok = ~isnan(x) & ~isnan(y) & ~isnan(z);
x = x(ok);  y = y(ok);  z = z(ok);

xi_survey = discretize(x, x_edges);
yi_survey = discretize(y, y_edges);

bathy_grid = nan(n_ybins, n_xbins);
count_grid = zeros(n_ybins, n_xbins);
for i = 1:length(x)
    if ~isnan(xi_survey(i)) && ~isnan(yi_survey(i))
        r = yi_survey(i); c = xi_survey(i);
        count_grid(r,c) = count_grid(r,c) + 1;
        if isnan(bathy_grid(r,c))
            bathy_grid(r,c) = z(i);
        else
            bathy_grid(r,c) = bathy_grid(r,c) + z(i);
        end
    end
end
mask_valid_counts = count_grid >= min_pts;
bathy_grid(mask_valid_counts) = bathy_grid(mask_valid_counts) ./ count_grid(mask_valid_counts);
depth_grid_survey = -bathy_grid;

figure
h = imagesc(x_centers, y_centers, depth_grid_survey);
set(gca,'YDir','normal')
set(h,'AlphaData',~isnan(depth_grid_survey))
axis tight
colormap(flipud(parula))
cb = colorbar; cb.Label.String = 'Depth [m, NAVD88]';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Survey Bathy %s - 5x5m bins', surveyLabel));
grid minor; box on
xlim([90 170]); ylim([602 1000]); clim([0 3])
hold on
plot(x, y, 'k.', 'MarkerSize', 1)

%% rmse map
valid = mask_valid_counts & ~isnan(depth_grid_speed);
rmse_err_grid = abs(depth_grid_speed - depth_grid_survey);
rmse_norm_grid = rmse_err_grid ./ depth_grid_survey;
rmse_norm_grid(~valid) = NaN;

figure
h = imagesc(x_centers, y_centers, rmse_norm_grid);
set(gca,'YDir','normal')
set(h,'AlphaData',~isnan(rmse_norm_grid))
set(gca,'Color','w')
axis tight; box on; grid minor
cmocean('-thermal');
cb = colorbar; clim([0 2]);
cb.Label.String = 'RMSE / h';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Normalized RMSE %s', dateTimeLabel))
xlim([100 180]); ylim([602 1000])

%% over/underestimate balance plot, 
norm_err = (depth_grid_speed - depth_grid_survey) ./ depth_grid_survey;
norm_err(~valid) = NaN;

figure
h = imagesc(x_centers, y_centers, norm_err);
set(h,'AlphaData',~isnan(norm_err))
set(gca,'YDir','normal')
axis tight; box on; grid minor
colormap(cmocean('balance'));
clim([-1 1])
cb = colorbar;
cb.Label.String = '$\epsilon$ / h';
cb.Label.Interpreter = 'latex';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Normalized Depth Error %s', dateTimeLabel), FontSize=15)
xlim([100 180]); ylim([602 1000])
set(gca,'Color','w')

dx = 10;
xq = min(x):dx:max(x);
yq = min(y):dx:max(y);
[Xq,Yq] = meshgrid(xq,yq);
Zq = griddata(x,y,z,Xq,Yq,'linear');
depth_contour = -Zq;
hold on
[C,hc] = contour(Xq,Yq,depth_contour,0.5:0.5:3,'k','LineWidth',1); % bathy contours
clabel(C,hc,'FontSize',7,'Color','k')

%% relative error vs. survey depth
figure;
depth = depth_grid_survey(:);
err = norm_err(:);
v = ~isnan(depth) & ~isnan(err);
plot(depth(v), err(v), '.')
hold on
for xbin = 0.25:0.25:3
    inBin = v & depth > xbin-0.125 & depth <= xbin+0.125;
    if sum(inBin) > 0
        plot(xbin, mean(err(inBin),'omitnan'), 'ro', 'MarkerFaceColor','r')
    end
end
yline(0,'k--')
xlabel('Survey Depth [m]')
yL = ylabel('$\epsilon$ / h'); yL.Interpreter = 'latex';
title(sprintf('Relative Depth Error vs. Survey Depth %s', dateTimeLabel))
grid minor; box on
xlim([0 3.5]); ylim([-1 1])
legend({'Individual 5x5m Bins','Mean Relative Error by Depth'}, 'Location','northeast')

%% std error plots
std_speed_grid = nan(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi_speed == c & yi_speed == r;
        if sum(mask) >= 10
            depth_samples = ((all_celerity(mask,5)).^2 ./ g) - tide;
            std_speed_grid(r,c) = std(depth_samples);
        end
    end
end

figure
h = imagesc(x_centers, y_centers, std_speed_grid);
set(gca,'YDir','normal')
set(h,'AlphaData',~isnan(std_speed_grid))
axis tight; box on; grid minor
cmocean('-thermal')
cb = colorbar; clim([0 2]);
cb.Label.String = 'Depth Std [m]';
title(sprintf('Celerity-Derived Depth Standard Deviation %s', dateTimeLabel))
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
xlim([86 200]); ylim([602 1000])

std_survey_grid = nan(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi_survey == c & yi_survey == r;
        if sum(mask) >= min_pts
            std_survey_grid(r,c) = std(-z(mask));
        end
    end
end

figure
h = imagesc(x_centers, y_centers, std_survey_grid);
set(gca,'YDir','normal')
set(h,'AlphaData',~isnan(std_survey_grid))
axis tight; box on; grid minor
cmocean('-thermal')
cb = colorbar; clim([0 0.3]);
cb.Label.String = 'Depth Std [m]';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Survey Bathymetry Standard Deviation %s', dateTimeLabel))
xlim([86 200]); ylim([602 1000])

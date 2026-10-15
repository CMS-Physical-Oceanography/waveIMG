
% BATHY INVERSION  Loads video-derived celerity + survey bathy for 1 hour, inverts celerity to depth, & comparison plots.

%% USER INPUT
dateTag  = '1002';    % MMDD
hourStr  = '1200';    % HHMM
year_str = '2013';    % survey/tide file year

bin_size = 5;    % m
min_pts  = 5;    % min survey pts per bin
g        = 9.81;

dateLabel = sprintf('%s/%s', dateTag(1:2), dateTag(3:4));
dateTimeLabel = sprintf('%s, %s', dateLabel, hourStr);

baseDir = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main';
videoOutputFile = fullfile(baseDir, 'mat_data', sprintf('%s_%s.mat', dateTag, hourStr));

% no bathy survey exists for 10/01 -- fall back to 10/02
surveyDateTag = dateTag;
if strcmp(dateTag, '1001'); surveyDateTag = '1002'; end
surveyFile = fullfile(baseDir, 'data', 'bathy_surveys', sprintf('RODDebbieTimeLagFix_%s%s.xyz', year_str, surveyDateTag));
tideFile = fullfile(baseDir, 'data', 'tide_duck', 'duck_waterLvls2013.csv');

%% load celerity
S = load(videoOutputFile);
all_celerity = S.all_celerity_total;

%% auto tide lookup
Ttide = readtable(tideFile, 'TextType', 'string');
tideDate = datetime(Ttide.Date, 'InputFormat', 'yyyy/MM/dd');
tideTimeOfDay = duration(Ttide.Time_LST_LDT_, 'InputFormat', 'hh:mm');
tideTime = tideDate + tideTimeOfDay;
waterLevel = Ttide.Verified_m_;

yr = str2double(year_str); mo = str2double(dateTag(1:2)); dy = str2double(dateTag(3:4)); hr = str2double(hourStr(1:2));
windowStart = datetime(yr, mo, dy, hr, 0, 0);
windowEnd   = windowStart + hours(1);
inWindow = tideTime >= windowStart & tideTime < windowEnd;
if ~any(inWindow)
    error('No tide data found for %s %s.', dateTag, hourStr);
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
xlim([90 170]); ylim([602 1000])

%% survey bathy - bin averaged
data = readmatrix(surveyFile,'FileType','text');
x = data(:,1); y = data(:,2); z = data(:,3);

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
title(sprintf('RODDebbie Survey Bathy %s - 5x5m bins', dateLabel))
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

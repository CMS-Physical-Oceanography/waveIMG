
function [depth_grid_speed_adj, depth_grid_speed, cx_adj_pts, cy_adj_pts, c_adj_pts, all_celerity, tide] = ...
    fn_piv_correction(dateTag, hourStr, year_str)

% FN_PIV_CORRECTION  Loads video-derived celerity + PIV currents + survey bathy for 1 hour, applies PIV correction, and produces
% raw-vs-PIV-corrected comparison plots.
%
% INPUTS:
%   dateTag  - 'MMDD' string, e.g. '1002'
%   hourStr  - 'HHMM' string, e.g. '1200'
%   year_str - 'YYYY' string, e.g. '2013'
%
% Fully self-contained: loads its own .mat, PIV, survey, and tide data.
% Independent of function_main_flow / function_bathy_inversion.

bin_size = 5;
piv_bin  = minutes(2); % time bin
min_pts  = 5;
g        = 9.81;

dateLabel = sprintf('%s/%s', dateTag(1:2), dateTag(3:4));
dateTimeLabel = sprintf('%s, %s', dateLabel, hourStr);

baseDir = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main';
videoOutputFile = fullfile(baseDir, 'mat_data', sprintf('%s_%s.mat', dateTag, hourStr));
pivFile         = fullfile(baseDir, 'data', 'PIV_2min', 'PVLAB_PIV_SurfaceFlows.mat');

surveyDateTag = dateTag;
if strcmp(dateTag, '1001'); surveyDateTag = '1002'; end
surveyFile = fullfile(baseDir, 'data', 'bathy_surveys', sprintf('RODDebbieTimeLagFix_%s%s.xyz', year_str, surveyDateTag));

tideFile = fullfile(baseDir, 'data', 'tide_duck', 'duck_waterLvls2013.csv');

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

%% load celerity
S = load(videoOutputFile);
all_celerity = S.all_celerity_total;
t_video      = S.all_celerity_time_total;

%% load + orient PIV data
P = load(pivFile);
u_full = -P.u; % changed b/c flipped in main flow
v_full = P.v; 
t_piv  = P.t;
if ~isdatetime(t_piv); t_piv = datetime(t_piv, 'ConvertFrom', 'datenum'); end
if ~isempty(t_piv.TimeZone); t_piv.TimeZone = ''; end

FX = P.FRFx;
FY = P.FRFy;
if ~isequal(size(u_full,1), size(FX,1)) || ~isequal(size(u_full,2), size(FX,2))
    error('u spatial dims do not match FRFx/FRFy grid size.');
end

pad = minutes(10);
piv_mask = t_piv >= (min(t_video) - pad) & t_piv <= (max(t_video) + pad);
if ~any(piv_mask)
    error('No PIV samples found near the video time window.');
end
t_piv  = t_piv(piv_mask);
u_full = u_full(:,:,piv_mask);
v_full = v_full(:,:,piv_mask);

edges_t = t_piv(1):piv_bin:t_piv(end)+piv_bin;
[~,~, pivBinIdx] = histcounts(t_piv, edges_t);

u_bin = cell(numel(edges_t)-1,1);
v_bin = cell(numel(edges_t)-1,1); 
for b = 1:numel(edges_t)-1
    idx = pivBinIdx == b;
    if any(idx)
       u_bin{b} = mean(u_full(:,:,idx), 3);
       v_bin{b} = mean(v_full(:,:,idx), 3);
    end
end

%% assign each video point to its PIV time bin, correct celerity

% [~,~, videoBinIdx] = histcounts(t_video, edges_t);
% cx_adj_pts = nan(size(all_celerity,1),1);
% cy_adj_pts = nan(size(all_celerity,1),1);
% c_adj_pts  = nan(size(all_celerity,1),1);
% 
% for b = 1:numel(u_bin)
%     if isempty(u_bin{b}); continue; end
%     pts = videoBinIdx == b;
%     if ~any(pts); continue; end
% 
%     u_at_pts = interp2(FX, FY, u_bin{b}, all_celerity(pts,1), all_celerity(pts,2), 'linear', NaN);
%     v_at_pts = interp2(FX, FY, v_bin{b}, all_celerity(pts,1), all_celerity(pts,2), 'linear', NaN);
% 
%     cx_adj_pts(pts) = all_celerity(pts,3) + u_at_pts;   % sign is flipped in fn_main_flow -(-...)
%     cy_adj_pts(pts) = all_celerity(pts,4) + v_at_pts;   
%     c_adj_pts(pts)  = hypot(cx_adj_pts(pts), cy_adj_pts(pts));
% end


% assign each video point to its PIV time bin, correct celerity (Doppler-shift projection)       correct method...
[~,~, videoBinIdx] = histcounts(t_video, edges_t);
cx_adj_pts = nan(size(all_celerity,1),1);
cy_adj_pts = nan(size(all_celerity,1),1);
c_adj_pts  = nan(size(all_celerity,1),1);

c_obs  = all_celerity(:,5);
cx_hat = all_celerity(:,3) ./ c_obs;   % unit vector of observed celerity direction
cy_hat = all_celerity(:,4) ./ c_obs;

for b = 1:numel(u_bin)
    if isempty(u_bin{b}); continue; end
    pts = videoBinIdx == b;
    if ~any(pts); continue; end

    u_at_pts = interp2(FX, FY, u_bin{b}, all_celerity(pts,1), all_celerity(pts,2), 'linear', NaN);
    v_at_pts = interp2(FX, FY, v_bin{b}, all_celerity(pts,1), all_celerity(pts,2), 'linear', NaN);

    % Doppler-shift correction: c_adj = c_obs - dot(u_piv, c_hat)
    u_dot_chat = u_at_pts .* cx_hat(pts) + v_at_pts .* cy_hat(pts);

    c_adj_pts(pts)  = c_obs(pts) - u_dot_chat;
    cx_adj_pts(pts) = c_adj_pts(pts) .* cx_hat(pts);   % direction unchanged, only magnitude corrected
    cy_adj_pts(pts) = c_adj_pts(pts) .* cy_hat(pts);
end

%% spatial grid
x_edges = min(all_celerity(:,1)) : bin_size : max(all_celerity(:,1)) + bin_size;
y_edges = min(all_celerity(:,2)) : bin_size : max(all_celerity(:,2)) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2;
y_centers = y_edges(1:end-1) + bin_size/2;
n_xbins = length(x_centers);
n_ybins = length(y_centers);

xi = discretize(all_celerity(:,1), x_edges);
yi = discretize(all_celerity(:,2), y_edges);

%% raw celerity bathy
vel_grid = nan(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi == c & yi == r;
        if sum(mask) >= 10
            vel_grid(r,c) = mean(all_celerity(mask,5));
        end
    end
end
depth_grid_speed = (vel_grid).^2 ./ g - tide;

%% PIV-adjusted celerity bathy
c_adj_grid = nan(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi == c & yi == r & ~isnan(c_adj_pts);
        if sum(mask) >= 10
            c_adj_grid(r,c) = mean(c_adj_pts(mask));
        end
    end
end
piv_valid = ~isnan(c_adj_grid);
depth_grid_speed_adj = (c_adj_grid).^2 ./ g - tide;
depth_grid_speed_adj(~piv_valid) = NaN;
depth_grid_speed(~piv_valid) = NaN;

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

%% figure: bathy maps, raw vs PIV-corrected
figure;
subplot(1,2,1); hold on
h = imagesc(x_centers, y_centers, depth_grid_speed);
set(h,'AlphaData',~isnan(depth_grid_speed))
colormap(flipud(parula))
cb = colorbar; cb.Label.String = 'Mean Depth [m, NAVD88]';
clim([0 3])
axis tight; set(gca,'YDir','normal')
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title('Celerity-Derived Bathymetry (raw)')
grid minor; box on
xlim([90 170]); ylim([602 840]);

subplot(1,2,2); hold on
h = imagesc(x_centers, y_centers, depth_grid_speed_adj);
set(h,'AlphaData',~isnan(depth_grid_speed_adj))
colormap(flipud(parula))
cb = colorbar; cb.Label.String = 'Mean Depth [m, NAVD88]';
clim([0 3])
axis tight; set(gca,'YDir','normal')
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title('Celerity-Derived Bathymetry (PIV-corrected)')
grid minor; box on
xlim([90 170]); ylim([602 840]);
sgtitle(sprintf('Celerity-Derived Bathymetry - %s (PIV-overlapping bins only)', dateTimeLabel))

%% error grids
valid = mask_valid_counts & ~isnan(depth_grid_speed) & piv_valid;
norm_err = (depth_grid_speed - depth_grid_survey) ./ depth_grid_survey;
norm_err(~valid) = NaN;

valid_adj = mask_valid_counts & ~isnan(depth_grid_speed_adj) & piv_valid;
norm_err_adj = (depth_grid_speed_adj - depth_grid_survey) ./ depth_grid_survey;
norm_err_adj(~valid_adj) = NaN;

rmse_norm_grid = abs(norm_err);
rmse_norm_grid_adj = abs(norm_err_adj);

figure;
subplot(1,2,1)
h = imagesc(x_centers, y_centers, rmse_norm_grid);
set(gca,'YDir','normal')
set(h,'AlphaData',~isnan(rmse_norm_grid))
set(gca,'Color','w')
axis tight; box on; grid minor
cmocean('-thermal');
cb = colorbar; clim([0 1]);
cb.Label.String = 'RMSE / h';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title('Normalized RMSE (raw)')
xlim([100 180]); ylim([602 840]);

subplot(1,2,2)
h = imagesc(x_centers, y_centers, rmse_norm_grid_adj);
set(gca,'YDir','normal')
set(h,'AlphaData',~isnan(rmse_norm_grid_adj))
set(gca,'Color','w')
axis tight; box on; grid minor
cmocean('-thermal');
cb = colorbar; clim([0 1]);
cb.Label.String = 'RMSE / h';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title('Normalized RMSE (PIV-corrected)')
xlim([100 180]); ylim([602 840]);
sgtitle(sprintf('Normalized RMSE %s', dateTimeLabel))

%% relative error vs. survey depth with best fit
figure;
subplot(1,2,1)
depth = depth_grid_survey(:);
err   = norm_err(:);
v = ~isnan(depth) & ~isnan(err);
plot(depth(v), err(v), '.')
hold on
xmean = []; ymean = [];
for xbin = 0.25:0.25:3
    inBin = v & depth > xbin-0.125 & depth <= xbin+0.125;
    if sum(inBin) > 0
        xmean(end+1) = xbin;
        ymean(end+1) = mean(err(inBin),'omitnan');
        plot(xbin, ymean(end), 'ro', 'MarkerFaceColor','r')
    end
end
p = polyfit(xmean, ymean, 1);
yfit = polyval(p, xmean);
plot(xmean, yfit, 'r--')
yline(0,'k--')
xlabel('Survey Depth [m]')
yL = ylabel('$\epsilon$ / h'); yL.Interpreter = 'latex';
title('Relative Depth Error (raw)')
grid minor; box on
xlim([0 3.5]); ylim([-1 1])
legend({'Individual 5x5m Bins', 'Mean Relative Error by Depth', sprintf('Best Fit (slope = %.3f)',p(1))}, 'Location','northeast')

subplot(1,2,2)
depth = depth_grid_survey(:);
err   = norm_err_adj(:);
v = ~isnan(depth) & ~isnan(err);
plot(depth(v), err(v), '.')
hold on
xmean = []; ymean = [];
for xbin = 0.25:0.25:3
    inBin = v & depth > xbin-0.125 & depth <= xbin+0.125;
    if sum(inBin) > 0
        xmean(end+1) = xbin;
        ymean(end+1) = mean(err(inBin),'omitnan');
        plot(xbin, ymean(end), 'ro', 'MarkerFaceColor','r')
    end
end
p = polyfit(xmean, ymean, 1);
yfit = polyval(p, xmean);
plot(xmean, yfit, 'r--')
yline(0,'k--')
xlabel('Survey Depth [m]')
yL = ylabel('$\epsilon$ / h'); yL.Interpreter = 'latex';
title('Relative Depth Error (PIV-corrected)')
grid minor; box on
xlim([0 3.5]); ylim([-1 1])
legend({'Individual 5x5m Bins', 'Mean Relative Error by Depth', sprintf('Best Fit (slope = %.3f)',p(1))}, 'Location','northeast')
sgtitle(sprintf('Relative Depth Error vs. Survey Depth %s', dateTimeLabel))

%% over/underestimate balance error map -- raw vs PIV-corrected, side by side
dx = 10;
xq = min(x):dx:max(x);
yq = min(y):dx:max(y);
[Xq,Yq] = meshgrid(xq,yq);
Zq = griddata(x,y,z,Xq,Yq,'linear');
depth_contour = -Zq;

figure;
subplot(1,2,1)
h = imagesc(x_centers, y_centers, norm_err);
set(h,'AlphaData',~isnan(norm_err))
set(gca,'YDir','normal')
axis tight; box on; grid minor
colormap(gca, cmocean('balance'));
clim([-1 1])
cb = colorbar;
cb.Label.String = '$\epsilon$ / h';
cb.Label.Interpreter = 'latex';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title('Raw')
xlim([100 180]); ylim([602 840])
set(gca,'Color','w')
hold on
[C,hc] = contour(Xq,Yq,depth_contour,0.5:0.5:3,'k','LineWidth',1);
clabel(C,hc,'FontSize',7,'Color','k')

subplot(1,2,2)
h = imagesc(x_centers, y_centers, norm_err_adj);
set(h,'AlphaData',~isnan(norm_err_adj))
set(gca,'YDir','normal')
axis tight; box on; grid minor
colormap(gca, cmocean('balance'));
clim([-1 1])
cb = colorbar;
cb.Label.String = '$\epsilon$ / h';
cb.Label.Interpreter = 'latex';
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title('PIV-corrected')
xlim([100 180]); ylim([602 840])
set(gca,'Color','w')
hold on
[C,hc] = contour(Xq,Yq,depth_contour,0.5:0.5:3,'k','LineWidth',1);
clabel(C,hc,'FontSize',7,'Color','k')
sgtitle(sprintf('Normalized Depth Error %s', dateTimeLabel))

end
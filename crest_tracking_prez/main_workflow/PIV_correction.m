
%  PIV correction pipeline: video-derived celerity, apply PIV, bathy comparison, error plots

%% USER INPUT -- for data paths               change surveyFile manually if analyzing 10/01 b/c no bathy survey
dateTag  = '1002';    % MMDD
hourStr  = '1200';    % HHMM
year_str = '2013';    % survey file year prefix

bin_size = 5;          % m
piv_bin  = minutes(2);
min_pts  = 5;          % min survey pts per bin
g        = 9.81;

% derived display labels -- used in all titles/sgtitles below
dateLabel = sprintf('%s/%s', dateTag(1:2), dateTag(3:4));   % e.g. '10/02'
hourLabel = hourStr;                                          % e.g. '1400'
dateTimeLabel = sprintf('%s, %s', dateLabel, hourLabel);       % e.g. '10/02, 1400'

% derived file paths
baseDir = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main';
videoOutputFile = fullfile(baseDir, 'mat_data', sprintf('%s_%s.mat', dateTag, hourStr));
pivFile         = fullfile(baseDir, 'data', 'PIV_2min', 'PVLAB_PIV_SurfaceFlows.mat');
surveyDateTag = dateTag;
if strcmp(dateTag, '1001'); surveyDateTag = '1002'; end   % no bathy survey for 10/01, use 10/02 instead
surveyFile = fullfile(baseDir, 'data', 'bathy_surveys', sprintf('RODDebbieTimeLagFix_%s%s.xyz', year_str, surveyDateTag));

% tide lookup from csv file
tideFile = fullfile(baseDir, 'data', 'tide_duck', 'duck_waterLvls2013.csv');
Ttide = readtable(tideFile, 'TextType', 'string');
tideDate = datetime(Ttide.Date, 'InputFormat', 'yyyy/MM/dd');
tideTimeOfDay = duration(Ttide.Time_LST_LDT_, 'InputFormat', 'hh:mm');
tideTime = tideDate + tideTimeOfDay;
waterLevel = Ttide.Verified_m_;
yr = str2double(year_str); mo = str2double(dateTag(1:2)); dy = str2double(dateTag(3:4)); hr = str2double(hourStr(1:2));
windowStart = datetime(yr, mo, dy, hr, 0, 0); windowEnd   = windowStart + hours(1);
inWindow = tideTime >= windowStart & tideTime < windowEnd;
if ~any(inWindow)
    error('No tide data found for %s %s (window %s to %s). Check date range (file covers 9/25-10/26).', ...
        dateTag, hourStr, datestr(windowStart), datestr(windowEnd));
end
tide = mean(waterLevel(inWindow), 'omitnan'); % tide-based water lvl for depth adjustment
% fprintf('Auto tide: %s %s -> mean verified water level = %.3f m (n=%d samples)\n', dateTag, hourStr, tide, sum(inWindow));

%% 1) load inputs
S = load(videoOutputFile);
all_celerity = S.all_celerity_total;
t_video      = S.all_celerity_time_total;

%% 2) load + orient PIV data
P = load(pivFile);
u_full = -P.u;
v_full = P.v;
t_piv  = P.t;
if ~isdatetime(t_piv); t_piv = datetime(t_piv, 'ConvertFrom', 'datenum'); end
if ~isempty(t_piv.TimeZone); t_piv.TimeZone = ''; end

FX = P.FRFx;
FY = P.FRFy;
if ~isequal(size(u_full,1), size(FX,1)) || ~isequal(size(u_full,2), size(FX,2))
    error('u spatial dims do not match FRFx/FRFy grid size.');
end

pad = minutes(10); % pad for piv time vector
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

%% 3) assign each video point to its PIV time bin, correct celerity

% [~,~, videoBinIdx] = histcounts(t_video, edges_t);             ***vector subtraction method old/worse
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
%     cx_adj_pts(pts) = all_celerity(pts,3) - u_at_pts;   % cx column 
%     cy_adj_pts(pts) = all_celerity(pts,4) - v_at_pts;   % cy column
%     c_adj_pts(pts)  = hypot(cx_adj_pts(pts), cy_adj_pts(pts));
% end

% 3) assign each video c-pt to its PIV time bin, correct celerity (Doppler-shift projection)
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

%% 4) same spatial grid
x_edges = min(all_celerity(:,1)) : bin_size : max(all_celerity(:,1)) + bin_size;
y_edges = min(all_celerity(:,2)) : bin_size : max(all_celerity(:,2)) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2;
y_centers = y_edges(1:end-1) + bin_size/2;
n_xbins = length(x_centers);
n_ybins = length(y_centers);
xi = discretize(all_celerity(:,1), x_edges);
yi = discretize(all_celerity(:,2), y_edges);

%% 5) raw celerity bathy
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

%% 6) PIV-adjusted celerity bathy
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

%% 7) survey bathy - bin averaged (kept for error/RMSE comparison, not plotted)
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

%% 8) figure: bathy maps, raw vs PIV-corrected (both restricted to PIV overlap)
figure;
subplot(1,2,1); hold on
h = imagesc(x_centers, y_centers, depth_grid_speed);
set(h,'AlphaData',~isnan(depth_grid_speed))
colormap(flipud(parula))
cb = colorbar; cb.Label.String = 'Mean Depth [m, NAVD88]';
clim([0 3])
axis tight; set(gca,'YDir','normal')
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title('cBathy (raw)')
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
title('cBathy (PIV)')
grid minor; box on
xlim([90 170]); ylim([602 840]);
sgtitle(sprintf('Celerity-Derived Bathymetry - %s (PIV-overlapping bins only)', dateTimeLabel))

%% 9) error grids
valid = mask_valid_counts & ~isnan(depth_grid_speed) & piv_valid;
norm_err = (depth_grid_speed - depth_grid_survey) ./ depth_grid_survey;
norm_err(~valid) = NaN;

valid_adj = mask_valid_counts & ~isnan(depth_grid_speed_adj) & piv_valid;
norm_err_adj = (depth_grid_speed_adj - depth_grid_survey) ./ depth_grid_survey;
norm_err_adj(~valid_adj) = NaN;

rmse_norm_grid = abs(norm_err);
rmse_norm_grid_adj = abs(norm_err_adj);

% figure; % plot RMSE maps, raw vs PIV-corrected
% subplot(1,2,1)
% h = imagesc(x_centers, y_centers, rmse_norm_grid);
% set(gca,'YDir','normal')
% set(h,'AlphaData',~isnan(rmse_norm_grid))
% set(gca,'Color','w')
% axis tight; box on; grid minor
% cmocean('-thermal');
% cb = colorbar; clim([0 1]);
% cb.Label.String = 'RMSE / h';
% xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
% title('Normalized RMSE (raw)')
% xlim([100 180]); ylim([602 840]);
% 
% subplot(1,2,2)
% h = imagesc(x_centers, y_centers, rmse_norm_grid_adj);
% set(gca,'YDir','normal')
% set(h,'AlphaData',~isnan(rmse_norm_grid_adj))
% set(gca,'Color','w')
% axis tight; box on; grid minor
% cmocean('-thermal');
% cb = colorbar; clim([0 1]);
% cb.Label.String = 'RMSE / h';
% xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
% title('Normalized RMSE (PIV-corrected)')
% xlim([100 180]); ylim([602 840]);
% sgtitle(sprintf('Normalized RMSE %s', dateLabel))

%% 11) figure: rel error vs depth w/ best fit line
% figure;
% subplot(1,2,1)
% depth = depth_grid_survey(:);
% err   = norm_err(:);
% v = ~isnan(depth) & ~isnan(err);
% plot(depth(v), err(v), '.')
% hold on
% xmean = [];
% ymean = [];
% for xbin = 0.25:0.25:3
%     inBin = v & depth > xbin-0.125 & depth <= xbin+0.125;
%     if sum(inBin) > 0
%         xmean(end+1) = xbin;
%         ymean(end+1) = mean(err(inBin),'omitnan');
% 
%         plot(xbin, ymean(end), 'ro', 'MarkerFaceColor','r')
%     end
% end
% 
% p = polyfit(xmean, ymean, 1);
% yfit = polyval(p, xmean);
% plot(xmean, yfit, 'r--')
% yline(0,'k--')
% xlabel('Survey Depth [m]')
% yL = ylabel('$\epsilon$ / h'); yL.Interpreter = 'latex';
% title('Relative Depth Error (raw)')
% grid minor; box on
% xlim([0 3.5]); ylim([-1 1])
% legend({'Individual 5x5m Bins', 'Mean Relative Error by Depth', sprintf('Best Fit (slope = %.3f)',p(1))}, 'Location','northeast')
% 
% subplot(1,2,2)
% depth = depth_grid_survey(:);
% err   = norm_err_adj(:);
% v = ~isnan(depth) & ~isnan(err);
% plot(depth(v), err(v), '.')
% hold on
% xmean = [];
% ymean = [];
% for xbin = 0.25:0.25:3
%     inBin = v & depth > xbin-0.125 & depth <= xbin+0.125;
%     if sum(inBin) > 0
%         xmean(end+1) = xbin;
%         ymean(end+1) = mean(err(inBin),'omitnan');
% 
%         plot(xbin, ymean(end), 'ro', 'MarkerFaceColor','r')
%     end
% end
% p = polyfit(xmean, ymean, 1);
% yfit = polyval(p, xmean);
% plot(xmean, yfit, 'r--')
% yline(0,'k--')
% xlabel('Survey Depth [m]')
% yL = ylabel('$\epsilon$ / h'); yL.Interpreter = 'latex';
% title('Relative Depth Error (PIV-corrected)')
% grid minor; box on
% xlim([0 3.5]); ylim([-1 1])
% legend({'Individual 5x5m Bins', 'Mean Relative Error by Depth', sprintf('Best Fit (slope = %.3f)',p(1))}, 'Location','northeast')
% sgtitle(sprintf('Relative Depth Error vs. Survey Depth %s', dateTimeLabel))

%% 12) figure: rel error vs depth w/ best fit line (raw vs PIV-corrected, overlaid)
figure; hold on

depth = depth_grid_survey(:);

% --- raw ---
err_raw = norm_err(:);
v_raw = ~isnan(depth) & ~isnan(err_raw);
h_raw_pts = plot(depth(v_raw), err_raw(v_raw), '.', 'Color', [0.30 0.55 0.95]);

xmean_raw = []; ymean_raw = [];
for xbin = 0.25:0.25:3
    inBin = v_raw & depth > xbin-0.125 & depth <= xbin+0.125;
    if sum(inBin) > 0
        xmean_raw(end+1) = xbin;
        ymean_raw(end+1) = mean(err_raw(inBin),'omitnan');
    end
end
h_raw_mean = plot(xmean_raw, ymean_raw, 'o', 'MarkerFaceColor', [0.10 0.30 0.80], 'MarkerEdgeColor', [0.10 0.30 0.80]);
p_raw = polyfit(xmean_raw, ymean_raw, 1);
h_raw_fit = plot(xmean_raw, polyval(p_raw, xmean_raw), '--', 'Color', [0.10 0.30 0.80], 'LineWidth', 1.5);

% --- PIV-corrected ---
err_adj = norm_err_adj(:);
v_adj = ~isnan(depth) & ~isnan(err_adj);
h_adj_pts = plot(depth(v_adj), err_adj(v_adj), '.', 'Color', [0.95 0.55 0.20]);

xmean_adj = []; ymean_adj = [];
for xbin = 0.25:0.25:3
    inBin = v_adj & depth > xbin-0.125 & depth <= xbin+0.125;
    if sum(inBin) > 0
        xmean_adj(end+1) = xbin;
        ymean_adj(end+1) = mean(err_adj(inBin),'omitnan');
    end
end
h_adj_mean = plot(xmean_adj, ymean_adj, 'o', 'MarkerFaceColor', [0.80 0.30 0.05], 'MarkerEdgeColor', [0.80 0.30 0.05]);
p_adj = polyfit(xmean_adj, ymean_adj, 1);
h_adj_fit = plot(xmean_adj, polyval(p_adj, xmean_adj), '--', 'Color', [0.80 0.30 0.05], 'LineWidth', 1.5);

yline(0,'k--')
xlabel('Survey Depth [m]')
yL = ylabel('$\epsilon$ / h'); yL.Interpreter = 'latex';
title(sprintf('Relative Depth Error (PIV-corrected vs. Raw) %s', dateTimeLabel), 'FontSize',15)
grid minor; box on
xlim([0.25 3]); ylim([-.8 .8])
legend([h_raw_pts, h_raw_mean, h_raw_fit, h_adj_pts, h_adj_mean, h_adj_fit], ...
    {'Raw: Individual Bins', 'Raw: Mean by Depth', 'Raw: Best Fit', ...
     'PIV: Individual Bins', 'PIV: Mean by Depth', 'PIV: Best Fit'}, ...
    'Location','northeast')

text(0.98, 0.09, sprintf('Raw slope = %.3f', p_raw(1)), ...
    'Units','normalized', 'HorizontalAlignment','right', 'Color',[0.10 0.30 0.80],'FontSize', 12, 'FontWeight','bold')
text(0.98, 0.04, sprintf('PIV-corrected slope = %.3f', p_adj(1)), ...
    'Units','normalized', 'HorizontalAlignment','right', 'Color',[0.80 0.30 0.05], 'FontSize', 12, 'FontWeight','bold')

%% 13) over/underestimate balance error map -- raw vs PIV-corrected, side by side
dx = 10; % dx for interpolation of survey bathy for contours (shared by both panels)
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
axis tight
box on
grid minor
colormap(gca, cmocean('balance'));
caxis([-1 1])
cb = colorbar;
cb.Label.String = '$\epsilon$ / h';
cb.Label.Interpreter = 'latex';
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title('Normalized Depth Error (raw)')
xlim([100 180])
ylim([602 840])
set(gca,'Color','w')
hold on
[C,hc] = contour(Xq,Yq,depth_contour,0.5:0.5:3,'k','LineWidth',1);
clabel(C,hc,'FontSize',7,'Color','k')

subplot(1,2,2)
h = imagesc(x_centers, y_centers, norm_err_adj);
set(h,'AlphaData',~isnan(norm_err_adj))
set(gca,'YDir','normal')
axis tight
box on
grid minor
colormap(gca, cmocean('balance'));
caxis([-1 1])
cb = colorbar;
cb.Label.String = '$\epsilon$ / h';
cb.Label.Interpreter = 'latex';
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title('Normalized Depth Error (PIV)')
xlim([100 180])
ylim([602 840])
set(gca,'Color','w')
hold on
[C,hc] = contour(Xq,Yq,depth_contour,0.5:0.5:3,'k','LineWidth',1);
clabel(C,hc,'FontSize',7,'Color','k')
sgtitle(sprintf('Normalized Depth Error %s', dateTimeLabel))

%% PIV vector field snapshot - 10/02 ~13:00

dateTag  = '1002'; hourStr = '1300'; year_str = '2013';

baseDir  = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main';
pivFile  = fullfile(baseDir, 'data', 'PIV_2min', 'PVLAB_PIV_SurfaceFlows.mat');
matFile  = fullfile(baseDir, 'mat_data', sprintf('%s_%s.mat', dateTag, hourStr));

% load PIV, find frame nearest the target time
P = load(pivFile);
FX = P.FRFx; FY = P.FRFy;
t_piv = P.t;
if ~isdatetime(t_piv); t_piv = datetime(t_piv, 'ConvertFrom', 'datenum'); end
if ~isempty(t_piv.TimeZone); t_piv.TimeZone = ''; end

target_time = datetime(str2double(year_str), str2double(dateTag(1:2)), str2double(dateTag(3:4)), ...
    str2double(hourStr(1:2)), str2double(hourStr(3:4)), 0);
[~, k] = min(abs(t_piv - target_time));
fprintf('Using PIV frame %d: %s\n', k, string(t_piv(k)));

u_frame = P.u(:,:,k);
v_frame = P.v(:,:,k);

% optional grayscale background (first available rectified frame from that hour)
haveBG = exist(matFile,'file');
if haveBG
    S = load(matFile, 'rectified_frames','X','Y');
    bg = [];
    for kk = 1:numel(S.rectified_frames)
        if ~isempty(S.rectified_frames{kk}); bg = S.rectified_frames{kk}; break; end
    end
    haveBG = ~isempty(bg);
end

% plot
figure; hold on
if haveBG
    h = imagesc(S.X, S.Y, bg);
    colormap(gca, bone)
    set(h, 'AlphaData', 0.6)
end

skip        = 2;   % thin the grid for readability
vec_scale   = 20;  % data-units of arrow length per 1 m/s (tune to taste)

quiver(FX(1:skip:end,1:skip:end), FY(1:skip:end,1:skip:end), ...
       u_frame(1:skip:end,1:skip:end)*vec_scale, v_frame(1:skip:end,1:skip:end)*vec_scale, ...
       0, 'Color','b','LineWidth',1)

box on
set(gca,'YDir','normal')
xlabel('x (m)'); ylabel('y (m)')
xlim([min(FX(:)) max(FX(:))]); ylim([min(FY(:)) max(FY(:))])
title(sprintf('PIV Surface Currents - %s/%s %s', dateTag(1:2), dateTag(3:4), string(t_piv(k),'HH:mm')), 'FontSize',12)
xlim([75 165]); ylim([600 830])

% reference vector (scale-matched to the field arrows above)
qx0 = min(FX(:)) + 0.08*range(FX(:));
% qy0 = max(FY(:)) - 0.05*range(FY(:));
qy0 = 630;
quiver(qx0, qy0, 1*vec_scale, 0, 0, 'Color','k','LineWidth',2)
text(qx0, qy0 + 0.03*range(FY(:)), '1 m/s', 'FontWeight','bold')



%% PIV curl field (hourly-averaged surface current vorticity)

% One curl field per available PIV frame within the target hour, then
% averaged -- same aggregation the Fbr curl map uses (mean over every
% along-crest sample collected that hour), so the two are comparable.

hour_start = datetime(str2double(year_str), str2double(dateTag(1:2)), str2double(dateTag(3:4)), ...
    str2double(hourStr(1:2)), 0, 0);
hour_end   = hour_start + hours(1);

in_hour   = t_piv >= hour_start & t_piv < hour_end;
frame_idx = find(in_hour);
fprintf('PIV frames in this hour: %d\n', numel(frame_idx))

xvec = FX(1,:);   % assumes FX/FY came from meshgrid(x,y) -- constant along the other dim
yvec = FY(:,1);

curl_stack = nan(size(FX,1), size(FX,2), numel(frame_idx));

for ii = 1:numel(frame_idx)
    kk = frame_idx(ii);
    u_ii = P.u(:,:,kk);
    v_ii = P.v(:,:,kk);

    [dvdx, ~] = gradient(v_ii, xvec, yvec);   % dv/dx
    [~, dudy] = gradient(u_ii, xvec, yvec);   % du/dy

    curl_stack(:,:,ii) = dvdx - dudy;         % zeta = dv/dx - du/dy
end

curl_piv_mean = mean(curl_stack, 3, 'omitnan');

figure
h = imagesc(xvec, yvec, curl_piv_mean);
set(h,'AlphaData',~isnan(curl_piv_mean))
set(gca,'YDir','normal')
axis tight; box on; grid minor
colormap(gca, cmocean('balance'));
cb = colorbar; cb.Label.String = '\nabla \times c_{PIV} [s^{-1}]';
cb.Label.Interpreter = 'tex';
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title('PIV Surface Current Vorticity', FontSize=15)
xlim([85 170]); ylim([623 827])
clim([-.05 .05])

%% print out rmse

rmse_raw_m = sqrt(mean((depth_grid_speed(valid) - depth_grid_survey(valid)).^2));
rmse_piv_m = sqrt(mean((depth_grid_speed_adj(valid_adj) - depth_grid_survey(valid_adj)).^2));
fprintf('Raw depth RMSE: %.3f m\n', rmse_raw_m)
fprintf('PIV-corrected depth RMSE: %.3f m\n', rmse_piv_m)

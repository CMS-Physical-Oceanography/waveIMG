% Fbr, vort calculations, old unclauded

%% USER INPUTS
dateTag = '1002';
hourStr = '1200';
year_str = '2013';

data_source = 'raw';     % 'raw' or 'piv'

%% LOAD MAT FILE
baseDir = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main'];
matDataDir = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/mat_data'];
S = load(fullfile(matDataDir,sprintf('%s_%s.mat',dateTag,hourStr)));
dateTimeLabel = sprintf('%s/%s %s:%s', dateTag(1:2), dateTag(3:4), hourStr(1:2), hourStr(3:4));

%% LOAD CREST WIDTHS.....old
crest_widths_all = vertcat(S.all_crest_widths{:});
crest_widths_all = crest_widths_all(~isnan(crest_widths_all));
crest_widths_all = crest_widths_all(crest_widths_all > 0);

%% LOAD CELERITY DATA
all_celerity_hour = S.all_celerity_total;
x_pts = all_celerity_hour(:,1);
y_pts = all_celerity_hour(:,2);

switch data_source
    case 'raw'
        cx_pts = all_celerity_hour(:,3);
        cy_pts = all_celerity_hour(:,4);
        c_pts = all_celerity_hour(:,5);

    case 'piv'
        [~,~,cx_adj_pts,cy_adj_pts,c_adj_pts,~,tide] = fn_piv_correction(dateTag,hourStr,year_str); % use piv-adj c

        cx_pts = cx_adj_pts;
        cy_pts = cy_adj_pts;
        c_pts = c_adj_pts;
end

% FILTER CELERITY POINTS
c_speed_min = 1;
c_speed_max = 7; % m/s, exclude unrealistic/erroneous celerity values
speed_mask = c_pts > c_speed_min & c_pts < c_speed_max;x_pts  = x_pts(speed_mask);
y_pts  = y_pts(speed_mask);
cx_pts = cx_pts(speed_mask);
cy_pts = cy_pts(speed_mask);
c_pts  = c_pts(speed_mask);
frame_ID = S.all_celerity_time_total(speed_mask);

%% LOAD CREST WIDTHS (matched to each individual celerity point)
crest_width_pts_all  = S.all_crest_width_pts_total;    % [x, y, width]
crest_width_time_all = S.all_crest_width_time_total;   % datetime, one per row

max_match_dist = 2; % m, max distance allowed between a celerity point and its matched width point

crest_width_pts = nan(size(x_pts));
for i = 1:numel(x_pts)
    same_frame = crest_width_time_all == frame_ID(i);
    if ~any(same_frame); continue; end
    cand_x = crest_width_pts_all(same_frame,1);
    cand_y = crest_width_pts_all(same_frame,2);
    cand_w = crest_width_pts_all(same_frame,3);
    d = hypot(cand_x - x_pts(i), cand_y - y_pts(i));
    [dmin, idx] = min(d);
    if dmin <= max_match_dist && cand_w(idx) > 0
        crest_width_pts(i) = cand_w(idx);
    end
end

% keep only points with a valid matched crest width
has_width = ~isnan(crest_width_pts);
x_pts    = x_pts(has_width);
y_pts    = y_pts(has_width);
cx_pts   = cx_pts(has_width);
cy_pts   = cy_pts(has_width);
c_pts    = c_pts(has_width);
frame_ID = frame_ID(has_width);
crest_width_pts = crest_width_pts(has_width);

fprintf('Celerity points with matched crest width: %d / %d\n', sum(has_width), numel(has_width))

%% period and tide
fname = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/' ...
    'RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/data/buoy_data/duck_offshore_cond.txt'];
opts = detectImportOptions(fname,'NumHeaderLines',2);
T = readtable(fname,opts);
T.Properties.VariableNames = {'YY','MM','DD','hh','mm','WDIR','WSPD','GST','WVHT','DPD','APD','MWD','PRES','ATMP','WTMP','DEWP','VIS','TIDE'};
time = datetime(T.YY,T.MM,T.DD,T.hh,T.mm,0);
yr = str2double(year_str);
mo = str2double(dateTag(1:2));
dy = str2double(dateTag(3:4));
target_day = datetime(yr,mo,dy);
target_hour = str2double(hourStr(1:2));
mask = dateshift(time,'start','day') == target_day & hour(time) == target_hour;
T_mean = mean(T.APD(mask),'omitnan'); % avg period for Fbr calc

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

%% BREAKING FORCE CALCULATION
g = 9.81;
h_pts = (c_pts.^2 ./ g) - tide;

theta_r = deg2rad(15); % roller angle

area_times_sin = 0.11*crest_width_pts.^2*tan(theta_r)*sec(theta_r); % A * sin(theta)

Fbr_mag_pts = nan(size(c_pts));
Fbr_dir_pts = atan2(cy_pts,cx_pts);

% enforce onshore (-x) sign convention once, before anything downstream uses it
flip = cx_pts > 0;
cx_pts(flip) = -cx_pts(flip);
Fbr_dir_pts = atan2(cy_pts, cx_pts);

valid = ~isnan(c_pts) & ~isnan(h_pts) & c_pts > 0 & h_pts > 0 & ~isnan(T_mean);

Fbr_mag_pts(valid) = 0.9*(g./(c_pts(valid).*h_pts(valid).*T_mean)).* area_times_sin(valid);
fprintf('Valid force points: %d\n',sum(valid))

%% BIN BREAKING FORCE
bin_size = 5;
x_edges = min(x_pts):bin_size:max(x_pts)+bin_size;
y_edges = min(y_pts):bin_size:max(y_pts)+bin_size;

x_centers = x_edges(1:end-1)+bin_size/2;
y_centers = y_edges(1:end-1)+bin_size/2;

xi = discretize(x_pts,x_edges);
yi = discretize(y_pts,y_edges);

Fbr_mag_grid = nan(length(y_centers),length(x_centers));
Fbr_dir_grid = nan(length(y_centers),length(x_centers));

for r = 1:length(y_centers)
    for c = 1:length(x_centers)

        mask_bin = xi == c & yi == r & ~isnan(Fbr_mag_pts);

        if sum(mask_bin) >= 10

            Fbr_mag_grid(r,c) = mean(Fbr_mag_pts(mask_bin),'omitnan');

            ang = Fbr_dir_pts(mask_bin);
            Fbr_dir_grid(r,c) = angle(mean(exp(1i*ang),'omitnan'));

        end
    end
end

%% BREAKING FORCE MAGNITUDE MAP

figure
h = imagesc(x_centers,y_centers,Fbr_mag_grid);
set(h,'AlphaData',~isnan(Fbr_mag_grid))
set(gca,'YDir','normal')
axis tight
box on
grid minor
cb = colorbar;
caxis([0 2]);
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title(sprintf('Breaking Force Magnitude %s',dateTimeLabel))
xlim([80 180]); ylim([602 840])


%% BREAKING FORCE DIRECTION MAP

dir_from_onshore_deg = mod(rad2deg(Fbr_dir_grid), 360) - 180; % dir from onshore
figure
h = imagesc(x_centers,y_centers,dir_from_onshore_deg);
set(h,'AlphaData',~isnan(Fbr_dir_grid))
set(gca,'YDir','normal')
axis tight
box on
grid minor
colormap(gca, cmocean('balance'));
caxis([-25 25]);   % tightened — check actual min/max of dir_from_onshore_deg first
cb = colorbar; cb.Label.String = 'F_{br} direction [deg]';
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title(sprintf('F_{br} Direction %s %s',dateTimeLabel))
xlim([80 180]); ylim([602 840])



%% SINGLE FRAME CREST POINT VECTOR FIELD OVER IMAGE

frame_to_plot = 100; % frame of last 5 mins to inspect

% rectified_frames{k} was built from frameTimes(k+1) of the LAST video file processed that hour, so reconstruct 
% that same timestamp vector here to guarantee the background img and the cel/Fbr points line up.
frame_times_abs = S.fileStartStamp + seconds(S.frameTimes(2:S.numberVideoFrames+1));

% keep only celerity points that came from the last video file (the one rectified_frames actually holds) 
% so frame_to_plot indexes consistently
last_file_mask = frame_ID >= min(frame_times_abs) & frame_ID <= max(frame_times_abs);
unique_frames = unique(frame_ID(last_file_mask));
frame_time = unique_frames(frame_to_plot);
frame_mask = frame_ID == frame_time & ~isnan(Fbr_mag_pts);

% find the rectified_frames index whose timestamp matches frame_time
rf_idx = find(frame_times_abs == frame_time, 1);
if isempty(rf_idx)
    error('No rectified frame found matching frame_time %s', string(frame_time))
end

fprintf('Plotting frame %d: %s\n',frame_to_plot,string(frame_time))
fprintf('Crest points plotted: %d\n',sum(frame_mask))

Fbr_mag_cap = prctile(Fbr_mag_pts(frame_mask), 90); % clip outliers for display only
Fbr_mag_plot = min(Fbr_mag_pts, Fbr_mag_cap);

Fx_pts = Fbr_mag_plot .* cos(Fbr_dir_pts);
Fy_pts = Fbr_mag_plot .* sin(Fbr_dir_pts);

figure
hold on
bg = S.rectified_frames{rf_idx}; % background img
h = imagesc(S.X,S.Y,bg);
set(h,'AlphaData',0.5)
colormap bone
axis equal tight
scatter(x_pts(frame_mask),y_pts(frame_mask),8,'filled') % crest pts
quiver(x_pts(frame_mask), y_pts(frame_mask), Fx_pts(frame_mask), Fy_pts(frame_mask), 1) % Fbr vects
xlim([90 200])
ylim([602 1000])
grid on; box on
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title(sprintf('F_{br} Vectors Frame %d (%s)', frame_to_plot,string(frame_time)))



%% VORTICITY GENERATION FROM Fbr CURL (Eqn. 11), point-by-point along each crest
% dw/dt = -dFbr_xc/dy_c, evaluated between each pair of adjacent crest points
% (adjacent = consecutive in y within the same frame, no large alongshore gap).
% A zero-celerity pad point brackets each crest end, one grid cell further
% alongshore, so the curl at the crest tips uses that pad point as its partner.

Fbr_xc_pts = Fbr_mag_pts;   % Fbr,xc is the stored magnitude itself (crest-local xc frame)

max_gap_y = bin_size;   % max alongshore gap between points still treated as the same crest
max_gap_x = bin_size; 
min_dy = 0.5;

dwdt_x = []; dwdt_y = []; dwdt_val = [];

unique_frames_all = unique(frame_ID);
for fnum = 1:numel(unique_frames_all)
    fID = unique_frames_all(fnum);
    m = frame_ID == fID & ~isnan(Fbr_xc_pts);
    if ~any(m); continue; end

    xf = x_pts(m); yf = y_pts(m); Ff = Fbr_xc_pts(m);
    [yf, ord] = sort(yf);
    xf = xf(ord); Ff = Ff(ord);

    % split into separate crest runs wherever the alongshore gap is too large
    gaps = diff(yf);
    run_break = [true; gaps > max_gap_y];
    run_id = cumsum(run_break);

    for r = 1:max(run_id)
        rm = run_id == r;

        xc  = xf(rm);
        yc  = yf(rm);
        Fxc = Ff(rm);

        % zero-celerity pad points, one grid cell beyond each crest end
        yc_pad  = [yc(1)-bin_size;  yc;  yc(end)+bin_size];
        xc_pad  = [xc(1);           xc;  xc(end)];
        Fxc_pad = [0;                Fxc; 0];

        dy   = diff(yc_pad);
        dF   = diff(Fxc_pad);
        dwdt = -dF ./ dy;                              % Eqn. 11
        dwdt(dy < min_dy) = NaN;  
        y_mid = yc_pad(1:end-1) + dy/2;
        x_mid = (xc_pad(1:end-1) + xc_pad(2:end)) / 2;

        dwdt_x   = [dwdt_x;   x_mid];
        dwdt_y   = [dwdt_y;   y_mid];
        dwdt_val = [dwdt_val; dwdt];
    end
end

fprintf('Vorticity-generation values computed: %d\n', numel(dwdt_val))

% BIN + PLOT VORTICITY GENERATION
xi_w = discretize(dwdt_x, x_edges);
yi_w = discretize(dwdt_y, y_edges);
dwdt_grid = nan(length(y_centers), length(x_centers));
for r = 1:length(y_centers)
    for c = 1:length(x_centers)
        mask_bin = xi_w == c & yi_w == r & ~isnan(dwdt_val);
        if sum(mask_bin) >= 1
            dwdt_grid(r,c) = mean(dwdt_val(mask_bin), 'omitnan');
        end
    end
end

figure
h = imagesc(x_centers, y_centers, dwdt_grid);
set(h,'AlphaData',~isnan(dwdt_grid))
set(gca,'YDir','normal')
axis tight; box on; grid minor
colormap(gca, cmocean('balance'));
cb = colorbar; cb.Label.String = '\partial\omega/\partial t [s^{-2}]';
clim([-0.5 .5])
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title(sprintf('Vorticity Generation %s', dateTimeLabel))
xlim([80 180]); ylim([602 840])
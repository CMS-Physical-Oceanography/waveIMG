% Fbr, vort calculations

%% USER INPUT
year_str   = '2013';
runDate    = '20131002';        % yyyymmdd of the video run
hourStr    = '1200';            % hhmm
camera     = 'rod13';      % 2021: 'NorthTower21' | 'SouthTower21'
                                % 2013: 'rod13'  (prefix of the saved .mat)

ens_surveyDate = '20131002';   % yyyymmdd of the bathy survey; for ensemble section


data_source = 'raw';            % 'raw' or 'piv'

bin_size = 5;          % m
piv_bin  = minutes(2);
g        = 9.81;

h_min = 0.25;           % m, exclude points with depth below this from Fbr (h = c^2/g; Fbr ~ 1/h blows up)
c_speed_min = 1;       % m/s, exclude unrealistic/erroneous celerity values
c_speed_max = 7;

% PIV orientation: flips raw PIV u to match FRF x (onshore = positive)
switch year_str
    case '2013'; piv_u_sign = -1;
    case '2021'; piv_u_sign = -1;
    otherwise;   error('Set piv_u_sign for year %s', year_str);
end

yr = str2double(runDate(1:4));  mo = str2double(runDate(5:6));
dy = str2double(runDate(7:8));  hr = str2double(hourStr(1:2));
dateLabel     = sprintf('%02d/%02d/%d', mo, dy, yr);
dateTimeLabel = sprintf('%s, %s', dateLabel, hourStr);
windowStart   = datetime(yr, mo, dy, hr, 0, 0);
windowEnd     = windowStart + hours(1);

%% paths
dataRoot  = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/rips_onedrive/NSF_Eddies';
matDir    = fullfile(dataRoot, 'mat_data');
tideFile  = fullfile(dataRoot, 'data', 'tide_duck', sprintf('duck_waterLvls%s.csv', year_str));

% buoy file (wave period for Fbr) -- 2013 location is the old one; change if it moved
switch year_str
    case '2013'
        buoyFile = fullfile(dataRoot, 'data', 'buoy_data', '2013_buoyHsDuck.txt');
    case '2021'
        buoyFile = fullfile(dataRoot, 'data', 'buoy_data', '2021_buoyHsDuck.txt');
    otherwise
        error('Add a buoy (wave period) file path for year %s', year_str);
end

% PIV file (only needed when data_source = 'piv')
if strcmp(data_source, 'piv')
    switch year_str
        case '2013'   % old location -- change if it moved
            pivFile = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main/data/PIV_2min/PVLAB_PIV_SurfaceFlows.mat';
        case '2021'
            pivFile = fullfile('/Volumes/RODSEX Video', 'PIV Means', sprintf('DUNEX%s_PIV_%s_%s.mat', year_str, runDate, hourStr));
        otherwise
            error('Add a PIV file path for year %s', year_str);
    end
    if ~exist(pivFile, 'file'); error('PIV file not found (drive plugged in?): %s', pivFile); end
end

% video output: match on camera + date_hour only, ignore anything after (_0000, _enh, _test, ...)
runKey = [runDate '_' hourStr];
% MAIN_FLOW_RECENT saves to mat_data/local_runs as <tower>_<dateTag>_<hourStr><runTag>.mat (e.g. SouthTower_20210904_1600_0000_enh.mat), so look there too.
L = dir(fullfile(matDir, [camera '_' runKey '*.mat']));
if isempty(L)
    L = dir(fullfile(matDir, 'local_runs', [camera '_' runKey '*.mat']));
end
if isempty(L); error('No mat file matching %s_%s*.mat in %s (or its local_runs subfolder)', camera, runKey, matDir); end
if numel(L) > 1
    [~, iNew] = max([L.datenum]);
    warning('%d files match; using the newest: %s', numel(L), L(iNew).name);
    L = L(iNew);
end
videoOutputFile = fullfile(L.folder, L.name);

%% auto tide lookup
Ttide = readtable(tideFile, 'TextType', 'string');
tideDate = datetime(Ttide.Date, 'InputFormat', 'yyyy/MM/dd');
tideTimeOfDay = duration(Ttide.Time_LST_LDT_, 'InputFormat', 'hh:mm');
tideTime = tideDate + tideTimeOfDay;
waterLevel = Ttide.Verified_m_;
inWindow = tideTime >= windowStart & tideTime < windowEnd;
if ~any(inWindow); error('No tide data found for %s %s.', runDate, hourStr); end
tide = mean(waterLevel(inWindow), 'omitnan');   % tide-based water lvl for depth adjustment

%% load mat file
t_load = tic;
fprintf('Loading %s\n', L.name);
S = load(videoOutputFile);
fprintf('LOAD MAT FILE: %.1f s\n', toc(t_load));

%% load celerity data
all_celerity_hour = S.all_celerity_total;
t_video = S.all_celerity_time_total;
x_pts = all_celerity_hour(:,1);
y_pts = all_celerity_hour(:,2);

switch data_source
    case 'raw'
        cx_pts = all_celerity_hour(:,3);
        cy_pts = all_celerity_hour(:,4);
        c_pts  = all_celerity_hour(:,5);

    case 'piv'
        P = load(pivFile);
        [cx_pts, cy_pts, c_pts] = apply_piv_correction(P, piv_u_sign, all_celerity_hour, ...
            t_video, windowStart, piv_bin);

    otherwise
        error('data_source must be ''raw'' or ''piv''.');
end

% filter celerity points
speed_mask = c_pts > c_speed_min & c_pts < c_speed_max;
x_pts  = x_pts(speed_mask);
y_pts  = y_pts(speed_mask);
cx_pts = cx_pts(speed_mask);
cy_pts = cy_pts(speed_mask);
c_pts  = c_pts(speed_mask);
frame_ID = t_video(speed_mask);

%% load crest widths + match to each individual celerity point
crest_width_pts_all  = S.all_crest_width_pts_total;    % [x, y, width]
crest_width_time_all = S.all_crest_width_time_total;   % datetime, one per row

max_match_dist = 2; % m, max distance allowed between a celerity point and its matched width point

t_match = tic;
crest_width_pts = nan(size(x_pts));

% group both point sets by frame (numeric keys + accumarray)
p_key = posixtime(frame_ID);
w_key = posixtime(crest_width_time_all);

[uw, ~, g_w] = unique(w_key);
w_by_frame = accumarray(g_w, (1:numel(w_key))', [numel(uw) 1], @(v){v}, {[]});
key2col    = containers.Map(uw, 1:numel(uw));

[up, ~, g_p] = unique(p_key);
p_by_frame = accumarray(g_p, (1:numel(p_key))', [numel(up) 1], @(v){v}, {[]});

for fnum = 1:numel(up)
    pt_idx = p_by_frame{fnum};
    if isempty(pt_idx); continue; end

    fkey = up(fnum);
    if ~isKey(key2col, fkey); continue; end
    w_idx = w_by_frame{key2col(fkey)};
    if isempty(w_idx); continue; end

    cand_xy  = crest_width_pts_all(w_idx, 1:2);
    cand_w   = crest_width_pts_all(w_idx, 3);
    query_xy = [x_pts(pt_idx), y_pts(pt_idx)];

    [nn_idx, dmin] = knnsearch(cand_xy, query_xy);   % KD-tree nearest neighbor -- one call per frame

    matched = dmin <= max_match_dist & cand_w(nn_idx) > 0;
    crest_width_pts(pt_idx(matched)) = cand_w(nn_idx(matched));
end
fprintf('crest-width matching loop: %.1f s\n', toc(t_match));

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

%% mean wave period for the hour (buoy)
opts = detectImportOptions(buoyFile,'NumHeaderLines',2);
T = readtable(buoyFile,opts);
if width(T) ~= 18
    error('Buoy file %s has %d columns, expected 18 (NDBC standard-met format). Check the header/columns.', buoyFile, width(T));
end
T.Properties.VariableNames = {'YY','MM','DD','hh','mm','WDIR','WSPD','GST','WVHT','DPD','APD','MWD','PRES','ATMP','WTMP','DEWP','VIS','TIDE'};
time = datetime(T.YY,T.MM,T.DD,T.hh,T.mm,0);
target_day = datetime(yr,mo,dy);
mask = dateshift(time,'start','day') == target_day & hour(time) == hr;
APD = T.APD;
APD(APD >= 99) = NaN;                 % NDBC missing-value flag (99.00)
T_mean = mean(APD(mask),'omitnan');   % avg period for Fbr calc
if isnan(T_mean)
    error('No valid buoy APD for %s %s in %s. Check the date range / time zone of the buoy file.', runDate, hourStr, buoyFile);
end
fprintf('Mean wave period (APD): %.2f s\n', T_mean)

%% Fbr calculation (Duncan 1981)
h_pts = (c_pts.^2 ./ g); % remotely estimated depth (from inversion)

theta_r = deg2rad(15); % roller angle, constant of 15

area_times_sin = 0.11*crest_width_pts.^2*tan(theta_r)*sec(theta_r); % A * sin(theta)

Fbr_mag_pts = nan(size(c_pts));

% enforce onshore (-x) sign convention once, before anything downstream uses it
flip = cx_pts > 0;
cx_pts(flip) = -cx_pts(flip);
Fbr_dir_pts = atan2(cy_pts, cx_pts);

valid = ~isnan(c_pts) & ~isnan(h_pts) & c_pts > 0 & h_pts > h_min & ~isnan(T_mean);
fprintf('Points removed by h_min = %.2f m: %d (%.1f %% of points with valid c)\n', h_min, ...
    sum(~isnan(h_pts) & h_pts > 0 & h_pts <= h_min), 100*sum(~isnan(h_pts) & h_pts > 0 & h_pts <= h_min)/sum(~isnan(h_pts) & h_pts > 0))

Fbr_mag_pts(valid) = 0.9*(g./(c_pts(valid).*h_pts(valid).*T_mean)).* area_times_sin(valid);
fprintf('Valid force points: %d\n',sum(valid))

%% bin Fbr (5x5m)
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

% %% Fbr magnitude map plot
% 
% figure
% h = imagesc(x_centers,y_centers,Fbr_mag_grid);
% set(h,'AlphaData',~isnan(Fbr_mag_grid))
% set(gca,'YDir','normal')
% axis tight
% box on
% grid minor
% cb = colorbar; cb.Label.String = 'F_{br,xc} [ms^{-2}]';
% cmocean('-thermal');
% caxis([0 0.5]);
% xlabel('Cross-shore [m]')
% ylabel('Alongshore [m]')
% title(sprintf('F_{br,xc} Magnitude - %s',dateTimeLabel), 'FontSize', 15)
% xlim([90 170]); ylim([610 835])
% 
% % Fbr direction map plot
% 
% dir_from_onshore_deg = mod(rad2deg(Fbr_dir_grid), 360) - 180; % dir from onshore
% figure
% h = imagesc(x_centers,y_centers,dir_from_onshore_deg);
% set(h,'AlphaData',~isnan(Fbr_dir_grid))
% set(gca,'YDir','normal')
% axis tight
% box on
% grid minor
% colormap(gca, cmocean('curl'));
% caxis([-20 20]);   % tightened — check actual min/max of dir_from_onshore_deg first
% cb = colorbar; cb.Label.String = 'F_{br} direction [deg]';
% xlabel('Cross-shore [m]')
% ylabel('Alongshore [m]')
% title(sprintf('F_{br} Direction - %s',dateTimeLabel), 'FontSize', 15)
% xlim([90 170]); ylim([610 835])

%% Fbr vectors over single frame ...old but need b/c it determines unique frame for diagnostic plots

frame_to_plot = 35; % frame of last 5 mins to inspect/diagnose, og is 25 for 2013 good crest

% rectified_frames{k} was built from frameTimes(k+1) of the LAST video file processed that hour, so reconstruct 
% that same timestamp vector here to guarantee the background img and the cel/Fbr points line up.
frame_times_abs = S.fileStartStamp + seconds(S.frameTimes(2:S.numberVideoFrames+1));

% keep only celerity points that came from the last video file (the one rectified_frames actually holds) so frame_to_plot indexes consistently
last_file_mask = frame_ID >= min(frame_times_abs) & frame_ID <= max(frame_times_abs);
unique_frames = unique(frame_ID(last_file_mask));
if isempty(unique_frames); error('No celerity points fall in the last video file (test run too short?).'); end
frame_to_plot = min(frame_to_plot, numel(unique_frames));   % guard for short/test runs
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

% figure
% hold on
% bg = S.rectified_frames{rf_idx}; % background img
% h = imagesc(S.X,S.Y,bg);
% set(h,'AlphaData',0.5)
% colormap bone
% % axis equal tight
% scatter(x_pts(frame_mask),y_pts(frame_mask),8,'filled') % crest pts
% quiver(x_pts(frame_mask), y_pts(frame_mask), Fx_pts(frame_mask), Fy_pts(frame_mask), 0.5, 'LineWidth', 0.8, 'MaxHeadSize',0.03) % Fbr vects
% xlim([90 200])
% ylim([602 1000])
% grid on; box on
% xlabel('Cross-shore [m]')
% ylabel('Alongshore [m]')
% title('F_{br} Vectors', FontSize=15)
% view([-90 90])


%% ALONG-CREST Fbr CURL, CREST IDENTITY FROM THE CREST-WIDTH POINT CLOUD - plot binned curl(Fbr) map

% crest membership + along-crest order are rebuilt here
% Each matched Fbr point is then snapped onto its nearest traced crest-width point and
% inherits that crest's ID and along-crest arclength position.
%
% Within a crest, curl between along-crest-adjacent points i, i+1 is:
%   curl_i = (Fbr_i+1 - Fbr_i) / y
% with y the straight-line distance between the two points -- along-crest coordinates 
% Each crest is padded with an Fbr = 0 point one step beyond its first and last real point
% (extrapolated along the local crest direction), so curl is also defined b/w a crest's tip and its pad.

max_crest_link_dist = 2*bin_size;   % beyond this gap, stop tracing -- crest has ended
crest_pad_dist       = 2;           % distance of the Fbr=0 pad point beyond each crest end
min_curl_dist        = 0.5;         % floor on point spacing before curl is computed (avoid /~0)

t_trace = tic;
curl_x = []; curl_y = []; curl_val = [];

% group frame_ID by frame -- w_by_frame/key2col/uw (the grouping of crest_width_time_all) are reused unchanged from the matching section above
p_key_c = posixtime(frame_ID);
[up_c, ~, g_p_c] = unique(p_key_c);
p_by_frame_c = accumarray(g_p_c, (1:numel(p_key_c))', [numel(up_c) 1], @(v){v}, {[]});

for fnum = 1:numel(up_c)
    pt_idx_all = p_by_frame_c{fnum};
    if isempty(pt_idx_all); continue; end

    fkey = up_c(fnum);
    if ~isKey(key2col, fkey); continue; end
    w_idx = w_by_frame{key2col(fkey)};
    if numel(w_idx) < 2; continue; end

    wx = crest_width_pts_all(w_idx,1);
    wy = crest_width_pts_all(w_idx,2);

    % matched Fbr points for this frame (already have c, h, crest width, Fbr)
    fr_keep = ~isnan(Fbr_mag_pts(pt_idx_all));
    if ~any(fr_keep); continue; end
    pt_idx = pt_idx_all(fr_keep);
    fx = x_pts(pt_idx); fy = y_pts(pt_idx); fF = Fbr_mag_pts(pt_idx);

    % trace the width cloud into ordered crest paths: crest ID + arclength per width point
    [crestID_w, s_w] = trace_crest_paths(wx, wy, max_crest_link_dist);

    % snap each Fbr point onto its nearest traced width point, inheriting crest ID + position
    [nn_idx, dmin] = knnsearch([wx wy], [fx fy]);
    keep = dmin <= max_match_dist;
    if ~any(keep); continue; end
    fx = fx(keep); fy = fy(keep); fF = fF(keep);
    crestID_f = crestID_w(nn_idx(keep));
    s_f       = s_w(nn_idx(keep));

    % walk each crest in along-crest order; curl between adjacent Fbr points, padded with an Fbr = 0 point one crest_pad_dist beyond each end
    crest_ids = unique(crestID_f);
    for ci = 1:numel(crest_ids)
        cm = crestID_f == crest_ids(ci);

        [~, ord] = sort(s_f(cm));
        idx_c    = find(cm);
        idx_c    = idx_c(ord);

        crest_x = fx(idx_c); crest_y = fy(idx_c); crest_F = fF(idx_c);

        if numel(crest_x) >= 2
            dir_start = [crest_x(1)-crest_x(2),       crest_y(1)-crest_y(2)];
            dir_end   = [crest_x(end)-crest_x(end-1), crest_y(end)-crest_y(end-1)];
        else
            dir_start = [0 -1]; dir_end = [0 1]; % too few real points to fit a direction -- assume alongshore
        end
        dir_start = dir_start / max(norm(dir_start), eps);
        dir_end   = dir_end   / max(norm(dir_end),   eps);

        x_pad = [crest_x(1)+crest_pad_dist*dir_start(1); crest_x; crest_x(end)+crest_pad_dist*dir_end(1)];
        y_pad = [crest_y(1)+crest_pad_dist*dir_start(2); crest_y; crest_y(end)+crest_pad_dist*dir_end(2)];
        F_pad = [0; crest_F; 0];

        ds        = hypot(diff(x_pad), diff(y_pad));  % y: distance between adjacent crest points
        dF        = diff(F_pad);                        % Fbr,i+1 - Fbr,i
        curl_step = dF ./ ds;
        curl_step(ds < min_curl_dist) = NaN;

        curl_x   = [curl_x;   (x_pad(1:end-1)+x_pad(2:end))/2];
        curl_y   = [curl_y;   (y_pad(1:end-1)+y_pad(2:end))/2];
        curl_val = [curl_val; curl_step];
    end
end
fprintf('along-crest tracing/curl loop: %.1f s\n', toc(t_trace));
fprintf('Along-crest Fbr curl values computed: %d\n', numel(curl_val))


% bin + plot alongcrest curl(Fbr)
t_bin = tic;
xi_c = discretize(curl_x, x_edges);
yi_c = discretize(curl_y, y_edges);
Fbr_curl_grid = nan(length(y_centers), length(x_centers));
for r = 1:length(y_centers)
    for cc = 1:length(x_centers)
        mask_bin = xi_c == cc & yi_c == r & ~isnan(curl_val);
        if sum(mask_bin) >= 25
            Fbr_curl_grid(r,cc) = mean(curl_val(mask_bin), 'omitnan');
        end
    end
end
fprintf('curl binning loop: %.1f s\n', toc(t_bin));

% n_trim_rows = 1;   % how many alongshore bin rows to blank at each edge         used to remove boundary bins (extremes)...
% Fbr_curl_grid(1:n_trim_rows, :) = NaN;
% Fbr_curl_grid(end-n_trim_rows+1:end, :) = NaN;

figure
h = imagesc(x_centers, y_centers, Fbr_curl_grid);
set(h,'AlphaData',~isnan(Fbr_curl_grid))
set(gca,'YDir','normal')
axis tight; box on; grid minor
colormap(gca, cmocean('balance'));
cb = colorbar; cb.Label.String = '\nabla \times F_{br} [s^{-2}]';
cb.Label.Interpreter = 'tex';
clim([-.05 .05])
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title(sprintf('\\nabla \\times F_{br} - %s', dateTimeLabel), ...
    'Interpreter', 'tex','FontSize', 15)
% xlim([85 170]); ylim([623 827]) % og for 2013
xlim([70 200]); ylim([650 1100]) 


%% Fbr vectors and alongcrest curl(Fbr) visualization/diagnostic for single frame

% --- pick which frame to inspect here, independent of frame_to_plot above ---
frame_to_plot_diag = min(25, numel(unique_frames));   % index into unique_frames (last video file only)
frame_time = unique_frames(frame_to_plot_diag);
frame_mask = frame_ID == frame_time & ~isnan(Fbr_mag_pts);
rf_idx     = find(frame_times_abs == frame_time, 1);
bg         = S.rectified_frames{rf_idx};

w_mask_1 = crest_width_time_all == frame_time;
wx1 = crest_width_pts_all(w_mask_1,1);
wy1 = crest_width_pts_all(w_mask_1,2);

[crestID_w1, s_w1] = trace_crest_paths(wx1, wy1, max_crest_link_dist);

fx1 = x_pts(frame_mask); fy1 = y_pts(frame_mask); fF1 = Fbr_mag_pts(frame_mask);
[nn_idx1, dmin1] = knnsearch([wx1 wy1], [fx1 fy1]);
keep1 = dmin1 <= max_match_dist;
fx1 = fx1(keep1); fy1 = fy1(keep1); fF1 = fF1(keep1);
crestID_f1 = crestID_w1(nn_idx1(keep1));
s_f1       = s_w1(nn_idx1(keep1));

% true-color the background so it doesn't fight with the curl colormap below
bg_rgb = ind2rgb(gray2ind(mat2gray(bg), 256), bone(256));

figure
xlimits = [130 155]; %[90 200]; 
ylimits = [715 805]; %[602 1000];
hold on
axis equal
h = imagesc(S.X, S.Y, bg_rgb);
set(h,'AlphaData',0.5)

curl_scale = max(abs(curl_val), [], 'omitnan');   % fixed scale so size/color are 

crest_ids1 = unique(crestID_f1);
for ci = 1:numel(crest_ids1)
    cm1   = crestID_f1 == crest_ids1(ci);
    [~, ord1] = sort(s_f1(cm1));
    idxc1 = find(cm1); idxc1 = idxc1(ord1);

    cx1 = fx1(idxc1); cy1 = fy1(idxc1); cF1 = fF1(idxc1);

    if numel(cx1) >= 2
        dir_start1 = [cx1(1)-cx1(2),       cy1(1)-cy1(2)];
        dir_end1   = [cx1(end)-cx1(end-1), cy1(end)-cy1(end-1)];
    else
        dir_start1 = [0 -1]; dir_end1 = [0 1];
    end
    dir_start1 = dir_start1 / max(norm(dir_start1), eps);
    dir_end1   = dir_end1   / max(norm(dir_end1),   eps);

    xpad1 = [cx1(1)+crest_pad_dist*dir_start1(1); cx1; cx1(end)+crest_pad_dist*dir_end1(1)];
    ypad1 = [cy1(1)+crest_pad_dist*dir_start1(2); cy1; cy1(end)+crest_pad_dist*dir_end1(2)];
    Fpad1 = [0; cF1; 0];

    ds1   = hypot(diff(xpad1), diff(ypad1));
    dF1   = diff(Fpad1);
    curl1 = dF1 ./ ds1;
    curl1(ds1 < min_curl_dist) = NaN;

    xmid1 = (xpad1(1:end-1)+xpad1(2:end))/2;
    ymid1 = (ypad1(1:end-1)+ypad1(2:end))/2;

    plot(xpad1, ypad1, '-', 'Color',[0.6 0.6 0.6], 'LineWidth',1)                % traced crest path incl. pads

    scatter(xpad1([1 end]), ypad1([1 end]), 40+300*abs(curl1([1 end]))/curl_scale, curl1([1 end]), ...
    'o', 'filled', 'MarkerEdgeColor','k', 'LineWidth', 1)

    scatter(xmid1, ymid1, 15+300*abs(curl1)/curl_scale, curl1, 'filled', 'MarkerEdgeColor','k')
end

q_fbr = quiver(x_pts(frame_mask), y_pts(frame_mask), Fx_pts(frame_mask), Fy_pts(frame_mask), 0.5, ...
    'Color',[0 .3 0], 'LineWidth',0.8, 'MaxHeadSize', .02);
legend(q_fbr, 'F_{br} vectors', 'Location','northeast')

colormap(gca, cmocean('balance'));
clim([-.2 .2])
cb = colorbar; cb.Label.String = '\nabla \times F_{br}  [s^{-2}]';
xlim(xlimits); ylim(ylimits)
grid on; box on
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title('F_{br} Vectors and Along-Crest Curl(F_{br})', FontSize=15);
view([-90 90]);




%% survey water depth (used by the variability diagnostic AND the ensemble section below)

h_source   = 'survey'; % 'survey' (h = tide - z_NAVD88) or 'remote' (h = c^2/g, water depth from the celerity inversion)
ens_survey_pad_xy  = 25;   % [m] only survey points within this distance of the celerity points are used
ens_survey_max_gap = 15;   % [m] discard interpolated depth farther than this from any survey point (no extrapolating across gaps)

if strcmp(h_source, 'survey')
    % survey file location / naming / columns: same as the bathy-inversion script
    svyDate = ens_surveyDate;  if isempty(svyDate); svyDate = runDate; end
    surveyDir = fullfile(dataRoot, 'data', 'bathy_surveys');
    switch year_str
        case '2013'; svyPattern = sprintf('RODDebbieTimeLagFix_%s.xyz', svyDate);
        case {'2018','2021'}; svyPattern = sprintf('FRF_%s_*.csv', svyDate);
        otherwise;   error('Add a survey filename pattern for year %s', year_str);
    end
    SVY = dir(fullfile(surveyDir, svyPattern));
    if isempty(SVY); error('No survey file matching %s in %s', svyPattern, surveyDir); end
    if numel(SVY) > 1; warning('%d survey files match; using %s', numel(SVY), SVY(1).name); end
    [~, svyName] = fileparts(SVY(1).name);
    svyData = readmatrix(fullfile(SVY(1).folder, SVY(1).name), 'FileType', 'text', 'NumHeaderLines', 0);
    if startsWith(svyName, 'RODDebbie')        % 2013: x y z columns
        sv_x = svyData(:,1);  sv_y = svyData(:,2);  sv_z = svyData(:,3);
    elseif startsWith(svyName, 'FRF_')         % FRF/LARC csv: FRF X, FRF Y, NAVD88 elevation
        sv_x = svyData(:,8);  sv_y = svyData(:,9);  sv_z = svyData(:,10);
    else
        error('Unknown survey format: %s. Add a case here.', svyName);
    end
    sv_ok = isfinite(sv_x) & isfinite(sv_y) & isfinite(sv_z) & ...
        sv_x >= min(x_pts)-ens_survey_pad_xy & sv_x <= max(x_pts)+ens_survey_pad_xy & ...
        sv_y >= min(y_pts)-ens_survey_pad_xy & sv_y <= max(y_pts)+ens_survey_pad_xy;
    sv_x = sv_x(sv_ok); sv_y = sv_y(sv_ok); sv_z = sv_z(sv_ok);
    if numel(sv_x) < 10; error('Fewer than 10 survey points near the celerity points (%s).', svyName); end

    zb_interp = scatteredInterpolant(sv_x, sv_y, sv_z, 'linear', 'none');
    zb_pts    = zb_interp(x_pts, y_pts);                          % NAVD88 bed elevation at each celerity point
    [~, d_sv] = knnsearch([sv_x sv_y], [x_pts y_pts]);
    zb_pts(d_sv > ens_survey_max_gap) = NaN;                      % do not trust interpolation across survey gaps
    h_survey_pts = tide - zb_pts;                                 % WATER depth (tide is NAVD88, as in the inversion script)

    h_remote_water = c_pts.^2 ./ g;                               % water depth from celerity
    fprintf('Survey %s: %d survey pts used; %d / %d celerity pts without survey depth (NaN)\n', ...
        SVY(1).name, numel(sv_x), nnz(isnan(h_survey_pts)), numel(h_survey_pts));
    fprintf('Water depth medians: survey %.2f m | celerity c^2/g %.2f m | median(celerity - survey) = %.2f m\n', ...
        median(h_survey_pts,'omitnan'), median(h_remote_water,'omitnan'), median(h_remote_water - h_survey_pts,'omitnan'));
end


%% Fbr VARIABILITY DIAGNOSTIC v1: var(ln()) method from ai

% Fbr = 0.9*g/(c*h*T) * 0.11*W^2*tan(th)*sec(th)
% T and theta_r are constant within the hour, so any variation in Fbr comes from
% crest width W (squared), phase speed c, and water depth h.  In log space:
%       ln Fbr = const + 2 ln W - ln c - ln h
%
% Each term's share of var(ln Fbr) = cov(term, ln Fbr) / var(ln Fbr); shares sum to 100 %.
%
% h = survey depth (h_source = 'survey') or c^2/g (h_source = 'remote')

min_pts_crest = 5;      % min points for a crest to count in the between/within split

% ---- 1) setup: Fbr recomputed with the chosen depth ------------------------
if strcmp(h_source,'survey'); h_d = h_survey_pts; else; h_d = h_pts; end
valid_d = ~isnan(c_pts) & ~isnan(h_d) & c_pts > 0 & h_d > h_min & ~isnan(T_mean);
F_d = nan(size(c_pts));
F_d(valid_d) = 0.9*(g./(c_pts(valid_d).*h_d(valid_d).*T_mean)) .* area_times_sin(valid_d);
dv = valid_d & ~isnan(F_d) & crest_width_pts > 0;

F = F_d(dv);   W = crest_width_pts(dv);   c = c_pts(dv);   h = h_d(dv);
K = log(0.9*g*0.11*tan(theta_r)*sec(theta_r)/T_mean);          % constant part of ln Fbr

lF    = log(F);
terms = [2*log(W), -log(c), -log(h)];                          % the three contributions to ln Fbr
names = {'crest width  (2 ln W)', 'phase speed (-ln c)', 'depth       (-ln h)'};

cs    = @(a,b) mean((a-mean(a)).*(b-mean(b)));                 % covariance
share = @(Tm,y) arrayfun(@(i) cs(Tm(:,i),y), 1:size(Tm,2)) / cs(y,y);
cv    = @(x) std(x)/mean(x);                                   % coefficient of variation

fprintf('\n===== Fbr VARIABILITY DIAGNOSTIC (%s, h = %s, N = %d points) =====\n', dateTimeLabel, h_source, numel(F))

% ---- 2) which input explains the spread? (all points) -----------------------
sh_all = share(terms, lF);
fprintf('\n-- Share of var(ln Fbr) --\n')
for i = 1:3; fprintf('  %-24s %5.1f %%\n', names{i}, 100*sh_all(i)); end
fprintf('  std(ln Fbr) = %.2f   (p90/p10 of Fbr = %.1fx)\n', std(lF), prctile(F,90)/prctile(F,10))
fprintf('  corr(ln c, ln h) = %.2f   (high = depth and speed vary together)\n', corr(log(c), log(h)))
fprintf('  Points with h < 0.3 m: %.1f %%   (Fbr ~ 1/h grows quickly here)\n', 100*mean(h < 0.3))

% ---- 3) let only one input vary, freeze the others at their median
F_Wonly = exp(K) * W.^2   ./ (median(c) * median(h));
F_conly = exp(K) * median(W)^2 ./ (c   * median(h));
F_honly = exp(K) * median(W)^2 ./ (median(c) * h);
fprintf('\n-- CV (std/mean) of Fbr if only one input varies --\n')
fprintf('  actual %.2f | only W %.2f | only c %.2f | only h %.2f\n', cv(F), cv(F_Wonly), cv(F_conly), cv(F_honly))

% ---- 4) between crests vs along a crest ------------------------------------
% rebuild crest IDs with the same trace/snap approach as the curl section
crest_gid = nan(size(x_pts));  gcount = 0;
for fnum = 1:numel(up_c)
    pt_idx = p_by_frame_c{fnum};
    pt_idx = pt_idx(dv(pt_idx));
    if isempty(pt_idx); continue; end
    fkey = up_c(fnum);
    if ~isKey(key2col, fkey); continue; end
    w_idx = w_by_frame{key2col(fkey)};
    if numel(w_idx) < 2; continue; end
    wx = crest_width_pts_all(w_idx,1);  wy = crest_width_pts_all(w_idx,2);
    [crestID_w, ~] = trace_crest_paths(wx, wy, max_crest_link_dist);
    [nn, dm] = knnsearch([wx wy], [x_pts(pt_idx) y_pts(pt_idx)]);
    ok = dm <= max_match_dist;
    crest_gid(pt_idx(ok)) = gcount + crestID_w(nn(ok));
    gcount = gcount + max(crestID_w);
end

gid = crest_gid(dv);
okg = ~isnan(gid);
[~,~,g1] = unique(gid(okg));
cnt = accumarray(g1, 1);
sel = false(size(gid));  sel(okg) = cnt(g1) >= min_pts_crest;
[~,~,gi] = unique(gid(sel));                                   % crest index for each selected point

Ts  = terms(sel,:);   lFs = lF(sel);
Tc  = zeros(max(gi), 3);
for i = 1:3; Tc(:,i) = accumarray(gi, Ts(:,i), [], @mean); end % crest-mean of each term
lFc = accumarray(gi, lFs, [], @mean);                          % crest-mean ln Fbr

lFw = lFs - lFc(gi);   Tw = Ts - Tc(gi,:);                     % along-crest anomalies
v_tot = cs(lFs,lFs);   v_w = cs(lFw,lFw);

fprintf('\n-- Between vs along a crest (%d crests with >= %d pts) --\n', max(gi), min_pts_crest)
fprintf('  var(ln Fbr): %.0f %% between crests, %.0f %% along a crest\n', 100*(v_tot-v_w)/v_tot, 100*v_w/v_tot)
sh_b = share(Tc(gi,:), lFc(gi));
sh_w = share(Tw, lFw);
fprintf('  Between-crest drivers : W %.0f %% | c %.0f %% | h %.0f %%\n', 100*sh_b)
fprintf('  Along-crest drivers   : W %.0f %% | c %.0f %% | h %.0f %%\n', 100*sh_w)


%% Fbr VARIABILITY DIAGNOSTIC v2 (range-based): how much does Fbr vary for a chosen range of c, h, W?

% Fbr = 0.9*g/(c*h*T) * 0.11*W^2*tan(th)*sec(th)  =  exp(K) * W^2 / (c*h)
% Step 1: histograms of c, h, W and Fbr for the hour.
% Step 2: you type a [low high] range for each input after looking at the histograms.
% Step 3: Fbr is evaluated at the extremes of those ranges and the % variation is reported.
% h = survey depth (h_source = 'survey') or c^2/g (h_source = 'remote').

% ---- 1) setup: Fbr recomputed with the chosen depth ------------------------
if strcmp(h_source,'survey'); h_d = h_survey_pts; else; h_d = h_pts; end
valid_d = ~isnan(c_pts) & ~isnan(h_d) & c_pts > 0 & h_d > h_min & ~isnan(T_mean);
F_d = nan(size(c_pts));
F_d(valid_d) = 0.9*(g./(c_pts(valid_d).*h_d(valid_d).*T_mean)) .* area_times_sin(valid_d);
dv = valid_d & ~isnan(F_d) & crest_width_pts > 0;

F = F_d(dv);   W = crest_width_pts(dv);   c = c_pts(dv);   h = h_d(dv);
K = log(0.9*g*0.11*tan(theta_r)*sec(theta_r)/T_mean);          % constant part of ln Fbr
cv = @(x) std(x)/mean(x);                                      % coefficient of variation (used later)
Fcalc = @(Wv,cv_,hv) exp(K) * Wv.^2 ./ (cv_ .* hv);            % Fbr from W, c, h

fprintf('\n===== Fbr VARIABILITY (range-based) (%s, h = %s, N = %d points) =====\n', dateTimeLabel, h_source, numel(F))

% ---- 2) histograms ---------------------------------------------------------
vars  = {c,   h,   W,   log(F)};
vname = {'c [m/s]', 'h [m]', 'W [m]', 'F_{br}'};
figure('Name','Fbr inputs: histograms');
tiledlayout(1,4,'TileSpacing','compact');
for i = 1:4
    nexttile
    histogram(vars{i}, 60, 'EdgeColor','none','FaceColor',[0.30 0.55 0.95]);
    xlim([min(vars{i}) max(vars{i})]) 
    xline(median(vars{i}),'k--');
    xline(prctile(vars{i},10),':r');  xline(prctile(vars{i},90),':r');
    xlabel(vname{i}); ylabel('count'); grid on; box on
    title(sprintf('median %.3g', median(vars{i})));
end
sgtitle(sprintf('Inputs to F_{br} - %s  (dashed = median, dotted red = p10/p90)', dateTimeLabel))
drawnow

fprintf('\n%-8s %10s %10s %10s %10s %10s\n', '', 'min', 'p10', 'median', 'p90', 'max')
for i = 1:3
    fprintf('%-8s %10.3g %10.3g %10.3g %10.3g %10.3g\n', strtok(vname{i},' '), min(vars{i}), prctile(vars{i},10), median(vars{i}), prctile(vars{i},90), max(vars{i}))
end

% ---- 3) automatically set ranges to p10-p90 -------------------------------
c_rng = prctile(c, [10 90]);
h_rng = prctile(h, [10 90]);
W_rng = prctile(W, [10 90]);

% ---- 4) Fbr over the chosen ranges -----------------------------------------
c0 = median(c);   h0 = median(h);   W0 = median(W);
F0 = Fcalc(W0, c0, h0);                                        % reference Fbr at the median inputs
% Fbr is largest for big W and small c, h; smallest for small W and big c, h
F_hi = Fcalc(W_rng(2), c_rng(1), h_rng(1));
F_lo = Fcalc(W_rng(1), c_rng(2), h_rng(2));

fprintf('\n-- p10-p90 ranges --\n')
fprintf('  c: [%.3g %.3g] m/s   h: [%.3g %.3g] m   W: [%.3g %.3g] m\n', c_rng, h_rng, W_rng)
fprintf('  Reference Fbr (median c, h, W) = %.3g\n', F0)

fprintf('\n-- Fbr change when ONE input spans its range (others at median) --\n')
oneW = Fcalc(W_rng, c0, h0);   oneC = Fcalc(W0, c_rng, h0);   oneH = Fcalc(W0, c0, h_rng);
rel  = @(f) 100*(f - F0)/F0;
fprintf('  W: %+6.0f %% to %+6.0f %%   (span %.0f %% of reference)\n', min(rel(oneW)), max(rel(oneW)), 100*(max(oneW)-min(oneW))/F0)
fprintf('  c: %+6.0f %% to %+6.0f %%   (span %.0f %% of reference)\n', min(rel(oneC)), max(rel(oneC)), 100*(max(oneC)-min(oneC))/F0)
fprintf('  h: %+6.0f %% to %+6.0f %%   (span %.0f %% of reference)\n', min(rel(oneH)), max(rel(oneH)), 100*(max(oneH)-min(oneH))/F0)



%% ===== WAVE-BY-WAVE ENSEMBLE (v3): padded crests, along-crest median filtering, survey depth, frame diagnostic =====
% Reuses from earlier sections: x_pts, y_pts, c_pts, crest_width_pts, Fbr_dir_pts, frame_ID, tide,
% T_mean, theta_r, g, h_min, crest_width_pts_all, w_by_frame, key2col, up_c, p_by_frame_c,
% max_crest_link_dist, max_match_dist, crest_pad_dist, min_curl_dist, dateTimeLabel, trace_crest_paths,
% h_source / h_survey_pts (survey block above); for the background image: unique_frames, frame_times_abs, S.
%
%  1. Every crest is PADDED with an Fbr = 0 point one crest_pad_dist beyond its first and last measured
%     point (same definition as the hourly curl section). All per-crest quantities use the padded crest.
%  2. Fbr is RECOMPUTED per crest from along-crest median-filtered c and W (inputs, not the output).
%     ens_med_len = 0 turns the filter off.
%  3. Depth h from the survey (water depth = tide - NAVD88 bed elevation) or from c^2/g ('remote').
%  4. Frame diagnostic: normalized crest coordinate, Fbr vectors and profiles for the crests in one frame.
%
% L = padded crest length (pad to pad), zeta = s/L (0 and 1 are the pad points), intCurl*, meanAbsCurl.

% ensemble USER INPUT
ens_min_pts  = 5;      % min matched Fbr points for a crest to count as a wave
ens_min_L    = 3;      % [m] min along-crest span of the measured points (before padding)
ens_nZ       = 51;     % points on the common zeta grid (50 intervals, dzeta = 0.02)
ens_stride   = 1;      % use every Nth frame (consecutive frames re-sample the same physical wave)
ens_max_plot = 150;    % max individual profiles drawn faintly in the profile figure

% --- noise reduction (along-crest median filter on the INPUTS c and W) ---
ens_med_len   = 0;     % [m] median window along the crest (~spacing of points is ~1 m); 0 = no filtering
ens_c_perwave = false; % true: replace c by one median value per crest (per-wave-celerity test)

% --- frame diagnostic ---
ens_diag_frame_idx  = 30;     % index into unique_frames (last video file), 25 is good one for 10/02/2013, 1200
ens_diag_max_crests = 8;      % draw only the N longest crests of that frame
ens_diag_vec_scale  = 6;      % [m of arrow per m s^-2 of Fbr]
ens_diag_vec_stride = 2;      % draw every Nth vector so the crest stays readable

ens_min_pts = max(ens_min_pts, 2);
zgrid = linspace(0, 1, ens_nZ); % grid for normalizing alongcrest
ens_filter_on = ens_med_len > 0 || ens_c_perwave;

% locate given frame for the diagnostic
diag_fnum = [];
if exist('unique_frames','var') && ~isempty(unique_frames)
    diag_time = unique_frames(min(ens_diag_frame_idx, numel(unique_frames)));
    diag_fnum = find(up_c == posixtime(diag_time), 1);
end
if isempty(diag_fnum); diag_fnum = min(ens_diag_frame_idx, numel(up_c)); end

% split frames into individual crests, filter, recompute Fbr, pad, normalize
t_ens = tic;

dt_fr = median(diff(up_c));
fidx  = round((up_c - up_c(1)) / dt_fr);          % frame counter (robust to missing frames)
Fcoef = 0.9*g/T_mean * 0.11*tan(theta_r)*sec(theta_r);   % Fbr = Fcoef * W^2 / (c*h)

ens_L = []; ens_npts = [];
ens_Fmean = []; ens_Fstd = []; ens_Fmax = []; ens_intF = [];
ens_intCurlPos = []; ens_intCurlNeg = [];
ens_xc = []; ens_yc = []; ens_t = NaT(0,1);
Fprof = {}; Cprof = {};
D = struct('x',{},'y',{},'Fraw',{},'F',{},'dir',{},'zeta',{},'L',{},'curl',{},'zmid',{},'id',{});
map_pts = {}; map_seg = {};     % point/segment storage for the spatial maps

for fnum = 1:numel(up_c)
    isDiag = (fnum == diag_fnum);
    useEns = mod(fidx(fnum), ens_stride) == 0;
    if ~useEns && ~isDiag; continue; end

    pt_idx_all = p_by_frame_c{fnum};
    if isempty(pt_idx_all); continue; end
    fkey = up_c(fnum);
    if ~isKey(key2col, fkey); continue; end
    w_idx = w_by_frame{key2col(fkey)};
    if numel(w_idx) < 2; continue; end

    wx = crest_width_pts_all(w_idx,1);
    wy = crest_width_pts_all(w_idx,2);

    pt_idx = pt_idx_all(isfinite(c_pts(pt_idx_all)) & isfinite(crest_width_pts(pt_idx_all)));
    if isempty(pt_idx); continue; end
    fx = x_pts(pt_idx); fy = y_pts(pt_idx);
    fc = c_pts(pt_idx); fW = crest_width_pts(pt_idx); fdir = Fbr_dir_pts(pt_idx);
    if strcmp(h_source,'survey'); fh = h_survey_pts(pt_idx); else; fh = nan(size(fx)); end

    % trace crests in the width cloud, snap points on
    [crestID_w, s_w] = trace_crest_paths(wx, wy, max_crest_link_dist);
    [nn_idx, dmin]   = knnsearch([wx wy], [fx fy]);
    keep = dmin <= max_match_dist;
    if ~any(keep); continue; end
    fx = fx(keep); fy = fy(keep); fc = fc(keep); fW = fW(keep); fdir = fdir(keep); fh = fh(keep);
    crestID_f = crestID_w(nn_idx(keep));
    s_f       = s_w(nn_idx(keep));
    t_frame   = frame_ID(pt_idx_all(1));

    for id = unique(crestID_f)'
        cm = find(crestID_f == id);
        if numel(cm) < ens_min_pts; continue; end
        [~, ord] = sort(s_f(cm));
        cm = cm(ord);

        cxs = fx(cm); cys = fy(cm); cc = fc(cm); ww = fW(cm); dd = fdir(cm);
        s_m = [0; cumsum(hypot(diff(cxs), diff(cys)))] + (0:numel(cxs)-1)'*1e-9;   % strictly increasing

        % ---- along-crest median filter on c and W (window in metres) ----
        cc_f = cc; ww_f = ww;
        if ens_med_len > 0
            cc_f = movmedian(cc, ens_med_len, 'SamplePoints', s_m);
            ww_f = movmedian(ww, ens_med_len, 'SamplePoints', s_m);
        end
        if ens_c_perwave
            cc_f = repmat(median(cc_f), size(cc_f));
        end

        % ---- depth ----
        if strcmp(h_source,'survey')
            hh = fh(cm);  hh_f = hh;                       % survey depth does not depend on c
        else
            hh = cc.^2/g;  hh_f = cc_f.^2/g;               % water depth from (filtered) remote celerity
        end

        F_raw = Fcoef * ww.^2   ./ (cc   .* hh);           % unfiltered
        F_f   = Fcoef * ww_f.^2 ./ (cc_f .* hh_f);         % filtered (identical to F_raw when the filter is off)
        good  = isfinite(F_raw) & isfinite(F_f) & cc > 0 & cc_f > 0 & ww > 0 & hh > h_min & hh_f > h_min;
        if nnz(good) < ens_min_pts; continue; end
        cxs = cxs(good); cys = cys(good); F_raw = F_raw(good); F_f = F_f(good); dd = dd(good);

        if sum(hypot(diff(cxs), diff(cys))) < ens_min_L; continue; end   % span of the measured points

        % ---- pad the crest: Fbr = 0 point one crest_pad_dist beyond each end ----
        e1 = [cxs(1)-cxs(2),       cys(1)-cys(2)];        e1 = e1 / max(norm(e1), eps);
        e2 = [cxs(end)-cxs(end-1), cys(end)-cys(end-1)];  e2 = e2 / max(norm(e2), eps);
        xp     = [cxs(1)+crest_pad_dist*e1(1); cxs; cxs(end)+crest_pad_dist*e2(1)];
        yp     = [cys(1)+crest_pad_dist*e1(2); cys; cys(end)+crest_pad_dist*e2(2)];
        Fp     = [0; F_f;   0];
        Fp_raw = [0; F_raw; 0];

        % ---- along-crest coordinate over the padded crest ----
        ds   = hypot(diff(xp), diff(yp));
        s    = [0; cumsum(ds)];
        L    = s(end);
        zeta = s / L;

        dF   = diff(Fp);                                  % along-crest Fbr steps, pad to pad
        curl = dF ./ ds;                                  % same definition as the hourly curl section
        curl(ds < min_curl_dist) = NaN;
        zeta_md = 0.5*(zeta(1:end-1) + zeta(2:end));

        [zu, iu] = unique(zeta);
        Fz    = interp1(zu, Fp(iu), zgrid, 'linear');
        Fmean = trapz(zgrid, Fz);
        Fstd  = sqrt(trapz(zgrid, (Fz - Fmean).^2));

        ok = ~isnan(curl);
        Cz = nan(1, ens_nZ);
        if nnz(ok) >= 2
            [zm, im] = unique(zeta_md(ok));
            cvv = curl(ok);  cvv = cvv(im);
            if numel(zm) >= 2
                Cz = interp1(zm, cvv, zgrid, 'linear', NaN);
                Cz = fillmissing(Cz, 'nearest');
            end
        end

        if useEns
            Fprof{end+1,1} = Fz;
            Cprof{end+1,1} = Cz;
            ens_L(end+1,1)          = L;
            ens_npts(end+1,1)       = numel(cxs);
            ens_Fmean(end+1,1)      = Fmean;
            ens_Fstd(end+1,1)       = Fstd;
            ens_Fmax(end+1,1)       = max(F_f);
            ens_intF(end+1,1)       = Fmean * L;
            ens_intCurlPos(end+1,1) = sum(max(dF,0));
            ens_intCurlNeg(end+1,1) = sum(min(dF,0));
            ens_xc(end+1,1)         = mean(cxs);
            ens_yc(end+1,1)         = mean(cys);
            ens_t(end+1,1)          = t_frame;

            % ---- point / segment storage for the spatial-map section ----
            cidx = numel(ens_L); % this crest's index in the ensemble arrays
            map_pts{end+1,1} = [cxs, cys, F_f, F_raw, repmat(cidx, numel(cxs), 1)];
            map_seg{end+1,1} = [(xp(1:end-1)+xp(2:end))/2, (yp(1:end-1)+yp(2:end))/2, curl, repmat(cidx, numel(curl), 1)];
        end

        if isDiag                                          % keep everything needed to draw this crest
            D(end+1) = struct('x',xp, 'y',yp, 'Fraw',Fp_raw, 'F',Fp, 'dir',dd, 'zeta',zeta, 'L',L, ...
                'curl',curl, 'zmid',zeta_md, 'id',id);
        end
    end
end

if isempty(ens_L); error('No crests passed the ensemble filters (min_pts = %d, min_L = %.1f m).', ens_min_pts, ens_min_L); end
Fmat = vertcat(Fprof{:});          % nCrest x nZ, Fbr(zeta)
Cmat = vertcat(Cprof{:});          % nCrest x nZ, along-crest curl(zeta)  [s^-2]
nE   = size(Fmat, 1);
Fshape = Fmat ./ ens_Fmean;        % amplitude-normalized shape, F / (crest-mean F)

% derived per-crest forcing quantities
intCurlAbs  = ens_intCurlPos - ens_intCurlNeg;     % sum |dFbr| along the padded crest
meanAbsCurl = intCurlAbs ./ ens_L;

fprintf('Ensemble build: %d crest events from %d frames (stride %d) in %.1f s\n', ...
    nE, numel(up_c), ens_stride, toc(t_ens));
fprintf('Settings: median window %.1f m | per-wave c = %d | h source = %s\n', ens_med_len, ens_c_perwave, h_source);

%% ensemble statistics
F_mean = mean(Fmat, 1, 'omitnan');    F_std = std(Fmat, 0, 1, 'omitnan');    F_med = median(Fmat, 1, 'omitnan');
F_p16  = prctile(Fmat, 16, 1);        F_p84 = prctile(Fmat, 84, 1);
C_mean = mean(Cmat, 1, 'omitnan');    C_std = std(Cmat, 0, 1, 'omitnan');
CA_mean = mean(abs(Cmat), 1, 'omitnan');
S_mean = mean(Fshape, 1, 'omitnan');  S_med = median(Fshape, 1, 'omitnan');
S_p16  = prctile(Fshape, 16, 1);      S_p84 = prctile(Fshape, 84, 1);

st = @(v) [mean(v,'omitnan'), std(v,0,'omitnan'), median(v,'omitnan')];
fprintf('\n===== WAVE-BY-WAVE ENSEMBLE (%s), N = %d crests =====\n', dateTimeLabel, nE)
fprintf('%-42s %10s %10s %10s\n', '', 'mean', 'std', 'median')
rows = {'Crest length L [m]',                           ens_L
        'Matched Fbr points per crest',                 ens_npts
        'Peak Fbr [m s^-2]',                            ens_Fmax
        'Crest-mean Fbr [m s^-2]',                      ens_Fmean
        'Along-crest std of Fbr [m s^-2]',              ens_Fstd
        'intF = int Fbr ds [m^2 s^-2]',                 ens_intF
        'intCurlPos [m s^-2]',                          ens_intCurlPos
        'intCurlNeg [m s^-2]',                          ens_intCurlNeg
        'intCurlAbs [m s^-2]',                          intCurlAbs
        'meanAbsCurl [s^-2]',                           meanAbsCurl};
for i = 1:size(rows,1)
    fprintf('%-42s %10.4f %10.4f %10.4f\n', rows{i,1}, st(rows{i,2}))
end

rr = @(a,b) [corr(a,b,'Rows','complete'), corr(a,b,'Type','Spearman','Rows','complete')];
fprintf('\n-- Correlations [Pearson, Spearman] --\n')
fprintf('  Fmean vs meanAbsCurl: %5.2f %5.2f | L vs meanAbsCurl: %5.2f %5.2f | L vs intCurlAbs: %5.2f %5.2f | Fstd vs meanAbsCurl: %5.2f %5.2f\n', ...
    rr(ens_Fmean, meanAbsCurl), rr(ens_L, meanAbsCurl), rr(ens_L, intCurlAbs), rr(ens_Fstd, meanAbsCurl))
fprintf('NOTE: consecutive frames re-sample the same physical wave, so N overstates the number of\n')
fprintf('independent events; use ens_stride to thin before quoting standard errors or p-values.\n')

ENS = struct('zeta',zgrid, 'F',Fmat, 'curl',Cmat, 'Fshape',Fshape, 'L',ens_L, 'npts',ens_npts, ...
    'Fmean',ens_Fmean, 'Fstd',ens_Fstd, 'Fmax',ens_Fmax, 'intF',ens_intF, ...
    'intCurlPos',ens_intCurlPos, 'intCurlNeg',ens_intCurlNeg, ...
    'intCurlAbs',intCurlAbs, 'meanAbsCurl',meanAbsCurl, ...
    'settings',struct('med_len',ens_med_len,'c_perwave',ens_c_perwave,'h_source',h_source,'stride',ens_stride,'pad_dist',crest_pad_dist), ...
    'xc',ens_xc, 'yc',ens_yc, 'time',ens_t);

% %% ensemble plots: average forcing profile + curl profile
% shade = @(ax,x,lo,hi,col) fill(ax, [x fliplr(x)], [hi fliplr(lo)], col, 'FaceAlpha',0.25, 'EdgeColor','none');
% pick  = unique(round(linspace(1, nE, min(nE, ens_max_plot))));
% gcol  = [0.80 0.80 0.80];  bcol = [0.10 0.30 0.80];
% 
% figure('Name','Ensemble profiles','Position',[100 100 1300 450]);
% tl = tiledlayout(1,3,'TileSpacing','compact');
% 
% ax = nexttile; hold(ax,'on')
% plot(ax, zgrid, Fmat(pick,:)', '-', 'Color', gcol)
% shade(ax, zgrid, F_p16, F_p84, bcol);
% plot(ax, zgrid, F_mean, '-',  'Color', bcol, 'LineWidth', 2)
% plot(ax, zgrid, F_med,  '--', 'Color', 'k',  'LineWidth', 1.2)
% xlabel(ax,'\zeta = s/L'); ylabel(ax,'F_{br} [m s^{-2}]'); title(ax,'Forcing profile')
% grid(ax,'on'); box(ax,'on'); xlim(ax,[0 1]); ylim(ax,[0 prctile(Fmat(:),99)])
% 
% ax = nexttile; hold(ax,'on')
% plot(ax, zgrid, Cmat(pick,:)', '-', 'Color', gcol)
% shade(ax, zgrid, C_mean-C_std, C_mean+C_std, bcol);
% h1 = plot(ax, zgrid, C_mean,  '-',  'Color', bcol, 'LineWidth', 2);
% h2 = plot(ax, zgrid, CA_mean, '--', 'Color', [0.80 0.30 0.05], 'LineWidth', 2);
% yline(ax, 0, 'k:')
% legend(ax, [h1 h2], {'mean curl', 'mean |curl|'}, 'Location','best')
% xlabel(ax,'\zeta = s/L'); ylabel(ax,'\nabla \times F_{br} [s^{-2}]', 'Interpreter','tex'); title(ax,'Along-crest curl profile')
% grid(ax,'on'); box(ax,'on'); xlim(ax,[0 1]); ylim(ax,[-3 3]*mean(CA_mean))
% 
% ax = nexttile; hold(ax,'on')
% plot(ax, zgrid, Fshape(pick,:)', '-', 'Color', gcol)
% shade(ax, zgrid, S_p16, S_p84, bcol);
% plot(ax, zgrid, S_mean, '-',  'Color', bcol, 'LineWidth', 2)
% plot(ax, zgrid, S_med,  '--', 'Color', 'k',  'LineWidth', 1.2)
% xlabel(ax,'\zeta = s/L'); ylabel(ax,'F_{br} / crest-mean F_{br}'); title(ax,'Amplitude-normalized shape')
% grid(ax,'on'); box(ax,'on'); xlim(ax,[0 1]); ylim(ax,[0 prctile(Fshape(:),99)])
% 
% title(tl, sprintf('Wave-by-wave ensemble (N = %d; mean, median dashed, 16-84%% band) - %s', nE, dateTimeLabel), 'FontSize', 14)

%% ensemble plots: per-crest distributions (padded crests)
bcol = [0.10 0.30 0.80];
figure;
tl = tiledlayout(2,2,'TileSpacing','compact');

nexttile(1); histogram(ens_L, 'FaceColor', bcol, 'EdgeColor','none');                % top left
xlabel('Crest length L [m]'); ylabel('Count'); title('Crest length'); grid on; box on
xlim([0 150]);

nexttile(3); histogram(ens_Fmean, 'FaceColor', bcol, 'EdgeColor','none');            % bottom left
xlabel('Crest-mean F_{br} [m s^{-2}]'); ylabel('Count'); title('Crest-mean breaking force'); grid on; box on
% xlim([0 150]);

nexttile(2, [2 1]); histogram(intCurlAbs, 'FaceColor', bcol, 'EdgeColor','none');    % entire right side
xlabel('\Omega_c = \Sigma|\nabla\times F_{br}| \Deltas [m s^{-2}]'); ylabel('Count')
title('Total vorticity forcing per crest'); grid on; box on

title(tl, sprintf('Per-crest distributions (N = %d) - %s', nE, dateTimeLabel), 'FontSize', 13)

%% scatterplots: intensity vs variability vs length as controls on vorticity forcing
sp = {ens_Fmean, meanAbsCurl, 'Crest-mean F_{br} [m s^{-2}]',           'Mean |\nabla\times F_{br}| [s^{-2}]'
      ens_L,     meanAbsCurl, 'Crest length L [m]',                      'Mean |\nabla\times F_{br}| [s^{-2}]'
      ens_L,     intCurlAbs,  'Crest length L [m]',                      'Total \Sigma|\DeltaF_{br}| [m s^{-2}]'
      ens_Fstd,  meanAbsCurl, 'Along-crest std of F_{br} [m s^{-2}]',    'Mean |\nabla\times F_{br}| [s^{-2}]'};

figure;
tl = tiledlayout(2,2,'TileSpacing','compact');
for i = 1:size(sp,1)
    ax = nexttile; hold(ax,'on')
    x = sp{i,1}; y = sp{i,2};
    scatter(ax, x, y, 12, bcol, 'filled', 'MarkerFaceAlpha', 0.4)
    m = isfinite(x) & isfinite(y);
    if nnz(m) > 2
        p  = polyfit(x(m), y(m), 1);
        xx = linspace(min(x(m)), max(x(m)), 50);
        plot(ax, xx, polyval(p, xx), 'k-', 'LineWidth', 1.2)
    end
    r = rr(x, y);
    title(ax, sprintf('r = %.2f, \\rho_s = %.2f', r(1), r(2)))
    xlabel(ax, sp{i,3}); ylabel(ax, sp{i,4}); grid(ax,'on'); box(ax,'on')
end
title(tl, sprintf('Vorticity forcing per crest (N = %d, med %.0f m, h: %s) - %s', nE, ens_med_len, h_source, dateTimeLabel), 'FontSize', 13)

%% FRAME DIAGNOSTIC: normalized along-crest grid, Fbr vectors, profiles for the crests in one frame
if isempty(D)
    warning('No crests passed the filters in the diagnostic frame (index %d); change ens_diag_frame_idx.', ens_diag_frame_idx)
else
    [~, ordL] = sort([D.L], 'descend');
    D = D(ordL(1:min(ens_diag_max_crests, numel(D))));
    ccols = lines(numel(D));
    tick_z = [0 0.5 1];

    figure;
    tl = tiledlayout(2,3,'TileSpacing','compact');

    axM = nexttile([2 2]); hold(axM,'on')
    if exist('frame_times_abs','var') && exist('diag_time','var') && isfield(S,'rectified_frames')
        rf = find(frame_times_abs == diag_time, 1);
        if ~isempty(rf) && ~isempty(S.rectified_frames{rf})
            bg_rgb = ind2rgb(gray2ind(mat2gray(double(S.rectified_frames{rf})), 256), bone(256));   % true color
            bgh = imagesc(axM, S.X, S.Y, bg_rgb);
            set(bgh, 'AlphaData', 0.5)
        end
    end
    colormap(axM, parula); clim(axM, [0 1])
    for k = 1:numel(D)
        plot(axM, D(k).x, D(k).y, '-', 'Color', ccols(k,:), 'LineWidth', 1.5)                               % padded crest path
        scatter(axM, D(k).x, D(k).y, 22, D(k).zeta, 'filled', 'MarkerEdgeColor', 'k', 'LineWidth', 0.3)
        plot(axM, D(k).x([1 end]), D(k).y([1 end]), 'x', 'Color', ccols(k,:), 'MarkerSize', 8, 'LineWidth', 1.5)   % Fbr = 0 pad points
        xr = D(k).x(2:end-1);  yr = D(k).y(2:end-1);  Fr = D(k).F(2:end-1);      % measured points carry the vectors
        qi = 1:ens_diag_vec_stride:numel(xr);
        quiver(axM, xr(qi), yr(qi), ens_diag_vec_scale*Fr(qi).*cos(D(k).dir(qi)), ...
            ens_diag_vec_scale*Fr(qi).*sin(D(k).dir(qi)), 1, ...
            'Color', [0 .3 0], 'LineWidth', 0.8, 'MaxHeadSize', 0.3)
        [zq, iq] = unique(D(k).zeta);
        xt = interp1(zq, D(k).x(iq), tick_z);  yt = interp1(zq, D(k).y(iq), tick_z);
        for q = 1:numel(tick_z)
            text(axM, xt(q), yt(q), sprintf(' %.2g', tick_z(q)), 'FontSize', 8, 'Color', ccols(k,:), 'FontWeight','bold')
        end
        text(axM, interp1(zq, D(k).x(iq), 0.25), interp1(zq, D(k).y(iq), 0.25), ...
            sprintf('  #%d  L=%.0f m', k, D(k).L), 'FontSize', 9, 'Color', ccols(k,:), 'FontWeight','bold')
    end
    cb = colorbar(axM); cb.Label.String = '\zeta = s/L';
    axis(axM, 'equal'); grid(axM,'on'); box(axM,'on')
    allx = vertcat(D.x);  ally = vertcat(D.y);                       % zoom to the crests
    xlim(axM, [min(allx) max(allx)] + [-15 15]);  ylim(axM, [min(ally) max(ally)] + [-15 15]);
    xlabel(axM,'Cross-shore [m]'); ylabel(axM,'Alongshore [m]')
    title(axM, sprintf('Crests, normalized coordinate \\zeta (labels), F_{br} vectors (green) - %s', string(diag_time)))
    view(axM, [-90 90])

    % profiles: x-axis reversed so zeta runs right to left, like the crests in the map (towards +alongshore)
    axF = nexttile; hold(axF,'on')
    for k = 1:numel(D)
        if ens_filter_on
            plot(axF, D(k).zeta, D(k).Fraw, ':', 'Color', ccols(k,:), 'LineWidth', 1)
        end
        plot(axF, D(k).zeta, D(k).F, '-', 'Color', ccols(k,:), 'LineWidth', 1.8)
    end
    xlabel(axF,'\zeta = s/L'); ylabel(axF,'F_{br} [m s^{-2}]'); xlim(axF,[0 1]); grid(axF,'on'); box(axF,'on')
    set(axF, 'XDir', 'reverse')
    if ens_filter_on
        title(axF, sprintf('F_{br}(\\zeta): dotted = unfiltered, solid = filtered (%.0f m)', ens_med_len))
    else
        title(axF, 'F_{br}(\zeta)')
    end

    axC = nexttile; hold(axC,'on')
    for k = 1:numel(D)
        plot(axC, D(k).zmid, D(k).curl, '-o', 'Color', ccols(k,:), 'MarkerSize', 3, 'LineWidth', 1.2)
    end
    yline(axC, 0, 'k:')
    xlabel(axC,'\zeta = s/L'); ylabel(axC,'\nabla \times F_{br} [s^{-2}]'); xlim(axC,[0 1]); grid(axC,'on'); box(axC,'on')
    set(axC, 'XDir', 'reverse')
    title(axC, 'Along-crest curl(\zeta)')
    title(tl, 'Single-frame diagnostic: individual breaking waves in the normalized crest system', 'FontSize', 14)
end

fprintf('Ensemble section total: %.1f s\n', toc(t_ens));




%% ===== SPATIAL MAPS: ensemble vs hourly-averaged approach =====
% Uses the SAME bins as the hourly maps (x_edges / y_edges / x_centers / y_centers from "BIN BREAKING FORCE").
% Hourly quantities: Fbr_mag_grid, Fbr_curl_grid, curl_x/curl_y/curl_val (padded, unfiltered, remote h).
% Ensemble quantities: filtered Fbr, depth from h_source, per-crest padded segments (stored by the ensemble loop).

map_min_pts    = 10;    % min points per bin for Fbr maps (hourly used 10)
map_min_seg    = 25;    % min curl segments per bin (hourly used 25)
map_min_crests = 20;    % min crest centroids per bin for the per-crest maps
map_xlim = [min(x_centers) max(x_centers)];
map_ylim = [min(y_centers) max(y_centers)];
% map_xlim = [70 200]; map_ylim = [650 1100];     % same window as the hourly curl plot
F_clim    = [0 0.5];
curl_clim = [-0.05 0.05];

cm_seq = cmocean('-thermal');
cm_div = cmocean('balance');
tag    = sprintf('ensemble: med %.0f m, h: %s', ens_med_len, h_source);

PT = vertcat(map_pts{:});     % [x y F_filtered F_raw crestIdx]
SG = vertcat(map_seg{:});     % [xmid ymid curl crestIdx]

% ---- binned fields ----
F_hr = Fbr_mag_grid;                                   % hourly mean Fbr
C_hr = Fbr_curl_grid;                                  % hourly mean curl
[A_hr,  ~] = bin_grid(curl_x,  curl_y,  abs(curl_val), @mean, x_edges, y_edges, map_min_seg);   % hourly mean |curl|
[F_ens, ~] = bin_grid(PT(:,1), PT(:,2), PT(:,3),       @mean, x_edges, y_edges, map_min_pts);
[C_ens, ~] = bin_grid(SG(:,1), SG(:,2), SG(:,3),       @mean, x_edges, y_edges, map_min_seg);
[A_ens, ~] = bin_grid(SG(:,1), SG(:,2), abs(SG(:,3)),  @mean, x_edges, y_edges, map_min_seg);
Coh_ens = abs(C_ens) ./ A_ens;                         % |mean curl| / mean |curl|: 1 = coherent sign, 0 = random sign

% ---- agreement with the hourly approach (bin by bin) ----
fprintf('\n===== ENSEMBLE vs HOURLY-AVERAGED (%s) =====\n', tag)
pairs = {'mean Fbr',      F_hr, F_ens
         'mean curl',     C_hr, C_ens
         'mean |curl|',   A_hr, A_ens};
for i = 1:size(pairs,1)
    a = pairs{i,2}(:);  b = pairs{i,3}(:);  mm = isfinite(a) & isfinite(b);
    pfit = polyfit(a(mm), b(mm), 1);
    fprintf('  %-22s bins %4d | r = %.3f | slope = %.3f | bias(ens-hr) = %+.4f | RMSE = %.4f\n', ...
        pairs{i,1}, nnz(mm), corr(a(mm), b(mm)), pfit(1), mean(b(mm)-a(mm)), sqrt(mean((b(mm)-a(mm)).^2)))
end
fprintf('  pooled mean |curl|: hourly %.4f | ensemble %.4f s^-2\n', ...
    mean(abs(curl_val),'omitnan'), mean(abs(SG(:,3)),'omitnan'))
fprintf('  REGRESSION TEST: with ens_med_len = 0, h_source = ''remote'', ens_stride = 1 the two should agree closely (r ~ 1, slope ~ 1).\n')

% % ---- FIGURE 1: hourly vs ensemble maps of Fbr and curl ----
% figure('Name','Spatial: hourly vs ensemble','Position',[60 60 1500 800]);
% tl = tiledlayout(2,3,'TileSpacing','compact');
% show_map(nexttile, x_centers, y_centers, F_hr,         'F_{br} hourly mean',                       F_clim, cm_seq, 'F_{br} [m s^{-2}]', map_xlim, map_ylim);
% show_map(nexttile, x_centers, y_centers, F_ens,        ['F_{br} ' tag],                            F_clim, cm_seq, 'F_{br} [m s^{-2}]', map_xlim, map_ylim);
% show_map(nexttile, x_centers, y_centers, F_ens - F_hr, 'F_{br} ensemble - hourly',                 [-0.2 0.2], cm_div, '\DeltaF_{br} [m s^{-2}]', map_xlim, map_ylim);
% show_map(nexttile, x_centers, y_centers, C_hr,         '\nabla\times F_{br} hourly',               curl_clim, cm_div, '\nabla\times F_{br} [s^{-2}]', map_xlim, map_ylim);
% show_map(nexttile, x_centers, y_centers, C_ens,        ['\nabla\times F_{br} ' tag],               curl_clim, cm_div, '\nabla\times F_{br} [s^{-2}]', map_xlim, map_ylim);
% show_map(nexttile, x_centers, y_centers, C_ens - C_hr, '\nabla\times F_{br} ensemble - hourly',    curl_clim, cm_div, '\Delta\nabla\times F_{br} [s^{-2}]', map_xlim, map_ylim);
% title(tl, sprintf('Hourly-averaged vs wave-by-wave ensemble binning - %s', dateTimeLabel), 'FontSize', 14)


% ---- FIGURE 3: validation against the hourly approach ----
figure('Name','Spatial: validation','Position',[60 60 1300 800]);
tl = tiledlayout(2,2,'TileSpacing','compact');

ax = nexttile; hold(ax,'on')
a = C_hr(:); b = C_ens(:); mm = isfinite(a) & isfinite(b);
scatter(ax, a(mm), b(mm), 14, [0.10 0.30 0.80], 'filled', 'MarkerFaceAlpha', 0.5)
lim = [-1 1] * max(abs([a(mm); b(mm)]));
plot(ax, lim, lim, 'k--')
pfit = polyfit(a(mm), b(mm), 1);
xlabel(ax,'hourly <\nabla\times F_{br}> [s^{-2}]'); ylabel(ax,'ensemble <\nabla\times F_{br}> [s^{-2}]')
title(ax, sprintf('bin-by-bin curl: r = %.2f, slope = %.2f', corr(a(mm), b(mm)), pfit(1)))
axis(ax,'equal'); xlim(ax,lim); ylim(ax,lim); grid(ax,'on'); box(ax,'on')

show_map(nexttile, x_centers, y_centers, C_ens - C_hr, 'curl: ensemble - hourly', curl_clim, cm_div, '\Delta\nabla\times F_{br} [s^{-2}]', map_xlim, map_ylim);

ax = nexttile; hold(ax,'on')                                  % cross-shore profile of Fbr (alongshore mean)
both = isfinite(F_hr) & isfinite(F_ens);
Fh = F_hr;  Fh(~both) = NaN;   Fe = F_ens;  Fe(~both) = NaN;
plot(ax, x_centers, mean(Fh,1,'omitnan'), 'k-',  'LineWidth', 2)
plot(ax, x_centers, mean(Fe,1,'omitnan'), 'b--', 'LineWidth', 2)
xlabel(ax,'Cross-shore [m]'); ylabel(ax,'alongshore-mean F_{br} [m s^{-2}]'); legend(ax,'hourly','ensemble','Location','best')
title(ax,'Cross-shore profile of F_{br}'); grid(ax,'on'); box(ax,'on')

ax = nexttile; hold(ax,'on')                                  % cross-shore profile of mean |curl|
both = isfinite(A_hr) & isfinite(A_ens);
Ah = A_hr;  Ah(~both) = NaN;   Ae = A_ens;  Ae(~both) = NaN;
plot(ax, x_centers, mean(Ah,1,'omitnan'), 'k-',  'LineWidth', 2)
plot(ax, x_centers, mean(Ae,1,'omitnan'), 'b--', 'LineWidth', 2)
xlabel(ax,'Cross-shore [m]'); ylabel(ax,'alongshore-mean |\nabla\times F_{br}| [s^{-2}]')
legend(ax,'hourly','ensemble','Location','best')
title(ax,'Cross-shore profile of mean |curl|'); grid(ax,'on'); box(ax,'on')
title(tl, sprintf('Does the ensemble reproduce the hourly-averaged result? - %s (%s)', dateTimeLabel, tag), 'FontSize', 14)


%% LOCAL FUNCTIONS

function [cx_adj_pts, cy_adj_pts, c_adj_pts] = apply_piv_correction(P, piv_u_sign, all_celerity, t_video, windowStart, piv_bin)
% APPLY_PIV_CORRECTION  Doppler-shift correction of video celerity using PIV
% surface currents (same method as PIV_correction.m):
%   c_adj = c_obs - dot(u_piv, c_hat), direction unchanged.
% Output rows line up 1:1 with the rows of all_celerity.

% DUNEX2021 PIV files: cX/cY = grid coords, X0/Y0 = u/v time series, stored
% transposed (x varies down rows), so flip to meshgrid orientation.
if ~isfield(P,'u') && all(isfield(P, {'cX','cY','X0','Y0'}))
    P.FRFx = P.cX';  P.FRFy = P.cY';
    P.u    = permute(P.X0, [2 1 3]);
    P.v    = permute(P.Y0, [2 1 3]);
end

miss = {'u','v','FRFx','FRFy'};  miss = miss(~isfield(P, miss));
if ~isempty(miss)
    error('PIV file is missing: %s. Variables in file: %s', strjoin(miss,', '), strjoin(fieldnames(P)', ', '));
end
u_full = piv_u_sign * P.u;
v_full = P.v;

if isfield(P, 't') && ~isempty(P.t)
    t_piv = P.t(:);
    if ~isdatetime(t_piv); t_piv = datetime(t_piv, 'ConvertFrom', 'datenum'); end
    if ~isempty(t_piv.TimeZone); t_piv.TimeZone = ''; end
else
    t_piv = windowStart + minutes(30);      % no time vector: treat as one hourly-mean field
end
if size(u_full,3) ~= numel(t_piv)
    error('PIV u has %d time slices but t has %d entries.', size(u_full,3), numel(t_piv));
end

FX = P.FRFx;
FY = P.FRFy;
if ~isequal(size(u_full,1), size(FX,1)) || ~isequal(size(u_full,2), size(FX,2))
    error('u spatial dims do not match FRFx/FRFy grid size.');
end

pad = minutes(10); % pad for piv time vector
piv_mask = t_piv >= (min(t_video) - pad) & t_piv <= (max(t_video) + pad);
if ~any(piv_mask)
    error('No PIV samples found near the video time window (video %s to %s, PIV %s to %s).', ...
        string(min(t_video)), string(max(t_video)), string(min(t_piv)), string(max(t_piv)));
end
t_piv  = t_piv(piv_mask);
u_full = u_full(:,:,piv_mask);
v_full = v_full(:,:,piv_mask);
if isscalar(t_piv)      % single hourly-mean field: one bin spanning all the video points
    edges_t = [min(t_video) max(t_video)+seconds(1)];
else
    edges_t = t_piv(1):piv_bin:t_piv(end)+piv_bin;
end
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

% assign each video c-pt to its PIV time bin, correct celerity (Doppler-shift projection)
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

    u_dot_chat = u_at_pts .* cx_hat(pts) + v_at_pts .* cy_hat(pts);

    c_adj_pts(pts)  = c_obs(pts) - u_dot_chat;
    cx_adj_pts(pts) = c_adj_pts(pts) .* cx_hat(pts);   % direction unchanged, only magnitude corrected
    cy_adj_pts(pts) = c_adj_pts(pts) .* cy_hat(pts);
end
end

function [crestID, s] = trace_crest_paths(x, y, max_link_dist)
% TRACE_CREST_PATHS  Along-crest order for an unorganized (x,y) point cloud that may contain several separate crests.
% Each point is chained to its nearest not-yet-used neighbor; a crest ends where no neighbor lies within
% max_link_dist (ran out of points), or where the nearest neighbor would reverse the direction of travel already 
% established along that crest(tracing back up the crest instead of further along it). Each crest's
% arclength s is oriented to increase with y, so curl signs stay consistent across crests and frames regardless of 
% which point tracing happened to start from.
n       = numel(x);
crestID = nan(n,1);
s       = nan(n,1);
visited = false(n,1);
curID   = 0;

while ~all(visited)
    curID = curID + 1;
    seed  = find(~visited, 1, 'first');
    chain = seed;
    visited(seed) = true;

    for dir_sign = [1 -1]      % grow forward from the seed, then backward
        cur     = seed;
        run_dir = [];
        while true
            cand = find(~visited);
            if isempty(cand); break; end
            d = hypot(x(cand)-x(cur), y(cand)-y(cur));
            [dmin, k] = min(d);
            if dmin > max_link_dist; break; end
            nxt  = cand(k);
            step = [x(nxt)-x(cur), y(nxt)-y(cur)] / max(dmin, eps);
            if ~isempty(run_dir) && dot(step, run_dir) < 0
                break   % next nearest point is back the way we came -- crest end
            end
            run_dir = step;
            if dir_sign == 1
                chain = [chain; nxt];
            else
                chain = [nxt; chain];
            end
            visited(nxt) = true;
            cur = nxt;
        end
    end

    if y(chain(1)) > y(chain(end))
        chain = flipud(chain);   % keep s increasing with y -- consistent curl sign
    end

    cx  = x(chain); cy = y(chain);
    arc = [0; cumsum(hypot(diff(cx), diff(cy)))];
    crestID(chain) = curID;
    s(chain)       = arc;
end
end


function [G, N] = bin_grid(x, y, v, fcn, x_edges, y_edges, minN)
% BIN_GRID  Bin scattered values onto the (y x x) grid defined by x_edges/y_edges.
% G = fcn applied per bin (NaN where fewer than minN values); N = raw count per bin.
nx = numel(x_edges) - 1;   ny = numel(y_edges) - 1;
x = x(:);  y = y(:);  v = v(:);
xi = discretize(x, x_edges);   yi = discretize(y, y_edges);
ok = ~isnan(xi) & ~isnan(yi) & ~isnan(v);
subs = [yi(ok) xi(ok)];
G = accumarray(subs, v(ok), [ny nx], fcn, NaN);
N = accumarray(subs, 1, [ny nx]);
G(N < minN) = NaN;
end

function show_map(ax, xc, yc, G, ttl, cl, cmap, lbl, xl, yl)
% SHOW_MAP  imagesc a gridded field with NaN transparency, matching the hourly map style.
h = imagesc(ax, xc, yc, G);
set(h, 'AlphaData', ~isnan(G));
set(ax, 'YDir', 'normal', 'Color', 'w');
colormap(ax, cmap);
if ~isempty(cl); clim(ax, cl); end
cb = colorbar(ax);  cb.Label.String = lbl;  cb.Label.Interpreter = 'tex';
axis(ax, 'tight');  box(ax, 'on');  grid(ax, 'minor');
xlim(ax, xl);  ylim(ax, yl);
xlabel(ax, 'Cross-shore [m]');  ylabel(ax, 'Alongshore [m]');
title(ax, ttl, 'Interpreter', 'tex', 'FontSize', 11);
end
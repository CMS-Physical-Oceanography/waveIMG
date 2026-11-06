% Fbr, vort calculations

%% USER INPUT
year_str   = '2021';
runDate    = '20210829';        % yyyymmdd of the video run
hourStr    = '1300';            % hhmm
camera     = 'NorthTower';      % 2021: 'NorthTower' | 'SouthTower'
                                % 2013: 'rod13'  (prefix of the saved .mat)

data_source = 'raw';            % 'raw' or 'piv'

bin_size = 5;          % m
piv_bin  = minutes(2);
g        = 9.81;

h_min = 0.2;           % m, exclude points with depth below this from Fbr (h = c^2/g - tide; Fbr ~ 1/h blows up)
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
        buoyFile = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main/data/buoy_data/duck_offshore_cond.txt';
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
% MAIN_FLOW_RECENT saves to mat_data/local_runs as <tower>_<dateTag>_<hourStr><runTag>.mat
% (e.g. SouthTower_20210904_1600_0000_enh.mat), so look there too.
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

%% LOAD MAT FILE
t_load = tic;
fprintf('Loading %s\n', L.name);
S = load(videoOutputFile);
fprintf('LOAD MAT FILE: %.1f s\n', toc(t_load));

%% LOAD CELERITY DATA
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

% FILTER CELERITY POINTS
speed_mask = c_pts > c_speed_min & c_pts < c_speed_max;
x_pts  = x_pts(speed_mask);
y_pts  = y_pts(speed_mask);
cx_pts = cx_pts(speed_mask);
cy_pts = cy_pts(speed_mask);
c_pts  = c_pts(speed_mask);
frame_ID = t_video(speed_mask);

%% LOAD CREST WIDTHS (matched to each individual celerity point)
crest_width_pts_all  = S.all_crest_width_pts_total;    % [x, y, width]
crest_width_time_all = S.all_crest_width_time_total;   % datetime, one per row

max_match_dist = 2; % m, max distance allowed between a celerity point and its matched width point

t_match = tic;
crest_width_pts = nan(size(x_pts));

% group both point sets by frame ONCE (numeric keys + accumarray)
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

%% BREAKING FORCE CALCULATION
h_pts = (c_pts.^2 ./ g) - tide;

theta_r = deg2rad(15); % roller angle, constant of 15 rn

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

%% BIN BREAKING FORCE
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
cb = colorbar; cb.Label.String = 'F_{br,xc} [ms^{-2}]';
cmocean('-thermal');
caxis([0 0.5]);
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title(sprintf('F_{br,xc} Magnitude - %s',dateTimeLabel), 'FontSize', 15)
xlim([90 170]); ylim([610 835])

%% BREAKING FORCE DIRECTION MAP

dir_from_onshore_deg = mod(rad2deg(Fbr_dir_grid), 360) - 180; % dir from onshore
figure
h = imagesc(x_centers,y_centers,dir_from_onshore_deg);
set(h,'AlphaData',~isnan(Fbr_dir_grid))
set(gca,'YDir','normal')
axis tight
box on
grid minor
colormap(gca, cmocean('curl'));
caxis([-20 20]);   % tightened — check actual min/max of dir_from_onshore_deg first
cb = colorbar; cb.Label.String = 'F_{br} direction [deg]';
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title(sprintf('F_{br} Direction - %s',dateTimeLabel), 'FontSize', 15)
xlim([90 170]); ylim([610 835])

%% SINGLE FRAME CREST POINT VECTOR FIELD OVER IMAGE

frame_to_plot = 25; % frame of last 5 mins to inspect

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

figure
hold on
bg = S.rectified_frames{rf_idx}; % background img
h = imagesc(S.X,S.Y,bg);
set(h,'AlphaData',0.5)
colormap bone
% axis equal tight
scatter(x_pts(frame_mask),y_pts(frame_mask),8,'filled') % crest pts
quiver(x_pts(frame_mask), y_pts(frame_mask), Fx_pts(frame_mask), Fy_pts(frame_mask), 0.5, 'LineWidth', 0.8, 'MaxHeadSize',0.03) % Fbr vects
xlim([90 200])
ylim([602 1000])
grid on; box on
xlabel('Cross-shore [m]')
ylabel('Alongshore [m]')
title('F_{br} Vectors', FontSize=15)
view([-90 90])


%% ALONG-CREST Fbr CURL, CREST IDENTITY FROM THE CREST-WIDTH POINT CLOUD - plot binned curl(Fbr) map
% x_pts/y_pts/Fbr_mag_pts don't carry a crest ID -- that identity was
% flattened away when crest_width_pts{k} was concatenated across fronts
% (fn_main_flow.m). So crest membership + along-crest order are rebuilt here
% from the raw crest-width point cloud (crest_width_pts_all/crest_width_time_all),
% which is dense enough to trace each physical crest as a curve. Each matched
% Fbr point is then snapped onto its nearest traced crest-width point and
% inherits that crest's ID and along-crest arclength position.
%
% Within a crest, curl between along-crest-adjacent points i, i+1 is
%   curl_i = (Fbr_i+1 - Fbr_i) / y
% with y the straight-line distance between the two points -- along-crest
% coordinates, so no angle/component decomposition is needed. Each crest is
% padded with an Fbr = 0 point one step beyond its first and last real point
% (extrapolated along the local crest direction), so curl is also defined
% between a crest's tip and its pad.

max_crest_link_dist = 2*bin_size;  % beyond this gap, stop tracing -- crest has ended
crest_pad_dist       = 2;    % distance of the Fbr=0 pad point beyond each crest end
min_curl_dist        = 0.5;         % floor on point spacing before curl is computed (avoid /~0)

t_trace = tic;
curl_x = []; curl_y = []; curl_val = [];

% group frame_ID by frame ONCE -- w_by_frame/key2col/uw (the grouping of
% crest_width_time_all) are reused unchanged from the matching section above
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

    % walk each crest in along-crest order; curl between adjacent Fbr points,
    % padded with an Fbr = 0 point one crest_pad_dist beyond each end
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


% BIN + PLOT ALONG-CREST Fbr CURL
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

% n_trim_rows = 1;   % how many alongshore bin rows to blank at each edge         used to remove boundary bins (extremes)
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
xlim([70 300]); ylim([450 1100]) 



%% SINGLE FRAME: Fbr VECTORS + ALONG-CREST CURL (diagnostic, same frame as above)
% Re-runs the same trace/snap/pad/curl steps as the ALONG-CREST Fbr CURL
% section, but only for frame_time, keeping each crest's full point-by-point
% sequence so it can be drawn with its actual connectivity -- the aggregated
% curl_x/curl_y/curl_val arrays don't retain that structure since every
% crest/frame gets flattened together for binning.

% --- pick which frame to inspect here, independent of frame_to_plot above ---
frame_to_plot_diag = min(25, numel(unique_frames));   % index into unique_frames (last video file only)
frame_time = unique_frames(frame_to_plot_diag);
frame_mask = frame_ID == frame_time & ~isnan(Fbr_mag_pts);
rf_idx     = find(frame_times_abs == frame_time, 1);
bg         = S.rectified_frames{rf_idx};
% -----------------------------------------------------------------------

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


%% Fbr VARIABILITY DIAGNOSTIC: which inputs drive the spread in Fbr?
% Fbr = 0.9*g/(c*h*T) * 0.11*W^2*tan(th)*sec(th),    h = c^2/g - tide
% T and theta_r are constants within an hour, so point-to-point (and
% wave-to-wave) variability can only come from W (squared) and c (which
% enters twice: directly, and through h). In log space:
%       ln Fbr = K + 2 ln W - ln c - ln h
% so each term's share of var(ln Fbr) is cov(term, ln Fbr)/var(ln Fbr);
% the shares sum to 1.

sig_c_rel     = 0.10;   % ASSUMED 1-sigma relative uncertainty in c (edit)
sig_W_rel     = 0.20;   % ASSUMED 1-sigma relative uncertainty in W (edit)
min_pts_crest = 5;      % min points for a crest to count in the wave-by-wave stats
h_small       = 0.3;    % [m] flag depths below this (Fbr ~ 1/h blows up)

dv = valid & ~isnan(Fbr_mag_pts) & crest_width_pts > 0;
F  = Fbr_mag_pts(dv);   W = crest_width_pts(dv);
c  = c_pts(dv);         h = h_pts(dv);
fid_d = frame_ID(dv);
K  = log(0.9*g*0.11*tan(theta_r)*sec(theta_r)/T_mean);

lF = log(F);
terms = [2*log(W), -log(c), -log(h)];
term_names = {'2 ln W (crest width)', '-ln c (direct)', '-ln h (h = c^2/g - tide)'};
chk = max(abs(lF - (K + sum(terms,2))));
fprintf('\n===== Fbr VARIABILITY DIAGNOSTIC (%s) =====\n', dateTimeLabel)
fprintf('N points: %d   decomposition check (should be ~0): %.2e\n', numel(F), chk)

cs    = @(a,b) mean((a-mean(a)).*(b-mean(b)));
share = @(Tm,y) arrayfun(@(i) cs(Tm(:,i),y), 1:size(Tm,2)) / cs(y,y);

% ---- 1) variance decomposition, all points -------------------------------
sh_all = share(terms, lF);
fprintf('\n-- Share of var(ln Fbr), all points --\n')
for i = 1:3; fprintf('  %-28s %6.1f %%\n', term_names{i}, 100*sh_all(i)); end
fprintf('  %-28s %6.1f %%  (c direct + via h)\n', 'c total', 100*(sh_all(2)+sh_all(3)))
fprintf('  std(ln Fbr) = %.2f   p90/p10 of Fbr = %.1fx\n', std(lF), prctile(F,90)/prctile(F,10))
fprintf('  corr(ln W, ln c) = %.2f\n', corr(log(W), log(c)))

% ---- 2) local sensitivity (elasticities) + error propagation -------------
E_W = 2*ones(size(F));                    % dlnF/dlnW
E_c = -(1 + 2*(h + tide)./h);             % dlnF/dlnc, since dlnh/dlnc = 2(h+tide)/h
relerr_W = abs(E_W)*sig_W_rel;
relerr_c = abs(E_c)*sig_c_rel;
relerr_tot = hypot(relerr_W, relerr_c);
fprintf('\n-- Local sensitivity --\n')
fprintf('  dlnF/dlnW = 2 (constant)\n')
fprintf('  dlnF/dlnc : median %.1f, p90 %.1f   (a 1%% error in c -> that %% error in Fbr)\n', median(E_c), prctile(E_c,10))
fprintf('  Points with h < %.2f m: %.1f %%\n', h_small, 100*mean(h < h_small))
fprintf('  Propagated rel. error in Fbr (sig_W=%.0f%%, sig_c=%.0f%%): median %.0f %% (W part %.0f %%, c part %.0f %%)\n', ...
    100*sig_W_rel, 100*sig_c_rel, 100*median(relerr_tot), 100*median(relerr_W), 100*median(relerr_c))

% ---- 3) counterfactual: let only one input vary ---------------------------
c0 = median(c);  h0 = c0^2/g - tide;  W0 = median(W);
F_Wonly = exp(K) * W.^2  ./ (c0*h0);      % only W varies
F_conly = exp(K) * W0^2  ./ (c .* h);     % only c varies (direct + via h)
cv = @(x) std(x)/mean(x);
fprintf('\n-- Coefficient of variation of Fbr if only one input varies --\n')
fprintf('  actual %.2f | only W %.2f | only c %.2f\n', cv(F), cv(F_Wonly), cv(F_conly))

% ---- 4) wave-by-wave: rebuild crest IDs, then between vs within crest -----
% (same trace/snap approach as the curl section; uses its frame grouping)
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
[~,~,gi] = unique(gid(sel));
nCrest = max(gi);
fprintf('\n-- Wave-by-wave (%d crests with >= %d pts) --\n', nCrest, min_pts_crest)

crestMean = @(v) accumarray(gi, v, [], @mean);
Ts   = terms(sel,:);   lFs = lF(sel);
Tc   = [crestMean(Ts(:,1)) crestMean(Ts(:,2)) crestMean(Ts(:,3))];
lFc  = crestMean(lFs);
Tw   = Ts - Tc(gi,:);  lFw = lFs - lFc(gi);          % within-crest anomalies

v_tot = cs(lFs,lFs);  v_w = cs(lFw,lFw);  v_b = v_tot - v_w;
fprintf('  var(ln Fbr): %.1f %% between crests, %.1f %% within a crest (along-crest)\n', 100*v_b/v_tot, 100*v_w/v_tot)
sh_b = share(Tc(gi,:), lFc(gi));   % between-crest drivers
sh_w = share(Tw, lFw);             % within-crest drivers
fprintf('  Between-crest drivers :  W %.0f %% | c direct %.0f %% | h %.0f %%\n', 100*sh_b)
fprintf('  Within-crest drivers  :  W %.0f %% | c direct %.0f %% | h %.0f %%\n', 100*sh_w)

% crest-level medians for plotting
W_cr = accumarray(gi, W(sel), [], @median);
c_cr = accumarray(gi, c(sel), [], @median);
F_cr = accumarray(gi, F(sel), [], @median);

% per-frame series
[uf, ~, gf] = unique(posixtime(fid_d));
F_fr = accumarray(gf, F, [], @median);
W_fr = accumarray(gf, W, [], @median);
c_fr = accumarray(gf, c, [], @median);
t_fr = datetime(uf, 'ConvertFrom', 'posixtime');
fprintf('  Frame-to-frame (median per frame): corr(Fbr,W) = %.2f, corr(Fbr,c) = %.2f\n', corr(F_fr,W_fr), corr(F_fr,c_fr))

% % ---- figures ---------------------------------------------------------------
% figure('Name','Fbr diagnostic: all points');
% tiledlayout(2,3,'TileSpacing','compact');
% 
% nexttile
% bar([sh_all(1) sh_all(2) sh_all(3) sh_all(2)+sh_all(3)]*100)
% set(gca,'XTickLabel',{'W^2','c direct','h','c total'}); ylabel('% of var(ln F_{br})')
% title('Variance share'); grid on; box on
% 
% nexttile
% scatter(W, F, 6, c, 'filled'); set(gca,'XScale','log','YScale','log'); colorbar
% xlabel('Crest width W [m]'); ylabel('F_{br}'); title('F_{br} vs W (color = c)'); grid on; box on
% 
% nexttile
% scatter(c, F, 6, h, 'filled'); set(gca,'YScale','log'); colorbar
% xlabel('c [m/s]'); ylabel('F_{br}'); title('F_{br} vs c (color = h)'); grid on; box on
% 
% nexttile
% scatter(h, F, 6, c, 'filled'); set(gca,'YScale','log'); xline(h_small,'r--'); colorbar
% xlabel('h [m]'); ylabel('F_{br}'); title('F_{br} vs h'); grid on; box on
% 
% nexttile
% bar([cv(F) cv(F_Wonly) cv(F_conly)])
% set(gca,'XTickLabel',{'actual','only W varies','only c varies'}); ylabel('std/mean')
% title('CV of F_{br}'); grid on; box on
% 
% nexttile
% histogram(relerr_tot*100, 'FaceColor',[.5 .5 .5], 'EdgeColor','none'); hold on
% histogram(relerr_W*100, 'FaceColor',[0.30 0.55 0.95], 'FaceAlpha',.5, 'EdgeColor','none')
% histogram(relerr_c*100, 'FaceColor',[0.95 0.55 0.20], 'FaceAlpha',.5, 'EdgeColor','none')
% xlabel('Propagated rel. error in F_{br} [%]'); legend('total','from W','from c'); title('Error budget (assumed \sigma)')
% grid on; box on
% sgtitle(sprintf('F_{br} variability drivers - %s', dateTimeLabel))
% 
% figure('Name','Fbr diagnostic: wave-by-wave');
% tiledlayout(1,3,'TileSpacing','compact');
% 
% nexttile
% loglog(W_cr, F_cr, 'o', 'MarkerFaceColor',[0.10 0.30 0.80]); grid on; box on
% xlabel('Crest median W [m]'); ylabel('Crest median F_{br}'); title('Between crests: F_{br} vs W')
% 
% nexttile
% semilogy(c_cr, F_cr, 'o', 'MarkerFaceColor',[0.80 0.30 0.05]); grid on; box on
% xlabel('Crest median c [m/s]'); ylabel('Crest median F_{br}'); title('Between crests: F_{br} vs c')
% 
% nexttile
% yyaxis left;  semilogy(t_fr, F_fr, '-'); ylabel('median F_{br}')
% yyaxis right; plot(t_fr, W_fr, '-'); hold on; plot(t_fr, c_fr, '-'); ylabel('median W [m], c [m/s]')
% legend('F_{br}','W','c'); title('Frame-to-frame'); grid on; box on
% sgtitle(sprintf('Wave-by-wave F_{br} - %s', dateTimeLabel))

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
% TRACE_CREST_PATHS  Along-crest order for an unorganized (x,y) point cloud
% that may contain several separate crests. Each point is chained to its
% nearest not-yet-used neighbor; a crest ends where no neighbor lies within
% max_link_dist (ran out of points), or where the nearest neighbor would
% reverse the direction of travel already established along that crest
% (tracing back up the crest instead of further along it). Each crest's
% arclength s is oriented to increase with y, so curl signs stay consistent
% across crests and frames regardless of which point tracing happened to
% start from.
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
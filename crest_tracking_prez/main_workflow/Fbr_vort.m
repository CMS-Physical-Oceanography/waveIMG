
% Fbr, vort calculations

%% USER INPUTS
dateTag = '1002';
hourStr = '1200';
year_str = '2013';

data_source = 'piv';     % 'raw' or 'piv'

%% LOAD MAT FILE
baseDir = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main'];
matDataDir = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main/mat_data'];
t_load = tic;
S = load(fullfile(matDataDir,sprintf('%s_%s.mat',dateTag,hourStr)));
fprintf('LOAD MAT FILE: %.1f s\n', toc(t_load));
dateTimeLabel = sprintf('%s/%s %s:%s', dateTag(1:2), dateTag(3:4), hourStr(1:2), hourStr(3:4));

%% LOAD CREST WIDTHS.....old
% crest_widths_all = vertcat(S.all_crest_widths{:});
% crest_widths_all = crest_widths_all(~isnan(crest_widths_all));
% crest_widths_all = crest_widths_all(crest_widths_all > 0);

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

%% period and tide
fname = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/' ...
    'RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main/data/buoy_data/duck_offshore_cond.txt'];
opts = detectImportOptions(fname,'NumHeaderLines',2);
T = readtable(fname,opts);
T.Properties.VariableNames = {'YY','MM','DD','hh','mm','WDIR','WSPD','GST','WVHT','DPD','APD','MWD','PRES','ATMP','WTMP','DEWP','VIS','TIDE'};
time = datetime(T.YY,T.MM,T.DD,T.hh,T.mm,0);
yr = str2double(year_str);
mo = str2double(dateTag(1:2));
dy = str2double(dateTag(3:4));
target_day = datetime(yr,mo,dy);
target_hour = str2double(hourStr(1:2));
mask = dateshift(time,'start','day') == target_day & hour(time) == target_hour; % changed from hour(time)
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

theta_r = deg2rad(15); % roller angle, constant of 15 rn

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
title(sprintf('F_{br} Direction - %s %s',dateTimeLabel), 'FontSize', 15)
xlim([90 170]); ylim([610 835])

%% SINGLE FRAME CREST POINT VECTOR FIELD OVER IMAGE

frame_to_plot = 25; % frame of last 5 mins to inspect

% rectified_frames{k} was built from frameTimes(k+1) of the LAST video file processed that hour, so reconstruct 
% that same timestamp vector here to guarantee the background img and the cel/Fbr points line up.
frame_times_abs = S.fileStartStamp + seconds(S.frameTimes(2:S.numberVideoFrames+1));

% keep only celerity points that came from the last video file (the one rectified_frames actually holds) so frame_to_plot indexes consistently
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

% group frame_ID by frame ONCE -- same fix as the matching loop above (this
% loop used to rescan crest_width_time_all/frame_ID with `==` once per unique
% frame, O(F*M)/O(F*N) for F frames). w_by_frame/key2col/uw (the grouping of
% crest_width_time_all) are reused unchanged from the matching section above
% -- that array never changes, no need to regroup it.
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

    % snap each Fbr point onto its nearest traced width point (KD-tree nearest
    % neighbor instead of a per-point loop), inheriting crest ID + position
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
% title(sprintf('\nabla \time F_{br} - %s', dateTimeLabel), 'FontSize', 15)
title(sprintf('\\nabla \\times F_{br} - %s', dateTimeLabel), ...
    'Interpreter', 'tex','FontSize', 15)
xlim([85 170]); ylim([623 827])


%% SINGLE FRAME: Fbr VECTORS + ALONG-CREST CURL (diagnostic, same frame as above)
% Re-runs the same trace/snap/pad/curl steps as the ALONG-CREST Fbr CURL
% section, but only for frame_time, keeping each crest's full point-by-point
% sequence so it can be drawn with its actual connectivity -- the aggregated
% curl_x/curl_y/curl_val arrays don't retain that structure since every
% crest/frame gets flattened together for binning.

% --- pick which frame to inspect here, independent of frame_to_plot above ---
frame_to_plot_diag = 25;                       % index into unique_frames (last video file only)
frame_time = unique_frames(frame_to_plot_diag);
frame_mask = frame_ID == frame_time & ~isnan(Fbr_mag_pts);
rf_idx     = find(frame_times_abs == frame_time, 1);
bg         = S.rectified_frames{rf_idx};
% -----------------------------------------------------------------------

w_mask_1 = crest_width_time_all == frame_time;
wx1 = crest_width_pts_all(w_mask_1,1);
wy1 = crest_width_pts_all(w_mask_1,2);
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
    % plot(xpad1([1 end]), ypad1([1 end]), 'kx', 'MarkerSize',8, 'LineWidth',1.5)  % Fbr=0 pad endpoints

    % scatter(xpad1([1 end]), ypad1([1 end]), 15+300*abs(curl1([1 end]))/curl_scale, curl1([1 end]), ...
    % 'x', 'LineWidth', 2)   % Fbr=0 pad endpoints, colored/sized like the real crest points

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


%% LOCAL FUNCTIONS

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
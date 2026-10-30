
% main flow

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath('/Users/prezleystrait/git/waveIMG/mfiles'));        % functions
addpath(genpath(fullfile(thisDir,'..')), '-begin');                 

% matDataDir = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/rips_onedrive/NSF_Eddies/mat_data/';
% if ~exist(matDataDir,'dir'); mkdir(matDataDir); end            for shared onedrive save...

matDataDir = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS_local/waveIMG_cpy/waveIMG-main/waveIMG-main/mat_data/local_runs/';
if ~exist(matDataDir,'dir'); mkdir(matDataDir); end

% INPUT
year = 2021;
tower = 'north'; % 2021: 'north' or 'south'
runTag    = '_test';    % set to '' for real runs (prevents overwriting saved outputs)
maxFrames = 250;        % used for test runs; set to 'Inf' for full videos

enhance_image = true;    % INPUT: true = water/foam contrast enhancement (Carini et al.)
if enhance_image; runTag = [runTag '_enh']; end    % enhanced runs get their own file names

switch year
    case 2013 
        IDs      = {'rod13'};
        dateTag  = '20131022';        % folder prefix, yyyymmdd
        hourList = 1600;              % -> 20131024_12
        numFiles = 1;                 % each vid is 5 mins, so set to 12 for full hour run
        startIdx = 1;

    case 2021 % dunex
        switch lower(tower)
            case 'north'; IDs = {'top21'};
            case 'south'; IDs = {'bot21'};
            case 'both';  IDs = {'top21','bot21'};
            otherwise;    error('tower must be ''north'', ''south'', or ''both'' (got ''%s'').', tower);
        end
        dateTag  = '20210904_1600';    % prefix, yyyymmdd_hhmm
        hourList = 0; numFiles = 1; startIdx = 1;      
end

for year_ID = 1:length(IDs)
    ID = IDs{year_ID};
    [info, icp, beta0] = define_camera_parameters_new(ID);

    if ~exist(info.base_dir, 'dir')
        error('Video drive not found at %s. Is it plugged in?', info.base_dir);
    end

for hourVal = hourList

    hourStr = sprintf('%04d', hourVal);

    switch info.folder_layout
        case 'datehour_folder'
            videoDir = fullfile(info.base_dir, info.vid_dir, [dateTag '_' hourStr(1:2)]);
        case 'date_hour'
            videoDir = fullfile(info.base_dir, info.vid_dir, dateTag, hourStr);
        otherwise   % 'flat'
            videoDir = fullfile(info.base_dir, info.vid_dir);
    end

    if isempty(info.vid_name_root)
        fileRoot = fullfile(videoDir, '*.mp4');
    else
        fileRoot = fullfile(videoDir, [info.vid_name_root,'_',dateTag,'*.mp4']);
    end

    fileList = dir(fileRoot);
    fileList = fileList(~startsWith({fileList.name}, '.'));   % drop macOS ._ files
    [~, sortIdx] = sort({fileList.name});                     % old script sorted by name
    fileList = fileList(sortIdx);

    if isempty(fileList)
        fprintf('No mp4 files found in %s, skipping hour.\n', videoDir);
        continue
    end

    selectedFiles = fileList(startIdx : min(startIdx + numFiles - 1, length(fileList)));
    firstVideoFile = selectedFiles(1).name;
    [~, firstBaseName] = fileparts(firstVideoFile);
    firstTokens = regexp(firstBaseName, '(\d{8})_(\d{6})', 'tokens');   % no ^ anchor, works for 2021 names too

    firstTokens = regexp(firstBaseName, '(\d{8})_(\d{4,6})', 'tokens');   % time can be hhmm or hhmmss

    if ~isempty(firstTokens) && ~isempty(firstTokens{1})
        firstDateToken = firstTokens{1}{1};
        firstTimeToken = firstTokens{1}{2};
        if numel(firstTimeToken) == 4; firstTimeToken = [firstTimeToken '00']; end   % hhmm -> hhmmss
            hourStartStamp = datetime(firstDateToken, 'InputFormat', 'yyyyMMdd') + hours(str2double(firstTimeToken(1:2))) + ...
                minutes(str2double(firstTimeToken(3:4))) + seconds(str2double(firstTimeToken(5:6)));
    else
        hourStartStamp = datetime('now');
    end

    all_crest_widths = {}; % preallocate storage
    all_crest_width_pts_total  = [];
    all_crest_width_time_total = [];
    all_celerity_total = [];
    all_celerity_time_total = [];
    all_crest_summary = {};

    sensors.q22.intensity = []; % sensor storage, not rlly used
    sensors.q22.probability = [];
    sensors.q22.time = [];
    sensors.videoTimes = {};
    sensors.videoSeconds = [];
    sensors.videoOffsets = [];

    [U, V]   = meshgrid(0:icp.NU-1, 0:icp.NV-1);
    X        = info.X_min:info.X_res:info.X_max;
    Y        = info.Y_min:info.Y_res:info.Y_max;
    [xx, yy] = meshgrid(X, Y);
    z_tide   = zeros(size(xx));
    [Uint, Vint] = getUVfromXYZ(xx, yy, z_tide, icp, beta0);
    Pnon     = 0.15;

% in-situ sensors, not rlly used...
sensors.q22.x = 133.4638;
sensors.q22.y = 824.3041;
[~, sensors.q22.ix] = min(abs(X - sensors.q22.x));
[~, sensors.q22.iy] = min(abs(Y - sensors.q22.y));

for fnum = 1:numel(selectedFiles)

videoFile = selectedFiles(fnum).name;
videoPath = fullfile(videoDir, videoFile);

[~, baseName] = fileparts(videoFile);
tokens = regexp(baseName, '(\d{8})_(\d{4,6})', 'tokens');

if ~isempty(tokens)
    dateToken = tokens{1}{1};
    timeToken = tokens{1}{2};
    if numel(timeToken) == 4; timeToken = [timeToken '00']; end   % hhmm -> hhmmss

    fh = str2double(timeToken(1:2));     % renamed so they don't shadow hour/minute/second
    fm = str2double(timeToken(3:4));
    fs = str2double(timeToken(5:6));

    fileStartStamp = datetime(dateToken, 'InputFormat', 'yyyyMMdd') + hours(fh) + minutes(fm) + seconds(fs);

    sensors.videoTimes{fnum} = sprintf('%02d:%02d:%02d', fh, fm, fs);
    sensors.videoSeconds(end+1) = fs;
    sensors.videoOffsets(end+1) = fm*60 + fs;
    sensors.videoStartStamps(fnum) = fileStartStamp;
else
    error('Could not parse date/time from file: %s', videoFile);
end
fprintf('\n=== Processing file %d/%d: %s ===\n', fnum, numel(selectedFiles), videoFile);

if ~exist(videoPath, 'file')
    warning('Missing video file, skipping: %s', videoPath);
    continue
end

try
    vid = VideoReader(videoPath);
catch
    warning('Could not open video file, skipping: %s', videoPath);
    continue
end

% vid processing setup
vidHz = vid.FrameRate;
invRate = 1;
dt = invRate / vidHz;
numberVideoFrames = length(1:invRate:vid.NumFrames);

X_front_store    = cell(1, numberVideoFrames);
Y_front_store    = cell(1, numberVideoFrames);
W_front_store    = cell(1, numberVideoFrames);
rectified_frames = cell(1, numberVideoFrames);
crest_summary    = cell(1, numberVideoFrames);
totalFramesNeeded = min(numberVideoFrames + 2, maxFrames);

vid.CurrentTime = 0;
rect_all   = {};                      % every frame, already rectified (small grid); replaces rawFrames
frameTimes = [];
IMG     = zeros([size(xx), 3]);
Ny_grid = size(xx, 1);
Nx_grid = size(xx, 2);
f = 0;

while hasFrame(vid) && f < totalFramesNeeded
    f = f + 1;
    frameTimes(f) = vid.CurrentTime;
    raw  = double(rgb2gray(readFrame(vid)));                        % full-res frame, temporary
    rect = interp2(U, V, raw, Uint, Vint, 'linear', nan);           % rectified frame
    
    if enhance_image
        if f == 1    % threshold from the first frame, held fixed for the whole video
            foam_th = water_foam_threshold(rect(~isnan(rect)), 0);  % NaNs (outside footprint) excluded; 0 = no plot
            fprintf('  foam/water threshold: %.1f\n', foam_th);
        end
        rect = 255./(1+exp(-3*pi/2*(rect-foam_th)/(255-foam_th)));  % sigmoid stretch; NaNs stay NaN
    end

    rect_all{f} = rect;

    if f < 3; continue; end                                         % need 3 frames before the first stack

    k = f - 2;                                                      % same k as before: stack = frames k, k+1, k+2
    IMG(:,:,1) = rect_all{k};
    IMG(:,:,2) = rect_all{k+1};
    IMG(:,:,3) = rect_all{k+2};

    rectified_frames{k} = IMG(:,:,2);
    [~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

    sensors.q22.intensity(end+1)   = IMG(sensors.q22.iy, sensors.q22.ix, 2);
    sensors.q22.probability(end+1) = prob(sensors.q22.iy, sensors.q22.ix);
    sensors.q22.time(end+1) = seconds(fileStartStamp - hourStartStamp) + frameTimes(k+1);

    [rclog, rcsummary] = bore_front_search_length(prob', info.Ny, info.Nx, 1, Pnon, X, Y);
    crest_summary{k} = rcsummary;

    W_sub = [];
    for ll = 1:length(rclog)
        W_sub = cat(1, W_sub, rclog{ll}(:,5));
    end
    X_sub = []; Y_sub = [];
    for ll = 1:length(rclog)
        X_sub = cat(1, X_sub, rclog{ll}(:,3));
        Y_sub = cat(1, Y_sub, rclog{ll}(:,4));
    end
    X_front_store{k} = X_sub;
    Y_front_store{k} = Y_sub;
    W_front_store{k} = W_sub;
end

actualFrames = f;
if actualFrames < 3
    warning('Only %d frames read from %s, skipping.', actualFrames, videoFile);
    continue
end
numberVideoFrames = actualFrames - 2;


% separate fronts via DBSCAN
separated_fronts = cell(1, numberVideoFrames);
crest_widths = cell(1, numberVideoFrames);  % new, parallel array for widths
crest_width_pts = cell(1, numberVideoFrames);  

for k = 1:numberVideoFrames

    X_temp = X_front_store{k}; % all CS pos for frame k
    Y_temp = Y_front_store{k}; % all AS ''
    W_temp = W_front_store{k};   % crest widths for this frame

    pts     = [X_temp(:), Y_temp(:)];
    if isempty(pts)
        separated_fronts{k} = {};
        crest_widths{k}     = [];
        crest_width_pts{k}  = [];
        continue
    end

    epsilon = 5 * info.Y_res; % neighborhood search radius (m) %    prev 4
    minPts  = 3; % min pts to be cons a core point of a cluster     prev 4

    % DBSCAN — returns a label vector the same length as pts
    % label = -1  : noise point, not part of any cluster
    % label =  1  : belongs to cluster 1
    % label =  2  : belongs to cluster 2  ...etc
    % DBSCAN works by:
    %   1. pick an unvisited point
    %   2. find all points within epsilon of it
    %   3. if >= minPts neighbours found — start a new cluster, add them all
    %   4. for each new cluster member, repeat the neighbour search
    %   5. keep expanding until no new points are reachable
    %   6. any point never reached by any cluster = noise, label -1

    labels  = dbscan(pts, epsilon, minPts);
    clusterIDs   = unique(labels(labels > 0));
    final_fronts = {};
    fcount       = 0;

    for c = 1:length(clusterIDs) % loop over each cluster
        mask = labels == clusterIDs(c);
        fx   = X_temp(mask);
        fy   = Y_temp(mask);
   
        if numel(fx) < 13; continue; end % rejects clusters w < 13pts.............was 25 on 8/27
        AS_extent = max(fy) - min(fy); % reject non-elongated fronts (blobs)
        CS_extent = max(fx) - min(fx);
        if AS_extent < 5 * info.Y_res && CS_extent < 5 * info.X_res
            continue
        end
        fcount = fcount + 1; % store as front
        final_fronts{fcount}.x = fx;
        final_fronts{fcount}.y = fy;
        final_fronts{fcount}.width = W_temp(mask);  % store widths for this cluster
    end

    if isempty(final_fronts)
        separated_fronts{k} = {};
        continue
    end
    filtered_fronts     = final_fronts(cellfun(@(f) numel(f.x) >= 10, final_fronts)); % remove fronts w fewer than 10 pts as safety net
    separated_fronts{k} = filtered_fronts;

    filtered_idx = cellfun(@(f) numel(f.x) >= 10, final_fronts);
    crest_widths{k} = [];
    crest_width_pts{k} = [];
    for i = find(filtered_idx)
        crest_widths{k} = [crest_widths{k}; final_fronts{i}.width];
    end    
    for i = find(filtered_idx)   % add this whole loop
    crest_width_pts{k} = [crest_width_pts{k}; final_fronts{i}.x(:), final_fronts{i}.y(:), final_fronts{i}.width(:)];
    end
end

% track fronts across frames (trying to see continuity) -- doesn't work great
maxIDs       = 2000;
globalColors = lines(maxIDs);
frontIDs     = cell(1, numberVideoFrames); % stores ID of each front in each frame
nextID       = 1; % counter for next ID

for k = 1:numberVideoFrames

    fronts_k = separated_fronts{k};

    if isempty(fronts_k) || ~iscell(fronts_k) % skip if no fronts detected
        frontIDs{k} = [];
        continue
    end

    if k == 1 % first frame case
        N           = length(fronts_k);
        frontIDs{k} = 1:N;
        nextID      = N + 1;
        continue
    end

    fronts_prev = separated_fronts{k-1};

    if isempty(fronts_prev) || ~iscell(fronts_prev) % assign IDs if nothing to match in prev
        N           = length(fronts_k);
        frontIDs{k} = nextID:(nextID+N-1);
        nextID      = nextID + N;
        continue
    end

    IDs_prev = frontIDs{k-1}; % IDs assigned in prev frame
    IDs_k    = zeros(1, length(fronts_k)); % IDs to assign in current frame

    for i = 1:length(fronts_k) % loop to find matching front in prev frame
        xi_min  = min(fronts_k{i}.x); % get CS min and max of fronts
        xi_max  = max(fronts_k{i}.x);
        yi_mean = mean(fronts_k{i}.y); % AS mean of front
        best_score = inf; % tracks best found match
        best_match = -1; % indx into fronts_prev of best match

        for j = 1:length(fronts_prev) % loop over every front in prev frame as candidate match
            xj_min  = min(fronts_prev{j}.x);
            xj_max  = max(fronts_prev{j}.x);
            yj_mean = mean(fronts_prev{j}.y);

            overlap = min(xi_max, xj_max) - max(xi_min, xj_min); % detect CS overlap
            if overlap <= 0; continue; end

            score = abs(yi_mean - yj_mean); % detect AS proximity
            if score < best_score
                best_score = score;
                best_match = j;
            end
        end
        y_match_thresh = 50 * info.Y_res; % max AS centroid proximity
        if best_match > 0 && best_score < y_match_thresh % assign same ID if good match
            IDs_k(i) = IDs_prev(best_match);
        else
            IDs_k(i) = nextID; % assign new ID if new
            nextID   = nextID + 1;
        end
    end
    frontIDs{k} = IDs_k;
end


% compute cross-shore velocities (cx); still needed for filtering out low cx for tracking animation...
vel_store = cell(1, numberVideoFrames-1);
y_tol     = 0.5 * info.Y_res; % w/in half a grid cell of dy, Y_res = 0.8923 m
u_min     = 0.15; % reject < 15 cm/s
u_max     = 5; % reject speeds > 5m/s

for k = 1:numberVideoFrames-1 % loop over every consectutive frame pair

    fronts_k   = separated_fronts{k}; % fronts in current frame (still in clusters)
    fronts_kp1 = separated_fronts{k+1}; % fronts in next frame

    if isempty(fronts_k) || isempty(fronts_kp1) % skip if either frame has no fronts detected
        vel_store{k} = [];
        continue
    end

    vel_pts = []; % [x, y, u]
    x2_all = []; % flattens all next frame fronts into one searchable cloud (removes DBscan separation)
    y2_all = [];
    for j = 1:length(fronts_kp1)
        x2_all = [x2_all; fronts_kp1{j}.x(:)];
        y2_all = [y2_all; fronts_kp1{j}.y(:)];
    end
    claimed = false(size(x2_all)); % pts can't be repeatedly mapped to

    for i = 1:length(fronts_k) % loop over every clustered front in frame

        x1 = fronts_k{i}.x; % CS pos's of pts in front i
        y1 = fronts_k{i}.y; % AS ^

        for p = 1:length(x1) % loop over individual pts in front

            xp = x1(p); % CS pos of current pt
            yp = y1(p);

            y_mask = abs(y2_all - yp) < y_tol; % find pts w/in y thresh
            if ~any(y_mask); continue; end

            dx    = x2_all(y_mask) - xp; % CS displacement of each candidate
            valid = dx < 0; % enforce onshore motion only
            if ~any(valid); continue; end % no valid onshore candidates

            orig_indices = find(y_mask); % gets OG indices for matching
            orig_indices = orig_indices(valid);
            dx_valid     = dx(valid); % keep only valid + onshore displacements

            not_claimed  = ~claimed(orig_indices); % excludes already claimed next frame pts
            if ~any(not_claimed); continue; end
            orig_indices = orig_indices(not_claimed); % keep only unclaimed candidates
            dx_valid     = dx_valid(not_claimed);

            [~, idx]  = min(abs(dx_valid)); % pick nearest onshore candidate
            best_orig = orig_indices(idx);

            x_match = x2_all(best_orig); % get phys coords
            claimed(best_orig) = true; % mark as claimed

            u = -(x_match - xp) / dt; % compute vel

            if u > u_min && u < u_max
                vel_pts = [vel_pts; xp, yp, u]; % vel threshold filter
            end
        end
    end
    vel_store{k} = vel_pts; % stores all valid vel pts
end


% build velocity-filtered front positions for plotting
separated_fronts_filtered = cell(1, numberVideoFrames);

for k = 1:numberVideoFrames-1
    vpts = vel_store{k};
    if isempty(vpts)
        separated_fronts_filtered{k} = {};
        continue
    end

    fronts_k = separated_fronts{k};
    filtered = {};
    fcount   = 0;

    for i = 1:length(fronts_k)
        x1 = fronts_k{i}.x;
        y1 = fronts_k{i}.y;

        % keep only pts from this front that appear in vel_store
        keep = false(size(x1));
        for p = 1:length(x1)
            % match on x,y position (vel_store cols 1,2 are xp,yp from frame k)
            match = abs(vpts(:,1) - x1(p)) < 1e-6 & abs(vpts(:,2) - y1(p)) < 1e-6;
            if any(match)
                keep(p) = true;
            end
        end

        if sum(keep) < 2; continue; end
        fcount = fcount + 1;
        filtered{fcount}.x = x1(keep);
        filtered{fcount}.y = y1(keep);
    end
    separated_fronts_filtered{k} = filtered;
end
separated_fronts_filtered{end} = {}; % last frame has no velocity pair


% full crest celerity from normal-crest intersections (all frames)
all_celerity = [];    % [x, y, cx, cy, celerity mag] for all valid crest matches
all_celerity_time = []; % store timestamps of c points
max_dy   = 5;   % max AS gap b/w neighboring crest pts
max_dx   = 5;   % ^ CS
ray_len  = 20;  % half length of crest-normal vector [m]
max_disp = 4;   % max allowed crest displacement b/w frames [m]

for k = 2:numberVideoFrames-1

    fronts_k   = separated_fronts_filtered{k};
    fronts_kp1 = separated_fronts_filtered{k+1};

    if isempty(fronts_k) || isempty(fronts_kp1)
        continue
    end

    intersections = [];
    kp1_fronts_sorted = cell(size(fronts_kp1)); % sort all frame k+1 fronts

    for i = 1:length(fronts_kp1)

        [y_sorted,idx] = sort(fronts_kp1{i}.y); % sort crest pts AS
        kp1_fronts_sorted{i}.x = fronts_kp1{i}.x(idx);
        kp1_fronts_sorted{i}.y = y_sorted;
    end

    for i = 1:length(fronts_k)

        x_pts = fronts_k{i}.x;
        y_pts = fronts_k{i}.y;

        if numel(y_pts) < 2
            continue
        end

        [y_sorted,idx] = sort(y_pts);
        x_sorted = x_pts(idx);

        dx = diff(x_sorted);
        dy = diff(y_sorted);
        seg_len = hypot(dx,dy);

        nx = -dy ./ seg_len; % unit normal x comp
        ny =  dx ./ seg_len; % ^ y

        x_mid = 0.5*(x_sorted(1:end-1)+x_sorted(2:end)); % crest seg midpoints
        y_mid = 0.5*(y_sorted(1:end-1)+y_sorted(2:end));

        for p = 1:length(x_mid)

            if nx(p) > 0 % force normal to point onshore
                nx(p) = -nx(p);
                ny(p) = -ny(p);
            end

            if (x_mid(p)+ray_len*nx(p)) > x_mid(p) % 2nd onshore direction check
                nx(p) = -nx(p);
                ny(p) = -ny(p);
            end

            x1 = x_mid(p)-ray_len*nx(p); % ray onshore endpt
            y1 = y_mid(p)-ray_len*ny(p);

            x2 = x_mid(p)+ray_len*nx(p); % ray offshore endpt
            y2 = y_mid(p)+ray_len*ny(p);

            dx_ray = x2-x1; % ray direction vector, x comp
            dy_ray = y2-y1;

            best_t = inf; % stores closest valid intersection along ray
            best_int = []; % coords of chosen intersection

            for fi = 1:length(kp1_fronts_sorted)

                x_kp1 = kp1_fronts_sorted{fi}.x; % sort crest x-comp pts
                y_kp1 = kp1_fronts_sorted{fi}.y;

                for s = 1:length(x_kp1)-1 % loop thru sorted pts in k+1

                    if abs(y_kp1(s+1)-y_kp1(s)) > max_dy || abs(x_kp1(s+1)-x_kp1(s)) > max_dx
                        continue % reject long crest segs
                    end

                    x3 = x_kp1(s); % first endpt of frame k+1 crest segment
                    y3 = y_kp1(s);

                    x4 = x_kp1(s+1); % second endpoint of frame k+1 crest seg
                    y4 = y_kp1(s+1);

                    dx_seg = x4-x3; % crest seg tangent vector x-comp
                    dy_seg = y4-y3;

                    denom = dx_ray*dy_seg - dy_ray*dx_seg; % 2D cross product: 0 -> parallel
                    if abs(denom) < 1e-10
                        continue % ray and crest are parallel
                    end

                    t = ((x3-x1)*dy_seg - (y3-y1)*dx_seg)/denom; % ray coord of intersection using Cramer's Law for 2x2 sys
                    u = ((x3-x1)*dy_ray - (y3-y1)*dx_ray)/denom; % crest coord of int

                    if u<0 || u>1 || t<0 || t>1 || t<0.5 % t<0.5 for onshore side of ray
                        continue % intersection not on crest seg
                    end

                    if abs(t-0.5) < abs(best_t-0.5) % choose intersection nearest original crest in frame k (minimizes displacemen)

                        best_t = t;
                        best_int = [x1+t*dx_ray , y1+t*dy_ray ]; % coords of ray & crest seg intersection
                    end
                end
            end

            if ~isempty(best_int)

                dx_disp = best_int(1)-x_mid(p); % CS displ from frame k->k+1
                dy_disp = best_int(2)-y_mid(p); % AS ^
                disp_dist = hypot(dx_disp,dy_disp); % crest displacement magnitude

                if dx_disp < 0 && disp_dist < max_disp % onshore and physically realistic

                    intersections = [intersections; x_mid(p), y_mid(p), best_int(1), best_int(2)];
                end
            end
        end
    end

    % if ~isempty(intersections)
    %     disp_dist = hypot(intersections(:,3)-intersections(:,1),intersections(:,4)-intersections(:,2));
    %     celerity = disp_dist ./ dt; % crest speed from displacement / dt
    %     all_celerity = [all_celerity; intersections(:,1), intersections(:,2), celerity];
    %     all_celerity_time = [all_celerity_time; repmat(fileStartStamp + seconds(frameTimes(k+1)), size(intersections,1), 1)];
    % end

    if ~isempty(intersections)
    dx_disp   = intersections(:,3) - intersections(:,1);
    dy_disp   = intersections(:,4) - intersections(:,2);
    disp_dist = hypot(dx_disp, dy_disp);
    celerity  = disp_dist ./ dt;

    cx = -dx_disp ./ dt;   % cross-shore component, onshore = positive (matches your u_min/u_max convention elsewhere)
    cy =  dy_disp ./ dt;   % alongshore component
    all_celerity = [all_celerity; intersections(:,1), intersections(:,2), cx, cy, celerity];
    all_celerity_time = [all_celerity_time; repmat(fileStartStamp + seconds(frameTimes(k+1)), size(intersections,1), 1)];
end
    fprintf('Frame %d: %d intersections\n', k, size(intersections,1));
end
    all_crest_summary = [all_crest_summary crest_summary]; % new for crest lengths ******************************
    all_crest_widths = [all_crest_widths crest_widths]; % new for crest widths all vid files ***
    for k = 1:numberVideoFrames   % add this whole block
        if isempty(crest_width_pts{k}); continue; end
        n = size(crest_width_pts{k}, 1);
        all_crest_width_pts_total  = [all_crest_width_pts_total; crest_width_pts{k}];
        all_crest_width_time_total = [all_crest_width_time_total; repmat(fileStartStamp + seconds(frameTimes(k+1)), n, 1)];
    end
    all_celerity_total = [all_celerity_total; all_celerity];
    all_celerity_time_total = [all_celerity_time_total; all_celerity_time];
    fprintf('  File %s done. Cumulative celerity points: %d\n', videoFile, size(all_celerity_total,1));
end

all_celerity = all_celerity_total; % final output
fprintf('\n=== DONE: %d total files processed, %d total celerity points ===\n', numel(selectedFiles), size(all_celerity,1));

% label each run by tower
switch ID
    case 'top21';  towerTag = 'NorthTower';
    case 'bot21';  towerTag = 'SouthTower';
    otherwise;     towerTag = ID;
end

sensorFileTag = sprintf('%s_%s_%s', towerTag, dateTag, hourStr);
sensorSaveDir = fullfile(matDataDir, 'sensor_timeseries');
if ~exist(sensorSaveDir,'dir'); mkdir(sensorSaveDir); end

save(fullfile(sensorSaveDir, ['sensor_' sensorFileTag runTag '.mat']), 'sensors')   % IMG props at sensor locs

% save the whole workspace except rawFrames (everything else is kept, incl. rectified_frames)
matOut = fullfile(matDataDir, sprintf('%s_%s_%s%s.mat', towerTag, dateTag, hourStr, runTag));
save(matOut, '-regexp', '^(?!rawFrames$).', '-v7.3');
fprintf('Saved %s workspace (no rawFrames) to %s\n', towerTag, matOut);

end   % end hourVal loop
end   % end year_ID loop ... video processing done



%% cumulative spatial distribution of celerity
figure; hold on;
colormap(parula);
scatter(all_celerity_total(:,1), all_celerity_total(:,2), 2, all_celerity_total(:,3), 'filled');
cb = colorbar; cb.Label.String = 'Celerity [m/s]';
clim([0 6]);
title('Celerity Distribution - 10/02, 13:00', FontSize=13);
xlabel('x (m)'); ylabel('y (m)');
box on; grid minor;
xlim([85 190]); ylim([605 1000]);

% bathy from celerity using linear theory
g = 9.81;
depth = all_celerity(:,5).^2 ./ g;
figure; hold on;
colormap(parula)
scatter(all_celerity(:,1), all_celerity(:,2), 2, depth, 'filled');
cb = colorbar;
cb.Label.String = 'Depth [m]';
clim([0 3]);  % depth range
title('Estimated Bathy from Celerity - 10/02')
xlabel('Cross-Shore [m]')
ylabel('Alongshore [m]')
box on; grid minor
axis equal tight;

% celerity histogram
figure;
edges = 0:0.2:6; 
h_hist = histogram(all_celerity(:,3), edges, 'FaceColor', 'b', 'EdgeColor', 'none','Normalization', 'probability');
hold on;
c_mean   = mean(all_celerity(:,3));
c_median = median(all_celerity(:,3));
h_mean   = xline(c_mean,   'r-',  'LineWidth', 2);
h_median = xline(c_median, 'y--', 'LineWidth', 2);
legend([h_hist, h_mean, h_median],{'Celerity distribution', sprintf('Mean = %.2f m/s',c_mean), sprintf('Median = %.2f m/s', c_median)},'Location', 'best');
xlabel('Celerity [m/s]'); ylabel('Frequency');
title('Distribution of Celerity (c) - all frames');
xlim([u_min u_max]);
grid on; box on;

fprintf('--- Celerity statistics (all frames) ---\n') % print celerity stats
fprintf('N points : %d\n',       size(all_celerity, 1))
fprintf('Mean     : %.3f m/s\n', mean(all_celerity(:,3)))
fprintf('Median   : %.3f m/s\n', median(all_celerity(:,3)))
fprintf('Std dev  : %.3f m/s\n', std(all_celerity(:,3)))
fprintf('Min      : %.3f m/s\n', min(all_celerity(:,3)))
fprintf('Max      : %.3f m/s\n', max(all_celerity(:,3)))

%% animated plot — tracked fronts
animFronts = separated_fronts_filtered;   % or separated_fronts for every detected front

% x_q22 = 133.4638;  y_q22 = 824.3041; % pressure sensor loc for ref

figAnim = figure('Name','Tracked fronts','Renderer','painters');
axAnim  = axes('Parent', figAnim);

for kk = 1:numberVideoFrames
    if ~ishandle(figAnim); break; end
    if isempty(rectified_frames{kk}); continue; end

    cla(axAnim);
    imagesc(axAnim, X, Y, rectified_frames{kk});
    set(axAnim, 'YDir', 'normal');          % Y increases upward
    colormap(axAnim, gray);
    hold(axAnim, 'on');
    % plot(axAnim, x_q22, y_q22, 'rp', 'MarkerSize', 10, 'MarkerFaceColor', 'r');

    fr = animFronts{kk};
    for ii = 1:numel(fr)
        plot(axAnim, fr{ii}.x, fr{ii}.y, 'r.', 'MarkerSize', 8);
    end
    hold(axAnim, 'off');

    title(axAnim, sprintf('Tracked fronts - frame %d / %d', kk, numberVideoFrames));
    % fprintf('frame %d\n', kk);              % progress: should count up in the Command Window
    pause(0.1);                             % pause alone flushes graphics; no separate drawnow
end

%%
% plot cx spatial distribution
% non_empty = vel_store(~cellfun(@isempty, vel_store));
% all_vel   = vertcat(non_empty{:});
% 
% figure; hold on
% colormap(parula)
% scatter(all_vel(:,1), all_vel(:,2), 8, all_vel(:,3), 'filled')
% cb = colorbar; cb.Label.String = 'Onshore Velocity [m/s]';
% caxis([0 5])
% title('Onshore Velocity Distribution')
% xlabel('Cross-shore (m)'); xlim([79 249]);
% ylabel('Alongshore (m)')

% %% plot cx histogram
% edges = 0:0.2:7;
% figure;
% h_hist = histogram(all_vel(:,3), edges, 'FaceColor', 'b', 'EdgeColor', 'none', 'Normalization','probability');
% hold on
% m_mean = mean(all_vel(:,3)); 
% m_median = median(all_vel(:,3));
% h_mean = xline(m_mean,   'r-',  'LineWidth', 2);
% h_median = xline(m_median, 'y--', 'LineWidth', 2);
% legend([h_hist, h_mean, h_median], {'Velocity distribution', sprintf('Mean = %.2f m/s', m_mean), ...
%      sprintf('Median = %.2f m/s', m_median)}, 'Location', 'best')
% xlabel('Onshore Celerity [m/s]'); ylabel('Frequency')
% title('Distribution of Onshore Celerity (c_x) - all frames')
% xlim([u_min u_max])
% grid on; box on
% 
% fprintf('--- Velocity statistics ---\n') % print summary stats to command window
% fprintf('N points : %d\n',       size(all_vel,1))
% fprintf('Mean     : %.3f m/s\n', mean(all_vel(:,3)))
% fprintf('Median   : %.3f m/s\n', median(all_vel(:,3)))
% fprintf('Std dev  : %.3f m/s\n', std(all_vel(:,3)))
% fprintf('Min      : %.3f m/s\n', min(all_vel(:,3)))
% fprintf('Max      : %.3f m/s\n', max(all_vel(:,3)))
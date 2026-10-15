
function [celerity_all, celerity_time_all, crestWidths_all, crestLengths_all, tide_all] = ...
    fn_main_flow(dateTag, hourList, numFiles, year_str)

% FN_MAIN_FLOW  Runs wave-front detection + celerity tracking across 1 or more hour subfolders for a given date.
%
% INPUTS:
%   dateTag   - 'MMDD' string, e.g. '1002'
%   hourList  - vector of hours to process, e.g. 1100:100:1300
%   numFiles  - # of video files per hour folder (default 12, 5-min files)
%   year_str  - 'YYYY' string, e.g. '2013' (used for tide lookup only)
%
% OUTPUTS:
%   celerity_all       - [x, y, cx, cy, celerity] across all processed hours
%   celerity_time_all  - datetime, one per row of celerity_all
%   crestWidths_all    - vector of all crest widths across all hours
%   crestLengths_all   - vector of all crest lengths across all hours
%   tide_all           - [hourVal, tide] array, one row per hour processed
%
% Also saves per-hour .mat files (sensor timeseries + full workspace)

if nargin < 3 || isempty(numFiles)
    numFiles = 12;
end
if nargin < 4 || isempty(year_str)
    year_str = '2013';
end

startIdx = 1;
addpath(genpath('../'));
[info, icp, beta0] = define_camera_parameters();
baseDataDir = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/data';
matDataDir  = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/mat_data';
tideFile    = fullfile(fileparts(matDataDir), 'data', 'tide_duck', 'duck_waterLvls2013.csv');

% fixed grid setup 
[U, V]   = meshgrid(0:icp.NU-1, 0:icp.NV-1);
X        = info.X_min:info.X_res:info.X_max;
Y        = info.Y_min:info.Y_res:info.Y_max;
[xx, yy] = meshgrid(X, Y);
z_tide   = zeros(size(xx));
[Uint, Vint] = getUVfromXYZ(xx, yy, z_tide, icp, beta0);
Pnon     = 0.15;

sensors_template.q22.x = 133.4638; % sensor q22 coords
sensors_template.q22.y = 824.3041;
[~, sensors_template.q22.ix] = min(abs(X - sensors_template.q22.x));
[~, sensors_template.q22.iy] = min(abs(Y - sensors_template.q22.y));

% tide lookup table
Ttide = readtable(tideFile, 'TextType', 'string');
tideDate = datetime(Ttide.Date, 'InputFormat', 'yyyy/MM/dd');
tideTimeOfDay = duration(Ttide.Time_LST_LDT_, 'InputFormat', 'hh:mm');
tideTime = tideDate + tideTimeOfDay;
waterLevel = Ttide.Verified_m_;

% accumulators across all hours in hourList
celerity_all      = [];
celerity_time_all = [];
crestWidths_all = [];
crestLengths_all = [];
crestWidths_all_cells  = {};   % kept as cell array to match reference plotting code style
crestSummary_all_cells = {};   % same, holds struct arrays per frame
tide_all          = [];

for hourVal = hourList

    hourStr = sprintf('%04d', hourVal);
    videoDir = fullfile(baseDataDir, dateTag, hourStr);

    if ~exist(videoDir, 'dir')
        fprintf('Skipping missing folder: %s\n', videoDir);
        continue
    end

    fileList = dir(fullfile(videoDir, '*.mp4'));
    [~, sortIdx] = sort({fileList.name});
    fileList = fileList(sortIdx);

    if isempty(fileList)
        fprintf('No mp4 files found in %s, skipping hour.\n', videoDir);
        continue
    end

    selectedFiles = fileList(startIdx : min(startIdx + numFiles - 1, length(fileList)));
    firstVideoFile = selectedFiles(1).name;
    [~, firstBaseName] = fileparts(firstVideoFile);
    firstTokens = regexp(firstBaseName, '^(\d{8})_(\d{6})_', 'tokens');

    if ~isempty(firstTokens) && ~isempty(firstTokens{1})
        firstDateToken = firstTokens{1}{1};
        firstTimeToken = firstTokens{1}{2};
        hourStartStamp = datetime(firstDateToken, 'InputFormat', 'yyyyMMdd') + hours(str2double(firstTimeToken(1:2))) + ...
            minutes(str2double(firstTimeToken(3:4))) + seconds(str2double(firstTimeToken(5:6)));
    else
        hourStartStamp = datetime('now');
    end

    all_crest_widths        = {};
    all_celerity_total       = [];
    all_crest_width_pts_total  = [];
    all_crest_width_time_total  = [];
    all_celerity_time_total  = [];
    all_crest_summary        = {};

    sensors = sensors_template;
    sensors.q22.intensity = [];
    sensors.q22.probability = [];
    sensors.q22.time = [];
    sensors.videoTimes = {};
    sensors.videoSeconds = [];
    sensors.videoOffsets = [];

    for fnum = 1:numel(selectedFiles)

        videoFile = selectedFiles(fnum).name;
        videoPath = fullfile(videoDir, videoFile);

        [~, baseName] = fileparts(videoFile);
        tokens = regexp(baseName, '^(\d{8})_(\d{6})_', 'tokens');

        if ~isempty(tokens)
            if iscell(tokens{1}) && numel(tokens{1}) >= 2
                dateToken = tokens{1}{1};
                timeToken = tokens{1}{2};
            elseif iscell(tokens) && numel(tokens) >= 2
                dateToken = tokens{1};
                timeToken = tokens{2};
            else
                error('Could not parse date/time from file: %s', videoFile);
            end

            hour   = str2double(timeToken(1:2));
            minute = str2double(timeToken(3:4));
            second = str2double(timeToken(5:6));

            fileStartStamp = datetime(dateToken, 'InputFormat', 'yyyyMMdd') + hours(hour) + minutes(minute) + seconds(second);

            sensors.videoTimes{fnum} = sprintf('%02d:%02d:%02d', hour, minute, second);
            sensors.videoSeconds(end+1) = second;
            sensors.videoOffsets(end+1) = minute*60 + second;
            sensors.videoStartStamps(fnum) = fileStartStamp;
        else
            sensors.videoTimes{fnum} = 'unknown';
            sensors.videoSeconds(end+1) = NaN;
            sensors.videoOffsets(end+1) = NaN;
        end

        fprintf('\n=== Processing file %d/%d: %s ===\n', fnum, numFiles, videoFile);

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

        vidHz = vid.FrameRate;
        invRate = 1;
        dt = invRate / vidHz;
        numberVideoFrames = length(1:invRate:vid.NumFrames);

        X_front_store    = cell(1, numberVideoFrames);
        Y_front_store    = cell(1, numberVideoFrames);
        W_front_store    = cell(1, numberVideoFrames);
        rectified_frames = cell(1, numberVideoFrames);
        crest_summary    = cell(1, numberVideoFrames);
        totalFramesNeeded = numberVideoFrames + 2;

        vid.CurrentTime = 0;
        rawFrames = {};
        frameTimes = [];
        f = 0;
        while hasFrame(vid) && f < totalFramesNeeded
            f = f + 1;
            frameTimes(f) = vid.CurrentTime;
            IMG = rgb2gray(readFrame(vid));
            rawFrames{f} = double(IMG); 
        end

        actualFrames = numel(rawFrames);
        if actualFrames < 3
            warning('Only %d frames read from %s, skipping.', actualFrames, videoFile);
            continue
        end
        numberVideoFrames = actualFrames - 2;

        IMG = zeros([size(xx), 3]);

        for k = 1:numberVideoFrames
            for ii = 1:3
                IMG(:,:,ii) = interp2(U, V, rawFrames{k+ii-1}, Uint, Vint, 'linear', nan);
            end
            rectified_frames{k} = IMG(:,:,2);
            [~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

            sensors.q22.intensity(end+1) = IMG(sensors.q22.iy, sensors.q22.ix, 2);
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

        separated_fronts = cell(1, numberVideoFrames);
        crest_widths = cell(1, numberVideoFrames);
        crest_width_pts = cell(1, numberVideoFrames);   

        for k = 1:numberVideoFrames
            X_temp = X_front_store{k};
            Y_temp = Y_front_store{k};
            W_temp = W_front_store{k};

            pts     = [X_temp(:), Y_temp(:)];
            epsilon = 5 * info.Y_res;
            minPts  = 3;

            labels  = dbscan(pts, epsilon, minPts);
            clusterIDs   = unique(labels(labels > 0));
            final_fronts = {};
            fcount       = 0;

            for c = 1:length(clusterIDs)
                mask = labels == clusterIDs(c);
                fx   = X_temp(mask);
                fy   = Y_temp(mask);

                if numel(fx) < 25; continue; end
                AS_extent = max(fy) - min(fy);
                CS_extent = max(fx) - min(fx);
                if AS_extent < 5 * info.Y_res && CS_extent < 5 * info.X_res
                    continue
                end
                fcount = fcount + 1;
                final_fronts{fcount}.x = fx;
                final_fronts{fcount}.y = fy;
                final_fronts{fcount}.width = W_temp(mask);
            end

            if isempty(final_fronts)
                separated_fronts{k} = {};
                continue
            end
            filtered_fronts     = final_fronts(cellfun(@(f) numel(f.x) >= 10, final_fronts));
            separated_fronts{k} = filtered_fronts;

            filtered_idx = cellfun(@(f) numel(f.x) >= 10, final_fronts);
            crest_widths{k} = [];
            for i = find(filtered_idx)
                crest_width_pts{k} = [crest_width_pts{k}; final_fronts{i}.x(:), final_fronts{i}.y(:), final_fronts{i}.width(:)];
            end
            for i = find(filtered_idx)
                crest_widths{k} = [crest_widths{k}; final_fronts{i}.width];
            end
        end

        frontIDs     = cell(1, numberVideoFrames);
        nextID       = 1;

        for k = 1:numberVideoFrames
            fronts_k = separated_fronts{k};
            if isempty(fronts_k) || ~iscell(fronts_k)
                frontIDs{k} = [];
                continue
            end
            if k == 1
                N           = length(fronts_k);
                frontIDs{k} = 1:N;
                nextID      = N + 1;
                continue
            end
            fronts_prev = separated_fronts{k-1};
            if isempty(fronts_prev) || ~iscell(fronts_prev)
                N           = length(fronts_k);
                frontIDs{k} = nextID:(nextID+N-1);
                nextID      = nextID + N;
                continue
            end
            IDs_prev = frontIDs{k-1};
            IDs_k    = zeros(1, length(fronts_k));
            for i = 1:length(fronts_k)
                xi_min  = min(fronts_k{i}.x);
                xi_max  = max(fronts_k{i}.x);
                yi_mean = mean(fronts_k{i}.y);
                best_score = inf;
                best_match = -1;
                for j = 1:length(fronts_prev)
                    xj_min  = min(fronts_prev{j}.x);
                    xj_max  = max(fronts_prev{j}.x);
                    yj_mean = mean(fronts_prev{j}.y);
                    overlap = min(xi_max, xj_max) - max(xi_min, xj_min);
                    if overlap <= 0; continue; end
                    score = abs(yi_mean - yj_mean);
                    if score < best_score
                        best_score = score;
                        best_match = j;
                    end
                end
                y_match_thresh = 50 * info.Y_res;
                if best_match > 0 && best_score < y_match_thresh
                    IDs_k(i) = IDs_prev(best_match);
                else
                    IDs_k(i) = nextID;
                    nextID   = nextID + 1;
                end
            end
            frontIDs{k} = IDs_k;
        end

        vel_store = cell(1, numberVideoFrames-1);
        y_tol     = 0.5 * info.Y_res;
        u_min     = 0.15;
        u_max     = 5;

        for k = 1:numberVideoFrames-1
            fronts_k   = separated_fronts{k};
            fronts_kp1 = separated_fronts{k+1};
            if isempty(fronts_k) || isempty(fronts_kp1)
                vel_store{k} = [];
                continue
            end
            vel_pts = [];
            x2_all = []; y2_all = [];
            for j = 1:length(fronts_kp1)
                x2_all = [x2_all; fronts_kp1{j}.x(:)];
                y2_all = [y2_all; fronts_kp1{j}.y(:)];
            end
            claimed = false(size(x2_all));
            for i = 1:length(fronts_k)
                x1 = fronts_k{i}.x;
                y1 = fronts_k{i}.y;
                for p = 1:length(x1)
                    xp = x1(p); yp = y1(p);
                    y_mask = abs(y2_all - yp) < y_tol;
                    if ~any(y_mask); continue; end
                    dx    = x2_all(y_mask) - xp;
                    valid = dx < 0;
                    if ~any(valid); continue; end
                    orig_indices = find(y_mask);
                    orig_indices = orig_indices(valid);
                    dx_valid     = dx(valid);
                    not_claimed  = ~claimed(orig_indices);
                    if ~any(not_claimed); continue; end
                    orig_indices = orig_indices(not_claimed);
                    dx_valid     = dx_valid(not_claimed);
                    [~, idx]  = min(abs(dx_valid));
                    best_orig = orig_indices(idx);
                    x_match = x2_all(best_orig);
                    claimed(best_orig) = true;
                    u = -(x_match - xp) / dt;
                    if u > u_min && u < u_max
                        vel_pts = [vel_pts; xp, yp, u];
                    end
                end
            end
            vel_store{k} = vel_pts;
        end

        separated_fronts_filtered = cell(1, numberVideoFrames);
        for k = 1:numberVideoFrames-1
            vpts = vel_store{k};
            if isempty(vpts)
                separated_fronts_filtered{k} = {};
                continue
            end
            fronts_k = separated_fronts{k};
            filtered = {}; fcount = 0;
            for i = 1:length(fronts_k)
                x1 = fronts_k{i}.x; y1 = fronts_k{i}.y;
                keep = false(size(x1));
                for p = 1:length(x1)
                    match = abs(vpts(:,1) - x1(p)) < 1e-6 & abs(vpts(:,2) - y1(p)) < 1e-6;
                    if any(match); keep(p) = true; end
                end
                if sum(keep) < 2; continue; end
                fcount = fcount + 1;
                filtered{fcount}.x = x1(keep);
                filtered{fcount}.y = y1(keep);
            end
            separated_fronts_filtered{k} = filtered;
        end
        separated_fronts_filtered{end} = {};

        all_celerity = [];
        all_celerity_time = [];
        max_dy   = 5; max_dx = 5; ray_len = 20; max_disp = 4;

        for k = 2:numberVideoFrames-1
            fronts_k   = separated_fronts_filtered{k};
            fronts_kp1 = separated_fronts_filtered{k+1};
            if isempty(fronts_k) || isempty(fronts_kp1); continue; end

            intersections = [];
            kp1_fronts_sorted = cell(size(fronts_kp1));
            for i = 1:length(fronts_kp1)
                [y_sorted,idx] = sort(fronts_kp1{i}.y);
                kp1_fronts_sorted{i}.x = fronts_kp1{i}.x(idx);
                kp1_fronts_sorted{i}.y = y_sorted;
            end

            for i = 1:length(fronts_k)
                x_pts = fronts_k{i}.x; y_pts = fronts_k{i}.y;
                if numel(y_pts) < 2; continue; end
                [y_sorted,idx] = sort(y_pts);
                x_sorted = x_pts(idx);
                dx = diff(x_sorted); dy = diff(y_sorted);
                seg_len = hypot(dx,dy);
                nx = -dy ./ seg_len; ny = dx ./ seg_len;
                x_mid = 0.5*(x_sorted(1:end-1)+x_sorted(2:end));
                y_mid = 0.5*(y_sorted(1:end-1)+y_sorted(2:end));

                for p = 1:length(x_mid)
                    if nx(p) > 0
                        nx(p) = -nx(p); ny(p) = -ny(p);
                    end
                    if (x_mid(p)+ray_len*nx(p)) > x_mid(p)
                        nx(p) = -nx(p); ny(p) = -ny(p);
                    end
                    x1 = x_mid(p)-ray_len*nx(p); y1 = y_mid(p)-ray_len*ny(p);
                    x2 = x_mid(p)+ray_len*nx(p); y2 = y_mid(p)+ray_len*ny(p);
                    dx_ray = x2-x1; dy_ray = y2-y1;

                    best_t = inf; best_int = [];
                    for fi = 1:length(kp1_fronts_sorted)
                        x_kp1 = kp1_fronts_sorted{fi}.x; y_kp1 = kp1_fronts_sorted{fi}.y;
                        for s = 1:length(x_kp1)-1
                            if abs(y_kp1(s+1)-y_kp1(s)) > max_dy || abs(x_kp1(s+1)-x_kp1(s)) > max_dx
                                continue
                            end
                            x3 = x_kp1(s); y3 = y_kp1(s);
                            x4 = x_kp1(s+1); y4 = y_kp1(s+1);
                            dx_seg = x4-x3; dy_seg = y4-y3;
                            denom = dx_ray*dy_seg - dy_ray*dx_seg;
                            if abs(denom) < 1e-10; continue; end
                            t = ((x3-x1)*dy_seg - (y3-y1)*dx_seg)/denom;
                            u = ((x3-x1)*dy_ray - (y3-y1)*dx_ray)/denom;
                            if u<0 || u>1 || t<0 || t>1 || t<0.5; continue; end
                            if abs(t-0.5) < abs(best_t-0.5)
                                best_t = t;
                                best_int = [x1+t*dx_ray , y1+t*dy_ray];
                            end
                        end
                    end

                    if ~isempty(best_int)
                        dx_disp = best_int(1)-x_mid(p);
                        dy_disp = best_int(2)-y_mid(p);
                        disp_dist = hypot(dx_disp,dy_disp);
                        if dx_disp < 0 && disp_dist < max_disp
                            intersections = [intersections; x_mid(p), y_mid(p), best_int(1), best_int(2)];
                        end
                    end
                end
            end

            % if ~isempty(intersections)
            %     disp_dist = hypot(intersections(:,3)-intersections(:,1),intersections(:,4)-intersections(:,2));
            %     celerity = disp_dist ./ dt;
            %     all_celerity = [all_celerity; intersections(:,1), intersections(:,2), celerity];
            %     all_celerity_time = [all_celerity_time; repmat(fileStartStamp + seconds(frameTimes(k+1)), size(intersections,1), 1)];
            % end
            if ~isempty(intersections)
                dx_disp   = intersections(:,3) - intersections(:,1);
                dy_disp   = intersections(:,4) - intersections(:,2);
                disp_dist = hypot(dx_disp, dy_disp);
                celerity  = disp_dist ./ dt;

                cx = -dx_disp ./ dt;   % cross-shore component, onshore positive
                cy =  dy_disp ./ dt;   % alongshore component

                all_celerity = [all_celerity; intersections(:,1), intersections(:,2), cx, cy, celerity];
                all_celerity_time = [all_celerity_time; repmat(fileStartStamp + seconds(frameTimes(k+1)), size(intersections,1), 1)];
            end
            fprintf('Frame %d: %d intersections\n', k, size(intersections,1));
        end

        all_crest_summary = [all_crest_summary crest_summary];
        all_crest_widths  = [all_crest_widths crest_widths];
        all_celerity_total      = [all_celerity_total; all_celerity];
        for k = 1:numberVideoFrames
            if isempty(crest_width_pts{k}); continue; end
            n = size(crest_width_pts{k}, 1);
            all_crest_width_pts_total  = [all_crest_width_pts_total; crest_width_pts{k}];
            all_crest_width_time_total = [all_crest_width_time_total; repmat(fileStartStamp + seconds(frameTimes(k+1)), n, 1)];
        end
        all_celerity_time_total = [all_celerity_time_total; all_celerity_time];
        fprintf('  File %s done. Cumulative celerity points: %d\n', videoFile, size(all_celerity_total,1));
    end

    fprintf('\n=== DONE hour %s: %d files processed, %d celerity points ===\n', hourStr, numFiles, size(all_celerity_total,1));

    % tide lookup for this hour
    yr = str2double(year_str);
    mo = str2double(dateTag(1:2));
    dy = str2double(dateTag(3:4));
    hr = str2double(hourStr(1:2));
    windowStart = datetime(yr, mo, dy, hr, 0, 0);
    windowEnd   = windowStart + hours(1);
    inWindow = tideTime >= windowStart & tideTime < windowEnd;
    if any(inWindow)
        tide_hour = mean(waterLevel(inWindow), 'omitnan');
    else
        warning('No tide data for %s %s -- tide set to NaN.', dateTag, hourStr);
        tide_hour = NaN;
    end
    tide_all = [tide_all; hourVal, tide_hour];

    all_celerity = all_celerity_total;
    all_celerity_time = all_celerity_time_total;

    % save per-hour outputs
    sensorFileTag = sprintf('%s_%s', dateTag, hourStr);
    sensorSaveDir = fullfile(matDataDir, 'sensor_timeseries');
    if ~exist(sensorSaveDir,'dir'); mkdir(sensorSaveDir); end
    save(fullfile(sensorSaveDir, ['sensor_' sensorFileTag '.mat']), 'sensors')
    save(fullfile(matDataDir, sprintf('%s_%s.mat', dateTag, hourStr)), '-v7.3');
    fprintf('Saved workspace for %s to %s\n', hourStr, matDataDir);

    % flatten widths for function output
    hour_widths = [];
    for kk = 1:numel(all_crest_widths)
        if isempty(all_crest_widths{kk})
            continue
        end
        hour_widths = [hour_widths; all_crest_widths{kk}(:)];
    end
    crestWidths_all = [crestWidths_all; hour_widths];
    
    % flatten lengths for function output
    hour_lengths = [];
    for kk = 1:numel(all_crest_summary)
        if isempty(all_crest_summary{kk})
            continue
        end
        if isstruct(all_crest_summary{kk})
            lengths_k = [all_crest_summary{kk}.length];
            hour_lengths = [hour_lengths; lengths_k(:)];
        end
    end
    crestLengths_all = [crestLengths_all; hour_lengths];

    % accumulate across hours for function outputs
    celerity_all      = [celerity_all; all_celerity_total];
    celerity_time_all = [celerity_time_all; all_celerity_time_total];
    crestWidths_all_cells  = [crestWidths_all_cells, all_crest_widths];
    crestSummary_all_cells = [crestSummary_all_cells, all_crest_summary];
end

%% PLOTS 

%  Crest Width Statistics (ALL processed videos) 
all_widths = vertcat(crestWidths_all_cells{:});
all_widths = all_widths( ~isnan(all_widths) & all_widths > 0 & all_widths <= 8);
edges = 0:0.2:8;
figure
histogram(all_widths, edges, 'FaceColor','r', 'EdgeColor','none', 'Normalization','probability');
hold on
w_mean   = mean(all_widths);
w_median = median(all_widths);
w_std    = std(all_widths);
hMean = xline(w_mean, 'b-', 'LineWidth', 2);
hMed  = xline(w_median, 'k--', 'LineWidth', 2);
hStd  = plot(nan, nan, 'w');
xlabel('Crest width [m]');
ylabel('Frequency');
title(sprintf('Distribution of Crest Width - %d Video(s)', numFiles));
xlim([edges(1) edges(end)]);
grid on
box on
legend([hMean hMed hStd], {sprintf('Mean = %.2f m', w_mean), sprintf('Median = %.2f m', w_median), ...
    sprintf('Std = %.2f m', w_std)}, 'Location', 'northeast');
hold off

% Crest Length Statistics
all_lengths = [];
for k = 1:numel(crestSummary_all_cells)
    if isempty(crestSummary_all_cells{k})
        continue
    end
    all_lengths = [all_lengths; [crestSummary_all_cells{k}.length]'];
end
all_lengths = all_lengths( ~isnan(all_lengths) & all_lengths > 0);
edges = 0:1:50;
figure
histogram(all_lengths, edges, 'FaceColor','r', 'EdgeColor','none', 'Normalization','probability');
hold on
L_mean   = mean(all_lengths);
L_median = median(all_lengths);
L_std    = std(all_lengths);
hMean = xline(L_mean, 'b-', 'LineWidth', 2);
hMed  = xline(L_median, 'k--', 'LineWidth', 2);
hStd  = plot(nan, nan, 'w');
xlabel('Crest length [m]');
ylabel('Frequency');
title(sprintf('Distribution of Crest Length - %d Video(s)', numFiles));
xlim([edges(1) edges(end)]);
grid on
box on
legend([hMean hMed hStd], {sprintf('Mean = %.2f m', L_mean), sprintf('Median = %.2f m', L_median), ...
     sprintf('Std = %.2f m', L_std)}, 'Location', 'northeast');
hold off

% Spatial mean velocity plot - 5x5 m binned grid 
bin_size = 5;
x_edges = min(celerity_all(:,1)) : bin_size : max(celerity_all(:,1)) + bin_size;
y_edges = min(celerity_all(:,2)) : bin_size : max(celerity_all(:,2)) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2;
y_centers = y_edges(1:end-1) + bin_size/2;
xi = discretize(celerity_all(:,1), x_edges);
yi = discretize(celerity_all(:,2), y_edges);
n_xbins = length(x_centers);
n_ybins = length(y_centers);
vel_grid = nan(n_ybins, n_xbins);
for r = 1:n_ybins
    for c = 1:n_xbins
        mask = xi == c & yi == r;
        if sum(mask) >= 10
            vel_grid(r, c) = mean(celerity_all(mask, 5));
        end
    end
end
figure; hold on
h = imagesc(x_centers, y_centers, vel_grid);
set(h, 'AlphaData', ~isnan(vel_grid));
colormap(parula);
cb = colorbar;
cb.Label.String = 'Mean Celerity [m/s]';
clim([0 5]);
axis tight;
set(gca, 'YDir', 'normal');
xlabel('Cross-shore (m)');
ylabel('Alongshore (m)');
title(sprintf('Mean Celerity — 5×5 m bins (%s/%s)', dateTag(1:2), dateTag(3:4)));
grid minor; box on;

end
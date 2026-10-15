clear all;
addpath(genpath('../'));
[info, icp, beta0] = define_camera_parameters();

videoDir  = '../../data/20130929/1100/';
videoFile = '20130929_112106_B314_00408CEBCECB_06.avi';
videoPath = fullfile(videoDir, videoFile);
vid   = VideoReader(videoPath);
vidHz = vid.FrameRate;

invRate           = round(vidHz / info.freq);
numberVideoFrames = length(1:invRate:vid.NumFrames);

[U, V]   = meshgrid(0:icp.NU-1, 0:icp.NV-1); % pix grid
X        = info.X_min:info.X_res:info.X_max; % CS phys grid [m]
Y        = info.Y_min:info.Y_res:info.Y_max; % AS ''
[xx, yy] = meshgrid(X, Y);
z_tide   = zeros(size(xx)); % no tidal correction
[Uint, Vint] = getUVfromXYZ(xx, yy, z_tide, icp, beta0); % map FRF grid -> pix coord

%% build front store across all frames
X_front_store    = cell(1, numberVideoFrames);
Y_front_store    = cell(1, numberVideoFrames);
rectified_frames = cell(1, numberVideoFrames);
dt               = 1 / info.freq; % time step b/w frames
Pnon             = 0.25; % prob thresh for crest ID *****

% read all needed frames sequentially upfront
totalFramesNeeded = numberVideoFrames + 2;  % +2 for the trailing [0 1 2] offset
rawFrames = cell(1, totalFramesNeeded);
vid.CurrentTime = 0;
for f = 1:totalFramesNeeded
    if hasFrame(vid)
        rawFrames{f} = double(rgb2gray(readFrame(vid)));
    end
end

% process stacks
IMG = zeros([size(xx), 3]); % preallocate 3 frame stack in phys grid space
for k = 1:numberVideoFrames

    % rectify each of 3 frames from pix space -> FRF grid
    for ii = 1:3
        IMG(:,:,ii) = interp2(U, V, rawFrames{k+ii-1}, Uint, Vint, 'linear', nan);
    end

    rectified_frames{k} = IMG(:,:,2); % store center frame

    % UNET to get brk front probs
    [~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

    % extract front pts from prob map
    rclog = bore_front_search_funwave_Prezley(prob', info.Ny, info.Nx, 1, Pnon);
    crlog = [];
    for ll = 1:length(rclog)
        crlog = cat(1, crlog, fliplr(rclog{ll}));
    end

    if isempty(crlog); continue; end

    ind = sub2ind(size(xx), crlog(:,1), crlog(:,2)); % conv grid idx to FRF coord
    X_front_store{k} = xx(ind); % CS pos
    Y_front_store{k} = yy(ind); % AS pos
end
%% separate fronts via DBSCAN
separated_fronts = cell(1, numberVideoFrames);

for k = 1:numberVideoFrames

    X_temp = X_front_store{k};
    Y_temp = Y_front_store{k};

    if isempty(X_temp)
        separated_fronts{k} = {};
        continue
    end

    pts    = [X_temp(:), Y_temp(:)];
    epsilon = 4 * max(info.X_res, info.Y_res); % neigh radius, inc to bridge gaps ***
    minPts = 5; % min neigh for core pt
    labels = dbscan(pts, epsilon, minPts);
    clusterIDs   = unique(labels(labels > 0)); % exclude noise label
    final_fronts = {};
    fcount       = 0;

    for c = 1:length(clusterIDs)
        mask = labels == clusterIDs(c);
        fx   = X_temp(mask);
        fy   = Y_temp(mask);

        min_cluster_pts = 40; % rej clust w too few pts, inc to remove noisy***
        if numel(fx) < min_cluster_pts
            continue
        end
        AS_extent = max(fy) - min(fy);
        CS_extent = max(fx) - min(fx);
        if AS_extent < 5 * info.Y_res && CS_extent < 5 * info.X_res % rej compact blobs
            continue
        end

        fcount = fcount + 1;
        final_fronts{fcount}.x = fx;
        final_fronts{fcount}.y = fy;
    end

    if isempty(final_fronts)
        separated_fronts{k} = {};
        continue
    end

    min_points = 10; % abs min points after shape filtering, safety net **
    filtered_fronts     = final_fronts(cellfun(@(f) numel(f.x) >= min_points, final_fronts));
    separated_fronts{k} = filtered_fronts;
end

% track fronts across frames
maxIDs       = 200; % max unique front IDs
globalColors = lines(maxIDs);
frontIDs     = cell(1, numberVideoFrames);
nextID       = 1;

for k = 1:numberVideoFrames

    fronts_k = separated_fronts{k};

    if isempty(fronts_k) || ~iscell(fronts_k)
        frontIDs{k} = []; % seed IDs from 1st frame
        continue
    end

    if k == 1
        N            = length(fronts_k);
        frontIDs{k}  = 1:N;
        nextID       = N + 1;
        continue
    end

    fronts_prev = separated_fronts{k-1};

    if isempty(fronts_prev) || ~iscell(fronts_prev)
        N            = length(fronts_k);
        frontIDs{k}  = nextID:(nextID+N-1); % assign new ID if no prev frame to match
        nextID       = nextID + N;
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

            % prevent matching fronts at diff CS pos
            overlap = min(xi_max, xj_max) - max(xi_min, xj_min);
            if overlap <= 0
                continue
            end

            score = abs(yi_mean - yj_mean);
            if score < best_score
                best_score = score;
                best_match = j;
            end
        end
        % max AS centroid drift [m] b/w frames to be same front ***
        y_match_thresh = 10 * info.Y_res; 
        if best_match > 0 && best_score < y_match_thresh
            IDs_k(i) = IDs_prev(best_match);
        else
            IDs_k(i) = nextID;
            nextID   = nextID + 1;
        end
    end

    frontIDs{k} = IDs_k;
end

%% animated plot
figure;
for k = 1:numberVideoFrames

    clf; hold on

    if isempty(rectified_frames{k})
        continue
    end

    imagesc(X, Y, rectified_frames{k});
    set(gca, 'YDir', 'normal')
    axis tight
    colormap(bone)
    title(sprintf('Tracked Fronts – Frame %d', k))

    fronts_k = separated_fronts{k};
    IDs_k    = frontIDs{k};

    if ~isempty(fronts_k)
        for i = 1:length(fronts_k)
            id = IDs_k(i);
            plot(fronts_k{i}.x, fronts_k{i}.y, '.', ...
                 'Color', globalColors(id,:), 'MarkerSize', 10)
        end
    end
    drawnow
    pause(0.3)
end



%% compute cross-shore velocities of front points
vel_store = cell(1, numberVideoFrames-1);
y_tol     = 0.5 * info.Y_res;  % FIX 1: tightened from 2 to 0.5
u_min     = 0;
u_max     = 5;

for k = 1:numberVideoFrames-1

    fronts_k   = separated_fronts{k};
    fronts_kp1 = separated_fronts{k+1};

    if isempty(fronts_k) || isempty(fronts_kp1)
        vel_store{k} = [];
        continue
    end

    vel_pts = [];

    % flatten next frame points for searching
    x2_all = [];
    y2_all = [];
    for j = 1:length(fronts_kp1)
        x2_all = [x2_all; fronts_kp1{j}.x(:)];
        y2_all = [y2_all; fronts_kp1{j}.y(:)];
    end

    claimed = false(size(x2_all));  % FIX 3: one-to-one matching tracker

    for i = 1:length(fronts_k)

        x1 = fronts_k{i}.x;
        y1 = fronts_k{i}.y;

        for p = 1:length(x1)

            xp = x1(p);
            yp = y1(p);

            % find candidates in next frame within alongshore window
            y_mask = abs(y2_all - yp) < y_tol;
            if ~any(y_mask); continue; end

            % enforce onshore motion
            dx    = x2_all(y_mask) - xp;
            valid = dx < 0;
            if ~any(valid); continue; end

            % FIX 2: reject diagonal matches — check alongshore displacement
            dy_candidates = abs(y2_all(y_mask) - yp);
            valid = valid & (dy_candidates < 0.5 * info.Y_res);
            if ~any(valid); continue; end

            % get original indices into x2_all for claimed tracking
            orig_indices = find(y_mask);
            orig_indices = orig_indices(valid);
            dx_valid     = dx(valid);

            % exclude already-claimed points
            not_claimed  = ~claimed(orig_indices);
            if ~any(not_claimed); continue; end

            orig_indices = orig_indices(not_claimed);
            dx_valid     = dx_valid(not_claimed);

            % pick nearest onshore unclaimed point
            [~, idx]  = min(abs(dx_valid));
            best_orig = orig_indices(idx);

            x_match = x2_all(best_orig);
            y_match = y2_all(best_orig);

            % FIX 3: mark as claimed
            claimed(best_orig) = true;

            % compute and filter velocity
            u = -(x_match - xp) / dt;
            if u > u_min && u < u_max
                vel_pts = [vel_pts; xp, yp, u]; %#ok<AGROW>
            end
        end
    end

    vel_store{k} = vel_pts;
end

non_empty = vel_store(~cellfun(@isempty, vel_store));
all_vel   = vertcat(non_empty{:});


%% plot vel
non_empty = vel_store(~cellfun(@isempty, vel_store));
all_vel   = vertcat(non_empty{:});

figure; hold on
set(gca, 'YDir', 'normal')
colormap(parula)
scatter(all_vel(:,1), all_vel(:,2), 10, all_vel(:,3), 'filled')
colorbar
caxis([0 5])
title('Cumulative Velocity Distribution')
xlabel('Cross-shore (m)')
ylabel('Alongshore (m)')

%% visualize mapping of pixels b/w frames
k_inspect = 5;  % change to any frame pair

fronts_k   = separated_fronts{k_inspect};
fronts_kp1 = separated_fronts{k_inspect + 1};

figure; hold on
imagesc(X, Y, rectified_frames{k_inspect});
set(gca, 'YDir', 'normal')
colormap(bone); axis tight
title(sprintf('Point matching: frame %d → %d', k_inspect, k_inspect+1))
xlabel('Cross-shore (m)'); ylabel('Alongshore (m)')

if isempty(fronts_k) || isempty(fronts_kp1)
    disp('One or both frames empty'); return
end

% flatten next frame points
x2_all = [];
y2_all = [];
for j = 1:length(fronts_kp1)
    x2_all = [x2_all; fronts_kp1{j}.x(:)];
    y2_all = [y2_all; fronts_kp1{j}.y(:)];
end

% plot all next-frame points
plot(x2_all, y2_all, 'c.', 'MarkerSize', 8)

claimed = false(size(x2_all));

for i = 1:length(fronts_k)

    x1 = fronts_k{i}.x;
    y1 = fronts_k{i}.y;

    % plot current frame front points
    plot(x1, y1, 'b.', 'MarkerSize', 8)

    for p = 1:length(x1)

        xp = x1(p);
        yp = y1(p);

        y_mask = abs(y2_all - yp) < y_tol;
        if ~any(y_mask); continue; end

        dx            = x2_all(y_mask) - xp;
        valid         = dx < 0;
        dy_candidates = abs(y2_all(y_mask) - yp);
        valid         = valid & (dy_candidates < 0.5 * info.Y_res);
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
        y_match = y2_all(best_orig);

        claimed(best_orig) = true;

        u = -(x_match - xp) / dt;
        if u <= u_min || u >= u_max; continue; end

        quiver(xp, yp, x_match - xp, y_match - yp, 0, ...
            'Color', 'r', ...
            'MaxHeadSize', 0.25, ...
            'LineWidth', 1)
    end
end



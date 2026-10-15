clear all;
addpath(genpath('../'));
[info, icp, beta0] = define_camera_parameters();

% videoDir  = '../../data/20130929/1100/';
% videoFile = '20130929_112106_B314_00408CEBCECB_16.avi';

videoDir = '../../data/20130929/'; % new 5 minute video
videoFile = '20130929_112106_B314_00408CEBCECB.mp4';

videoPath = fullfile(videoDir, videoFile);
vid   = VideoReader(videoPath);
vidHz = vid.FrameRate;

invRate           = round(vidHz / info.freq); % invRate = 2
numberVideoFrames = length(1:invRate:vid.NumFrames); % ^^^ downsamples to look at every other frame

[U, V]   = meshgrid(0:icp.NU-1, 0:icp.NV-1); % pixel space grid
X        = info.X_min:info.X_res:info.X_max; % info.X_res = 0.6863 m
Y        = info.Y_min:info.Y_res:info.Y_max;
[xx, yy] = meshgrid(X, Y); % phys grid
z_tide   = zeros(size(xx));
[Uint, Vint] = getUVfromXYZ(xx, yy, z_tide, icp, beta0); % projects phys grid to pix grid

% build front store across all frames
X_front_store    = cell(1, numberVideoFrames); % holds phys coords of fronts
Y_front_store    = cell(1, numberVideoFrames);
rectified_frames = cell(1, numberVideoFrames);
dt               = 1 / info.freq; % step b/w processed frames (.4 sec ~ 1/2.5 sec)
Pnon             = 0.25; % prob threshold for front detection

totalFramesNeeded = numberVideoFrames + 2;
rawFrames = cell(1, totalFramesNeeded);
vid.CurrentTime = 0;
for f = 1:totalFramesNeeded
    if hasFrame(vid)
        rawFrames{f} = double(rgb2gray(readFrame(vid))); % converts to grayscale b/c need intensity
    end
end

%% process stacks — sub-grid peak fitting on prob map
IMG    = zeros([size(xx), 3]);
Ny_grid = size(xx, 1); % number of AS grid points (rows)
Nx_grid = size(xx, 2); % number of CS grid points (cols)

for k = 1:numberVideoFrames

    for ii = 1:3
        IMG(:,:,ii) = interp2(U, V, rawFrames{k+ii-1}, Uint, Vint, 'linear', nan);
    end

    rectified_frames{k} = IMG(:,:,2); % stores middle frame of 3-img stack

    [~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0); % identify brking, gives 2D brking prob

    rclog = bore_front_search_funwave_Prezley(prob', info.Ny, info.Nx, 1, Pnon); % gives detected fronts
    crlog = [];
    for ll = 1:length(rclog)
        crlog = cat(1, crlog, fliplr(rclog{ll})); % flattens all rclog into single matrix
    end

    if isempty(crlog); continue; end

    % detect orientation -swaps if needed
    if max(crlog(:,1)) <= Nx_grid && max(crlog(:,2)) <= Ny_grid
        % crlog is [col, row] as expected from fliplr
        col_all = crlog(:, 1);
        row_all = crlog(:, 2);
    else
        % crlog is [row, col] — swap
        row_all = crlog(:, 1);
        col_all = crlog(:, 2);
    end

    % clamp to grid bounds as safety net, discards pts outside of grid bounds
    in_bounds = col_all >= 1 & col_all <= Nx_grid & ...
                row_all >= 1 & row_all <= Ny_grid;
    col_all = col_all(in_bounds);
    row_all = row_all(in_bounds);

    if isempty(col_all); continue; end

    % make sure prob is oriented same as xx — [Ny x Nx]
    if ~isequal(size(prob), size(xx))
        prob = prob';
    end

    % loop for 
    X_sub = zeros(numel(col_all), 1);
    Y_sub = zeros(numel(col_all), 1);
    for pt = 1:numel(col_all) 

        col = col_all(pt); % integer, grid-snapped indices detected from bore_front f'n
        row = row_all(pt);

        Y_sub(pt) = yy(row, col); % AS position — stays grid snapped

        % CS neighbourhood for parabola fit; takes window of 2 cells in CS dir around each detected front pt
        col_lo = max(col - 2, 1);
        col_hi = min(col + 2, Nx_grid);
        cols   = col_lo:col_hi; % neighborhood of 5 indices

        if numel(cols) < 3 % uses grid snapped pts near edges when < 3 pts nearby
            X_sub(pt) = xx(row, col); % keeps grid snapped indices
            continue
        end

        p_vals = double(prob(row, cols)); % extract UNET prob values in neighborhood def ^
        x_vals = X(cols); % x coords of pts in parabola fit

        % fit quadratic to prob profile across neighborhood, peak of downward parabola -> sub-grid CS position
        coeffs = polyfit(x_vals, p_vals, 2);
        a      = coeffs(1); % x^2 coef
        b      = coeffs(2); % linear term used for peak loc

        if a >= 0 % upward curving parabola -> no use of parabola fitting
            % no clear peak — fall back to snapped grid node
            X_sub(pt) = xx(row, col);
            continue
        end

        x_peak    = -b / (2 * a); % where UNET prob peaks b/w grid nodes, this is continous CS pos where UNET is max
        x_peak    = max(x_vals(1), min(x_vals(end), x_peak)); % makes sure fit is in neighborhood
        X_sub(pt) = x_peak; % stores subgrid CS pos for this front pt
    end

    X_front_store{k} = X_sub; % stores continuous x pos
    Y_front_store{k} = Y_sub; % stores grid snapped y pos
end



%% animated plot — subgrid-refined UNET fronts

figure;
for k = 1:numberVideoFrames

    clf; hold on

    if isempty(rectified_frames{k})
        continue
    end

    imagesc(X, Y, rectified_frames{k});
    set(gca, 'YDir', 'normal')
    colormap(bone)
    axis tight
    title(sprintf('Sub-grid UNET fronts — frame %d', k))
    x_plot = X_front_store{k};
    y_plot = Y_front_store{k};

    if ~isempty(x_plot)
        plot(x_plot, y_plot, 'r.', 'MarkerSize', 10)
    end

    xlabel('Cross-shore X (m)')
    ylabel('Alongshore Y (m)')
    drawnow
    pause(0.4)
end

%% compute cross-shore velocities
vel_store = cell(1, numberVideoFrames-1);
y_tol     = 0.5 * info.Y_res; % w/in half a grid cell of dy, Y_res = 0.8923 m
u_min     = 0;
u_max     = 7; % reject speeds > 7m/s

for k = 1:numberVideoFrames-1 % loop over every consectutive frame pair

    x1 = X_front_store{k};
    y1 = Y_front_store{k};
    x2 = X_front_store{k+1};
    y2 = Y_front_store{k+1};
    
    if isempty(x1) || isempty(x2)
    vel_store{k} = [];
    continue
end

vel_pts = [];
claimed = false(size(x2));

for p = 1:length(x1)

    xp = x1(p);
    yp = y1(p);
    y_mask = abs(y2 - yp) < y_tol;
    if ~any(y_mask)
        continue
    end

    dx = x2(y_mask) - xp;
    valid = dx < 0;
    if ~any(valid)
        continue
    end

    orig_indices = find(y_mask);
    orig_indices = orig_indices(valid);

    dx_valid = dx(valid);
    not_claimed = ~claimed(orig_indices);
    if ~any(not_claimed)
        continue
    end

    orig_indices = orig_indices(not_claimed);
    dx_valid     = dx_valid(not_claimed);
    [~, idx] = min(abs(dx_valid));
    best_idx = orig_indices(idx);
    claimed(best_idx) = true;

    u = -(x2(best_idx) - xp) / dt; % celerity calculation

    if u > u_min && u < u_max
        vel_pts = [vel_pts; xp, yp, u];
    end
end

vel_store{k} = vel_pts;
end

%% plot cumulative velocity distribution
non_empty = vel_store(~cellfun(@isempty, vel_store));
all_vel   = vertcat(non_empty{:});

figure; hold on
set(gca, 'YDir', 'normal')
colormap(parula)
scatter(all_vel(:,1), all_vel(:,2), 10, all_vel(:,3), 'filled')
cb = colorbar; cb.Label.String = 'Onshore Velocity [m/s]';
caxis([0 7])
title('Onshore Velocity Distribution')
xlabel('Cross-shore (m)')
ylabel('Alongshore (m)')

%% quick histogram of vel
figure;
h_hist = histogram(all_vel(:,3), 50, 'FaceColor', 'b', 'EdgeColor', 'none', ...
    'Normalization', 'probability');

hold on
m_mean = mean(all_vel(:,3)); 
m_median = median(all_vel(:,3));
h_mean = xline(m_mean,   'r-',  'LineWidth', 2);
h_median = xline(m_median, 'y--', 'LineWidth', 2);
legend([h_hist, h_mean, h_median], {'Velocity distribution', sprintf('Mean = %.2f m/s', m_mean), ...
     sprintf('Median = %.2f m/s', m_median)}, 'Location', 'best')

xlabel('Onshore velocity [m/s]'); ylabel('Frequency')
title('Distribution of bore front speeds')
xlim([u_min u_max])
grid on; box on

% print summary stats to command window
fprintf('--- Velocity statistics ---\n')
fprintf('N points : %d\n',       size(all_vel,1))
fprintf('Mean     : %.3f m/s\n', mean(all_vel(:,3)))
fprintf('Median   : %.3f m/s\n', median(all_vel(:,3)))
fprintf('Std dev  : %.3f m/s\n', std(all_vel(:,3)))
fprintf('Min      : %.3f m/s\n', min(all_vel(:,3)))
fprintf('Max      : %.3f m/s\n', max(all_vel(:,3)))
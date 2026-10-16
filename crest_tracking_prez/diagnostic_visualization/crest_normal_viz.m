
% crest normals — single frame pair with selectable frame index
k = 124; % starting frame input; > 1

figure; hold on;
bg = rectified_frames{k-1}; % background img
h = imagesc(X, Y, bg);
alpha(h, 0.5); % transparency
colormap bone; axis equal tight;

fronts_k = separated_fronts_filtered{k};
if isempty(fronts_k)
    disp('No fronts detected in selected frame.');
else
    for i = 1:length(fronts_k)
        x_pts = fronts_k{i}.x;
        y_pts = fronts_k{i}.y;
        if numel(y_pts) < 2; continue; end

        [y_sorted, sort_idx] = sort(y_pts);   % sort by AS (y)
        x_sorted = x_pts(sort_idx);

        plot(x_sorted, y_sorted, 'Color', [1.0 0.85 0.0], 'LineWidth', 2); % crests
        scatter(x_sorted, y_sorted, 6, 'filled', 'MarkerFaceColor', [0.2 0.4 0.8]); % crest pts 

        dy = diff(y_sorted); % crest segment vector (b/w crest points)
        dx = diff(x_sorted);
        seg_len = sqrt(dx.^2 + dy.^2); % crest seg length

        tx = dx ./ seg_len; % unit tang vector x-comp
        ty = dy ./ seg_len;
        nx = -ty; % x comp of normal vector obtained from rotating; normal vect = nxi + nyj = -tyi + txj
        ny =  tx;

        x_mid = 0.5 * (x_sorted(1:end-1) + x_sorted(2:end)); % midpts
        y_mid = 0.5 * (y_sorted(1:end-1) + y_sorted(2:end));

        arrow_len = 4 * info.Y_res; % normal vector length

        for p = 1:length(y_mid) % if normal is pointing offshore (wrong) -> flips

            if nx(p) > 0
                nx(p) = -nx(p);
                ny(p) = -ny(p);
            end
            plot([x_mid(p) - arrow_len*nx(p), x_mid(p) + arrow_len*nx(p)], [y_mid(p) - arrow_len*ny(p), y_mid(p) + arrow_len*ny(p)],'k-', 'LineWidth', 1);
        end
    end
end

% frame k+1: crest only
fronts_kp1 = separated_fronts_filtered{k+1};
if ~isempty(fronts_kp1)
    for i = 1:length(fronts_kp1)
        x_pts = fronts_kp1{i}.x;
        y_pts = fronts_kp1{i}.y;
        if numel(y_pts) < 2; continue; end

        [y_sorted, sort_idx] = sort(y_pts);   % sort by AS (y) — same as frame k
        x_sorted = x_pts(sort_idx);

        plot(x_sorted, y_sorted, '-', 'Color','[0.5 .8 0]', 'LineWidth', 2);       % yellow-orange
        scatter(x_sorted, y_sorted, 6, 'filled', 'MarkerFaceColor', [0.1 0.2 0.5]);  % dark blue
    end
end
xlabel('x (m)'); ylabel('y (m)');
grid on;
title(sprintf('Crest Normal Vectors — frame %d', k));


% normal-crest intersection and displacement vectors
intersections = []; % [x_k, y_k, x_int, y_int]
fronts_k   = separated_fronts_filtered{k};
fronts_kp1 = separated_fronts_filtered{k+1};

ray_len = 20; % (half) length of normal vect

if ~isempty(fronts_k) && ~isempty(fronts_kp1)

    % --- build k+1 crest segments — store as separate fronts, NOT concatenated ---
    % this avoids phantom segments between fronts
    kp1_fronts_sorted = {};
    for i = 1:length(fronts_kp1)
        x_pts = fronts_kp1{i}.x;
        y_pts = fronts_kp1{i}.y;
        [y_sorted, sort_idx] = sort(y_pts);
        x_sorted = x_pts(sort_idx);
        kp1_fronts_sorted{i}.x = x_sorted;
        kp1_fronts_sorted{i}.y = y_sorted;
    end

    for i = 1:length(fronts_k)
        x_pts = fronts_k{i}.x;
        y_pts = fronts_k{i}.y;
        if numel(y_pts) < 2; continue; end

        [y_sorted, sort_idx] = sort(y_pts);
        x_sorted = x_pts(sort_idx);

        dy = diff(y_sorted);
        dx = diff(x_sorted);
        seg_len = sqrt(dx.^2 + dy.^2);

        tx = dx ./ seg_len;
        ty = dy ./ seg_len;
        nx = -ty;
        ny =  tx;

        x_mid = 0.5 * (x_sorted(1:end-1) + x_sorted(2:end)); % midpoints
        y_mid = 0.5 * (y_sorted(1:end-1) + y_sorted(2:end));

        for p = 1:length(x_mid)

            % enforce onshore direction — primary check
            if nx(p) > 0
                nx(p) = -nx(p);
                ny(p) = -ny(p);
            end

            % enforce onshore direction — secondary check on ray endpoint
            x2_ray_test = x_mid(p) + ray_len * nx(p);
            if x2_ray_test > x_mid(p)
                nx(p) = -nx(p);
                ny(p) = -ny(p);
            end

            % ray endpoints — centered on frame k midpoint
            x1_ray = x_mid(p) - ray_len * nx(p);
            y1_ray = y_mid(p) - ray_len * ny(p);
            x2_ray = x_mid(p) + ray_len * nx(p);
            y2_ray = y_mid(p) + ray_len * ny(p);

            dx_ray = x2_ray - x1_ray;
            dy_ray = y2_ray - y1_ray;

            best_t   = inf;
            best_int = [];

            % loop over each k+1 front separately to avoid phantom segments
            for fi = 1:length(kp1_fronts_sorted)
                x_kp1 = kp1_fronts_sorted{fi}.x;
                y_kp1 = kp1_fronts_sorted{fi}.y;

                for s = 1:length(x_kp1)-1

                    x3 = x_kp1(s);   y3 = y_kp1(s);
                    x4 = x_kp1(s+1); y4 = y_kp1(s+1);

                    dx_seg = x4 - x3;
                    dy_seg = y4 - y3;

                    denom = dx_ray * dy_seg - dy_ray * dx_seg;
                    if abs(denom) < 1e-10; continue; end % parallel — skip

                    t = ((x3 - x1_ray) * dy_seg - (y3 - y1_ray) * dx_seg) / denom;
                    u = ((x3 - x1_ray) * dy_ray - (y3 - y1_ray) * dx_ray) / denom;

                    if u < 0 || u > 1; continue; end % outside k+1 segment
                    if t < 0 || t > 1; continue; end % outside ray bounds

                    % only consider onshore half of ray (t > 0.5 = onshore direction)
                    if t < 0.5; continue; end

                    % pick intersection closest to frame k midpoint (t closest to 0.5)
                    if abs(t - 0.5) < abs(best_t - 0.5)
                        best_t   = t;
                        best_int = [x1_ray + t*dx_ray, y1_ray + t*dy_ray];
                    end
                end
            end
            
            max_disp = 6; 

            % validate intersection is onshore of frame k midpoint
            if ~isempty(best_int)
                       
            dx_disp = best_int(1) - x_mid(p);
            dy_disp = best_int(2) - y_mid(p);
            disp_dist = sqrt(dx_disp^2 + dy_disp^2);

                if dx_disp < 0 && disp_dist < max_disp  % onshore + within distance threshold
                intersections = [intersections; x_mid(p), y_mid(p), best_int(1), best_int(2)];
                end
            end
        end
    end
end

% displacement vectors — plot on existing figure
if ~isempty(intersections)
    for q = 1:size(intersections, 1)
        x_start = intersections(q, 1);
        y_start = intersections(q, 2);
        x_end   = intersections(q, 3);
        y_end   = intersections(q, 4);
        plot([x_start, x_end], [y_start, y_end], '-', 'Color', 'r', 'LineWidth', 2.4); % red displacement vectors
    end
end
view([-90 90]); % rotate 90 degres

% , [0.1 0.8 0.3]
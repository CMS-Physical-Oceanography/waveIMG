
%% visualize point matching arrows
k_inspect = 1; % input of x gives frame x -> x+1

fronts_k   = separated_fronts{k_inspect};
fronts_kp1 = separated_fronts{k_inspect + 1};

figure; hold on
imagesc(X, Y, rectified_frames{k_inspect});
set(gca, 'YDir', 'normal')
colormap(bone); axis tight
title(sprintf('Point matching: frame %d → %d', k_inspect, k_inspect+1))
xlabel('Cross-shore (m)'); ylabel('Alongshore (m)')

if ~isempty(fronts_k) && ~isempty(fronts_kp1)

    x2_all = [];
    y2_all = [];
    for j = 1:length(fronts_kp1)
        x2_all = [x2_all; fronts_kp1{j}.x(:)];
        y2_all = [y2_all; fronts_kp1{j}.y(:)];
    end

    plot(x2_all, y2_all, 'c.', 'MarkerSize', 10)

    claimed = false(size(x2_all));

    for i = 1:length(fronts_k)

        x1 = fronts_k{i}.x;
        y1 = fronts_k{i}.y;

        plot(x1, y1, 'b.', 'MarkerSize', 10)

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

            quiver(xp, yp, x_match - xp, y_match - yp, 0,'Color', 'r', 'MaxHeadSize', 2, 'LineWidth', 1)
        end
    end
end


%% visualize point matching for arbitrary # of frames
frame_range = 1:5;   % <-- change to any desired frame set

figure; hold on
imagesc(X, Y, rectified_frames{frame_range(1)}); % first frame in range as background
set(gca, 'YDir', 'normal')
colormap(bone); axis tight
title(sprintf('Point matching: frames %d-%d overlaid', frame_range(1), frame_range(end)))
xlabel('Cross-shore (m)'); ylabel('Alongshore (m)')

frame_colors = lines(length(frame_range)); % one color per frame pair

for ii = 1:length(frame_range)

    fi = frame_range(ii);

    if fi >= numberVideoFrames
        continue
    end

    k_inspect  = fi;
    fronts_k   = separated_fronts{k_inspect};
    fronts_kp1 = separated_fronts{k_inspect + 1};

    if isempty(fronts_k) || isempty(fronts_kp1); continue; end

    x2_all = []; 
    y2_all = [];
    for j = 1:length(fronts_kp1)
        x2_all = [x2_all; fronts_kp1{j}.x(:)];
        y2_all = [y2_all; fronts_kp1{j}.y(:)];
    end

    claimed = false(size(x2_all));

    for i = 1:length(fronts_k)

        x1 = fronts_k{i}.x;
        y1 = fronts_k{i}.y;

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

            quiver(xp, yp, x_match - xp, y_match - yp, 0, 'Color', frame_colors(ii,:),'MaxHeadSize', 1, 'LineWidth', 1)
        end
    end
end
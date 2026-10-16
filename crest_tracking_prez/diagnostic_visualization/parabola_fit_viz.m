% general visualization of parabola fitting method concept; uses 6 arbitrary points

k_vis = 1; % select which frame to inspect
n_show = 1; % example points


IMG = zeros([size(xx), 3]);
for ii = 1:3
    IMG(:,:,ii) = interp2(U, V, rawFrames{k_vis + ii - 1}, Uint, Vint, 'linear', nan);
end

dt = 1 / info.freq;
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

if ~isequal(size(prob), size(xx))
    prob = prob';
end

% front detection local copy
rclog = bore_front_search_funwave_Prezley(prob', info.Ny, info.Nx, 1, Pnon);

crlog = [];
for ll = 1:length(rclog)
    crlog = cat(1, crlog, fliplr(rclog{ll}));
end

if isempty(crlog)
    warning('No front detected in this frame');
    return;
end

if max(crlog(:,1)) <= Nx_grid && max(crlog(:,2)) <= Ny_grid
    col_all = crlog(:,1);
    row_all = crlog(:,2);
else
    row_all = crlog(:,1);
    col_all = crlog(:,2);
end

in_bounds = col_all >= 1 & col_all <= Nx_grid & ...
            row_all >= 1 & row_all <= Ny_grid;

col_all = col_all(in_bounds);
row_all = row_all(in_bounds);

if numel(col_all) < n_show
    warning('Not enough front points');
    return;
end

idx_show = round(linspace(1, numel(col_all), n_show));

figure('Name', sprintf('Parabola fits — frame %d', k_vis), ...
       'Position', [100 100 1200 600]);

for ex = 1:n_show

    pt = idx_show(ex);
    col = col_all(pt);
    row = row_all(pt);

    col_lo = max(col - 2, 1);
    col_hi = min(col + 2, Nx_grid);
    cols = col_lo:col_hi;

    p_vals = double(prob(row, cols));
    x_vals = X(cols);

    coeffs = polyfit(x_vals, p_vals, 2);
    a = coeffs(1);
    b = coeffs(2);

    subplot(2,3,ex); hold on; box on; grid on;

    stem(x_vals, p_vals, 'k', 'filled', ...
        'MarkerSize', 8, 'LineWidth', 1.5, ...
        'DisplayName', 'UNET prob at grid nodes');

    x_dense = linspace(x_vals(1), x_vals(end), 300);
    p_fit = polyval(coeffs, x_dense);

    if a < 0

        plot(x_dense, p_fit, 'b-', 'LineWidth', 2, ...
            'DisplayName', 'Fitted parabola');

        x_peak = -b/(2*a);
        x_peak = max(x_vals(1), min(x_vals(end), x_peak));
        p_peak = polyval(coeffs, x_peak);

        plot(x_peak, p_peak, 'rv', 'MarkerSize', 12, ...
            'MarkerFaceColor', 'r', 'LineWidth', 1.5, ...
            'DisplayName', sprintf('Sub-grid peak %.4fm', x_peak));

        x_snap = xx(row, col);
        xline(x_snap, 'g--', 'LineWidth', 1.5, ...
            'Label', sprintf('Snapped %.4fm', x_snap), ...
            'LabelVerticalAlignment', 'bottom');

        offset_cm = (x_peak - x_snap) * 100;

        title(sprintf('pt %d | row %d col %d | offset = %.1f cm', ...
            pt, row, col, offset_cm), 'FontSize', 8);

    else

        plot(x_dense, p_fit, 'r--', 'LineWidth', 2, ...
            'DisplayName', 'No peak (fallback)');

        title(sprintf('pt %d | row %d col %d | FALLBACK', ...
            pt, row, col), 'FontSize', 8);
    end

    xlabel('Cross-shore X (m)');
    ylabel('UNET probability');
    ylim([0 1]);
    xlim([x_vals(1) - 0.2, x_vals(end) + 0.2]);
    legend('Location', 'best', 'FontSize', 7);
end

sgtitle(sprintf('Parabola peak fitting — frame %d', k_vis), 'FontSize', 10);

%% single plot, style as above^
k_vis = 9;     % frame to inspect
pt_idx = 100;   % front point index to inspect

IMG = zeros([size(xx), 3]);
for ii = 1:3
    IMG(:,:,ii) = interp2(U, V, rawFrames{k_vis + ii - 1}, ...
                          Uint, Vint, 'linear', nan);
end

dt = 1 / info.freq;
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

if ~isequal(size(prob), size(xx))
    prob = prob';
end

% Detect front
rclog = bore_front_search_funwave_Prezley(prob', info.Ny, info.Nx, 1, Pnon);

crlog = [];
for ll = 1:length(rclog)
    crlog = cat(1, crlog, fliplr(rclog{ll}));
end

if isempty(crlog)
    error('No front detected in frame %d', k_vis);
end

if max(crlog(:,1)) <= Nx_grid && max(crlog(:,2)) <= Ny_grid
    col_all = crlog(:,1);
    row_all = crlog(:,2);
else
    row_all = crlog(:,1);
    col_all = crlog(:,2);
end

in_bounds = col_all >= 1 & col_all <= Nx_grid & ...
            row_all >= 1 & row_all <= Ny_grid;

col_all = col_all(in_bounds);
row_all = row_all(in_bounds);

% Select one front point
col = col_all(pt_idx);
row = row_all(pt_idx);

% 5-point stencil
col_lo = max(col - 2, 1);
col_hi = min(col + 2, Nx_grid);
cols = col_lo:col_hi;

p_vals = double(prob(row, cols));
x_vals = X(cols);

coeffs = polyfit(x_vals, p_vals, 2);
a = coeffs(1);
b = coeffs(2);

figure;
hold on;
box on;
grid on;

stem(x_vals, p_vals, 'k', 'filled', ...
    'MarkerSize', 8, ...
    'LineWidth', 1.5, ...
    'DisplayName', 'UNET probabilities');

x_dense = linspace(x_vals(1), x_vals(end), 300);
p_fit = polyval(coeffs, x_dense);

plot(x_dense, p_fit, 'b-', ...
    'LineWidth', 2, ...
    'DisplayName', 'Parabolic fit');

if a < 0

    x_peak = -b/(2*a);
    x_peak = max(x_vals(1), min(x_vals(end), x_peak));
    p_peak = polyval(coeffs, x_peak);

    plot(x_peak, p_peak, 'rv', ...
        'MarkerFaceColor', 'r', ...
        'MarkerSize', 12, ...
        'LineWidth', 1.5, ...
        'DisplayName', sprintf('Sub-grid peak = %.3f m', x_peak));

    x_snap = xx(row, col);

    xline(x_snap, 'g--', ...
        'LineWidth', 1.5, ...
        'DisplayName', sprintf('Snapped grid = %.3f m', x_snap));

    offset_cm = (x_peak - x_snap) * 100;

    title(sprintf('Frame %d | row=%d col=%d | offset = %.1f cm', ...
        k_vis, row, col, offset_cm));

else

    title(sprintf('Frame %d | row=%d col=%d | No valid peak', ...
        k_vis, row, col));

end

xlabel('Cross-shore X (m)');
ylabel('UNET probability');
ylim([0 1]);
legend('Location', 'northeast');

%% specified point for parabola visualization

k_vis = 1; % choose processed frame
x_target = 160.098; % point wanting to viualize; example bad one from 7.8s file 16, frame 1 is (160.098, 810.636)
y_target = 810.636;

IMG = zeros([size(xx), 3]);
for ii = 1:3
    IMG(:,:,ii) = interp2(U, V,rawFrames{k_vis + ii - 1}, Uint, Vint, 'linear', nan);
end

dt = 1 / info.freq;
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

if ~isequal(size(prob), size(xx))
    prob = prob';
end

dist2 = (xx - x_target).^2 + (yy - y_target).^2;
[~, ind_min] = min(dist2(:));
[row, col] = ind2sub(size(xx), ind_min);

x_snap = xx(row, col);
y_snap = yy(row, col);

fprintf('\n'); % print + check requested point
fprintf('Requested physical point:\n');
fprintf('x = %.3f m\n', x_target);
fprintf('y = %.3f m\n', y_target);
fprintf('\nNearest grid node:\n');
fprintf('row = %d\n', row);
fprintf('col = %d\n', col);
fprintf('x_snap = %.3f m\n', x_snap);
fprintf('y_snap = %.3f m\n', y_snap);

% parabola fit method:
Nx_grid = size(xx, 2);

% 5-point cross-shore neighborhood
col_lo = max(col - 2, 1);
col_hi = min(col + 2, Nx_grid);
cols = col_lo:col_hi;

if numel(cols) < 3
    error('Point too close to grid edge.');
end

% UNET probabilities
p_vals = double(prob(row, cols));
x_vals = X(cols); % physical x coordinates

coeffs = polyfit(x_vals, p_vals, 2); % quadratic fit
a = coeffs(1);
b = coeffs(2);

figure; hold on; grid on;

% raw probability samples
stem(x_vals, p_vals, 'k','filled', 'LineWidth', 1.5, 'MarkerSize', 8,'DisplayName', 'UNET prob at grid nodes');

x_dense = linspace(x_vals(1), x_vals(end), 400); % smooth parabola
p_fit = polyval(coeffs, x_dense);

if a < 0

    plot(x_dense, p_fit, 'b-', 'LineWidth', 2,'DisplayName', 'Fitted parabola');
    x_peak = -b / (2*a); % subgrid peak

    % clamp to neighborhood
    x_peak = max(x_vals(1), min(x_vals(end), x_peak));
    p_peak = polyval(coeffs, x_peak);

    plot(x_peak, p_peak, 'rv',  'MarkerFaceColor', 'r', 'MarkerSize', 12, 'LineWidth', 1.5, 'DisplayName', 'Sub-grid peak');

    % snapped location
    xline(x_snap, 'g--',  'LineWidth', 1.5, 'Label', sprintf('Snapped %.3f m', x_snap), 'LabelVerticalAlignment', 'bottom');
    offset_cm = (x_peak - x_snap) * 100;

    title(sprintf(['Frame %d | Requested Point (%.3f, %.3f) m\n', 'Offset = %.2f cm'], k_vis, x_target, y_target, offset_cm));
    fprintf('\n');
    fprintf('Sub-grid peak:\n');
    fprintf('x_peak = %.6f m\n', x_peak);
    fprintf('offset = %.2f cm\n', offset_cm);
else
    plot(x_dense, p_fit, 'r--', 'LineWidth', 2, 'DisplayName', 'Fallback fit');
    title(sprintf(['Frame %d | Requested Point (%.3f, %.3f) m\n', 'Fallback: parabola does not open downward'], ...
    k_vis, x_target, y_target));
    fprintf('\nFallback case: a >= 0\n');
end
xlabel('Cross-shore X (m)');
ylabel('UNET probability');
ylim([0 1]);
legend('Location', 'best');


%% individual point transect + parabola shift inspection...

% USER INPUT
k_vis = 1; % frame to visualize
% x_target = 160.098; % target point that is messed up, etc.
% y_target = 810.646;
x_target = 157.115; y_target = 812.25;
x_range = [147 167]; % CS range

IMG = zeros([size(xx), 3]); % build image stack

for ii = 1:3
    IMG(:,:,ii) = interp2(U, V, rawFrames{k_vis + ii - 1}, Uint, Vint, 'linear', nan);
end
dt = 1 / info.freq;
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

if size(prob,1) ~= length(Y)
    prob = prob';
end

% SNAP POINT TO GRID
dist2 = (xx - x_target).^2 + (yy - y_target).^2;
[~, ind_min] = min(dist2(:));
[row, col] = ind2sub(size(xx), ind_min);

x_snap = xx(row,col);

% NEIGHBORHOOD FOR PARABOLA FIT
Nx = size(xx,2);

col_lo = max(col - 2, 1);
col_hi = min(col + 2, Nx);
cols = col_lo:col_hi;

p_vals = double(prob(row, cols));
x_vals = X(cols);

coeffs = polyfit(x_vals, p_vals, 2);
a = coeffs(1);
b = coeffs(2);

% PARABOLA PEAK
if a < 0
    x_peak = -b/(2*a);
    x_peak = max(x_vals(1), min(x_vals(end), x_peak));
else
    x_peak = x_snap;
end

% SHIFT
offset_cm = (x_peak - x_snap)*100;

% ===== TRANSECT AT Y =====
[~, y_idx] = min(abs(Y - y_target));
prob_transect = prob(y_idx, :);
mask = (X >= x_range(1)) & (X <= x_range(2));

figure
subplot(2,2,1)
imagesc(X, Y, prob)
set(gca,'YDir','normal')
hold on
plot(x_target, y_target,'rx','MarkerSize',12,'LineWidth',2)
plot(x_snap, y_target,'go','MarkerSize',10,'LineWidth',2)
xlabel('X (m)'); ylabel('Y (m)')
title('Full Crest Probability Field')
colormap(parula); colorbar

subplot(2,2,2)
imagesc(x_vals, 1, p_vals)
hold on
plot(x_peak, 1,'rv','MarkerFaceColor','r','MarkerSize',10)
plot(x_snap, 1,'go','MarkerSize',8)
set(gca,'YTick',[])
xlabel('X neighborhood (m)')
title('Parabola Fit at Point')

subplot(2,2,3)
plot(X(mask), prob_transect(mask),'k','LineWidth',1.5)
grid on
xlabel('Cross-shore X (m)')
ylabel('Probability')
title(sprintf('Transect at Y ≈ %.3f m', Y(y_idx)))
xline(x_target, 'r--', LineWidth=2)

subplot(2,2,4)
plot(x_vals, p_vals,'ko','MarkerFaceColor','k'); hold on
x_dense = linspace(x_vals(1), x_vals(end), 200);
p_fit = polyval(coeffs, x_dense);

if a < 0
    plot(x_dense, p_fit,'b-','LineWidth',2)
    plot(x_peak, polyval(coeffs,x_peak),'rv','MarkerFaceColor','r')
end

grid on
xlabel('X (m)')
ylabel('Prob')
title(sprintf('Shift = %.2f cm', offset_cm))
sgtitle('Crest Probability + Parabola Subgrid Shift Inspection')



%% individual point transect + parabola shift inspection

% USER INPUT
k_vis = 15; % frame to visualize

% x_target = 160.098; % working example, good fit
% y_target = 810.646;

x_target = 148.431;
y_target = 870.822;
x_range = [138 158];

IMG = zeros([size(xx), 3]);
for ii = 1:3
    IMG(:,:,ii) = interp2(U, V, rawFrames{k_vis + ii - 1}, Uint, Vint, 'linear', nan);
end

dt = 1 / info.freq;
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

if size(prob,1) ~= length(Y)
    prob = prob';
end

% SNAP POINT TO GRID
dist2 = (xx - x_target).^2 + (yy - y_target).^2;
[~, ind_min] = min(dist2(:));
[row, col] = ind2sub(size(xx), ind_min);
x_snap = xx(row,col);

% NEIGHBORHOOD FOR PARABOLA FIT
Nx = size(xx,2);
col_lo = max(col - 2, 1);
col_hi = min(col + 2, Nx);
cols = col_lo:col_hi;
p_vals = double(prob(row, cols));
x_vals = X(cols);
coeffs = polyfit(x_vals, p_vals, 2);
a = coeffs(1);
b = coeffs(2);

% PARABOLA PEAK
if a < 0
    x_peak = -b/(2*a);
    x_peak = max(x_vals(1), min(x_vals(end), x_peak));
else
    x_peak = x_snap;
end
offset_cm = (x_peak - x_snap)*100;
% TRANSECT AT Y
[~, y_idx] = min(abs(Y - y_target));
prob_transect = prob(y_idx, :);
mask = (X >= x_range(1)) & (X <= x_range(2));
figure

% Full probability field
subplot(2,2,1)
imagesc(X, Y, prob)
set(gca,'YDir','normal')
hold on
h1 = plot(x_target, y_target, 'rx', 'MarkerSize',12, 'LineWidth',2);
h2 = plot(x_snap, y_target, 'go', 'MarkerSize',10, 'LineWidth',2);
xlabel('Cross-shore X (m)')
ylabel('Alongshore Y (m)')
title('Full Crest Probability Field')
legend([h1 h2], {'Sub-grid peak','Nearest grid node'}, 'Location','northeast')
colormap(parula)
colorbar

% Neighborhood view
subplot(2,2,2)
imagesc(x_vals,1,p_vals)
hold on
h1 = plot(x_peak,1,'rv','MarkerFaceColor','r','MarkerSize',10);
h2 = plot(x_snap,1,'go','MarkerSize',8,'LineWidth',1.5);
set(gca,'YTick',[])
xlabel('Cross-shore X (m)')
title('Parabola Fit Neighborhood')
legend([h1 h2], {'Sub-grid peak','Snapped grid node'}, 'Location','northeast')

% Cross-shore transect
subplot(2,2,3)
h1 = plot(X(mask), prob_transect(mask), 'k', 'LineWidth',1.5);
hold on
h2 = xline(x_target, 'r--', 'LineWidth',2);
grid on
xlabel('Cross-shore X (m)')
ylabel('Crest Probability')
title(sprintf('Transect at Y = %.3f m', Y(y_idx)))
legend([h1 h2], {'Crest probability transect','Parabola Fit CS location'}, 'Location','best')

% Parabola fit
subplot(2,2,4)
h1 = plot(x_vals, p_vals, 'ko', 'MarkerFaceColor','k');
hold on
x_dense = linspace(x_vals(1), x_vals(end), 200);
p_fit = polyval(coeffs, x_dense);

if a < 0
    h2 = plot(x_dense, p_fit, 'b-', 'LineWidth',2);
    h3 = plot(x_peak, polyval(coeffs,x_peak), 'rv', 'MarkerFaceColor','r');
end

grid on
xlabel('Cross-shore X (m)')
ylabel('Crest Probability')
title(sprintf('Shift = %.2f cm', offset_cm))
sgtitle(sprintf('Frame %d | Point (%.3f, %.3f) m | Crest Probability + Parabola Shift Inspection', k_vis, x_target, y_target))


%% 2 subplot, from slides, prob field and prob graph
% USER INPUT
k_vis = 1; % frame to visualize

x_target = 160.098; % working example, good fit
y_target = 810.646;

% x_target = 148.431;
% y_target = 870.822;
x_range = [150 170];

% ==========================
% BUILD IMAGE STACK
% ==========================
IMG = zeros([size(xx), 3]);

for ii = 1:3
    IMG(:,:,ii) = interp2(U, V, rawFrames{k_vis + ii - 1}, Uint, Vint,'linear', nan);
end

dt = 1 / info.freq;

[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

if size(prob,1) ~= length(Y)
    prob = prob';
end

% ==========================
% SNAP POINT TO GRID
% ==========================
dist2 = (xx - x_target).^2 + (yy - y_target).^2;

[~, ind_min] = min(dist2(:));

[row, col] = ind2sub(size(xx), ind_min);

x_snap = xx(row,col);
y_snap = yy(row,col);

% ==========================
% PARABOLA FIT
% ==========================
Nx = size(xx,2);

col_lo = max(col - 2, 1);
col_hi = min(col + 2, Nx);

cols = col_lo:col_hi;

p_vals = double(prob(row, cols));
x_vals = X(cols);

coeffs = polyfit(x_vals, p_vals, 2);

a = coeffs(1);
b = coeffs(2);

if a < 0
    x_peak = -b/(2*a);
    x_peak = max(x_vals(1), min(x_vals(end), x_peak));
else
    x_peak = x_snap;
end

offset_cm = (x_peak - x_snap) * 100;

% ==========================
% CROSS-SHORE TRANSECT
% ==========================
[~, y_idx] = min(abs(Y - y_target));

prob_transect = prob(y_idx, :);

mask = X >= x_range(1) & X <= x_range(2);

figure;
% --------------------------
% LEFT: FULL PROBABILITY FIELD
% --------------------------
subplot(1,2,1)

imagesc(X, Y, prob)

% set(gca,'YDir','normal')

hold on

h1 = plot(x_target, y_target, ...
    'rx', ...
    'MarkerSize',12, ...
    'LineWidth',2);

h2 = plot(x_snap, y_snap, ...
    'go', ...
    'MarkerSize',10, ...
    'LineWidth',2);

xlabel('Cross-shore X (m)')
ylabel('Alongshore Y (m)')

title('Full Crest Probability Field')

legend([h1 h2], ...
    {'Crest Point'}, ...
    'Location','northeast')

colormap(parula)
colorbar

% --------------------------
% RIGHT: CROSS-SHORE TRANSECT
% --------------------------
subplot(1,2,2)

h1 = plot(X(mask), prob_transect(mask), 'k', 'LineWidth',1.5);

hold on

h2 = xline(x_target, 'r--', 'LineWidth',2);

grid on

xlabel('Cross-shore X (m)')
ylabel('Crest Probability')

title(sprintf(['Probability Transect at Y = %.3f m'], Y(y_idx)))

legend([h1 h2], {'Crest probability transect', 'Grid-Snapped Point'}, 'Location','southwest')

%sgtitle(sprintf(['Crest Probability Inspection at ', 'Point (%.3f, %.3f)'], x_target, y_target))


function plot_frame_crest_lengths(k)
% plot_frame_crest_lengths(k) -- overlay traced crest paths on the UNET
% probability map for frame k, each labeled with its total crest length.
%
% Each crest is drawn as its own traced polyline through the (x,y) points
% stored for that cluster -- i.e. exactly the path that crestLen =
% sum(sqrt(diff(x).^2+diff(y).^2)) integrates over in
% bore_front_search_funwave_Prezley. There is no straight-line or
% alongshore-span substitute drawn anywhere here, so the line you see is
% the same path the length number was computed from.
%
% Requires in base workspace: rawFrames, Uint, Vint, U, V, X, Y, dt, xx, yy
% and separated_fronts with .x, .y, and .length fields per cluster.

rawFrames = evalin('base', 'rawFrames');
Uint      = evalin('base', 'Uint');
Vint      = evalin('base', 'Vint');
U         = evalin('base', 'U');
V         = evalin('base', 'V');
X         = evalin('base', 'X');
Y         = evalin('base', 'Y');
dt        = evalin('base', 'dt');
xx        = evalin('base', 'xx');
yy        = evalin('base', 'yy');

if evalin('base', 'exist(''separated_fronts'', ''var'')')
    separated_fronts = evalin('base', 'separated_fronts');
else
    error('separated_fronts not found in base workspace -- run the main pipeline through the clustering step first.');
end

if k < 1 || k+2 > numel(rawFrames)
    error('Frame %d needs rawFrames{%d}..{%d}, but only %d raw frames exist.', ...
        k, k, k+2, numel(rawFrames));
end
if length(separated_fronts) < k || isempty(separated_fronts{k})
    error('No fronts stored in separated_fronts{%d}.', k);
end

% --- rebuild 3-frame stack and recompute probability (same as main loop) ---
IMG = zeros([size(xx), 3]);
for ii = 1:3
    IMG(:,:,ii) = interp2(U, V, rawFrames{k+ii-1}, Uint, Vint, 'linear', nan);
end
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

fronts_k = separated_fronts{k};

% plot probability map
figure('Color', 'w');
imagesc(X, Y, prob);
colormap(gca, parula);
clim([0 1]);
set(gca, 'YDir', 'reverse');
cb = colorbar;
cb.Label.String = 'UNET probability';
hold on;
xlabel('Cross-shore [m]');
ylabel('Alongshore [m]');
title(sprintf('Crest Length Traces — Frame %d', k));
axis tight;

for i = 1:length(fronts_k)
    if ~isfield(fronts_k{i}, 'x') || ~isfield(fronts_k{i}, 'y')
        warning('Cluster %d in frame %d has no x/y fields -- skipping.', i, k);
        continue
    end
    x = fronts_k{i}.x(:);
    y = fronts_k{i}.y(:);
    if numel(x) < 2
        continue % need at least 2 points to trace a path
    end

    % draw the traced crest path itself -- this is what crestLen integrates
    plot(x, y, 'r-', 'LineWidth', 1.5);

    % label with the stored total length at the crest's mean location
    if isfield(fronts_k{i}, 'length') && isfield(fronts_k{i}, 'xc') && isfield(fronts_k{i}, 'yc')
        xc_i = fronts_k{i}.xc;
        yc_i = fronts_k{i}.yc;
        len_i = fronts_k{i}.length;
        text(xc_i, yc_i, sprintf('%.1f m', len_i), ...
            'Color', 'w', 'FontSize', 9, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    elseif isfield(fronts_k{i}, 'length')
        % fall back to midpoint of the traced path if xc/yc weren't stored
        mid = ceil(numel(x)/2);
        text(x(mid), y(mid), sprintf('%.1f m', fronts_k{i}.length), ...
            'Color', 'w', 'FontSize', 9, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    else
        warning('Cluster %d in frame %d has no length field -- path drawn without label.', i, k);
    end
end

hold off;
view([0 -90])
end
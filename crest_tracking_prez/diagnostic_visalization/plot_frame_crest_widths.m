
function plot_frame_crest_widths(k)
% plot_frame_crest_widths(k) -- overlay crest width vectors on the UNET
% probability map for frame k.
%
% Each width is drawn as a HORIZONTAL red line segment. This matches
% exactly how bore_front_search_funwave_Prezley measures width: a
% fixed-AS-column scan across CS, walking outward from the probability
% peak (xsub) until the Pnon threshold is crossed on either side. There
% is no crest-normal or tangent-based measurement anywhere in that
% function, so drawing the segment at any angle other than horizontal
% would misrepresent what was actually computed.
%
% Requires in base workspace: rawFrames, Uint, Vint, U, V, X, Y, dt, xx, yy
% and separated_fronts with a .width field per cluster.

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
clim([0 1]);                 % lock colorbar to full 0-1 probability range
set(gca, 'YDir', 'reverse'); % explicit, matches imagesc default orientation
cb = colorbar;
cb.Label.String = 'UNET probability';
hold on;
xlabel('Cross-shore [m]');
ylabel('Alongshore [m]');
title(sprintf('Crest Width Vectors — Frame %d', k));
axis tight;

% --- collect all horizontal width segments, then draw in one call ---
xseg = [];
yseg = [];

max_crest_width = 8; % m; exclude from plot only

for i = 1:length(fronts_k)

    if ~isfield(fronts_k{i}, 'width')
        warning('Cluster %d in frame %d has no width field -- skipping.', i, k);
        continue
    end

    x = fronts_k{i}.x(:);
    y = fronts_k{i}.y(:);
    w = fronts_k{i}.width(:);

    if numel(x) ~= numel(w)
        warning('Cluster %d: width count (%d) does not match point count (%d) -- skipping.', ...
            i, numel(w), numel(x));
        continue
    end

    keep = w <= max_crest_width;   % drop spurious width detections
    x = x(keep);
    y = y(keep);
    w = w(keep);

    if isempty(x)
        continue
    end

    x1 = x - w/2;
    x2 = x + w/2;
    n  = numel(x);

    xc = nan(3*n, 1);
    xc(1:3:end) = x1;
    xc(2:3:end) = x2;

    yc = nan(3*n, 1);
    yc(1:3:end) = y;
    yc(2:3:end) = y;

    xseg = [xseg; xc]; %#ok<AGROW>
    yseg = [yseg; yc]; %#ok<AGROW>
end

if ~isempty(xseg)
    plot(xseg, yseg, 'r-', 'LineWidth', 1.2);
end

hold off;
view([0 -90]);
end
function inspect_frame_3panel(k, t_step, t_total)
% inspect_frame_3panel(k, t_step, t_total)
%   3-panel figure: (1) rectified RGB-stack background image for frame k,
%   (2) UNET probability map for frame k, (3) detected crests sampled
%   every t_step seconds out to t_total seconds, colored by time.
%
%   inspect_frame_3panel(k) uses t_step = 1, t_total = 5.
%
% Requires in base workspace: rawFrames, Uint, Vint, U, V, X, Y, dt, xx, yy
% and (for panel 3) separated_fronts — a cell array where
% separated_fronts{frame_idx} is a cell array of structs with fields x, y.

if nargin < 2
    t_step = 1;
end
if nargin < 3
    t_total = 5;
end

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
    separated_fronts = {};
end

%% --- Build 3-frame rectified RGB stack for frame k (same as reference) ---
IMG = zeros([size(xx), 3]);
for ii = 1:3
    IMG(:,:,ii) = interp2(U, V, rawFrames{k+ii-1}, Uint, Vint, 'linear', nan);
end

% UNET probability for this stack
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

%% --- Figure layout ---
figure('Color', 'w');
tl = tiledlayout(1, 3, 'TileSpacing', 'tight', 'Padding', 'compact');

% ---------- Panel 1: rectified RGB stack ----------
ax1 = nexttile(tl);
IMGdisp = IMG;
validMask = all(~isnan(IMGdisp), 3);
IMGdisp(IMGdisp < 0) = 0;
mx = max(IMGdisp(:), [], 'omitnan');
if mx > 0
    IMGdisp = IMGdisp / mx;
end
for c = 1:3
    layer = IMGdisp(:,:,c);
    layer(~validMask) = 1;   % show invalid region as white
    IMGdisp(:,:,c) = layer;
end
image(ax1, X, Y, IMGdisp);
set(ax1, 'YDir', 'reverse');
xlabel(ax1, 'x (m)'); ylabel(ax1, 'y (m)');
title('Rectified IMG', FontSize=15);
axis(ax1, 'tight'); view([0 -90])


% ---------- Panel 2: UNET probability map ----------
ax2 = nexttile(tl);
probDisp = prob;
probDisp(~validMask) = NaN;
imagesc(ax2, X, Y, probDisp, 'AlphaData', ~isnan(probDisp));
set(ax2, 'YDir', 'reverse', 'YTickLabel', [], 'Color', 'w');
colormap(ax2, gray);
xlabel(ax2, 'x (m)');
title('U-Net Probability', FontSize=15);
axis(ax2, 'tight'); view([0 -90])

% ---------- Panel 3: crests every t_step s out to t_total s ----------
ax3 = nexttile(tl);
hold(ax3, 'on');

% flat background patch over the valid (rectified) domain, white outside
bgColor = [0.68 0.74 0.80];
bgRGB = ones([size(validMask), 3]);
for c = 1:3
    layer = bgRGB(:,:,c);
    layer(validMask) = bgColor(c);
    bgRGB(:,:,c) = layer;
end
image(ax3, X, Y, bgRGB);

tvals = 0:t_step:t_total;
cmap = local_time_colormap(256);
for t_j = tvals
    frame_idx = k + round(t_j / dt);
    if frame_idx > numel(separated_fronts) || isempty(separated_fronts{frame_idx})
        continue;
    end
    cidx = 1 + round((size(cmap,1)-1) * (t_j / t_total));
    col = cmap(cidx, :);
    fronts_j = separated_fronts{frame_idx};
    for i = 1:numel(fronts_j)
        plot(ax3, fronts_j{i}.x, fronts_j{i}.y, '.', 'Color', col, 'MarkerSize', 6);
    end
end
hold(ax3, 'off');
set(ax3, 'YDir', 'reverse', 'YTickLabel', []);
xlabel(ax3, 'x (m)');
title('Crests (every 1s)', FontSize=15);
axis(ax3, 'tight'); view([0 -90])

colormap(ax3, cmap);
caxis(ax3, [0 t_total]);
cb3 = colorbar(ax3, 'Location', 'east');
cb3.Label.String = 't (s)';
cb3.Ticks = [0:5];

end

function cmap = local_time_colormap(n)
% Plasma-like colormap (dark navy -> purple -> pink -> orange) without
% requiring any extra toolbox.
if nargin < 1
    n = 256;
end
anchors = [0.05 0.05 0.30;   % dark navy   (t = 0)
           0.30 0.10 0.55;   % purple
           0.60 0.30 0.65;   % violet
           0.85 0.45 0.50;   % pink/salmon
           0.95 0.65 0.20];  % orange      (t = max)
xa = linspace(0, 1, size(anchors,1));
xq = linspace(0, 1, n);
cmap = interp1(xa, anchors, xq, 'pchip');
cmap = min(max(cmap, 0), 1);
end
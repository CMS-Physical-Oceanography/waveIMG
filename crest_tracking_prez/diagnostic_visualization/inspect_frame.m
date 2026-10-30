function inspect_frame(k)
% inspect_frame(k) -- rectified image and UNET probability for frame k
% Requires in base workspace: rect_all, X, Y, dt (and optionally separated_fronts)
rect_all = evalin('base', 'rect_all');
X        = evalin('base', 'X');
Y        = evalin('base', 'Y');
dt       = evalin('base', 'dt');
if evalin('base', 'exist(''separated_fronts'', ''var'')')
    separated_fronts = evalin('base', 'separated_fronts');
else
    separated_fronts = {};
end

% same 3-frame stack as the main loop
IMG = cat(3, rect_all{k}, rect_all{k+1}, rect_all{k+2});
rectified = IMG(:,:,2);

% recompute UNET probability for this stack
[~, prob, ~, ~, ~] = wave_front_from_IMG_UNET(IMG, X, Y, dt, 0);

% Plot side-by-side
figure;

% left: rectified B/W image with tracked crest overlay
subplot(1,2,1);
imagesc(X, Y, rectified);
set(gca, 'YDir', 'reverse');
colormap(gca, gray);
hold on;
if ~isempty(separated_fronts) && iscell(separated_fronts) && length(separated_fronts) >= k
    fronts_k = separated_fronts{k};
    if ~isempty(fronts_k)
        for i = 1:length(fronts_k)
            plot(fronts_k{i}.x, fronts_k{i}.y, 'r.', 'MarkerSize', 8);
        end
    end
end
hold off;
title(sprintf('Rectified B/W + Fronts — Frame %d', k));

% right: UNET probability, no tracked crest overlay
subplot(1,2,2);
imagesc(X, Y, prob);
set(gca, 'YDir', 'reverse');
% colorbar;
% axis equal tight;
title(sprintf('UNET Probability — Frame %d', k));
view();
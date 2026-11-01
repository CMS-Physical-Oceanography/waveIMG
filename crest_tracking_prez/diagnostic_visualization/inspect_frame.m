
function inspect_frame(k)
% inspect_frame(k) -- rectified image and UNET probability for frame k
% Re-reads frames k..k+2 from the video (nothing large is kept in memory).
% Requires in base workspace: videoPath, frameTimes, U, V, Uint, Vint, X, Y, dt,
% enhance_image (and foam_th if enhanced); optionally separated_fronts.
B = @(n) evalin('base', n);
U = B('U'); V = B('V'); Uint = B('Uint'); Vint = B('Vint');
X = B('X'); Y = B('Y'); dt = B('dt'); frameTimes = B('frameTimes');
enh = B('enhance_image');
if enh; foam_th = B('foam_th'); end
if evalin('base', 'exist(''separated_fronts'', ''var'')')
    separated_fronts = B('separated_fronts');
else
    separated_fronts = {};
end

vid = VideoReader(B('videoPath'));
vid.CurrentTime = frameTimes(k);          % jump to frame k
IMG = zeros([size(Uint), 3]);
for ii = 1:3
    r = interp2(U, V, double(rgb2gray(readFrame(vid))), Uint, Vint, 'linear', nan);
    if enh
        r = 255./(1+exp(-3*pi/2*(r-foam_th)/(255-foam_th)));
    end
    IMG(:,:,ii) = r;
end
rectified = IMG(:,:,2);

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
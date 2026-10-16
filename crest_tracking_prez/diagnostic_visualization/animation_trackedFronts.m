% ANIMATED TRACKED FRONTS - only shows last 5mins of hour

%% USER INPUT
dateTag  = '1002';    % MMDD
hourStr  = '1200';    % HHMM

frame_range = [];     % [] = all frames, or e.g. [1 200]
frame_step  = 1;      % 1 = every frame, 2 = every other, ...
pause_time  = 0.1;    % s between frames on screen (0.2 = real time at 5 Hz)
show_raw    = false;  % also draw the un-velocity-filtered fronts in grey behind
xlims       = [];     % [] = full rectified extent, or e.g. [85 200]
ylims       = [];     % [] = full, or e.g. [602 1000]

save_video  = false;  % write an .mp4 next to this script
video_fps   = 5;

baseDir = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/' ...
    'waveIMG_cpy/waveIMG-main/waveIMG-main'];

%% LOAD
matFile = fullfile(baseDir,'mat_data',sprintf('%s_%s.mat',dateTag,hourStr));
D = load(matFile, 'rectified_frames','separated_fronts_filtered','separated_fronts', ...
    'frontIDs','X','Y','dt','frameTimes','fileStartStamp','sensors');

need = {'rectified_frames','separated_fronts_filtered','frontIDs','X','Y'};
missing = need(~isfield(D, need));
if ~isempty(missing)
    error('%s is missing: %s', matFile, strjoin(missing, ', '));
end

RF = D.rectified_frames;
FF = D.separated_fronts_filtered;
ID = D.frontIDs;
Xg = D.X; Yg = D.Y;
nF = numel(RF);

if isempty(frame_range); frame_range = [1 nF]; end
frames = frame_range(1):frame_step:min(frame_range(2), nF);

% absolute timestamp per frame -- rectified_frames{k} was built from frameTimes(k+1).
% rectified_frames is preallocated to vid.NumFrames but only filled to NumFrames-2,
% so numel(frameTimes) == nF and a `>= nF+1` test could never pass.
have_t = isfield(D,'frameTimes') && isfield(D,'fileStartStamp') && numel(D.frameTimes) >= 2;
dt_use = 0.2; if isfield(D,'dt'); dt_use = D.dt; end
t_abs  = NaT(1,nF);
if have_t
    nT = min(nF, numel(D.frameTimes) - 1);
    t_abs(1:nT) = D.fileStartStamp + seconds(D.frameTimes(2:nT+1));
else
    warning('frameTimes/fileStartStamp unavailable -- falling back to elapsed time from frame 1.');
end

% sensor marker, if it was saved
have_q22 = isfield(D,'sensors') && isfield(D.sensors,'q22') && isfield(D.sensors.q22,'x');

% fixed grey scale across the whole animation -- otherwise imagesc rescales every
% frame and the background flickers
bg0 = [];
for k = frames
    if ~isempty(RF{k}); bg0 = RF{k}; break; end
end
if isempty(bg0); error('No non-empty rectified frames in the requested range.'); end
cl = prctile(bg0(~isnan(bg0)), [1 99]);

cmap7 = lines(7);   % lines(N) just cycles these 7, so this matches globalColors(id,:)

%% FIGURE -- built once, updated in place (much faster than clf every frame)
fig = figure('Color','w');
ax  = axes(fig); hold(ax,'on')

him = imagesc(ax, Xg, Yg, nan(numel(Yg), numel(Xg)));
set(him,'AlphaData',0)
colormap(ax, bone); clim(ax, cl);
set(ax,'YDir','normal')          % matches every other figure in the pipeline
box(ax,'on'); grid(ax,'minor')
xlabel(ax,'Cross-shore [m]'); ylabel(ax,'Alongshore [m]')
if isempty(xlims); xlims = [min(Xg) max(Xg)]; end
if isempty(ylims); ylims = [min(Yg) max(Yg)]; end
xlim(ax, xlims); ylim(ax, ylims)

% if have_q22
%     plot(ax, D.sensors.q22.x, D.sensors.q22.y, 'p', 'MarkerSize',12, ...
%         'MarkerFaceColor','r', 'MarkerEdgeColor','r')
% end

ht = title(ax, '', 'FontSize', 14);
front_h = gobjects(0);   % handles to this frame's front markers

if save_video
    vidName = sprintf('tracked_fronts_%s_%s.mp4', dateTag, hourStr);
    vw = VideoWriter(vidName, 'MPEG-4');
    vw.FrameRate = video_fps;
    open(vw);
end

%% ANIMATE
for k = frames
    if isempty(RF{k}); continue; end

    set(him, 'CData', RF{k}, 'AlphaData', ~isnan(RF{k}));

    delete(front_h);
    front_h = gobjects(0);

    if show_raw && isfield(D,'separated_fronts') && k <= numel(D.separated_fronts)
        fr = D.separated_fronts{k};
        for i = 1:numel(fr)
            front_h(end+1) = plot(ax, fr{i}.x, fr{i}.y, '.', ...
                'Color',[0.65 0.65 0.65], 'MarkerSize',4); %#ok<SAGROW>
        end
    end

    if k <= numel(FF) && ~isempty(FF{k})
        fronts_k = FF{k};
        IDs_k    = ID{k};
        for i = 1:numel(fronts_k)
            if i <= numel(IDs_k) && IDs_k(i) > 0
                col = cmap7(mod(IDs_k(i)-1, 7)+1, :);
            else
                col = [0 0 0];
            end
            front_h(end+1) = plot(ax, fronts_k{i}.x, fronts_k{i}.y, '.', ...
                'Color',col, 'MarkerSize',10); %#ok<SAGROW>
        end
    end

    if ~isnat(t_abs(k))
        set(ht, 'String', sprintf('Tracked Fronts at %s', string(t_abs(k), 'HH:mm:ss')));
    else
        set(ht, 'String', sprintf('Tracked Fronts at t + %.2f s', (k-1)*dt_use));
    end

    drawnow limitrate

    if save_video
        writeVideo(vw, getframe(fig));
    elseif pause_time > 0
        pause(pause_time)
    end
end

if save_video
    close(vw);
    fprintf('Wrote %s (%d frames @ %d fps)\n', vidName, numel(frames), video_fps);
end

tv = t_abs(frames); tv = tv(~isnat(tv));
if ~isempty(tv)
    fprintf('Animated %s -> %s\n', string(min(tv)), string(max(tv)));
end
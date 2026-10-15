% CREST LENGTH -- from bore_front_search_length rcsummary (xc, yc, width, length)
%
% Uses the detector's own per-crest length and centroid, taken BEFORE DBSCAN and
% before the 25-point cluster filter, so there is no ~20 m detection floor. The
% price is that nothing rejects noise, hence min_crest_len below.
%
% Edge handling: rcsummary has no per-point coordinates, so a crest is approximated
% as an alongshore segment of length L centred on (xc,yc). It is discarded if the
% centroid or either approximate end lies within edge_buffer of the footprint.

%% USER INPUT
dateTag  = '0925';    % MMDD
hourStr  = '1700';    % HHMM
year_str = '2013';    % survey / tide file year

min_crest_len = 3;    % m, discard crests shorter than this (noise floor)
edge_buffer   = 1;    % m, discard a crest reaching this close to the domain edge
bin_size      = 5;    % m, map grid
xprof_bin     = 5;    % m, cross-shore profile bin
min_samples   = 5;    % min crests in a map bin before it's plotted
min_prof      = 10;   % min crests in a cross-shore bin before it's plotted

show_domain_check = true;

baseDir = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/' ...
'waveIMG_cpy/waveIMG-main/waveIMG-main'];

%% LOAD
matFile = fullfile(baseDir,'mat_data',sprintf('%s_%s.mat',dateTag,hourStr));
S  = load(matFile, 'all_crest_summary','X','Y');
CS = S.all_crest_summary;
Xg = S.X(:).';
Yg = S.Y(:).';
dateTimeLabel = sprintf('%s/%s %s:%s', dateTag(1:2), dateTag(3:4), hourStr(1:2), hourStr(3:4));

R = load(matFile, 'rectified_frames');
bg = [];
for kk = 1:numel(R.rectified_frames)
    if ~isempty(R.rectified_frames{kk}); bg = R.rectified_frames{kk}; break; end
end
clear R
if isempty(bg)
    error('No non-empty rectified_frames in %s -- cannot define the domain footprint.', matFile);
end
valid = ~isnan(bg);
fprintf('Rectified footprint: %d / %d grid cells valid (%.1f%%)\n', ...
    nnz(valid), numel(valid), 100*nnz(valid)/numel(valid));

%% DOMAIN EDGE
vpad = false(size(valid)+2);
vpad(2:end-1,2:end-1) = valid;
edge_cell = valid & ( ~vpad(1:end-2,2:end-1) | ~vpad(3:end,2:end-1) | ...
                      ~vpad(2:end-1,1:end-2) | ~vpad(2:end-1,3:end) );
[er, ec] = find(edge_cell);
edge_xy  = [reshape(Xg(ec),[],1), reshape(Yg(er),[],1)];
fprintf('Domain boundary cells: %d\n', size(edge_xy,1));

%% FLATTEN rcsummary -> one row per crest
rows = cell(numel(CS),1);
nfr  = 0;
for k = 1:numel(CS)
    r = CS{k};
    if isempty(r) || ~isstruct(r); continue; end
    nfr = nfr + 1;
    L  = [r.length].';  xc = [r.xc].';  yc = [r.yc].';  wd = [r.width].';
    n  = min([numel(L) numel(xc) numel(yc) numel(wd)]);
    rows{k} = [repmat(k,n,1), L(1:n), xc(1:n), yc(1:n), wd(1:n)];
end
A = vertcat(rows{:});                       % [frame, L, xc, yc, width]
fprintf('Frames with crests: %d | raw crests: %d\n', nfr, size(A,1));

good = isfinite(A(:,2)) & isfinite(A(:,3)) & isfinite(A(:,4)) & A(:,2) >= min_crest_len;
A = A(good,:);
fprintf('After length >= %.1f m: %d crests\n', min_crest_len, size(A,1));

%% EDGE TEST -- centroid and both approximate crest ends
xc = A(:,3); yc = A(:,4); LL = A(:,2);
qx = [xc; xc; xc];
qy = [yc; yc - LL/2; yc + LL/2];

[~, dq] = knnsearch(edge_xy, [qx qy]);
iX = min(max(round(interp1(Xg, 1:numel(Xg), qx, 'nearest','extrap')),1), numel(Xg));
iY = min(max(round(interp1(Yg, 1:numel(Yg), qy, 'nearest','extrap')),1), numel(Yg));
dq(~valid(sub2ind(size(valid), iY, iX))) = 0;

n = numel(xc);
d_min = min([dq(1:n), dq(n+1:2*n), dq(2*n+1:3*n)], [], 2);

crest_log = [A, d_min, double(d_min >= edge_buffer)];   % [frame,L,xc,yc,width,d_edge,keep]
kept = crest_log(:,7) == 1;

fprintf('Kept: %d | rejected at edge: %d (%.1f%%)\n', ...
    sum(kept), sum(~kept), 100*mean(~kept));
fprintf('Kept crest length: mean %.1f m | median %.1f m | p95 %.1f m | max %.1f m\n', ...
    mean(crest_log(kept,2)), median(crest_log(kept,2)), ...
    prctile(crest_log(kept,2),95), max(crest_log(kept,2)));

xm = crest_log(kept,3);
ym = crest_log(kept,4);
Lm = crest_log(kept,2);

%% DOMAIN / BUFFER CHECK FIGURE
if show_domain_check
    [XX, YY] = meshgrid(Xg, Yg);
    d_grid = nan(size(valid));
    [~, dv] = knnsearch(edge_xy, [XX(valid), YY(valid)]);
    d_grid(valid) = dv;

    figure; hold on

    contour(Xg, Yg, d_grid, [edge_buffer edge_buffer], 'Color','k', 'LineWidth',1.5);
    scatter(crest_log(~kept,3), crest_log(~kept,4), 6, 'r', 'filled', ...
        'MarkerFaceAlpha', 0.25)
    scatter(crest_log(kept,3),  crest_log(kept,4),  6, 'b', 'filled', ...
        'MarkerFaceAlpha', 0.25)
    axis tight; box on
    xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
    title(sprintf('Rectified Footprint, %.0f m Edge Buffer - %s', edge_buffer, dateTimeLabel), ...
        'FontSize', 15)
    text(0.02, 0.97, sprintf('red = rejected (%d)   blue = kept (%d)', sum(~kept), sum(kept)), ...
        'Units','normalized', 'VerticalAlignment','top', 'FontWeight','bold')
end

%% DOMAIN CHECK FIGURE -- FULL CREST EXTENT (not just centroids)
% Same figure as above, but instead of one point per crest at its centroid,
% draw the crest's full reported alongshore extent as a line segment
% [yc-L/2, yc+L/2] at x = xc. This shows how much physical crest length is
% actually being thrown out near the edge, rather than just whether the
% centroid happened to land inside the buffer.
if show_domain_check
    xk  = crest_log(:,3);
    yc0 = crest_log(:,4);
    Lk  = crest_log(:,2);
    y1  = yc0 - Lk/2;
    y2  = yc0 + Lk/2;
    isKept = crest_log(:,7) == 1;

    % NaN-separated segment lists so each color group draws in one plot()
    % call instead of one line() per crest (much faster for large A).
    segX = @(m) reshape([xk(m)  xk(m)  nan(sum(m),1)].', [], 1);
    segY = @(m) reshape([y1(m)  y2(m)  nan(sum(m),1)].', [], 1);

    figure; hold on
   
    contour(Xg, Yg, d_grid, [edge_buffer edge_buffer], 'Color','k', 'LineWidth',1.5);
    scatter(xk(isKept), yc0(isKept), 6, 'b', 'filled', 'MarkerFaceAlpha', 0.25)
    plot(segX(~isKept), segY(~isKept), '-', 'Color','r', 'LineWidth',0.1)

    axis tight; box on
    xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
    title(sprintf('Rectified Footprint,  %s (full crest extent)', dateTimeLabel))
    text(0.02, 0.97, sprintf('rejected crests (%d), kept crests (%d)', ...
        sum(~isKept), sum(isKept)), 'Units','normalized', 'VerticalAlignment','top','FontWeight','bold')
end

%% BIN THE CENTROIDS
x_edges = min(xm) : bin_size : max(xm) + bin_size;
y_edges = min(ym) : bin_size : max(ym) + bin_size;
x_centers = x_edges(1:end-1) + bin_size/2;
y_centers = y_edges(1:end-1) + bin_size/2;
n_xbins = numel(x_centers);
n_ybins = numel(y_centers);

xi = discretize(xm, x_edges);
yi = discretize(ym, y_edges);
ok = ~isnan(xi) & ~isnan(yi);

lin   = sub2ind([n_ybins n_xbins], yi(ok), xi(ok));
N     = n_ybins * n_xbins;
sum_v = accumarray(lin, Lm(ok), [N 1], @sum, 0);
n_v   = accumarray(lin, 1,      [N 1], @sum, 0);

len_vec = nan(N,1);
keep_bin = n_v >= min_samples;
len_vec(keep_bin) = sum_v(keep_bin) ./ n_v(keep_bin);

len_grid = reshape(len_vec, [n_ybins n_xbins]);
n_grid   = reshape(n_v,     [n_ybins n_xbins]);
fprintf('Map bins with >= %d crests: %d / %d\n', min_samples, sum(keep_bin), N);

%% BIN CREST EXTENTS -- fraction of crests kept vs. rejected/truncated per bin
% Instead of binning only each crest's centroid, expand every crest into
% the full alongshore extent [yc-L/2, yc+L/2] at x = xc, and mark EVERY
% bin that extent overlaps. A crest counts once in each bin it touches, so
% a bin only grazed by the tip of a long rejected crest still shows up
% with a reduced kept-fraction -- not just the bin containing that
% crest's centroid.

xa  = crest_log(:,3);
La  = crest_log(:,2);
yc0 = crest_log(:,4);
y1a = yc0 - La/2;
y2a = yc0 + La/2;
ka  = crest_log(:,7) == 1;      % per-crest keep flag
nCrestA = numel(xa);

xa_edges = min(xa)  : bin_size : max(xa)  + bin_size;
ya_edges = min(y1a) : bin_size : max(y2a) + bin_size;
xa_centers = xa_edges(1:end-1) + bin_size/2;
ya_centers = ya_edges(1:end-1) + bin_size/2;
n_xabins = numel(xa_centers);
n_yabins = numel(ya_centers);

xai = discretize(xa,  xa_edges);
yi1 = discretize(y1a, ya_edges);
yi2 = discretize(y2a, ya_edges);

validRow = ~isnan(xai) & ~isnan(yi1) & ~isnan(yi2);
y_bins_cell = cell(nCrestA,1);
y_bins_cell(validRow) = arrayfun(@(i) (yi1(i):yi2(i)).', ...
    find(validRow), 'UniformOutput', false);

nTouch = cellfun(@numel, y_bins_cell);
xbin_t = repelem(xai, nTouch);
keep_t = repelem(ka,  nTouch);
ybin_t = vertcat(y_bins_cell{:});

lin_t = sub2ind([n_yabins n_xabins], ybin_t, xbin_t);
Na = n_yabins * n_xabins;

n_tot_a  = accumarray(lin_t, 1,      [Na 1], @sum, 0);
n_kept_a = accumarray(lin_t, keep_t, [Na 1], @sum, 0);

frac_kept = nan(Na,1);
has_data  = n_tot_a >= min_samples;
frac_kept(has_data) = 100 * n_kept_a(has_data) ./ n_tot_a(has_data);

frac_grid = reshape(frac_kept, [n_yabins n_xabins]);
fprintf('Fraction-kept (full extent) map: %d / %d bins with >= %d crest-touches\n', ...
    sum(has_data), Na, min_samples);

% PLOT -- % of crests kept per bin (full extent)
figure
h = imagesc(xa_centers, ya_centers, frac_grid);
set(h,'AlphaData',~isnan(frac_grid))
set(gca,'YDir','normal')
axis tight; box on; grid minor
colormap(flipud(cmocean('balance')));
cb = colorbar; cb.Label.String = '% of crests kept (full extent)';
clim([0 100])
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Percent of Kept Crests - %s', dateTimeLabel))
xlim([90 170]); ylim([602 1000])

%% PLOT -- mean crest length map
figure
h = imagesc(x_centers, y_centers, len_grid);
set(h,'AlphaData',~isnan(len_grid))
set(gca,'YDir','normal')
axis tight; box on; grid minor
cmocean('-thermal');
cb = colorbar; cb.Label.String = 'Mean crest length [m]';
clim([0 ceil(prctile(Lm,95)/5)*5])
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title("Mean Crest Length - " + string(dateTimeLabel));
xlim([90 170]); ylim([602 1000])

%% PLOT -- crest count per bin
figure
h = imagesc(x_centers, y_centers, n_grid);
set(h,'AlphaData',n_grid > 0)
set(gca,'YDir','normal')
axis tight; box on; grid minor
cmocean('-gray');
cb = colorbar; cb.Label.String = 'Crests per bin';
clim
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Crest Counts - %s', dateTimeLabel), 'FontSize', 15)
xlim([90 170]); ylim([602 1000])

%% PLOT -- mean crest length vs cross-shore
xp_edges   = floor(min(xm)/xprof_bin)*xprof_bin : xprof_bin : ceil(max(xm)/xprof_bin)*xprof_bin + xprof_bin;
xp_centers = xp_edges(1:end-1) + xprof_bin/2;
nb = numel(xp_centers);

bi   = discretize(xm, xp_edges);
okp  = ~isnan(bi);
n_p    = accumarray(bi(okp), 1,       [nb 1], @sum,  0);
mean_p = accumarray(bi(okp), Lm(okp), [nb 1], @mean, NaN);
std_p  = accumarray(bi(okp), Lm(okp), [nb 1], @std,  NaN);

thin = n_p < min_prof;
mean_p(thin) = NaN;
std_p(thin)  = NaN;

figure
subplot(3,1,[1 2]); hold on
scatter(xm, Lm, 6, [0.30 0.55 0.95], 'filled', 'MarkerFaceAlpha', 0.12)
errorbar(xp_centers, mean_p, std_p, 'o-', 'Color',[0.10 0.30 0.80], ...
    'MarkerFaceColor',[0.10 0.30 0.80], 'MarkerSize',6, 'LineWidth',1.5, 'CapSize',4)
box on; grid minor; set(gca,'Layer','top')
ylabel('Crest length [m]')
title(sprintf('Mean Crest Length vs Cross-shore - %s (%.0f m bins, \\pm1\\sigma)', ...
    dateTimeLabel, xprof_bin), 'FontSize', 15)
xlim([min(xp_edges) max(xp_edges)])
ylim([0 ceil(prctile(Lm,99)/5)*5])

subplot(3,1,3)
bar(xp_centers, n_p, 1, EdgeColor='none');
box on; grid minor; set(gca,'Layer','top')
xlabel('Cross-shore [m]'); ylabel('Crest Count')
xlim([min(xp_edges) max(xp_edges)])

%% ================= CREST LENGTH vs SURVEYED DEPTH =================
surveyDir = fullfile(baseDir,'data','bathy_surveys');
tideFile  = fullfile(baseDir,'data','tide_duck','duck_waterLvls2013.csv');

sf = fullfile(surveyDir, sprintf('RODDebbieTimeLagFix_%s%s.xyz', year_str, dateTag));
if ~isfile(sf)
    dlist = dir(fullfile(surveyDir,'RODDebbieTimeLagFix_*.xyz'));
    if isempty(dlist); error('No survey files found in %s', surveyDir); end
    dts = NaT(numel(dlist),1);
    for k = 1:numel(dlist)
        tok = regexp(dlist(k).name,'(\d{8})','tokens','once');
        if ~isempty(tok); dts(k) = datetime(tok{1},'InputFormat','yyyyMMdd'); end
    end
    target = datetime([year_str dateTag],'InputFormat','yyyyMMdd');
    [~, ibn] = min(abs(dts - target));
    sf = fullfile(surveyDir, dlist(ibn).name);
    warning('No survey for %s -- using nearest (%s, %+d days).', ...
        dateTag, dlist(ibn).name, days(dts(ibn)-target));
end

Tt = readtable(tideFile,'TextType','string');
tideTime = datetime(Tt.Date,'InputFormat','yyyy/MM/dd') + ...
           duration(Tt.Time_LST_LDT_,'InputFormat','hh:mm');
yr = str2double(year_str); mo = str2double(dateTag(1:2));
dy = str2double(dateTag(3:4)); hr = str2double(hourStr(1:2));
w0 = datetime(yr,mo,dy,hr,0,0);
inW = tideTime >= w0 & tideTime < w0 + hours(1);
tide = mean(Tt.Verified_m_(inW),'omitnan');
fprintf('Tide for %s %s: %.2f m NAVD88\n', dateTag, hourStr, tide);

Dxyz = readmatrix(sf,'FileType','text');
inb  = Dxyz(:,2) >= min(ym) & Dxyz(:,2) <= max(ym);
sx = Dxyz(inb,1); sz = Dxyz(inb,3);

bz  = discretize(sx, xp_edges);
okz = ~isnan(bz);
z_mean = accumarray(bz(okz), sz(okz), [nb 1], @mean, NaN);
z_std  = accumarray(bz(okz), sz(okz), [nb 1], @std,  NaN);
n_z    = accumarray(bz(okz), 1,       [nb 1], @sum,  0);
z_mean(n_z < 5) = NaN;  z_std(n_z < 5) = NaN;
h_mean = tide - z_mean;

xbar = NaN;
lmax = islocalmax(z_mean,'MinProminence',0.05);
if any(lmax)
    ibl = find(lmax); [~,j] = max(z_mean(ibl)); xbar = xp_centers(ibl(j));
end
[~, ipk] = max(mean_p);  xpk = xp_centers(ipk);
fprintf('Crest-length peak: x = %.1f m | bar crest: x = %.1f m | offset %+.1f m\n', ...
    xpk, xbar, xpk - xbar);
if ~isnan(xbar)
    fprintf('Still-water depth over the bar: %.2f m | alongshore std of bed there: %.2f m\n', ...
        tide - max(z_mean(lmax)), z_std(ibl(j)));
end

% ---- dual-axis plot ------------------------------------------------------
c_len = [0.10 0.30 0.80];

figure
yyaxis left
plot(xp_centers, mean_p, 'o-', 'Color',c_len, ...
    'MarkerFaceColor',c_len, 'MarkerSize',7, 'LineWidth',1.8)
ylabel('Mean crest length [m]')
ylim([0 ceil(max(mean_p)/10)*10])

yyaxis right
plot(xp_centers, h_mean, '-', 'Color','k', 'LineWidth',2.5)
ylabel('Depth [m]')
set(gca,'YDir','reverse')

ax = gca;
ax.YAxis(1).Color = c_len;
ax.YAxis(2).Color = 'k';

grid minor; box on; set(ax,'Layer','top')
xlabel('Cross-shore [m]')
xlim([min(xp_edges) max(xp_edges)])
title(sprintf('Crest Length and Bathymetry - %s', dateTimeLabel),'FontSize',15)

%% ============================ DIAGNOSTIC ============================
% One frame: each crest drawn as an alongshore segment of its reported length,
% centred on its reported centroid, labelled with L.
[uft, ~, gft] = unique(crest_log(:,1));
cnt_kept = accumarray(gft, crest_log(:,7), [], @sum);
[~, ibest] = max(cnt_kept);
fsel = uft(ibest);
sel  = crest_log(:,1) == fsel;

figure; hold on
if exist('d_grid','var')
    contour(Xg, Yg, d_grid, [edge_buffer edge_buffer], 'Color',[0.85 0.10 0.10], 'LineWidth',1.2);
end
ii = find(sel);
for q = 1:numel(ii)
    r = crest_log(ii(q),:);
    col = cmap_diag(q);
    if r(7) == 1
        plot([r(3) r(3)], [r(4)-r(2)/2, r(4)+r(2)/2], '-', 'Color',col, 'LineWidth',2.5)
        plot(r(3), r(4), 'p', 'MarkerFaceColor',col, 'MarkerEdgeColor','k', 'MarkerSize',12)
        text(r(3)+3, r(4), sprintf('%.0f m', r(2)), 'FontSize',9, 'FontWeight','bold')
    else
        plot([r(3) r(3)], [r(4)-r(2)/2, r(4)+r(2)/2], '-', 'Color',[0.75 0.75 0.75], 'LineWidth',1.5)
        plot(r(3), r(4), 'x', 'Color',[0.85 0.10 0.10], 'MarkerSize',10, 'LineWidth',2)
    end
end
set(gca,'YDir','normal'); axis equal; box on; grid minor
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('rcsummary crests, frame %d (%d kept, %d rejected)', ...
    fsel, sum(crest_log(sel,7)==1), sum(crest_log(sel,7)==0)), 'FontSize', 14)

%% LOCAL FUNCTION
function c = cmap_diag(i)
base = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.49 0.18 0.56; 0.47 0.67 0.19;
        0.30 0.75 0.93; 0.64 0.08 0.18; 0.93 0.69 0.13; 0.20 0.20 0.20];
c = base(mod(i-1, size(base,1))+1, :);
end
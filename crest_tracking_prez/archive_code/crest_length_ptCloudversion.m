% CREST LENGTH -- POINT-CLOUD VERSION -- from bore_front_search_length rcsummary (xc, yc, width, length)
%
% Same source and same detector-level (pre-DBSCAN, pre-cluster-filter) crest
% list as the centroid version, but instead of logging ONE row per crest at
% (xc,yc), each crest is expanded into multiple along-crest points spaced
% pt_spacing apart, spanning its reported length. Every one of those points
% is tagged with the crest's full length L, so a 40 m crest contributes many
% more data points than a 4 m crest -- the binning/averaging below therefore
% happens over the along-crest point cloud, not over crest centroids.
%
% Edge handling: rcsummary has no true per-point coordinates, so as before a
% crest is approximated as an alongshore segment of length L centred on
% (xc,yc); the "along-crest points" here are synthetic samples along that
% approximated segment. A crest is discarded (all of its points dropped) if
% the MINIMUM distance-to-edge over all of its sampled points is < edge_buffer
% -- i.e. the same logic as the centroid version's 3-point test, just with
% finer sampling.

%% USER INPUT
dateTag  = '1002';    % MMDD
hourStr  = '1200';    % HHMM
year_str = '2013';    % survey / tide file year

min_crest_len = 3;    % m, discard crests shorter than this (noise floor)
edge_buffer   = 5;    % m, discard a crest (all its points) reaching this close to the domain edge
pt_spacing    = 1;    % m, spacing between synthetic along-crest points
bin_size      = 5;    % m, map grid
xprof_bin     = 5;    % m, cross-shore profile bin
min_samples   = 5;    % min POINTS in a map bin before it's plotted
min_prof      = 10;   % min POINTS in a cross-shore bin before it's plotted

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

%% FLATTEN rcsummary -> one row per crest (same as centroid version)
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
n_crest = size(A,1);
fprintf('After length >= %.1f m: %d crests\n', min_crest_len, n_crest);

%% EXPAND EACH CREST INTO ALONG-CREST POINTS
% Each crest i (frame, L, xc, yc, width) becomes npts(i) points, all at the
% same xc, spread alongshore from yc-L/2 to yc+L/2, each carrying the FULL
% crest length L as its value. crest_id links each point back to row i of A.
pt_cell  = cell(n_crest,1);
for i = 1:n_crest
    L  = A(i,2);
    xc = A(i,3);
    yc = A(i,4);
    npts = max(round(L/pt_spacing) + 1, 2);
    yoff = linspace(-L/2, L/2, npts).';
    pt_cell{i} = [repmat(A(i,1),npts,1), repmat(L,npts,1), ...
                  repmat(xc,npts,1), yc + yoff, repmat(i,npts,1)];
end
P = vertcat(pt_cell{:});   % [frame, L, x, y, crest_id]
fprintf('Expanded %d crests into %d along-crest points (spacing %.1f m)\n', ...
    n_crest, size(P,1), pt_spacing);

%% EDGE TEST -- every synthetic along-crest point
qx = P(:,3); qy = P(:,4);
[~, dq] = knnsearch(edge_xy, [qx qy]);
iX = min(max(round(interp1(Xg, 1:numel(Xg), qx, 'nearest','extrap')),1), numel(Xg));
iY = min(max(round(interp1(Yg, 1:numel(Yg), qy, 'nearest','extrap')),1), numel(Yg));
dq(~valid(sub2ind(size(valid), iY, iX))) = 0;

% roll up to crest level: a crest is kept only if ALL of its points clear edge_buffer
d_min_crest = accumarray(P(:,5), dq, [n_crest 1], @min, Inf);
crest_keep  = d_min_crest >= edge_buffer;

crest_log = [A, d_min_crest, double(crest_keep)];   % [frame,L,xc,yc,width,d_edge,keep] -- per CREST
point_keep = crest_keep(P(:,5));                    % broadcast crest-level keep down to points

fprintf('Kept: %d crests (%d points) | rejected at edge: %d crests (%.1f%%)\n', ...
    sum(crest_keep), sum(point_keep), sum(~crest_keep), 100*mean(~crest_keep));
fprintf('Kept crest length: mean %.1f m | median %.1f m | p95 %.1f m | max %.1f m\n', ...
    mean(A(crest_keep,2)), median(A(crest_keep,2)), ...
    prctile(A(crest_keep,2),95), max(A(crest_keep,2)));

Pk = P(point_keep,:);      % kept points: [frame, L, x, y, crest_id]
xm = Pk(:,3);
ym = Pk(:,4);
Lm = Pk(:,2);

%% DOMAIN / BUFFER CHECK FIGURE
if show_domain_check
    [XX, YY] = meshgrid(Xg, Yg);
    d_grid = nan(size(valid));
    [~, dv] = knnsearch(edge_xy, [XX(valid), YY(valid)]);
    d_grid(valid) = dv;

    figure; hold on
    h = imagesc(Xg, Yg, d_grid);
    set(h,'AlphaData',~isnan(d_grid))
    set(gca,'YDir','normal')
    cmocean('-gray');
    cb = colorbar; cb.Label.String = 'Distance to domain edge [m]';
    clim([0 40])
    contour(Xg, Yg, d_grid, [edge_buffer edge_buffer], 'Color',[0.85 0.10 0.10], 'LineWidth',1.5);
    Pbad = P(~point_keep,:);
    scatter(Pbad(:,3), Pbad(:,4), 4, [0.85 0.10 0.10], 'filled', 'MarkerFaceAlpha', 0.15)
    scatter(xm, ym, 4, [0.10 0.30 0.80], 'filled', 'MarkerFaceAlpha', 0.15)
    axis tight; box on
    xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
    title(sprintf('Rectified Footprint, %.0f m Edge Buffer - %s', edge_buffer, dateTimeLabel), ...
        'FontSize', 15)
    text(0.02, 0.97, sprintf('red = rejected pts (%d)   blue = kept pts (%d)', ...
        sum(~point_keep), sum(point_keep)), ...
        'Units','normalized', 'VerticalAlignment','top', 'FontWeight','bold')
end

%% BIN THE ALONG-CREST POINTS
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
fprintf('Map bins with >= %d points: %d / %d\n', min_samples, sum(keep_bin), N);

%% PLOT -- mean crest length map (point-weighted)
figure
h = imagesc(x_centers, y_centers, len_grid);
set(h,'AlphaData',~isnan(len_grid))
set(gca,'YDir','normal')
axis tight; box on; grid minor
cmocean('-thermal');
cb = colorbar; cb.Label.String = 'Mean crest length [m] (point-weighted)';
clim([0 ceil(prctile(Lm,95)/5)*5])
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title("Mean Crest Length (point cloud) - " + string(dateTimeLabel));
xlim([90 170]); ylim([602 1000])

%% PLOT -- point count per bin
figure
h = imagesc(x_centers, y_centers, n_grid);
set(h,'AlphaData',n_grid > 0)
set(gca,'YDir','normal')
axis tight; box on; grid minor
cmocean('-gray');
cb = colorbar; cb.Label.String = 'Along-crest points per bin';
clim
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('Along-crest Point Counts - %s', dateTimeLabel), 'FontSize', 15)
xlim([90 170]); ylim([602 1000])

%% PLOT -- mean crest length vs cross-shore (point-weighted)
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
scatter(xm, Lm, 4, [0.30 0.55 0.95], 'filled', 'MarkerFaceAlpha', 0.06)
errorbar(xp_centers, mean_p, std_p, 'o-', 'Color',[0.10 0.30 0.80], ...
    'MarkerFaceColor',[0.10 0.30 0.80], 'MarkerSize',6, 'LineWidth',1.5, 'CapSize',4)
box on; grid minor; set(gca,'Layer','top')
ylabel('Crest length [m]')
title(sprintf('Mean Crest Length vs Cross-shore (point cloud) - %s (%.0f m bins, \\pm1\\sigma)', ...
    dateTimeLabel, xprof_bin), 'FontSize', 15)
xlim([min(xp_edges) max(xp_edges)])
ylim([0 ceil(prctile(Lm,99)/5)*5])

subplot(3,1,3)
bar(xp_centers, n_p, 1, EdgeColor='none');
box on; grid minor; set(gca,'Layer','top')
xlabel('Cross-shore [m]'); ylabel('Along-crest Point Count')
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
ylabel('Mean crest length [m] (point-weighted)')
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
title(sprintf('Crest Length and Bathymetry (point cloud) - %s', dateTimeLabel),'FontSize',15)

%% ============================ DIAGNOSTIC ============================
% One frame: each crest is drawn as its full set of synthetic along-crest
% points (not just a segment + centroid), labelled once with L.
[uft, ~, gft] = unique(P(:,1));
% count kept points per frame to pick the busiest frame
cnt_kept_pts = accumarray(gft, point_keep, [], @sum);
[~, ibest] = max(cnt_kept_pts);
fsel = uft(ibest);
selP = P(:,1) == fsel;
selKeep = point_keep(selP);

figure; hold on
if exist('d_grid','var')
    contour(Xg, Yg, d_grid, [edge_buffer edge_buffer], 'Color',[0.85 0.10 0.10], 'LineWidth',1.2);
end
Psel = P(selP,:);         % [frame, L, x, y, crest_id]
KeepSel = selKeep;
crest_ids_here = unique(Psel(:,5));
for q = 1:numel(crest_ids_here)
    cid = crest_ids_here(q);
    m   = Psel(:,5) == cid;
    col = cmap_diag(q);
    pts = Psel(m,:);
    isKept = crest_keep(cid);
    if isKept
        plot(pts(:,3), pts(:,4), '-', 'Color', col, 'LineWidth', 1.5)
        scatter(pts(:,3), pts(:,4), 22, col, 'filled', 'MarkerEdgeColor','k')
        yc_lab = mean(pts(:,4));
        text(pts(1,3)+3, yc_lab, sprintf('%.0f m', pts(1,2)), 'FontSize',9, 'FontWeight','bold')
    else
        plot(pts(:,3), pts(:,4), '-', 'Color',[0.75 0.75 0.75], 'LineWidth',1)
        scatter(pts(:,3), pts(:,4), 14, [0.85 0.10 0.10], 'x')
    end
end
set(gca,'YDir','normal'); axis equal; box on; grid minor
xlabel('Cross-shore [m]'); ylabel('Alongshore [m]')
title(sprintf('rcsummary crests (point cloud), frame %d (%d pts kept, %d pts rejected)', ...
    fsel, sum(KeepSel), sum(~KeepSel)), 'FontSize', 14)

%% LOCAL FUNCTION
function c = cmap_diag(i)
base = [0.00 0.45 0.74; 0.85 0.33 0.10; 0.49 0.18 0.56; 0.47 0.67 0.19;
        0.30 0.75 0.93; 0.64 0.08 0.18; 0.93 0.69 0.13; 0.20 0.20 0.20];
c = base(mod(i-1, size(base,1))+1, :);
end
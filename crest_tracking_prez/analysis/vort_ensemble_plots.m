% Per-crest ensemble distributions (padded crests) compared across several runs.
% Stand-alone: loads each processed run, recomputes Fbr per crest, plots line histograms.
% Same method and parameters as the wave-by-wave ensemble section of Fbr_vort_gen.m.


% *** Gives ensemble figure with histos for: crest length, crest-mean Fbr, curl(Fbr)

%% USER INPUT
% one row per run: {runDate (yyyymmdd), hourStr (hhmm), bathy survey date (yyyymmdd)}
runs = {'20130925', '1600', '20130925'
        '20131001', '1100', '20131002'    
        '20131002', '1200', '20131002'
        '20131022', '1600', '20131022'};

year_str = '2013';
camera   = 'rod13';

g           = 9.81;
theta_r     = deg2rad(15);   % roller angle
h_min       = 0.25;          % m, exclude shallower points (Fbr ~ 1/h blows up)
c_speed_min = 1;             % m/s, exclude unrealistic celerity values
c_speed_max = 7;
bin_size    = 5;             % m (only sets the crest-tracing link distance)

max_match_dist      = 2;            % m, max distance between a celerity point and its crest-width point
max_crest_link_dist = 2*bin_size;   % m, beyond this gap a traced crest ends
crest_pad_dist      = 2;            % m, distance of the Fbr = 0 pad point beyond each crest end

ens_min_pts   = 5;       % min matched Fbr points for a crest to count as a wave
ens_min_L     = 3;       % m, min along-crest span of the measured points (before padding)
ens_nZ        = 51;      % points on the normalized along-crest grid
ens_med_len   = 0;       % m, along-crest median window on c and W; 0 = no filtering
ens_c_perwave = false;   % true: one median celerity per crest

ens_survey_pad_xy  = 25;   % m, only survey points within this distance of the celerity points are used
ens_survey_max_gap = 15;   % m, discard interpolated depth farther than this from any survey point

% histogram bins + normalization
L_edges   = 0:3:100;          % crest length [m]
F_edges   = 0:0.02:1;         % crest-mean Fbr [m s^-2]
O_edges   = 0:0.2:7;        % vorticity forcing per crest [m s^-2]
hist_norm = 'probability';    % 'probability' (fraction of crests, comparable between runs) or 'count'

%% paths
dataRoot  = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/rips_onedrive/NSF_Eddies';
matDir    = fullfile(dataRoot, 'mat_data');
surveyDir = fullfile(dataRoot, 'data', 'bathy_surveys');
tideFile  = fullfile(dataRoot, 'data', 'tide_duck', sprintf('duck_waterLvls%s.csv', year_str));
buoyFile  = fullfile(dataRoot, 'data', 'buoy_data', sprintf('%s_buoyHsDuck.txt', year_str));

%% tide + buoy tables (read once)
Ttide    = readtable(tideFile, 'TextType', 'string');
tideTime = datetime(Ttide.Date, 'InputFormat', 'yyyy/MM/dd') + duration(Ttide.Time_LST_LDT_, 'InputFormat', 'hh:mm');
tideLvl  = Ttide.Verified_m_;

Tb = readtable(buoyFile, detectImportOptions(buoyFile, 'NumHeaderLines', 2));
buoyTime = datetime(Tb{:,1}, Tb{:,2}, Tb{:,3}, Tb{:,4}, Tb{:,5}, 0);
buoyAPD  = Tb{:,11};                    % average wave period (NDBC standard-met column 11)
buoyAPD(buoyAPD >= 99) = NaN;           % NDBC missing-value flag

%% loop over runs
nRuns = size(runs, 1);
R = struct('label', cell(nRuns,1), 'L', [], 'Fmean', [], 'Omega', []);
zgrid = linspace(0, 1, ens_nZ);
ens_min_pts = max(ens_min_pts, 2);

for ir = 1:nRuns
    runDate = runs{ir,1};  hourStr = runs{ir,2};  svyDate = runs{ir,3};
    t0 = datetime([runDate hourStr], 'InputFormat', 'yyyyMMddHHmm');
    R(ir).label = char(t0, 'MM/dd/yyyy, HHmm');
    t_run = tic;

    % ---- tide and mean wave period for the hour ----
    tide   = mean(tideLvl(tideTime >= t0 & tideTime < t0 + hours(1)), 'omitnan');
    T_mean = mean(buoyAPD(buoyTime >= t0 & buoyTime < t0 + hours(1)), 'omitnan');
    if isnan(tide) || isnan(T_mean); error('No tide or buoy period for %s.', R(ir).label); end

    % ---- processed video output (newest match; also looks in local_runs) ----
    Lf = [dir(fullfile(matDir, sprintf('%s_%s_%s*.mat', camera, runDate, hourStr)))
          dir(fullfile(matDir, 'local_runs', sprintf('%s_%s_%s*.mat', camera, runDate, hourStr)))];
    if isempty(Lf); error('No mat file for %s_%s_%s in %s', camera, runDate, hourStr, matDir); end
    [~, iNew] = max([Lf.datenum]);
    S = load(fullfile(Lf(iNew).folder, Lf(iNew).name), 'all_celerity_total', 'all_celerity_time_total', ...
        'all_crest_width_pts_total', 'all_crest_width_time_total');

    % ---- celerity points (raw), speed filter ----
    keep = S.all_celerity_total(:,5) > c_speed_min & S.all_celerity_total(:,5) < c_speed_max;
    x_pts = S.all_celerity_total(keep,1);
    y_pts = S.all_celerity_total(keep,2);
    c_pts = S.all_celerity_total(keep,5);
    t_pts = posixtime(S.all_celerity_time_total(keep));     t_pts = t_pts(:);
    W_all = S.all_crest_width_pts_total;                    % [x, y, width]
    t_W   = posixtime(S.all_crest_width_time_total);        t_W = t_W(:);

    % ---- survey water depth at each celerity point (h = tide - NAVD88 bed elevation) ----
    sv = readmatrix(fullfile(surveyDir, sprintf('RODDebbieTimeLagFix_%s.xyz', svyDate)), 'FileType', 'text');
    ok = all(isfinite(sv(:,1:3)), 2) & ...
        sv(:,1) >= min(x_pts)-ens_survey_pad_xy & sv(:,1) <= max(x_pts)+ens_survey_pad_xy & ...
        sv(:,2) >= min(y_pts)-ens_survey_pad_xy & sv(:,2) <= max(y_pts)+ens_survey_pad_xy;
    sv = sv(ok, 1:3);
    zb = scatteredInterpolant(sv(:,1), sv(:,2), sv(:,3), 'linear', 'none');
    h_pts = tide - zb(x_pts, y_pts);
    [~, d_sv] = knnsearch(sv(:,1:2), [x_pts y_pts]);
    h_pts(d_sv > ens_survey_max_gap) = NaN;                 % do not trust interpolation across survey gaps

    % ---- group celerity points and crest-width points by frame ----
    [uf, ~, gp] = unique(t_pts);
    [inF, gw]   = ismember(t_W, uf);
    p_by_frame  = accumarray(gp,      (1:numel(gp))', [numel(uf) 1], @(v){v}, {[]});
    w_by_frame  = accumarray(gw(inF), find(inF),      [numel(uf) 1], @(v){v}, {[]});

    % ---- per crest: Fbr, pad, length, crest-mean Fbr, vorticity forcing ----
    Fcoef = 0.9*g/T_mean * 0.11*tan(theta_r)*sec(theta_r);  % Fbr = Fcoef * W^2 / (c*h)   (Duncan 1981)
    ens_L = []; ens_Fmean = []; ens_Omega = [];

    for fnum = 1:numel(uf)
        w_idx = w_by_frame{fnum};
        if numel(w_idx) < 2; continue; end
        p_idx = p_by_frame{fnum};
        wx = W_all(w_idx,1);  wy = W_all(w_idx,2);  wW = W_all(w_idx,3);

        % trace the width cloud into crests; snap each celerity point onto its nearest width point
        [crestID_w, s_w] = trace_crest_paths(wx, wy, max_crest_link_dist);
        [nn, dmin] = knnsearch([wx wy], [x_pts(p_idx) y_pts(p_idx)]);
        m = dmin <= max_match_dist & wW(nn) > 0;
        if ~any(m); continue; end
        p_idx = p_idx(m);  nn = nn(m);
        fx = x_pts(p_idx);  fy = y_pts(p_idx);  fc = c_pts(p_idx);  fh = h_pts(p_idx);
        fW = wW(nn);  crestID_f = crestID_w(nn);  s_f = s_w(nn);

        for id = unique(crestID_f)'
            cm = find(crestID_f == id);
            if numel(cm) < ens_min_pts; continue; end
            [~, ord] = sort(s_f(cm));
            cm = cm(ord);
            cxs = fx(cm);  cys = fy(cm);  cc = fc(cm);  ww = fW(cm);  hh = fh(cm);

            % optional along-crest median filter on the inputs c and W (off when ens_med_len = 0)
            if ens_med_len > 0
                s_m = [0; cumsum(hypot(diff(cxs), diff(cys)))] + (0:numel(cxs)-1)'*1e-9;
                cc  = movmedian(cc, ens_med_len, 'SamplePoints', s_m);
                ww  = movmedian(ww, ens_med_len, 'SamplePoints', s_m);
            end
            if ens_c_perwave; cc(:) = median(cc); end

            F    = Fcoef * ww.^2 ./ (cc .* hh);
            good = isfinite(F) & hh > h_min;
            if nnz(good) < ens_min_pts; continue; end
            cxs = cxs(good);  cys = cys(good);  F = F(good);
            if sum(hypot(diff(cxs), diff(cys))) < ens_min_L; continue; end

            % pad the crest: Fbr = 0 point one crest_pad_dist beyond each end
            e1 = [cxs(1)-cxs(2),       cys(1)-cys(2)];        e1 = e1 / max(norm(e1), eps);
            e2 = [cxs(end)-cxs(end-1), cys(end)-cys(end-1)];  e2 = e2 / max(norm(e2), eps);
            xp = [cxs(1)+crest_pad_dist*e1(1); cxs; cxs(end)+crest_pad_dist*e2(1)];
            yp = [cys(1)+crest_pad_dist*e1(2); cys; cys(end)+crest_pad_dist*e2(2)];
            Fp = [0; F; 0];

            s = [0; cumsum(hypot(diff(xp), diff(yp)))];     % along-crest coordinate, pad to pad
            L = s(end);
            [zu, iu] = unique(s / L);
            Fz = interp1(zu, Fp(iu), zgrid, 'linear');

            ens_L(end+1,1)     = L;                         % padded crest length
            ens_Fmean(end+1,1) = trapz(zgrid, Fz);          % crest-mean Fbr
            ens_Omega(end+1,1) = sum(abs(diff(Fp)));        % sum |curl_i| * ds_i over the N+1 segments
        end
    end
    if isempty(ens_L); error('No crests passed the filters for %s.', R(ir).label); end

    R(ir).L = ens_L;  R(ir).Fmean = ens_Fmean;  R(ir).Omega = ens_Omega;
    fprintf('%s: %d crests | tide %.2f m | T %.2f s | median L %.1f m, Fmean %.3f m/s^2, Omega_c %.2f m/s^2 | %.0f s\n', ...
        R(ir).label, numel(ens_L), tide, T_mean, median(ens_L), median(ens_Fmean), median(ens_Omega), toc(t_run));
end

%% per-crest distributions, one line per run
cols = lines(nRuns);
if strcmp(hist_norm, 'count'); ylab = 'Count'; else; ylab = 'Fraction of crests'; end
% {field, bin edges, xlabel, title, tile number, rows spanned}
panels = {'L',     L_edges, 'Crest length L [m]',                                         'Crest length',                      1, 1
          'Fmean', F_edges, 'Crest-mean F_{br} [m s^{-2}]',                               'Crest-mean breaking force',         3, 1
          'Omega', O_edges, '\Omega_c = \Sigma|\nabla\times F_{br}| \Delta s [m s^{-2}]', 'Vorticity generation per crest', 2, 2};

figure;
tl = tiledlayout(2, 2, 'TileSpacing', 'compact');
for ip = 1:size(panels, 1)
    ax = nexttile(panels{ip,5}, [panels{ip,6} 1]);  hold(ax, 'on')
    edges = panels{ip,2};
    ctrs  = edges(1:end-1) + diff(edges)/2;
    for ir = 1:nRuns
        n = histcounts(R(ir).(panels{ip,1}), edges, 'Normalization', hist_norm);
        plot(ax, ctrs, n, '-', 'Color', cols(ir,:), 'LineWidth', 1.5);
    end
    xlim(ax, panels{ip,2}([1 end]));
    xlabel(ax, panels{ip,3});  ylabel(ax, ylab);  title(ax, panels{ip,4});  grid(ax, 'on');  box(ax, 'on');
    if panels{ip,5} == 2
        legLabels = arrayfun(@(r) sprintf('%s (N = %d)', r.label, numel(r.L)), R, 'UniformOutput', false);
    else
        legLabels = arrayfun(@(r) r.label, R, 'UniformOutput', false);
    end

    legend(ax, legLabels, 'Location', 'northeast');
end

title(tl, 'Per-crest distributions', 'FontSize', 13)


%% LOCAL FUNCTIONS

function [crestID, s] = trace_crest_paths(x, y, max_link_dist)
% TRACE_CREST_PATHS  Along-crest order for an unorganized (x,y) point cloud
% that may contain several separate crests. Each point is chained to its
% nearest not-yet-used neighbor; a crest ends where no neighbor lies within
% max_link_dist, or where the nearest neighbor would reverse the direction of
% travel already established along that crest. Each crest's arclength s is
% oriented to increase with y.
n       = numel(x);
crestID = nan(n,1);
s       = nan(n,1);
visited = false(n,1);
curID   = 0;

while ~all(visited)
    curID = curID + 1;
    seed  = find(~visited, 1, 'first');
    chain = seed;
    visited(seed) = true;

    for dir_sign = [1 -1]      % grow forward from the seed, then backward
        cur     = seed;
        run_dir = [];
        while true
            cand = find(~visited);
            if isempty(cand); break; end
            d = hypot(x(cand)-x(cur), y(cand)-y(cur));
            [dmin, k] = min(d);
            if dmin > max_link_dist; break; end
            nxt  = cand(k);
            step = [x(nxt)-x(cur), y(nxt)-y(cur)] / max(dmin, eps);
            if ~isempty(run_dir) && dot(step, run_dir) < 0
                break   % next nearest point is back the way we came -- crest end
            end
            run_dir = step;
            if dir_sign == 1
                chain = [chain; nxt];
            else
                chain = [nxt; chain];
            end
            visited(nxt) = true;
            cur = nxt;
        end
    end

    if y(chain(1)) > y(chain(end))
        chain = flipud(chain);   % keep s increasing with y
    end

    cx  = x(chain); cy = y(chain);
    arc = [0; cumsum(hypot(diff(cx), diff(cy)))];
    crestID(chain) = curID;
    s(chain)       = arc;
end
end
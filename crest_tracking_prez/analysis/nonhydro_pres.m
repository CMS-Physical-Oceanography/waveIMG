%% nonhydro_pres.m
% 1) 1 hr of 8 Hz pressure from RD(13) -> nonlinear eta (Martins et al. 2020)
% 2) 20-80% front-face slope extraction (same method as roller_slopes.m / PIV_correction script)
% Output: deta_dt  [m/s] one slope per detected wave, deta_dt_mean = mean of those

%% ---------------- USER INPUTS ----------------
matfile  = "/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/Grimes, Derek J's files - ROD/RD_20131002.mat";
idx      = 13;        % RD(idx)
delta_m  = 0.50;      % [m] sensor height above bed  <-- INPUT
t_start  = [];        % [s] start of 1-hr window on t_sec clock ([] = first sample)
win_len  = 3600;      % [s]
fs       = 8;         % [Hz]
rho      = 1025;      % [kg/m^3]
g        = 9.81;      % [m/s^2]
fc       = 1.0;       % [Hz] low-pass cutoff on zeta_hyd (reduces noise amplification)

% --- pressure units ---
p_to_Pa  = 1e4;       % dbar -> Pa  (use 1e5 if it is absolute pressure in bar)
Patm     = 0;         % [Pa] 0 if p is already gauge; 101325 if p is absolute
h0       = [];        % [m] mean depth ([] = mean hydrostatic depth over the window)

% ripple-rejection thresholds (identical to roller_slopes.m)
wp.minProm            = 0.01;   % [m]
wp.minPeakDist        = 3;      % [s]
wp.minWaveHeight      = 0.035;  % [m] trough-to-crest
wp.minTroughCrestTime = 1;      % [s]
wp.maxTroughCrestTime = 20;     % [s]
%% ---------------------------------------------

S = load(matfile, 'RD');
t_all = S.RD(idx).t_sec(:);
p_all = S.RD(idx).p(:) * p_to_Pa;

if isempty(t_start), t_start = t_all(1); end
in = t_all >= t_start & t_all < t_start + win_len;
t  = t_all(in);
Pm = p_all(in);
dt = 1/fs;
fprintf('Window: %.1f to %.1f s, N = %d (expected %d)\n', t(1), t(end), numel(t), win_len*fs);
if max(abs(diff(t) - dt)) > 1e-3
    warning('t_sec not uniformly spaced at 1/fs; central differences assume constant dt.');
end

%% Martins et al. (2020) nonlinear reconstruction
depth_hyd = (Pm - Patm)/(rho*g) + delta_m;
if isempty(h0), h0 = mean(depth_hyd, 'omitnan'); end
eta_hyd = depth_hyd - h0;

[b,a] = butter(4, fc/(fs/2));
eta_hyd = filtfilt(b,a,eta_hyd);            % zero-phase, so crest timing is preserved

% zeta_sl = zeta_hyd - (h0/(2g)) * (1 - (delta_m/h0)^2) * d^2(zeta_hyd)/dt^2
eta_hyd_tt = d2dt2_central(eta_hyd, dt);
eta_lin = eta_hyd - (h0/(2*g)) * (1 - (delta_m/h0)^2) * eta_hyd_tt;

% zeta_snl = zeta_sl - (1/g) * [ d/dt(zeta_sl * dzeta_sl/dt) - (delta_m/h0)^2 * (dzeta_sl/dt)^2 ]
eta_lin_t  = ddt_central(eta_lin, dt);
eta_nonlin = eta_lin - (1/g) * ( ddt_central(eta_lin .* eta_lin_t, dt) - (delta_m/h0)^2 * eta_lin_t.^2 );

% trim the NaN edge samples left by the central differences
good = ~isnan(eta_nonlin);
rm   = @(x) x(good) - mean(x(good));        % trimmed + zero-mean
eta_nl = rm(eta_nonlin);
tt   = t(good) - t(1);                      % time since window start [s]

%% 20-80% front-face slopes
deta_dt = extractWaveSlopes(eta_nl, fs, wp);      % [m/s], one value per wave
deta_dt_mean = mean(deta_dt);
fprintf('%d waves detected, mean dEta/dt = %.4f m/s\n', numel(deta_dt), deta_dt_mean);

%% diagnostics: stats
hyd_t = rm(eta_hyd);  lin_t = rm(eta_lin);  nl_t = rm(eta_nonlin);

lin_corr = eta_lin - eta_hyd;  nl_corr = eta_nonlin - eta_lin;
fprintf('std [m]: hyd %.3f | lin corr %.3f | nl corr %.3f\n', ...
    std(eta_hyd,'omitnan'), std(lin_corr,'omitnan'), std(nl_corr,'omitnan'));

ws_hyd = extractWaveSlopes(hyd_t, fs, wp);
ws_lin = extractWaveSlopes(lin_t, fs, wp);
ws_nl  = extractWaveSlopes(nl_t,  fs, wp);
fprintf('median / 95th pct slope [m/s]: hyd %.2f/%.2f | lin %.2f/%.2f | nl %.2f/%.2f\n', ...
    median(ws_hyd), prctile(ws_hyd,95), median(ws_lin), prctile(ws_lin,95), median(ws_nl), prctile(ws_nl,95));

%% diagnostics: plots
% 1) spectra
[p1,f] = pwelch(hyd_t, [], [], [], fs);
[p2,~] = pwelch(nl_t,  [], [], [], fs);
figure; loglog(f,p1,f,p2); grid on
legend('\zeta_{hyd}','\zeta_{snl}'); xlabel('f [Hz]'); ylabel('PSD [m^2/Hz]')

% 2) 60 s excerpt (starting 600 s into the window)
i0 = find(tt >= 600, 1);
ii = i0 : min(i0 + 60*fs, numel(tt));
figure; plot(tt(ii), hyd_t(ii), tt(ii), nl_t(ii)); grid on
legend('\zeta_{hyd}','\zeta_{snl}'); xlabel('t [s]'); ylabel('\zeta [m]')

% 3) steepest front in the record (+/- 5 s)
dn = ddt_central(nl_t, dt);
[~,k] = max(dn);
kk = max(k-5*fs,1) : min(k+5*fs, numel(tt));
figure; plot(tt(kk), hyd_t(kk), '.-', tt(kk), nl_t(kk), '.-'); grid on
legend('\zeta_{hyd}','\zeta_{snl}'); xlabel('t [s]'); ylabel('\zeta [m]')

% 4) slope CDFs at each stage
figure; hold on
for w = {ws_hyd, ws_lin, ws_nl}
    plot(sort(w{1}), (1:numel(w{1}))/numel(w{1}));
end
grid on; xlabel('dEta/dt [m/s]'); ylabel('CDF'); legend('hyd','lin','snl')

%% ---------------- local functions ----------------
function dx = ddt_central(x, dt)
    dx = nan(size(x));
    dx(2:end-1) = (x(3:end) - x(1:end-2)) / (2*dt);
end

function d2x = d2dt2_central(x, dt)
    d2x = nan(size(x));
    d2x(2:end-1) = (x(3:end) - 2*x(2:end-1) + x(1:end-2)) / dt^2;
end

function waveSlope = extractWaveSlopes(eta, fs, wp)
    t = (0:length(eta)-1)'/fs;
    [crestVals, crestIdx] = findpeaks(eta, 'MinPeakProminence', wp.minProm, ...
        'MinPeakDistance', round(wp.minPeakDist*fs));
    [troughNeg, troughIdx] = findpeaks(-eta, 'MinPeakProminence', wp.minProm, ...
        'MinPeakDistance', round(wp.minPeakDist*fs));
    troughVals  = -troughNeg;
    crestTimes  = t(crestIdx);
    troughTimes = t(troughIdx);

    waveSlope = [];
    for i = 1:length(troughIdx)
        j = find(crestIdx > troughIdx(i), 1, 'first');   % first crest after this trough
        if isempty(j); continue; end
        dtw  = crestTimes(j) - troughTimes(i);
        dEta = crestVals(j)  - troughVals(i);
        if dtw >= wp.minTroughCrestTime && dtw <= wp.maxTroughCrestTime && dEta >= wp.minWaveHeight
            seg = (troughIdx(i):crestIdx(j))';
            e   = eta(seg);
            tv  = t(seg);
            lo  = troughVals(i) + 0.2*dEta;
            hi  = troughVals(i) + 0.8*dEta;

            k80 = find(e >= hi, 1, 'first');           % first sample at/above 80%
            if isempty(k80) || k80 < 2; continue; end
            k20 = find(e(1:k80) <= lo, 1, 'last');     % last sample at/below 20% before that
            if isempty(k20) || k20 >= k80; continue; end

            % linear interpolation for the 20% and 80% crossing times
            if e(k20+1) == e(k20) || e(k80) == e(k80-1); continue; end
            t20 = tv(k20)   + (lo - e(k20))   / (e(k20+1) - e(k20))   * (tv(k20+1)   - tv(k20));
            t80 = tv(k80-1) + (hi - e(k80-1)) / (e(k80)   - e(k80-1)) * (tv(k80)     - tv(k80-1));

            waveSlope(end+1,1) = (hi - lo) / (t80 - t20); %#ok<AGROW>  % [m/s]
        end
    end
end
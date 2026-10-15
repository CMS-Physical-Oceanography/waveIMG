function [rclog, rcsummary] = bore_front_search_length(Q0, nr, nc, r0, Qmax, xvec, yvec)
% new way to directly incorporate parabola fitting

% Connected-region bore-front search (Q0>=Qmax, deflate algorithm) with
% built-in sub-grid parabola refinement of the cross-shore front
% location.

% INPUTS
% Q0    = UNET probability map (transposed so rows=cross-shore, cols=alongshore)
% nr,nc = image dimensions (legacy inputs, actual size taken from Q0)
% r0    = smoothing window size and minimum connected-region size
% Qmax  = probability threshold for identifying crest pixels
% xvec  = cross-shore coordinates corresponding to image rows (optional)
% yvec  = alongshore coordinates corresponding to image columns (optional)
%
% OUTPUTS
% rclog     = cell array containing one connected crest per cell. Each crest
%             stores the cross-shore location, alongshore location, and crest
%             width at every alongshore column.
% rcsummary = struct array, one entry per crest (same order as rclog), with
%             fields:
%               .xc     - mean cross-shore center location of the crest
%               .yc     - mean alongshore center location of the crest
%               .width  - mean crest width (over all alongshore columns)
%               .length = traced alongshore crest length (arc length, not
%                         a straight-line span)

if nargin < 6, xvec = []; end
if nargin < 7, yvec = []; end

[nrows, ncols] = size(Q0); %#ok<ASGLU> % use actual Q0 size, not nr/nc

if r0 > 1
    f1  = hamming(r0);
    f   = f1*f1';
    f   = f./sum(f(:));
    tmp = Q0 >= Qmax;
    tmp = conv2(tmp, f, 'same');
      Qsmooth = conv2(Q0, f, 'same');   % ADDED: smoothed field for edge search ***********

else
    tmp = Q0 >= Qmax; % threshold prob field
      Qsmooth = Q0;                      % ADDED: no smoothing requested, so use raw *************

end

bw = bwboundaries(ceil(tmp), 'noholes'); % every reg > Qmax is a breaking wave crest
Nw = length(bw);

rclog = {};
N = zeros(1, Nw);

% ADDED: preallocate per-crest summary stats **************************
crestLen = nan(1, Nw);
meanWid  = nan(1, Nw);
xc       = nan(1, Nw);
yc       = nan(1, Nw);
% ***********************************************************************

for ii = 1:Nw % process each crest individually
    rc    = bw{ii}; % row/col indices for this connected crest
    N(ii) = size(rc,1); % # of pixels in this crest
    cu    = unique(rc(:,2)); % unique AS cols in this crest
    ru    = nan(size(cu)); % integer CS row
    xsub  = nan(size(cu));
    ysub  = nan(size(cu));
    wid   = nan(size(cu)); % crest width

    for jj = 1:length(cu) % loop over each AS column, find CS center, then refine
        thisCol = find(rc(:,2) == cu(jj));
        ru(jj)  = round(mean(rc(thisCol,1))); % grid-snapped CS row, as before

        if ~isempty(xvec)
            row0   = ru(jj);
            col0   = cu(jj);
            row_lo = max(row0 - 2, 1); % fit quadratic to 5 pt neighborhood around prob maximum
            row_hi = min(row0 + 2, nrows);
            rows   = row_lo:row_hi; % CS neighborhood (rows, since rows=CS in Q0)

            if numel(rows) < 3
                xsub(jj) = xvec(row0);
            else
                p_vals = double(Q0(rows, col0)); % prob values within local neighborhood
                x_vals = xvec(rows); % corresponding CS coords

                coeffs = polyfit(x_vals(:), p_vals(:), 2); % quadratic fit
                a = coeffs(1);
                b = coeffs(2);

                if a >= 0 % parabola opens up -> revert to OG pixel loc
                    xsub(jj) = xvec(row0);
                else
                    x_peak = -b/(2*a); % sub-grid CS position of prob peak
                    xlo    = min(x_vals);
                    xhi    = max(x_vals);
                    x_peak = max(xlo, min(xhi, x_peak)); % clamp within fitting window
                    xsub(jj) = x_peak;
                end
            end

            % extract prob profile thru crest
            p_col = double(Qsmooth(:, col0));  % CHANGED to Qsmooth instead of Q0 ************************************


            [~, idx_peak] = min(abs(xvec - xsub(jj))); % nearest pixel to refined crest center

            idx_off = find(p_col(1:idx_peak) < Qmax, 1, 'last'); % offshore crest edge

            % search offshore until probability first falls below the threshold
            % interpolate between neighboring pixels to estimate the threshold crossing with sub-grid accuracy.
            if isempty(idx_off) || idx_off >= numel(p_col)
                x_edge_off = xvec(1);
            else
                x_edge_off = interp1(p_col(idx_off:idx_off+1), xvec(idx_off:idx_off+1), Qmax, 'linear', 'extrap');
            end

            idx_shore = find(p_col(idx_peak:end) < Qmax, 1, 'first'); % shoreward crest edge
            if isempty(idx_shore)
                x_edge_shore = xvec(end);
            else
                idx_shore = idx_shore + idx_peak - 1;
                if idx_shore <= 1
                    x_edge_shore = xvec(idx_shore);
                else
                    x_edge_shore = interp1(p_col(idx_shore-1:idx_shore), xvec(idx_shore-1:idx_shore),Qmax, 'linear', 'extrap');
                end
            end
            wid(jj) = abs(x_edge_shore - x_edge_off); % crest width is diff b/w offshore and shoreward edges
        end

        if ~isempty(yvec)
            ysub(jj) = yvec(cu(jj)); % grid-snapped AS lookup (no sub-grid refinement)
        end
    end

    wid = movmedian(wid, 5, 'omitnan');

    % ADDED: traced crest length + per-crest summary stats *****************
    % Use refined sub-grid coords where available, otherwise fall back to
    % the grid-snapped pixel coords. cu is already ascending (from
    % unique()), so cx/cy are already in along-crest order -- summing
    % consecutive segment lengths traces the crest path itself (including
    % any cross-shore wander) rather than assuming a straight line.
    if ~isempty(xvec)
        cx = xsub;
    else
        cx = ru;
    end
    if ~isempty(yvec)
        cy = ysub;
    else
        cy = cu;
    end


    % truncate path at first turn sharper than 90 deg (stops fold-back/wrap for crest lengths)
    dx = diff(cx(:)); dy = diff(cy(:));
    ang = atan2d(abs(dx(1:end-1).*dy(2:end) - dy(1:end-1).*dx(2:end)), dx(1:end-1).*dx(2:end) + dy(1:end-1).*dy(2:end));
    cutIdx = find(ang > 60, 1, 'first'); % index into interior points where turn exceeds limit
    if ~isempty(cutIdx)
        keepN = cutIdx; % keep points 1..cutIdx (segment count = cutIdx-1 kept whole)
        cx = cx(1:keepN); cy = cy(1:keepN);
        ru = ru(1:keepN); cu = cu(1:keepN);
        xsub = xsub(1:keepN); ysub = ysub(1:keepN); wid = wid(1:keepN);
    end


    segs        = sqrt(diff(cx(:)).^2 + diff(cy(:)).^2);
    crestLen(ii) = sum(segs, 'omitnan');
    meanWid(ii)  = mean(wid, 'omitnan');
    xc(ii)       = mean(cx, 'omitnan');
    yc(ii)       = mean(cy, 'omitnan');
    % ************************************************************************

    if isempty(xvec)
        rclog{ii,1} = [ru, cu, wid];
    elseif isempty(yvec)
        rclog{ii,1} = [ru, cu, xsub, wid];
    else
        rclog{ii,1} = [ru, cu, xsub, ysub, wid];
    end
end

% sort by size and remove regions smaller than r0
[N, srt] = sort(N, 'descend');
rclog = rclog(srt);

% ADDED: carry the per-crest summary stats through the same sort/filter ***
crestLen = crestLen(srt);
meanWid  = meanWid(srt);
xc       = xc(srt);
yc       = yc(srt);

keep     = N >= r0;
rclog    = rclog(keep);
crestLen = crestLen(keep);
meanWid  = meanWid(keep);
xc       = xc(keep);
yc       = yc(keep);

rcsummary = struct('xc', num2cell(xc), 'yc', num2cell(yc), ...
                    'width', num2cell(meanWid), 'length', num2cell(crestLen));

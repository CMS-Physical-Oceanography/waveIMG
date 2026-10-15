function rclog = bore_front_search_funwave_Prezley_v2(Q0, nr, nc, r0, Qmax, xvec, yvec)
% new way to directly incorporate parabola fitting -- v2
%
% USAGE: rclog = bore_front_search_funwave_Prezley_v2(Q0,nr,nc,r0,Qmax,xvec,yvec);
%
% Connected-region bore-front search (Q0>=Qmax, deflate algorithm) with
% built-in sub-grid parabola refinement of the cross-shore front
% location.
%
% The image is first convolved with an r0 x r0 window. The shore should
% be close to the bottom of the image (small rows == offshore), i.e.
% ROWS of Q0 are cross-shore (CS), COLUMNS are alongshore (AS). This
% matches calling the function with Q0 = prob', where prob is sized
% [AS x CS] (rows=AS, cols=CS), as is typical for a UNET probability map
% defined on a (Y,X) grid.
%
% CHANGES FROM v1:
%   (1) bwboundaries -> bwconncomp on the FILLED mask. v1 traced only the
%       blob's perimeter and averaged perimeter rows per column; at a
%       curved/hooked tip the same column is crossed by two arms of that
%       perimeter, and averaging them could land the "center" in the
%       trough between the arms rather than on the ridge (pinching).
%       Now every pixel of the blob is available per column, and the
%       center is the row of MAX probability among the blob's own rows
%       in that column -- a real high-probability point, not an average.
%   (2) The edge search (where Q0 first drops below Qmax on each side of
%       the peak) is now restricted to that blob's own row range in that
%       column, +/- a small buffer, instead of scanning the ENTIRE
%       column top to bottom. If no crossing is found in that restricted
%       range, width is NaN -- never snapped to xvec(1)/xvec(end) (the
%       domain edge), which was causing widths to extend past the
%       visible probability blob.
%   (3) The parabola sub-grid peak refinement (the actual "aspect" you
%       asked to keep) is UNCHANGED in method -- same +/-2-row window,
%       same polyfit, same concave-down guard -- it's just now centered
%       on the max-probability row found in step (1) instead of the
%       averaged-boundary-row estimate from v1.
if nargin < 6, xvec = []; end
if nargin < 7, yvec = []; end
[nrows, ncols] = size(Q0); %#ok<ASGLU> % use actual Q0 size, not nr/nc
if r0 > 1
    f1  = hamming(r0);
    f   = f1*f1';
    f   = f./sum(f(:));
    tmp = Q0 >= Qmax;
    tmp = conv2(tmp, f, 'same');
else
    tmp = Q0 >= Qmax;
end
maskFull = ceil(tmp) > 0;

% CHANGE (1): bwconncomp on the filled mask, not bwboundaries on the
% perimeter. Same computational cost class as bwboundaries.
CC = bwconncomp(maskFull, 8);
L  = labelmatrix(CC);
Nw = CC.NumObjects;
rclog = {};
N = cellfun(@numel, CC.PixelIdxList);

bufferPx = 2; % small margin so the edge search can find a crossing just outside the blob's own rows

for ii = 1:Nw
    [rowsAll, colsAll] = find(L == ii); % all pixels belonging to this blob
    cu    = unique(colsAll);
    ru    = nan(size(cu));
    xsub  = nan(size(cu));
    ysub  = nan(size(cu));
    wid   = nan(size(cu)); % crest width
for jj = 1:length(cu) % loop over each AS column, find CS center, then refine
        colHere  = cu(jj);
        rowsHere = rowsAll(colsAll == colHere); % CHANGE (1): this blob's own rows in this column

        [~, mi]  = max(Q0(rowsHere, colHere));  % CHANGE (1): max-probability row, not mean-of-boundary-rows
        ru(jj)   = rowsHere(mi);
if ~isempty(xvec)
            row0   = ru(jj);
            col0   = colHere;
            row_lo = max(row0 - 2, 1);
            row_hi = min(row0 + 2, nrows);
            rows   = row_lo:row_hi; % CS neighborhood (rows, since rows=CS in Q0)
% ---- parabola sub-grid peak refinement (UNCHANGED from v1) ----
if numel(rows) < 3
                xsub(jj) = xvec(row0);
else
                p_vals = double(Q0(rows, col0));
                x_vals = xvec(rows);
                coeffs = polyfit(x_vals(:), p_vals(:), 2);
                a = coeffs(1);
                b = coeffs(2);
if a >= 0
                    xsub(jj) = xvec(row0);
else
                    x_peak = -b/(2*a); % sub-grid CS position of prob peak
                    xlo    = min(x_vals);
                    xhi    = max(x_vals);
                    x_peak = max(xlo, min(xhi, x_peak)); % clamp into neighborhood
                    xsub(jj) = x_peak;
end
end
            % ---- CHANGE (2): edge search restricted to this blob's own
            % row range in this column, not the whole column ----
            rowMin = min(rowsHere); rowMax = max(rowsHere);
            searchLo = max(rowMin - bufferPx, 1);
            searchHi = min(rowMax + bufferPx, nrows);
            p_col = double(Q0(searchLo:searchHi, col0));
            xcol  = xvec(searchLo:searchHi);

            [~, idx_peak] = min(abs(xcol - xsub(jj)));

            idx_off = find(p_col(1:idx_peak) < Qmax, 1, 'last');
if isempty(idx_off) || idx_off >= idx_peak
                x_edge_off = NaN; % CHANGE (2): was xvec(1) (domain edge) in v1
else
                x_edge_off = interp1(p_col(idx_off:idx_off+1), xcol(idx_off:idx_off+1), Qmax, 'linear', 'extrap');
end
            idx_shore = find(p_col(idx_peak:end) < Qmax, 1, 'first');
if isempty(idx_shore)
                x_edge_shore = NaN; % CHANGE (2): was xvec(end) (domain edge) in v1
else
                idx_shore = idx_shore + idx_peak - 1;
if idx_shore <= 1
                    x_edge_shore = xcol(idx_shore);
else
                    x_edge_shore = interp1(p_col(idx_shore-1:idx_shore), xcol(idx_shore-1:idx_shore),Qmax, 'linear', 'extrap');
end
end
if ~isnan(x_edge_off) && ~isnan(x_edge_shore)
                wid(jj) = abs(x_edge_shore - x_edge_off);
end % else leave NaN -- no crossing found within this blob's own extent
end
if ~isempty(yvec)
            ysub(jj) = yvec(colHere); % grid-snapped AS lookup (no sub-grid refinement)
end
end
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
rclog = rclog(N >= r0);

% 2-min PIV plot animation

pivFile = '/Volumes/RODSEX Video/PIV Means/ROD2013_PIV_20131020_0903.mat';
P = load(pivFile);

% map variable names onto the common set (u, v, FRFx, FRFy, t)
if ~isfield(P,'u') && all(isfield(P, {'cX','cY','X0','Y0'}))   % DUNEX2021 naming
    P.FRFx = P.cX';  P.FRFy = P.cY';
    P.u    = permute(P.X0, [2 1 3]);
    P.v    = permute(P.Y0, [2 1 3]);
end
u = P.u;  FRFx = P.FRFx;  FRFy = P.FRFy;  t = P.t(:);
if ~isdatetime(t); t = datetime(t, 'ConvertFrom', 'datenum'); end

piv_u_sign = -1;            % onshore = positive; set from the along-wave sign check for this year
u = piv_u_sign * u;

xv = FRFx(1,:);  yv = FRFy(:,1);

figure
ax = axes; hold(ax,'on');
hImg = imagesc(ax, xv, yv, u(:,:,1), 'AlphaData', ~isnan(u(:,:,1)));
set(ax, 'YDir', 'normal', 'Color', 'w');
axis(ax, 'tight');
xlim(ax, [min(xv) max(xv)]);  ylim(ax, [min(yv) max(yv)]);   % or set your own, e.g. [80 200] / [600 830]
colormap(ax, cmocean('balance'));
clim(ax, [-0.25 0.25]);
cb = colorbar(ax);  cb.Label.String = 'Cross-shore velocity [m/s]';
xlabel(ax, 'Cross-shore [m]');  ylabel(ax, 'Alongshore [m]');

for k = 1:size(u,3)
    if ~ishandle(hImg); break; end
    set(hImg, 'CData', u(:,:,k), 'AlphaData', ~isnan(u(:,:,k)));
    title(ax, sprintf('PIV Cross-shore Velocity - %s', char(t(k), 'yyyy-MM-dd HH:mm:ss')));
    pause(0.1)
end
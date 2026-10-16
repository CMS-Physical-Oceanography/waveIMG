
% debbie bathy raw
filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/bathy_surveys/RODDebbieTimeLagFix_20131002.xyz'];
data = readmatrix(filename,'FileType','text');

x = data(:,1);
y = data(:,2);
z = data(:,3);

figure
scatter3(x,y,z,5,z,'filled')
xlabel('x')
ylabel('y')
zlabel('Elevation')
axis equal
colorbar

%% debbie interp - linear interpolation for visualization

filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/bathy_surveys/RODDebbieTimeLagFix_20131002.xyz'];
data = readmatrix(filename,'FileType','text');
 
x = data(:,1);
y = data(:,2);
z = data(:,3);

% create interpolation grid
dx = 5;

xq = min(x):dx:max(x);
yq = min(y):dx:max(y);
[Xq,Yq] = meshgrid(xq,yq);

Zq = griddata(x,y,z,Xq,Yq,'linear'); % lin interp
Zdepth = -Zq;

% plot
figure
h = imagesc(xq,yq,Zdepth);
set(h,'AlphaData',~isnan(Zdepth))
set(gca,'YDir','normal')
axis tight
box on
grid minor
% cb = colorbar;
% cb.Label.String = 'Depth [m]';
colormap(flipud(parula))
clim([0 3])
xlabel('Cross-Shore [m]')
ylabel('Alongshore [m]')
% title('Interpolated Survey Bathy', FontSize=15)

xlim([90 170])
ylim([602 1000])

%%
% FRF LARC survey raw
filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/surveys for prezley/FRF_20210830_1210_DUNEX_NAVD88_LARC_GPS_UTC_v20210831.csv'];
data = readmatrix(filename,'FileType','text');

x = data(:,8);
y = data(:,9);
z = data(:,10);

figure
scatter3(x,y,z,5,z,'filled')
xlabel('x')
ylabel('y')
zlabel('Elevation')
axis equal
colorbar

%% FRF larc survey interpolated

% filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
%     'waveIMG-main/waveIMG-main/data/surveys for prezley/FRF_20210907_1213_DUNEX_NAVD88_LARC_GPS_UTC_v20210911.csv'];

filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/'...
    'waveIMG-main/waveIMG-main/data/bathy_surveys/FRF_20180919_1154_FRF_NAVD88_LARC_GPS_UTC_v20180920.csv']
data = readmatrix(filename,'FileType','text');

% FRF_20210901_1211_DUNEX_NAVD88_LARC_GPS_UTC_v20210905.csv
% FRF_20210830_1210_DUNEX_NAVD88_LARC_GPS_UTC_v202109.csv
% FRF_20210905_1212_DUNEX_NAVD88_LARC_GPS_UTC_v20210914.csv
% FRF_20210907_1213_DUNEX_NAVD88_LARC_GPS_UTC_v20210911.csv

% This file has no header row. Column layout (inferred from value
% ranges -- verify against data(1:5,:) if the plot looks off):
%   1 flag, 2 line_id, 3 session_id, 4 lat, 5 lon,
%   6 sp_easting, 7 sp_northing, 8 frf_x (cross-shore, m),
%   9 frf_y (alongshore, m), 10 elevation NAVD88 (m),
%   11 ellipsoid_ht, 12 date, 13 time_utc, 14 point_id

x = data(:,8); % good for 9/19/2018
y = data(:,9);
z = data(:,10);

% x = data(:,10); % good for 10/4,17/2018
% y = data(:,11);
% z = data(:,12);




% create interpolation grid
dx = 5;
xq = min(x):dx:max(x);
yq = min(y):dx:max(y);
[Xq,Yq] = meshgrid(xq,yq);
Zq = griddata(x,y,z,Xq,Yq,'linear'); % lin interp
Zdepth = -Zq;
% plot
figure
h = imagesc(xq,yq,Zdepth);
set(h,'AlphaData',~isnan(Zdepth))
set(gca,'YDir','normal')
axis tight
box on
grid minor
cb = colorbar;
cb.Label.String = 'Depth [m]';
colormap(flipud(parula))
clim([0 3])
xlabel('Cross-Shore [m]')
ylabel('Alongshore [m]')
title('Interpolated Survey Bathy')

xlim([90 200])
ylim([602 1000])


%% backpack eps survey 2022

filename = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/' ...
    'RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/data/bathy_surveys/' ...
    '2022_BIASEX_debby_backpack.eps'];

data = readmatrix(filename, 'FileType', 'text');

% ---- VERIFY COLUMN LAYOUT BEFORE TRUSTING x/y/z BELOW ----
disp(size(data))
disp(data(1:5,:))
% Backpack/CRAB survey .eps files at FRF are typically whitespace- or
% comma-delimited text with columns similar to:
%   1 profile_id/line, 2 frf_x (cross-shore, m), 3 frf_y (alongshore, m),
%   4 elevation NAVD88 (m)   [layout varies by survey -- check disp() above]

x = data(:,2);   % frf_x (cross-shore) -- adjust after checking disp() output
y = data(:,3);   % frf_y (alongshore)
z = data(:,4);   % elevation NAVD88

% Remove rows with NaN/Inf in any of x, y, z
validRows = isfinite(x) & isfinite(y) & isfinite(z);
x = x(validRows);
y = y(validRows);
z = z(validRows);

% create interpolation grid
dx = 5;
xq = min(x):dx:max(x);
yq = min(y):dx:max(y);
[Xq,Yq] = meshgrid(xq,yq);
Zq = griddata(x,y,z,Xq,Yq,'linear'); % lin interp
Zdepth = -Zq;

% plot
figure
h = imagesc(xq,yq,Zdepth);
set(h,'AlphaData',~isnan(Zdepth))
set(gca,'YDir','normal')
axis tight
box on
grid minor
cb = colorbar;
cb.Label.String = 'Depth [m]';
colormap(flipud(parula))
clim([0 3])
xlabel('Cross-Shore [m]')
ylabel('Alongshore [m]')
title('Interpolated Survey Bathy - BIASEX Debby Backpack, 2022')
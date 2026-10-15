%% Sensor locations over interpolated bathymetry

% 1. Read bathymetry
bathyFile = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy/' ...
    'waveIMG-main/waveIMG-main/data/bathy_surveys/RODDebbieTimeLagFix_20131002.xyz'];

bathy = readmatrix(bathyFile,'FileType','text');

x = bathy(:,1);
y = bathy(:,2);
z = bathy(:,3);

% Remove any NaN rows
valid = isfinite(x) & isfinite(y) & isfinite(z);
x = x(valid);
y = y(valid);
z = z(valid);


% 2. Interpolate bathymetry
dx = 5;   % interpolation spacing [m]
xq = min(x):dx:max(x);
yq = min(y):dx:max(y);

[Xq,Yq] = meshgrid(xq,yq);

Zq = griddata(x,y,z,Xq,Yq,'linear');

% Convert elevation to positive depth
Zdepth = -Zq;


% 3. Read pressure sensor locations

sensorFile = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/RIPS/waveIMG_cpy' ...
    '/waveIMG-main/waveIMG-main/data/sensor_data/RODSEX_sensors_locs.xyz'];

fid = fopen(sensorFile,'r');
sensorData = [];
while ~feof(fid)

    line = fgetl(fid);

    % Try to read numeric values from this line
    vals = sscanf(line,'%f');

    % Valid sensor line should contain:
    % ID, X, Y, Z = 4 numeric values
    if numel(vals) == 4
        sensorData(end+1,:) = vals(:)';
    end
end
fclose(fid);

% Columns:
% 1 = Sensor ID
% 2 = X [m]
% 3 = Y [m]
% 4 = Z [cm]

sensorID = sensorData(:,1);
sensorX  = sensorData(:,2);
sensorY  = sensorData(:,3);
sensorZ  = sensorData(:,4);
fprintf('Number of sensors found: %d\n',length(sensorID));


% 4. Plot bathymetry
figure

h = imagesc(xq,yq,Zdepth);

set(h,'AlphaData',~isnan(Zdepth))

set(gca,'YDir','normal')

axis tight
box on
grid minor
hold on

colormap(flipud(parula))

cb = colorbar;
cb.Label.String = 'Depth [m]';

clim([0 3]);


% 5. Plot ALL pressure sensors
plot(sensorX, sensorY, 'rp', 'MarkerSize', 11, 'MarkerFaceColor', 'r');

for i = 1:length(sensorID)
    text(sensorX(i)+4, sensorY(i), sprintf('%d',sensorID(i)), 'Color','r', 'FontSize',9);
end

xlabel('Cross-Shore [m]')
ylabel('Alongshore [m]')
title('Pressure Sensor Locations Over Bathymetry')
xlim([74.6 250.4]); ylim([589.6 1000.4]); % matches tracking animation plot

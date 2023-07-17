function [time,zw] = load_FRF_waterlevels(startDate,endDate);
%
% USAGE:
%
% loads 6-min water level time-series from FRF pier between the startDate/endDate.
% For example:
% 
%     startDate = '20130920';
%     endDate   = '20131020';
%     [time,zw] = load_FRF_waterlevels(startDate,endDate);

% $$$ url = ['https://tidesandcurrents.noaa.gov/waterlevels.html?id=8651370&units=metric&bdate=',startDate,'&edate=',endDate,'&timezone=GMT&datum=NAVD&interval=6&action=data'];

url = ['https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?begin_date=',startDate,'&end_date=',endDate,'&station=8651370&product=water_level&interval=6&datum=NAVD&time_zone=gmt&units=metric&format=csv'];

data = webread(url);
time = convertTo(table2array(data(:,1)),'datenum');
zw   = table2array(data(:,2));

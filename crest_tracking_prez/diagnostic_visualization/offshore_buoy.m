
%% buoy data plots old
% only one day...
fname = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/' ...
    'RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/data/buoy_data/' ...
    'duck_offshore_cond.txt']; 

opts = detectImportOptions(fname, 'NumHeaderLines', 2);
T = readtable(fname, opts);
T.Properties.VariableNames = {'YY','MM','DD','hh','mm','WDIR','WSPD','GST','WVHT','DPD','APD', ...
    'MWD','PRES','ATMP','WTMP','DEWP','VIS','TIDE'};

time = datetime(T.YY, T.MM, T.DD, T.hh, T.mm, 0);

target_day = datetime(2013, 10, 2); % only plot one day...
mask = dateshift(time, 'start', 'day') == target_day;

t_day = time(mask);
wvht  = T.WVHT(mask);
dpd   = T.DPD(mask);
apd   = T.APD(mask);

figure;
% subplot(2,1,1)
plot(t_day, wvht, 'b-', 'LineWidth', 1.5)
ylabel('Hsig (m)')
title('Offshore Sig Wave Height – 02 Oct 2013 (St.44056)')
xlim([datetime(2013,10,2,6,0,0)  datetime(2013,10,2,20,0,0)])
xlabel('Time')
grid on

% subplot(2,1,2)
figure
plot(t_day, dpd, 'r-', 'LineWidth', 1.5)
ylabel('Offshore Peak Period (s)')
xlabel('Time')
title('Offshore Peak Period – 02 Oct 2013 (St.44056)')
xlim([datetime(2013,10,2,6,0,0)  datetime(2013,10,2,20,0,0)])
grid on

figure
plot(t_day, apd, 'r-', 'LineWidth', 1.5)
ylabel('Offshore Average Period (s)')
xlabel('Time')
title('Offshore Avg Period – 02 Oct 2013 (St.44056)')
xlim([datetime(2013,10,2,6,0,0)  datetime(2013,10,2,20,0,0)])
grid on

%% buoy data, plot multiple days
fname = ['/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/' ...
    'RIPS/waveIMG_cpy/waveIMG-main/waveIMG-main/data/buoy_data/' ...
    '2022_buoyHsDuck.txt']; % buoy data file ***

opts = detectImportOptions(fname, 'NumHeaderLines', 2);
T = readtable(fname, opts);
T.Properties.VariableNames = { ...
    'YY','MM','DD','hh','mm','WDIR','WSPD','GST','WVHT','DPD','APD', ...
    'MWD','PRES','ATMP','WTMP','DEWP','VIS','TIDE'};

time = datetime(T.YY, T.MM, T.DD, T.hh, T.mm, 0);
wvht = T.WVHT;

% ---- ADJUSTABLE INPUTS ----

% Date ranges to plot: add/remove rows as needed, {startDay, endDay}
ranges = { ...
      % datetime(2013,9,23), datetime(2013,10,4); ...   % 2013
      % datetime(2013,10,20), datetime(2013,10,25)};

    % datetime(2018,9,16),  datetime(2018,9,22); ...  % 2018
    % datetime(2018,10,1),  datetime(2018,10,7); ...
    % datetime(2018,10,14), datetime(2018,10,20)};

    % datetime(2021,8,27), datetime(2021,9,6); ...     % 2021
    % datetime(2021,9,6), datetime(2021,9,14);
    % datetime(2021,10,5), datetime(2021,10,11)};

    datetime(2022,8,19), datetime(2022,8,25); ...   % 2022
    datetime(2022,9,12), datetime(2022,9,30); ...
    datetime(2022,10,5), datetime(2022,10,23)}; ...


% Survey dates to mark with vertical red dotted lines.
% Add as many datetimes as needed; each line is only drawn on the
% subplot(s) whose range contains it.
surveyDates = [ ...
    % datetime(2013,9,25); datetime(2013,10,2); datetime(2013,10,22); datetime(2013,10,23)]; % 2013

    % datetime(2018,9,19); ...    % 2018
    % datetime(2018,10,4); ...
    % datetime(2018,10,17)];

    % datetime(2021,8,30); datetime(2021,9,1); datetime(2021,9,5); datetime(2021,9,7); ...    % 2021
    % datetime(2021,9,11); datetime(2021,10,8)];

    datetime(2022,8,22); datetime(2022,9,14); datetime(2022,9,20); datetime(2022,9,27); datetime(2022,10,7); ... % 2022, no jul/nov
    datetime(2022,10,11); datetime(2022,10,21)]; 



% Project date lists to shade (light blue = project 1, light green = project 2) from prev lit
CiaraDates = [ ...
    datetime(2022, 10,8)];   % <-- edit these

RezaDates = [ ...
    datetime(2022,10,8)]; % <-- edit these

yLimits = [0 3]; % set to [] to auto-scale each subplot



% ---- PLOT ----
nRanges = size(ranges, 1);

figure;
for i = 1:nRanges
    startDay = ranges{i,1};
    endDay   = ranges{i,2} + days(1) - seconds(1); % include full last day

    mask = time >= startDay & time <= endDay;

    subplot(nRanges,1,i)
    plot(time(mask), wvht(mask), 'b-', 'LineWidth', 1.5)
    hold on

    % Light grey shading bordering each survey day (00:00 to 24:00)
    inRange = surveyDates(surveyDates >= startDay & surveyDates <= endDay);
    for k = 1:numel(inRange)
        dayStart = dateshift(inRange(k), 'start', 'day');
        dayEnd   = dayStart + days(1);
        patch([dayStart dayEnd dayEnd dayStart], [-100 -100 100 100], ...
    [1 0 0], 'EdgeColor', 'none', 'FaceAlpha', 0.1, 'HandleVisibility', 'off');
    end

    % Vertical red dotted lines bordering each survey day (00:00 to 24:00)
    inRange = surveyDates(surveyDates >= startDay & surveyDates <= endDay);
    for k = 1:numel(inRange)
        dayStart = dateshift(inRange(k), 'start', 'day');
        dayEnd   = dayStart + days(1);
        xline(dayStart, '--r', 'LineWidth', 1.5);
        xline(dayEnd,   '--r', 'LineWidth', 1.5);
    end



    % Light blue shading for Ciara dates
    inRangeP1 = CiaraDates(CiaraDates >= startDay & CiaraDates <= endDay);
    for k = 1:numel(inRangeP1)
        dayStart = dateshift(inRangeP1(k), 'start', 'day');
        dayEnd   = dayStart + days(1);
        patch([dayStart dayEnd dayEnd dayStart], [-100 -100 100 100], ...
            [0.68 0.85 0.9], 'EdgeColor', 'none', 'FaceAlpha', 0.3, 'HandleVisibility', 'off');
    end
    
    % Light green shading for Project 2 dates
    inRangeP2 = RezaDates(RezaDates >= startDay & RezaDates <= endDay);
    for k = 1:numel(inRangeP2)
        dayStart = dateshift(inRangeP2(k), 'start', 'day');
        dayEnd   = dayStart + days(1);
        patch([dayStart dayEnd dayEnd dayStart], [-100 -100 100 100], ...
            [0.7 0.9 0.7], 'EdgeColor', 'none', 'FaceAlpha', 0.3, 'HandleVisibility', 'off');
    end



    hold off

    ylabel('Hs [m]')
    title(sprintf('Hs - %s to %s', ...
        datestr(ranges{i,1}, 'mmm dd'), datestr(ranges{i,2}, 'mmm dd, yyyy')))
    xlim([startDay endDay])
    grid on

    if ~isempty(yLimits)
        ylim(yLimits)
    end

    if i == nRanges
        xlabel('Time')
    end
end

sgtitle(sprintf('Offshore Hs with Relevant Dates - Duck, %d', year(ranges{1,1})))

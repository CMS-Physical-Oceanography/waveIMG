
% functionalized skeleton flow

%% USER INPUT

dateTag     = '1002';          % MMDD
hourStr     = '1200';          % single hour, HHMM (bathy inversion / PIV correction / Fbr)
hourList    = 1200:100:1400;   % hours to process consecutively (for main flow fn1)
numFiles    = 12;              % # video files per hour folder (5-min files)
year_str    = '2013';          % survey/tide file year
data_source = 'piv';           % 'raw' or 'piv' -- celerity used for the breaking force
frame_to_plot = 25;            % frame index (last video file of hourStr) for the Fbr frame figures

run_main_flow = false;         % false = reuse existing mat_data/<dateTag>_<hourStr>.mat
                               % true  = re-process video from scratch (slow)

%% 1. main flow -- wave-front detection + celerity tracking

if run_main_flow
    [celerity_all, celerity_time_all, crestWidths_all, crestLengths_all, tide_all] = ...
        fn_main_flow(dateTag, hourList, numFiles, year_str);
end

%% 2. bathy inversion -- celerity -> depth, compared to survey

[depth_grid_speed, depth_grid_survey, x_centers, y_centers] = ...
    fn_bathy_inversion(dateTag, hourStr, year_str);

%% 3. PIV correction -- PIV-adjusted celerity -> depth

[depth_grid_speed_adj, depth_grid_speed_pivraw, cx_adj_pts, cy_adj_pts, c_adj_pts, ...
    all_celerity_hour, tide] = fn_piv_correction(dateTag, hourStr, year_str);

%% 4. breaking force + along-crest curl(Fbr)

piv = struct('cx_adj_pts',cx_adj_pts, 'cy_adj_pts',cy_adj_pts, 'c_adj_pts',c_adj_pts);

[Fbr_mag_pts, Fbr_dir_pts, Fbr_mag_grid, Fbr_dir_grid, Fbr_curl_grid, ...
 curl_x, curl_y, curl_val, x_centers_force, y_centers_force] = ...
    fn_breaking_force(dateTag, hourStr, year_str, data_source, frame_to_plot, frame_to_plot, piv);
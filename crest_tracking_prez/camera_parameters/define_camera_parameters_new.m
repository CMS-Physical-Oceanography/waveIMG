function [info,icp,beta0,descriptionStr] = define_camera_parameters_new(ID)
% Build info (video + grid settings), and get camera calibration for a given ID.
% Camera calibrations (icp, beta0) come from getCameraParams.m, so new cameras
% only need to be added there. This file only holds video/grid settings.

%% ---------- camera calibration (single source of truth)
[icp, beta0, descriptionStr] = getCameraParams(ID);   % already builds distortion tables

%% ---------- defaults shared by all cameras
info.ID     = ID;
info.format = 'avi';
info.ext    = '.mp4';
info.freq   = icp.FrameRate;

% grid info
info.X_min = 75;   info.X_max = 250;
info.Y_min = 590;  info.Y_max = 1000;
info.Nx = 256;     info.Ny = 512;      % neural network size

% other info
info.Al_bar = 10;  info.Cs_bar = 10;
info.X_gap = [];   info.Y_gap = [];
info.vel_bnd = [-2 2];
info.wndw = 20;    info.stp = 10;
info.minvar = 100; info.maxskew = 2; info.minent = 6;

%% ---------- per-camera video settings / overrides
info.base_dir      = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/rips_onedrive/data/mp4';
info.folder_layout = 'flat';      % 'flat' = files directly in vid_dir; 'date_hour' = vid_dir/<dateTag>/<hour>/

switch ID
    case 'top21'
        info.vid_dir       = '2021';
        info.vid_name_root = 'Dunex_NorthTower';

    case 'bot21'
        info.vid_dir       = '2021';
        info.vid_name_root = 'Dunex_SouthTower';   % TODO: confirm against your files

    case {'top18','bot18'}
        info.vid_dir       = '2018';
        info.vid_name_root = 'TODO';

    case 'rod13'
        info.base_dir      = '/Users/prezleystrait/Library/CloudStorage/OneDrive-UNC-Wilmington/rips_onedrive/NSF_eddie/mp4';
        info.vid_dir       = '2013';
        info.folder_layout = 'date_hour';          % .../2013/<MMDD>/<HH00>/
        info.vid_name_root = '';                   % names start with yyyymmdd_hhmmss_, no prefix

    otherwise
        error('define_camera_parameters_new:NoVideoSettings', ...
              'No video settings defined for ID ''%s''. Add a case here.', ID);
end
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
info.base_dir      = '/Volumes/RODSEX Video';
info.folder_layout = 'flat';   % 'flat'            : files directly in base_dir/vid_dir
                               % 'datehour_folder' : base_dir/vid_dir/<yyyymmdd>_<hh>/
                               % 'date_hour'       : base_dir/vid_dir/<dateTag>/<HH00>/

switch ID
    case 'top21'
        info.vid_dir       = 'DunexMP4';
        info.vid_name_root = 'Dunex_NorthTower';
        info.X_min = 40;     info.X_max = 250;
        info.Y_min = 600;    info.Y_max = 1100;

    case 'bot21'
        info.vid_dir       = 'DunexMP4';
        info.vid_name_root = 'Dunex_SouthTower';   % TODO: confirm against your files
        info.X_min = 75;     info.X_max = 250;
        info.Y_min = 500;    info.Y_max = 750;

    case {'top18','bot18'}
        info.vid_dir       = 'RSEX18MP4';
        info.vid_name_root = 'TODO';               % TODO: check filenames in that folder

    case 'rod13'
        info.vid_dir       = '';                   % hour folders sit at the drive root
        info.folder_layout = 'datehour_folder';    % e.g. /Volumes/RODSEX Video/20131024_12/
        info.vid_name_root = '';                   % names start with yyyymmdd_hhmmss_

    otherwise
        error('define_camera_parameters_new:NoVideoSettings', ...
              'No video settings defined for ID ''%s''. Add a case here.', ID);
end

%% ---------- derived quantities
info.X_res = (info.X_max - info.X_min)/(info.Nx - 1);
info.Y_res = (info.Y_max - info.Y_min)/(info.Ny - 1);

end
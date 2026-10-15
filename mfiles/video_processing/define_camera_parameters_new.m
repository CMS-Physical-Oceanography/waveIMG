function [info,icp,beta0] = define_camera_parameters_new(ID);
% build structures with video, grid, and camera info
%
% video info
info.format = 'avi';% need to determine if this needs to be camera specific...
info.freq   = 2;
% grid info 
info.X_min = 75;
info.X_max = 250;
info.Y_min = 590;
info.Y_max = 1000;
% estimate grid resolution based on neural network size
info.Nx    = 256;
info.Ny    = 512;
info.X_res = (info.X_max-info.X_min)/(info.Nx-1);
info.Y_res = (info.Y_max-info.Y_min)/(info.Ny-1);
% other info
info.Al_bar = 10;
info.Cs_bar = 10;
info.X_gap = [];
info.Y_gap = [];
info.vel_bnd = [-2 2];
info.wndw = 20;
info.stp = 10;
info.minvar = 100;
info.maxskew = 2;
info.minent = 6;

switch ID
    case 'top21'
%% define camera intrinsic parameters
% DUNEX 2021 Top Optical Camera
% Genie Nano C2590, serial number S113817
% Calibration from getCameraParams('top21')

info.vid_dir = 'DunexMP4';
info.vid_name_root = 'Dunex_NorthTower';
info.format = 'avi';% need to determine if this needs to be camera specific...

icp.Model = 'Genie Nano C2590';
icp.SN = 'S113817';
icp.Experiment = 'DUNEX 2021';

icp.PixelFormat = 'Bayer';
icp.BitDepth = 10;
icp.FrameRate = 2;

icp.NU = 2592;
icp.NV = 2048;

icp.c0U = 1277.127279983144;
icp.c0V = 1053.709936574411;

icp.fx = 2567.906532245813;
icp.fy = 2565.990182031598;

icp.d1 = -0.083670192494;
icp.d2 =  0.159080684708;
icp.d3 =  0.0;

icp.t1 = -0.001764102399;
icp.t2 = -0.002003147309;
icp.ac = 0.0;

%% estimate camera radial distortion coefficients
icp = makeRadialDistortion(icp);

%% estimate camera tangential distortion parameters
icp = makeTangentialDistortion(icp);

%% extrinsic camera parameters
% [x, y, z, pitch, roll, azimuth]
beta0 = [34.3611 584.8403 42.5829 ...
         67.4954 1.2241 34.3617];
    case 'rod13'

     % RODSex Tower Video Camera
        % The camera cal came from
        % D:\RODSEX\video_calibration_and_georectification\video_cal\cal1_20150819\cal1_params.mat
        % This was done in Davids office on 08/19/2015.
        % In cal1_params.mat, the calibration info is in a matlab
        % cameraParams object.  This requires the computer vision tool box
        % to read.
        beta0 = [35.0911 585.0288 42.4419 72.1536 0.1974 44.8175];
        
        icp.Model = '';
        icp.SN = '';
        icp.Experiment = 'RODSEX';
        icp.PixelFormat = 'RGB';
        icp.BitDepth = 24;
        icp.FrameRate = 5;
        icp.NU = 2048;
        icp.NV = 1536;
        icp.c0U = 1090.3;
        icp.c0V = 797.5;
        icp.fx = 1951.8;
        icp.fy = 1953.0;
        icp.d1 = -0.3826;
        icp.d2 = 0.2136;
        icp.d3 = -0.0815;
        icp.t1 = 0.00005;
        icp.t2 = 0.0003069;
        icp.ac = 0.0008533;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'Optical Camera From The FRF Pier During RSEX2017';
            
end
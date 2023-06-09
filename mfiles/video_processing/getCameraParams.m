function [icp, beta0, descriptionStr] = getCameraParams(ID)

% [icp, beta0] = getCameraParams(ID)
%  ========================================================================
% Current verison = Version 2, 09/07/2021
% 
% This program outputs the camera intrinsic parameters (icp) and extrinsic
% parameters (beta0) for a given camera rectification and calibration. For
% each new experiment and camera, once a calibration and rectification have
% been finalized, this program should be updated and added too.
% 
% Inputs:
%     ID = A string identifying the Experiment, camera, and location. Valid
%          flags are currently....
%          'top21' = DUNEX2021 tower optical camera to the north
%          'bot21' = DUNEX2021 tower optical camera to the south
%          'dji_0366' = DUNEX2019 drone camera for video DJI_0366.mov
%          'dji_0367' = DUNEX2019 drone camera for video DJI_0367.mov
%          'gopro6084' = RSEX2018 drone camera for video GOPR6084.mp4
%          'top18' = RSEX2018 Top Tower Camera (camera looking more north
%                    with 12mm lens)
%          'bot18' = RSEX2018 Bottom Tower Camera (camera looking more
%                    offshore with 8mm lens)
%          'teo17' = RSEX2017 Tower Optical
%          'tir17' = RSEX2017 Tower IR
%          'peo17' = RSEX2017 Pier Optical
%          'pir17' = RSEX2017 Pier IR
%          'rod13' = RODSEX tower camera
%          'bg2012' = Bargap camera calibration from Melissa
% 
% Outputs:
%     icp = A structure with the camera intrinsic parameters.
%     beta0 = A column vector with the camera extrinsic parameters. Format
%             is  [x, y, z, pitch, roll, azimuth]
%     descriptionStr = String with description of the camera. Used to help
%                      identify camreas and label plots.
% 
% Version History:
%     1) 02/14/2018: Original
%     2) 10/09/2018: Added 17 to all the RSEX2017 ID strings
%                    Added in the calibration coefficients for RSEX2018
%                    cameras
%     3) 06/24/2020: Added camera info for the RSEX2018 and DuneX2019 Drone
%                    flights.
%     4) 07/31/2020: Added additional info to the intrinsic parameters.
%     5) 09/07/2021: Added info for the Dunex 2021 top and bottom cameras
%  ========================================================================

    if strcmp(ID, 'top21')
        % DUNEX2021 Top Camera:
        % Camera SN S113817 with 12mm lens
        beta0 = [34.3611 584.8403 42.5829 67.4954 1.2241 34.3617];
        
        icp.Model = 'Genie Nano C2590';
        icp.SN = 'S113817';
        icp.Experiment = 'DUNEX 2021';
        icp.PixelFormat = 'Bayer';
        icp.BitDepth = 10;
        icp.FrameRate = 2;
        icp.NU = 2592;
        icp.NV = 2048;
        icp.c0U = 1277.127279983144035;
        icp.c0V = 1053.709936574410904;
        icp.fx = 2567.906532245812741;
        icp.fy = 2565.990182031598124;
        icp.d1 = -0.083670192493999;
        icp.d2 = 0.159080684707714;
        icp.d3 = 0.0;
        icp.t1 = -0.001764102398571;
        icp.t2 = -0.002003147308834;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'Top Optical Camera From The FRF Tower During DUNEX2021';
        
        
    elseif strcmp(ID, 'bot21')
        % DUNEX2021 Bottom Camera:
        % Camera SN S1154084 with 8mm lens
        beta0 = [33.6561 583.8746 42.8418 64.8939 -1.2744 81.4041];
        
        icp.Model = 'Genie Nano C2590';
        icp.SN = 'S1154084';
        icp.Experiment = 'DUNEX 2021';
        icp.PixelFormat = 'Bayer';
        icp.BitDepth = 10;
        icp.FrameRate = 2;
        icp.NU = 2592;
        icp.NV = 2048;
        icp.c0U = 1293.095605219293930;
        icp.c0V = 1046.181039017064450;
        icp.fx = 1758.611235060972831;
        icp.fy = 1760.225599679427660;
        icp.d1 = -0.098077634063113;
        icp.d2 = 0.090417889345970;
        icp.d3 = 0.0;
        icp.t1 = -0.000465021460864;
        icp.t2 = -0.001151722191006;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'Bottom Optical Camera From The FRF Tower During DUNEX2021';
        
        
        
    elseif strcmp(ID, 'dji_0366')
        % DJI Zenmuse X5s
        % for flight with video DJI_0366.mov
        beta0 = [115.4943 622.0648 60.7722 0 0 75.8584];
        
        icp.Model = 'Zenmuse X5s';
        icp.SN = '';
        icp.Experiment = 'DUNEX 2019';
        icp.PixelFormat = 'RGB';
        icp.BitDepth = 24;
        icp.FrameRate = 30;
        icp.NU = 3840;
        icp.NV = 2160;
        icp.c0U = 1958.8467;
        icp.c0V = 1038.1481;
        icp.fx = 3348.7053;
        icp.fy = 3344.5492;
        icp.d1 = 0.0271;
        icp.d2 = 0.0;
        icp.d3 = 0.0;
        icp.t1 = -0.0031;
        icp.t2 = 0.0058;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'DUNEX 2019 GoPro Drone Camera For Video GOPR6084.mp4';
        
        
        
    elseif strcmp(ID, 'dji_0367')
        % DJI Zenmuse X5s
        % for flight with video DJI_0367.mov
        beta0 = [114.9935 621.6912 61.3554 0 0 73.1602];
        
        icp.Model = 'Zenmuse X5s';
        icp.SN = '';
        icp.Experiment = 'DUNEX 2019';
        icp.PixelFormat = 'RGB';
        icp.BitDepth = 24;
        icp.FrameRate = 30;
        icp.NU = 3840;
        icp.NV = 2160;
        icp.c0U = 1958.8467;
        icp.c0V = 1038.1481;
        icp.fx = 3348.7053;
        icp.fy = 3344.5492;
        icp.d1 = 0.0271;
        icp.d2 = 0.0;
        icp.d3 = 0.0;
        icp.t1 = -0.0031;
        icp.t2 = 0.0058;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'DUNEX 2019 GoPro Drone Camera For Video GOPR6084.mp4';
        
        
        
    elseif strcmp(ID, 'gopro6084')
        % GoPro Camera (Hero4 Black)
        % For flight with video GOPR6084.mp4
        beta0 = [178.1113 596.8515 100.0885 0.0 0.0 86.9061];
        
        icp.Model = 'Hero4 Black';
        icp.SN = '';
        icp.Experiment = 'RSEX 2018';
        icp.PixelFormat = 'RGB';
        icp.BitDepth = 24;
        icp.FrameRate = 30;
        icp.NU = 1920;
        icp.NV = 1080;
        icp.c0U = 960;
        icp.c0V = 540;
        icp.fx = 1033.0830;
        icp.fy = 1032.9247;
        icp.d1 = 0.0;
        icp.d2 = 0.0;
        icp.d3 = 0.0;
        icp.t1 = 0.0;
        icp.t2 = 0.0;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'GoPro Drone Camera For Video GOPR6084.mp4';
        
        
        
    elseif strcmp(ID, 'top18')
        % RSEX2018 Top Camera:
        % Camera SN S1133817 with 12mm lens
        % icp from CalibResults_S1133817_12mm_f11.mat
        beta0 = [34.21947 584.63584 42.96854 71.94828 0.24613 54.50108];
        
        icp.Model = 'Genie Nano C2590';
        icp.SN = '';
        icp.Experiment = 'RSEX 2018';
        icp.PixelFormat = 'Bayer';
        icp.BitDepth = 10;
        icp.FrameRate = 5;
        icp.NU = 2592;
        icp.NV = 2048;
        icp.c0U = 1305.452246380004000;
        icp.c0V = 1049.423620181106300;
        icp.fx = 2586.682985941321000;
        icp.fy = 2586.519548196773500;
        icp.d1 = -0.101681772893099;
        icp.d2 = 0.184365464895113;
        icp.d3 = 0.0;
        icp.t1 = -0.001376216844589;
        icp.t2 = -0.000874507337251;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'Top Optical Camera From The FRF Tower During RSEX2018';
        
        
        
    elseif strcmp(ID, 'bot18')
        % RSEX2018 Bottom Camera:
        % Camera SN S1154084 with 8mm lens
        % icp from CalibResults_S1154084_08mm_f11.mat
        beta0 = [34.46151 584.21702 42.79689 63.40126 -0.83152 75.18325];
        
        icp.Model = 'Genie Nano C2590';
        icp.SN = '';
        icp.Experiment = 'RSEX 2018';
        icp.PixelFormat = 'Bayer';
        icp.BitDepth = 10;
        icp.FrameRate = 5;
        icp.NU = 2592;
        icp.NV = 2048;
        icp.c0U = 1301.479062434464600;
        icp.c0V = 1053.347019909629100;
        icp.fx = 1743.387765217196100;
        icp.fy = 1743.663955538744400;
        icp.d1 = -0.100169054435584;
        icp.d2 = 0.087054074101961;
        icp.d3 = 0.0;
        icp.t1 = -0.000372504086986;
        icp.t2 = 0.000168088107201;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'Bottom Optical Camera From The FRF Tower During RSEX2018';
        
        
    
    elseif strcmpi(ID, 'teo17')
        % RSEX2017 Tower Optical:
        % icp from CalibResults_2590_12mm_fs8.mat
        % beta0 from TowerEORect_Final_0m.mat
        beta0 = [35.0876 584.1864 42.3572 61.4983 -0.8862 83.2122];
        
        icp.Model = 'Genie Nano C2590';
        icp.SN = '';
        icp.Experiment = 'RSEX 2017';
        icp.PixelFormat = 'Bayer';
        icp.BitDepth = 10;
        icp.FrameRate = 5;
        icp.NU = 2592;
        icp.NV = 2048;
        icp.c0U = 1323.056;
        icp.c0V = 1065.723;
        icp.fx = 2551.7796;
        icp.fy = 2554.2859;
        icp.d1 = -0.109195;
        icp.d2 = 0.162884;
        icp.d3 = 0.0;
        icp.t1 = 0.00158198;
        icp.t2 = 0.00133200;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'Optical Camera From The FRF Tower During RSEX2017';
        
        
        
    elseif strcmpi(ID, 'tir17')
        % RSEX2017 Tower IR:
        % icp from CalibResults_IR_16mm_WithHousing_20180110.mat
        % beta0 from TowerIRRect_final_0m.mat
        beta0 = [34.3918 584.7182 42.7901 62.0728 0.1583 85.6139];
        
        icp.Model = 'Atom 1024';
        icp.SN = '';
        icp.Experiment = 'RSEX 2017';
        icp.PixelFormat = 'IR';
        icp.BitDepth = 14;
        icp.FrameRate = 30;
        icp.NU = 1024;
        icp.NV = 768;
        icp.c0U = 499.812;
        icp.c0V = 393.746;
        icp.fx = 963.8349;
        icp.fy = 964.1196;
        icp.d1 = 0.011963;
        icp.d2 = 0.0;
        icp.d3 = 0.0;
        icp.t1 = 0.00202699;
        icp.t2 = -0.00025561;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'IR Camera From The FRF Tower During RSEX2017';
        
        
        
    elseif strcmpi(ID, 'peo17')
        % RSEX2017 Pier Optical:
        % icp from CalibResults_1940_8mm_fs8.mat
        % beta0 from PierEORect_Final_0m.mat
        beta0 = [189.8066 519.7223 8.6929 69.3919 -1.5748 332.5935];
        
        icp.Model = 'Genie Nano C1920';
        icp.SN = '';
        icp.Experiment = 'RSEX 2017';
        icp.PixelFormat = 'Bayer';
        icp.BitDepth = 10;
        icp.FrameRate = 15;
        icp.NU = 1936;
        icp.NV = 1216;
        icp.c0U = 965.940;
        icp.c0V = 595.691;
        icp.fx = 1399.6792;
        icp.fy = 1399.9660;
        icp.d1 = -0.103941;
        icp.d2 = 0.073465;
        icp.d3 = 0.0;
        icp.t1 = 0.00005433;
        icp.t2 = 0.00298069;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'IR Camera From The FRF Pier During RSEX2017';
        
        
        
    elseif strcmpi(ID, 'pir17')
        % RSEX2017 Pier IR:
        % icp from CalibResults_IR_9mm_WithHousing_20180110.mat
        % beta0 from PierIRRect_Final_0m.mat
        beta0 = [189.8716 518.6534 8.8411 58.3350 -0.4391 337.3224];
        
        icp.Model = 'Atom 1024';
        icp.SN = '';
        icp.Experiment = 'RSEX 2017';
        icp.PixelFormat = 'IR';
        icp.BitDepth = 14;
        icp.FrameRate = 30;
        icp.NU = 1024;
        icp.NV = 768;
        icp.c0U = 510.780;
        icp.c0V = 389.737;
        icp.fx = 587.2063;
        icp.fy = 587.7172;
        icp.d1 = -0.119592;
        icp.d2 = 0.066167;
        icp.d3 = 0.0;
        icp.t1 = 0.00087502;
        icp.t2 = 0.00191252;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = 'Optical Camera From The FRF Pier During RSEX2017';
        
        
    elseif strcmpi(ID, 'rod13')
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
        
        
    elseif strcmpi(ID, 'bg2012')
        % BarGap 2012 Tower Camera for Melissa
        beta0 = [33.5950 587.108 43.271 71.3461 -1.2346 53.1856];
        
        icp.Model = '';
        icp.SN = '';
        icp.Experiment = 'BARGAP 2012';
        icp.PixelFormat = 'RGB';
        icp.BitDepth = 24;
        icp.FrameRate = 30;
        icp.NU = 1280;
        icp.NV = 720;
        icp.c0U = 640;
        icp.c0V = 360;
        icp.fx = 1519.8260;
        icp.fy = 1519.8260;
        icp.d1 = 0.0;
        icp.d2 = 0.0;
        icp.d3 = 0.0;
        icp.t1 = 0.0;
        icp.t2 = 0.0;
        icp.ac = 0.0;
        
        icp = makeRadialDistortion(icp);
        icp = makeTangentialDistortion(icp);
        
        descriptionStr = '';
        
        
        
    else
        error('getCameraParams:InvalidID',...
              ['Invalid input ID \nValid inputs are \n'...
               '''top21''\n'...
               '''bot21''\n'...
               '''dji_0366''\n'...
               '''dji_0367''\n'...
               '''gopro6084''\n'...
               '''top18''\n'...
               '''bot18''\n'...
               '''teo17''\n'...
               '''tir17''\n'...
               '''peo17''\n'...
               '''pir17''\n'...
               '''rod13''\n'...
               '''bg2012'' '])
        
    end

end
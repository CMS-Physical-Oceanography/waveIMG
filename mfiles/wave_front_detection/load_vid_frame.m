function IMG = load_vid_frame(videoDir,videoFile,frameNum)
% 1) function reads video, grid, and camera parameters;
addpath(genpath('../'));
[info, icp, beta0] = define_camera_parameters();% located in waveIMG/mfiles/video_processing
%
% 2) read video frames, etc.
% where are videos? what are the filenames (this would eventually require a loop)
if ~exist('videoDir','var')
    videoDir = ['../../data/20130929/1100/'];
    videoFile= ['20130929_112106_B314_00408CEBCECB_11.avi'];
end
% load video
videoPath = [videoDir,filesep,videoFile];
% loads the current video, but does not rectify, yet.
vid   = VideoReader(videoPath);
vidHz = vid.FrameRate;
vidDr = vid.Duration;
% determine frame indeces from the playback speed and sample frequency.
invRate           = round(vidHz/info.freq);
videoFrameIndices = 1:invRate:vid.NumFrames;
numberVideoFrames = length(videoFrameIndices);% (another loop here, frameNum from 1:nVF-3)
%
% prepare image (U,V) coordinates for rectification
[U, V] = meshgrid(0:icp.NU-1, 0:icp.NV-1);
% generate grid (X,Y) coords for transformation
X = info.X_min:info.X_res:info.X_max;
Y = info.Y_min:info.Y_res:info.Y_max;
[xx,yy] = meshgrid(X,Y);
% this is where you'd apply tidal correction
z_tide    = zeros(size(xx));
% use CIRN toolbox to map (x,y) to (U,V) for later interpolation
% if you're not correcting for tides/waterlevel variation, this can be done once
[Uint,Vint]  = getUVfromXYZ(xx,yy, z_tide, icp, beta0);
% we use a 3-image time-stack... I trained it on 0.5 Hz.
if ~exist('frameNum','var')
    frameNum = 1;
end
% $$$ frames   = frameNum + [0 1 2];
% $$$ for ii   = 1:3
% $$$     % load frame    
    IMGraw  = double(rgb2gray(read(vid,frameNum)));
% $$$     % interpolate to grid points
    IMG     = interp2(U,V,IMGraw,Uint,Vint, 'linear', nan);
% $$$ end
%

clear all
close all
% the steps involved are,
% 1) define camera, grid, network parameters
% 2) load a video, read frames, rectify and interp to regular FRF grid
% 3) (optional: 1=yes/0=no) re-scale the image intensity (gray-scale) to enhance contrast between foam/water
enhance_image = 0;
% 4) apply neural network to get an array of front probabilities (continuous 0=non-front to 1=front)
% 5) extract the coordinates of the ridges/maxima in (4). This is the sketchy/subjective/kludgy. 
%
% 1) function reads video, grid, and camera parameters;
addpath(genpath('../'));
[info, icp, beta0] = define_camera_parameters();% located in waveIMG/mfiles/video_processing
%
% 2) read video frames, etc.
% where are videos? what are the filenames (this would eventually require a loop)
videoDir = ['../../data/20130929/1100/'];
videoFile= ['20130929_112106_B314_00408CEBCECB_11.avi'];
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
frameNum = 1;
frames   = frameNum + [0 1 2];
for ii   = 1:3
    % load frame    
    IMGraw  = double(rgb2gray(read(vid,frames(ii))));
    % interpolate to grid points
    IMG(:,:,ii) = interp2(U,V,IMGraw,Uint,Vint, 'linear', nan);
end
%
% 3) (optional) now use Carinni et al to try and separate water/foam peaks (if any)
if enhance_image
    [foam_th,foam_pk,ob,opdf] = water_foam_threshold(IMG,1);
    %
    f2 = gcf;
    % now re-scale IMG using the water/foam threshold
    IMG0 = IMG;
    IMG  = 255./(1+exp(-3*pi/2*(IMG0-foam_th)/(255-foam_th)));
    H    = hist(IMG(:),ob);
    hold on,plot(ob,H/numel(IMG),'-k')
    %
    IMG = uint8(IMG);
    %
    % make a figure
    f1 = figure;
    f1a1 = subplot(1,2,1);
    RI = imref2d(size(IMG0));
    RI.XWorldLimits = [info.X_min info.X_max];
    RI.YWorldLimits = [info.Y_min info.Y_max];
    imshow(uint8(IMG),RI)
    % imagesc(X, Y, IMG)
    %               
    % colormap('bone')
    xlabel(' $x$ [m]', 'interpreter','latex')
    ylabel(' $y$ [m]', 'interpreter','latex') 
    axis(f1a1,'equal')
    set(f1a1,'tickdir','out','ticklabelinterpreter','latex','fontsize',15,'ydir','normal')
    title(f1a1,"Psuedo-Image");
    %
    figure(f1);
    f1a2 = subplot(1,2,2);
    RI = imref2d(size(IMG));
    RI.XWorldLimits = [info.X_min info.X_max];
    RI.YWorldLimits = [info.Y_min info.Y_max];
    imshow(IMG,RI)
    % imagesc(X, Y, IMG)
    %               
    % colormap('bone')
    xlabel(' $x$ [m]', 'interpreter','latex')
    ylabel(' $y$ [m]', 'interpreter','latex') 
    axis(f1a2,'equal')
    set(f1a2,'tickdir','out','ticklabelinterpreter','latex','fontsize',15,'ydir','normal')
    title(f1a2,"Enhanced Contrast");
    linkaxes([f1a1 f1a2])
    %
end
%
%
% 4) apply neural network
dt = 1/info.freq;
% [pred,prob,xp,yp,tp] = wave_front_from_IMG_CNN(IMG,X,Y,dt,1);
[pred,prob,xp,yp,tp] = wave_front_from_IMG_UNET(IMG,X,Y,dt,1);
%
% 5) try to extract coordinates of the high probability ridges in "prob"
% to be extra confusing I wrote the search function with (row,column)==(x,y)
% so we must transpose everything for what comes next...
r0=20;
Pmax=1;
Pmin=0.75*Pmax;
Pnon=0.25*Pmax;
% you would need to iterate here through prob(Ny,Nx,Nt)
[crlog,bblog,fnlog] = bore_front_search(prob',info.Ny,info.Nx,r0,Pnon,Pmin,Pmax,0);
%
% now switch everything back from (r,c)=(x,y) to (r,c)=(y,x)
if isempty(crlog),
    disp(['Uh oh, no fronts identified!'])
    return
end
C_front = crlog(:,1);% column==y
R_front = crlog(:,2);% row   ==x
ind = sub2ind(size(xx),C_front, R_front);
X_front = xx(ind);
Y_front = yy(ind);
% recall row/column are switched
rcFront = [C_front R_front];
xyFront = [X_front Y_front];
%
hold on, plot(X_front,Y_front,'r.','markersize',4)
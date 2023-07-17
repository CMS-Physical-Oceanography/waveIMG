function [info,icp,beta0] = define_camera_parameters();
% build structures with video, grid, and camera info
%
% video info
info.format = 'avi';
info.freq   = 2.5;
% grid info 
info.X_min = 75;
info.X_max = 250;
info.Y_min = 590;
info.Y_max = 1000;
% estimate grid resolution based on network size
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


%% define camera intrinsic parameters
% see CIRN-toolbox for calibration procedure
icp.PixelFormat = 'RGB';
icp.BitDepth =  24;
icp.FrameRate =  5;
icp.NU = 2048;
icp.NV = 1536;
icp.c0U = 1.0903e+03;
icp.c0V = 797.5000;
icp.fx = 1.9518e+03;
icp.fy = 1953;
icp.d1 = -0.3826;
icp.d2 = 0.2136;
icp.d3 = -0.0815;
icp.t1 = 5.0000e-05;
icp.t2 = 3.0690e-04;
icp.ac = 8.5330e-04;
%
%% estimate camera radial distortion coefficients
icp = makeRadialDistortion(icp);
% $$$ r = 0: 0.001: 2;   % max tan alpha likely to see.
% $$$ r2 = r.*r;
% $$$ fr = 1 + icp.d1*r2 + icp.d2*r2.*r2 + icp.d3*r2.*r2.*r2;
% $$$ % limit to increasing r-distorted (no folding back)
% $$$ rd = r.*fr;
% $$$ good = diff(rd)>0;      
% $$$ icp.r = r(good);
% $$$ icp.fr = fr(good);
%% estimate camera tangental distortion parameters
icp = makeTangentialDistortion(icp);
% $$$ % This is taken from the Caltech cam cal docs.  
% $$$ xmax = 1.5;     % no idea if this is good
% $$$ dx = 0.1;
% $$$ ymax = 1.3;
% $$$ dy = 0.1;
% $$$ %
% $$$ icp.x = -xmax: dx: xmax;
% $$$ icp.y = -ymax: dy: ymax;
% $$$ [X,Y] = meshgrid(icp.x,icp.y);
% $$$ X  = X(:); Y = Y(:);
% $$$ r2 = X.*X + Y.*Y;
% $$$ icp.dx = reshape(2*icp.t1*X.*Y + icp.t2*(r2+2*X.*X),[],length(icp.x));
% $$$ icp.dy = reshape(icp.t1*(r2+2*Y.*Y) + 2*icp.t2*X.*Y,[],length(icp.x));
%
% extrinsic camera parameters (requires several steps within CIRN-toolbox)
beta0 = [35.0911  585.0288   42.4419   72.1536    0.1974   44.8175];
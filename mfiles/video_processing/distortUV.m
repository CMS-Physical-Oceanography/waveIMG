function [Ud, Vd] = distortUV(Uu, Vu, icp)

% [Ud, Vd] = distortUV(Uu, Vu, icp)
% =================================================
% Current verison = Version 1, 04/20/2017
% 
% Converts pixels from undistorted to distorted image coordinates.  This
% program is based off distortCaltech.m from the CIRN UAV-toolbox and is
% based on equations from the Cal Tech calibration toolbox manual.
% 
% Inputs:
%     Uu = U pixel poistion, in image coordinates, to be distorted.  Uu may
%          be a 1D vector or a 2D array.
%     Vu = V pixel poistion, in image coordinates, to be distorted.  Vu may
%          be a 1D vector or a 2D array.
%     icp = structure made from the camera parameter structure produced by
%           makeIntrinsicStructureFromCalTechCal.m
% 
% Outputs:
%     Ud = distorted U pixel position in image coordinates.  Is the same
%          size as Uu.
%     Vd = distorted V pixel position in image coordinates.  Is the same
%          size as Vu.
% 
% Version History:
%     1) 04/20/2017: Original
% =================================================

[rowU, colU] = size(Uu);
[rowV, colV] = size(Vu);
if rowU ~= rowV || colU ~= colV
    error('Input Uu and Vu must be the same size')
end

% convert Uu and Vu into normalized camera coordinates
x = (Uu(:)-icp.c0U)/icp.fx;
y = (Vu(:)-icp.c0V)/icp.fy;

% distortion based on distance from image center
r2 = x.*x + y.*y;
r = sqrt(r2);
rOut = r > 2;

% Find the radial distortion factor 
fr = 1 + icp.d1*r2 + icp.d2*r2.*r2 + icp.d3*r2.*r2.*r2;

% Find the tangential distortion factor 
dx = 2*icp.t1*x.*y + icp.t2*(r2+2*x.*x);
dy = icp.t1*(r2+2*y.*y) + 2*icp.t2*x.*y;

% distort locations in camera coordinates
x2 = x.*fr + dx;
y2 = y.*fr + dy;

% get rid of values with large r. These may distort back into the image
% space
x2(rOut) = NaN;
y2(rOut) = NaN;

% convert from camera coordinates back to image coordinates
ud = (x2+icp.ac.*y2).*icp.fx + icp.c0U;       % accounts for skewness
vd = y2.*icp.fy + icp.c0V;

% convert undistorted pixels into same aray size as inputs
Ud = reshape(ud, rowU, colU);
Vd = reshape(vd, rowV, colV);
function icp = makeTangentialDistortion(icp)

% icp = makeTangentialDistortion(icp)
% =========================================================================
% Current verison = Version 1, 04/11/2017
%
%  computes the tangential distortion over an expected domain x and y
%  in tan(alpha) coords that can be used for an interp2 for any required
%  set of x,y values.
% 
% Taken from makefr.m from the CIRN UAVToolbox
% 
% copied by Levi Gorrell to keep codes compartmentalized
% 
% Inputs:
%     icp = camera intrinsic and distortion parameters from
%           makeIntrinsicStructFromCalTechCal.m
% 
% Outputs:
%     icp = the camera intrisic and distortion parameters with the computed
%           tangential distortion.
% 
% Version History:
%     1) 04/11/2017: Original
% =========================================================================

% This is taken from the Caltech cam cal docs.  
xmax = 1.5;     % no idea if this is good
dx = 0.1;
ymax = 1.3;
dy = 0.1;

icp.x = -xmax: dx: xmax;
icp.y = -ymax: dy: ymax;
[X,Y] = meshgrid(icp.x,icp.y);
X = X(:); Y = Y(:);
r2 = X.*X + Y.*Y;
icp.dx = reshape(2*icp.t1*X.*Y + icp.t2*(r2+2*X.*X),[],length(icp.x));
icp.dy = reshape(icp.t1*(r2+2*Y.*Y) + 2*icp.t2*X.*Y,[],length(icp.x));


%
%   Copyright (C) 2017  Coastal Imaging Research Network
%                       and Oregon State University

%    This program is free software: you can redistribute it and/or  
%    modify it under the terms of the GNU General Public License as 
%    published by the Free Software Foundation, version 3 of the 
%    License.

%    This program is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.

%    You should have received a copy of the GNU General Public License
%    along with this program.  If not, see
%                                <http://www.gnu.org/licenses/>.

% CIRN: https://coastal-imaging-research-network.github.io/
% CIL:  http://cil-www.coas.oregonstate.edu
%
%key UAVProcessingToolbox
%


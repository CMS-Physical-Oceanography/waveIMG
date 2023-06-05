function K = makeCameraMatrix(icp)

% K = makeCameraMatrix(icp)
% ============================================
% Current verison = Version 1, 04/20/2017
% 
% Makes the intrinsic camera matrix from a structure with the intrinsic and
% distortion parameters for the camera. 
% 
% Outputs:
%     icp = structure made from the camera parameter structure produced by
%           makeIntrinsicStructureFromCalTechCal.m
% 
% Inputs:
%     K = camera matrix to convert from image pixels to camera coordinates
%         normalized in z
% 
% Version History:
%     1) 04/20/2017: Original
% ============================================

K = [icp.fx  icp.ac*icp.fx  icp.c0U;...
     0       -icp.fy        icp.c0V;...
     0       0              1      ];

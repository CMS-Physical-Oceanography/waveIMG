function R = makeCameraRotationMatrix(pitch, roll, azimuth)

% R = makeCameraRotationMatrix(pitch, roll, azimuth)
% ================================================== 
% Current Verion = Version 1, 05/30/2017
% 
% Takes pitch, roll, and azimuth of the camera and makes the rotation
% matrix needed to go from camera coordinates to world coordinates.  This
% code was slightly modified from angles2R.m found in the CIRN UAV-Toolbox.
% 
% Inputs:
%     pitch = camera angle in degrees from nadir. (rotation about cameras y
%             axis)
%     roll = Rotation about the camera's z axis in degrees
%     azimuth = Rotation about the cameras y axis in degrees from north.
% 
% Outputs:
%     R = camera's rotation matrix to go from camera to real world
%         coordinates
% 
% Version History:
%     1) 05/30/2017: Original
% ==================================================

R(1,1) = cosd(azimuth) * cosd(roll) + sind(azimuth) * cosd(pitch) * sind(roll);
R(1,2) = -cosd(roll) * sind(azimuth) + sind(roll) * cosd(pitch) * cosd(azimuth);
R(1,3) = sind(roll) * sind(pitch);
R(2,1) = -sind(roll) * cosd(azimuth) + cosd(roll) * cosd(pitch) * sind(azimuth);
R(2,2) = sind(roll) * sind(azimuth) + cosd(roll) * cosd(pitch) * cosd(azimuth);
R(2,3) = cosd(roll) * sind(pitch);
R(3,1) = sind(pitch) * sind(azimuth);
R(3,2) = sind(pitch) * cosd(azimuth);
R(3,3) = -cosd(pitch);
function [U, V] = getUVfromXYZ(X, Y, Z, icp, beta0)

% [U, V] = getUVfromXYZ(X, Y, Z, icp)
% ================================================================
% Current verison = Version 1, 04/20/2017
% 
% Returns the image coordinates of a set of real world, rectangular
% coordinates.  
% 
% Inputs:
%     X = The real world, rectangular, X coordinate.  X should be posotive
%         to the east. May be scalar, 1D vector, or 2D array.
%     Y = The real world, rectangular, Y coordinate.  Y should be posotive
%         to the north. May be scalar, 1D vector, or 2D array.
%     Z = The real world, rectangual, Z coordinate.  Z should be posotive
%         up. May be scalar, 1D vector, or 2D array.
%     icp = The structure containing the camera's intrinsic and calibration
%           parameters.  Strucutre created with
%           makeInstrinsicStructFromCalTechCal.m
%     beta0 = The camera extrinsic parameters defined as a row vector with
%             elements [x y z pitch roll azimuth].
% 
% Outputs:
%     U = The U image coordinate corresponding to the X, Y, Z real world
%         coordinate. Will be the same size as X, Y, Z.
%     V = The V image coordinate corresponding to the X, Y, Z real world
%         coordinate. Will be the same size as X, Y, Z.
% 
% Version History:
%     1) 04/20/2017: Original
% ================================================================

[rowX, colX] = size(X);
[rowY, colY] = size(Y);
[rowZ, colZ] = size(Z);
if rowX ~= rowY || colX ~= colY || rowX ~= rowZ || colX ~= colZ
    error('Input X, Y, and Z must be the same size')
end

% convet x, y, and z into one matrix for matrix multiplication
XYZ = [X(:)'; Y(:)'; Z(:)'; ones(1,length(X(:)))];

% make the P matrix
K = makeCameraMatrix(icp);
R = makeCameraRotationMatrix(beta0(4), beta0(5), beta0(6));
IC = [eye(3) -beta0(1:3)'];
 
P = K*R*IC;

% Convet x, y, z to undistorted U, V.
UVZc = P*XYZ;
UV = UVZc./repmat(UVZc(3,:),3,1); % Normalize each column of UVZc by the bottom element, which is Zc (so the bottom row is now all ones).

% Distort the computed pixel coordinates
[U,V] = distortUV(UV(1,:)',UV(2,:)',icp);

% reshape back into original input size
U = reshape(U, rowX, colX);
V = reshape(V, rowX, colX);
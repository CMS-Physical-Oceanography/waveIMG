function mask = rebuildMaskFromAnnotationLog(logFile, imageSize)
%REBUILDMASKFROMANNOTATIONLOG Reconstruct a binary annotation mask.
%
%   mask = rebuildMaskFromAnnotationLog(logFile, imageSize)
%
% logFile is a .mat annotation log produced by CNNTrainingAnnotator.
% imageSize can be omitted; the size stored in the log is used.

S = load(logFile,'-mat');
if isfield(S,'imageSize')
    if nargin < 2
        imageSize = S.imageSize(1:2);
    end
else
    error('The annotation log does not contain imageSize.');
end

mask = false(imageSize(1),imageSize(2));
if ~isfield(S,'regionHistory')
    return
end

H = S.regionHistory;
for k = 1:numel(H)
    poly = poly2mask(H(k).vertices(:,1),H(k).vertices(:,2), ...
        imageSize(1),imageSize(2));
    switch lower(H(k).action)
        case 'add'
            mask = mask | poly;
        case 'remove'
            mask = mask & ~poly;
        otherwise
            error('Unknown annotation action "%s" in region %d.',H(k).action,k);
    end
end
end

function rclog= bore_front_search_funwave_v2(Q0,nr,nc,r0,Qmax);
%
% USAGE: rclog= bore_front_search_v2(Q0,nr,nc,r0,Qmax);
%
% this is a connected region search with Q0>Qmax & deflate algorithm.
% image is first convolved with an r0xr0 window. 
% The shore should be close to the bottom of the image (small rows==offshore)
%
%
% $$$ figure, imagesc(Q0)
%

f1 = hamming(r0);
f  = f1*f1';
f  = f./sum(f(:));
tmp = Q0>=Qmax;
tmp = conv2(tmp,f,'same');

bw = bwboundaries(ceil(tmp),'noholes');
Nw = length(bw);

% loop over the boundaries, take the average x-location of each front
rclog = {};
for ii = 1:Nw
    rc     = bw{ii};
    N(ii)  = size(rc,1);
    cu     = unique(rc(:,2));
    ru     = nan*cu;
    for jj=1:length(cu)
        thisCol = find(rc(:,2)==cu(jj));
        ru(jj)  = round(mean(rc(thisCol,1)));
    end
    rclog{ii,1} = [ru, cu];
end
%
% sort by size and remove regions from a single r0 size
[N,srt] = sort(N,'descend');
rclog = rclog(srt);
rclog = rclog(N>=r0);

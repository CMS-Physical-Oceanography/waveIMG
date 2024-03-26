function [RT,Rmax,Tmax,R,T] = radon_DG(X,Y,Q,r0,dr,dT,threshold)
%
R   = 0:dr:r0-dr;
if length(dT)==1
    T   = -pi:dT:pi-dT;
else
    T = dT;
    dT = T(2)-T(1);
end
RT  = zeros(length(R),length(T));
if ~exist('threshold','var')
    threshold = 0.5;
end
%
% in case input is Log(F); make sure small numbers aren't too small, or large numbers aren't too large
maxQ = max(Q(~isinf(Q)));
minQ = min(Q(~isinf(Q)));
Q(Q>maxQ) = maxQ;
Q(Q<minQ) = minQ;
%
for kk = 1:length(R)
    for ll = 1:length(T)
        in = (abs(R(kk)-X*cos(T(ll))-Y*sin(T(ll)))<threshold);%  inter1(X*cos(T(ll))+Y*sin(T(ll)), Q(ll), R(kk) ); %
        RT(kk,ll) = sum(Q(in));
    end
end
% normalize by segment length
RTnorm = RT./repmat([2*r0*sin(acos(R/r0))]',1,length(T));
%
[iR,iT] = find(RT==max(RT(:)));
%
Rmax = R(iR);
Tmax = T(iT);
if length(Rmax)>1;
    %   disp('multiple maxima: radon_DG.m, line 23')
    Rmax = Rmax(1);
    Tmax = Tmax(1);
end